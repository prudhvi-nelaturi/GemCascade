#!/usr/bin/env python3
"""
GemCascade — asset generator.

This script IS the game's visual design surface: every PNG under assets/ and
store/ is generated from here, so art tweaks are code edits + a re-run rather
than a round trip through an image editor. Same role as GlassRush's
scripts/gen_assets.py, but built on Pillow instead of hand-rolled PNG writing,
which buys us real gradients, gaussian glows and soft shadows.

Run:
    python3 scripts_gen/gen_assets.py            # regenerate everything
    python3 scripts_gen/gen_assets.py gems ui    # regenerate one or more groups

Groups: gems, particles, backgrounds, ui, icons, store

Everything is deterministic (fixed RNG seeds) and idempotent — re-running
overwrites the same files with byte-identical content.

Rendering conventions
---------------------
* Shapes are drawn supersampled (SS) and downsampled with LANCZOS, which is our
  antialiasing: Pillow's ImageDraw has no AA of its own.
* Unit shapes live in [-1, 1] x [-1, 1] with +y pointing DOWN (image space), and
  are normalised so the larger axis touches 1.0.
* Light comes from the top-left (LIGHT_DIR) everywhere — gems, buttons, coins
  and the icon all agree on it, which is most of what makes a set of sprites
  read as "one game" rather than "a folder of images".
"""

import colorsys
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
STORE = os.path.join(ROOT, "store")

# Light direction shared by every asset (normalised, +y down => this is up-left).
LIGHT_DIR = (-0.56, -0.83)


# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------

def hx(s):
    """'#RRGGBB' -> (r, g, b)."""
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def clamp8(v):
    return max(0, min(255, int(round(v))))


def mix(c1, c2, t):
    """Linear blend between two RGB tuples."""
    t = max(0.0, min(1.0, t))
    return tuple(clamp8(a + (b - a) * t) for a, b in zip(c1, c2))


def with_alpha(c, a):
    return (c[0], c[1], c[2], clamp8(a))


def hsv(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return (clamp8(r * 255), clamp8(g * 255), clamp8(b * 255))


def ramp(dark, base, light, f):
    """Maps a lighting factor to a colour along dark->base->light.

    Multiplying an RGB by a scalar (the naive way to shade) desaturates into mud
    at the dark end and clips to grey at the bright end. Interpolating along a
    hand-picked three-stop ramp instead keeps the hue rich in shadow and pushes
    highlights toward the gem's own tint, which is what makes the facets read as
    a jewel rather than a shaded polygon.
    """
    if f <= 1.0:
        return mix(dark, base, (f - 0.25) / 0.75)
    return mix(base, light, (f - 1.0) / 0.45)


# ---------------------------------------------------------------------------
# Gradient / mask helpers
# ---------------------------------------------------------------------------

_RADIAL = Image.radial_gradient("L")  # 256x256, black at centre -> white at r=128


def radial_mask(size, center, radius, power=1.0):
    """L mask: 255 at `center`, falling to 0 at `radius` (0 elsewhere)."""
    d = max(2, int(radius * 2))
    g = ImageOps.invert(_RADIAL.resize((d, d), Image.BILINEAR))
    if power != 1.0:
        g = g.point(lambda v: clamp8(255.0 * ((v / 255.0) ** power)))
    m = Image.new("L", size, 0)
    m.paste(g, (int(center[0] - radius), int(center[1] - radius)))
    return m


def radial_glow(size, center, radius, color, alpha=255, power=1.6):
    """RGBA layer holding a soft circular glow."""
    layer = Image.new("RGBA", size, with_alpha(color, 0))
    solid = Image.new("RGBA", size, with_alpha(color, 255))
    m = radial_mask(size, center, radius, power=power)
    if alpha < 255:
        m = m.point(lambda v: clamp8(v * alpha / 255.0))
    layer.paste(solid, (0, 0), m)
    return layer


def _stop_column(length, stops):
    """1-px strip of interpolated colour stops. stops: [(pos 0..1, rgb), ...]."""
    stops = sorted(stops, key=lambda s: s[0])
    col = Image.new("RGB", (1, length))
    px = col.load()
    for i in range(length):
        t = i / max(1, length - 1)
        lo = stops[0]
        hi = stops[-1]
        for a, b in zip(stops, stops[1:]):
            if a[0] <= t <= b[0]:
                lo, hi = a, b
                break
        span = max(1e-6, hi[0] - lo[0])
        px[0, i] = mix(lo[1], hi[1], (t - lo[0]) / span)
    return col


def vertical_gradient(size, stops):
    w, h = size
    return _stop_column(h, stops).resize((w, h), Image.BICUBIC)


def horizontal_gradient(size, stops):
    w, h = size
    col = _stop_column(w, stops).transpose(Image.ROTATE_270)  # (1,w) -> (w,1)
    return col.resize((w, h), Image.BICUBIC)


def rounded_mask(size, radius, inset=0):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([inset, inset, size[0] - 1 - inset, size[1] - 1 - inset],
                        radius=radius, fill=255)
    return m


def add_vignette(img, strength=0.45, radius_factor=0.78, power=1.7, tint=(0, 0, 0)):
    w, h = img.size
    m = radial_mask((w, h), (w / 2.0, h / 2.0), max(w, h) * radius_factor, power=power)
    a = ImageChops.invert(m).point(lambda v: clamp8(v * strength))
    img.paste(Image.new("RGB", (w, h), tint), (0, 0), a)
    return img


def add_grain(img, amount=0.16, sigma=22):
    """Subtle film grain — keeps big flat gradients from banding on device."""
    n = Image.effect_noise(img.size, sigma).convert("RGB")
    return Image.blend(img, ImageChops.overlay(img, n), amount)


def paste_rgba(base, layer, offset=(0, 0)):
    """Alpha-composite `layer` onto an RGB or RGBA `base` at `offset`."""
    base.paste(layer, offset, layer)
    return base


# ---------------------------------------------------------------------------
# Geometry helpers (unit shapes, +y down)
# ---------------------------------------------------------------------------

def regular_polygon(n, rot_deg=0.0):
    out = []
    for i in range(n):
        a = math.radians(rot_deg + i * 360.0 / n)
        out.append((math.cos(a), math.sin(a)))
    return out


def rect_points(hw, hh):
    return [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]


def cut_corners(pts, t):
    """Replaces every vertex with two points t along each adjacent edge.

    This is how the emerald / trillion / cushion silhouettes get their
    characteristic clipped corners without hand-listing coordinates.
    """
    n = len(pts)
    out = []
    for i in range(n):
        prev = pts[(i - 1) % n]
        cur = pts[i]
        nxt = pts[(i + 1) % n]
        out.append((cur[0] + (prev[0] - cur[0]) * t, cur[1] + (prev[1] - cur[1]) * t))
        out.append((cur[0] + (nxt[0] - cur[0]) * t, cur[1] + (nxt[1] - cur[1]) * t))
    return out


def normalize_shape(pts):
    m = max(max(abs(x), abs(y)) for x, y in pts)
    return [(x / m, y / m) for x, y in pts]


def scale_pts(pts, s):
    return [(x * s, y * s) for x, y in pts]


def rotate_pts(pts, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(x * ca - y * sa, x * sa + y * ca) for x, y in pts]


def place(pts, cx, cy, r, sx=1.0, sy=1.0):
    return [(cx + x * r * sx, cy + y * r * sy) for x, y in pts]


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def four_point_star(draw, cx, cy, r, thick, color, diagonal=0.0):
    """The classic sparkle glint: two crossed slivers (+ optional diagonals)."""
    draw.polygon([(cx, cy - r), (cx + thick, cy), (cx, cy + r), (cx - thick, cy)], fill=color)
    draw.polygon([(cx - r, cy), (cx, cy - thick), (cx + r, cy), (cx, cy + thick)], fill=color)
    if diagonal > 0.0:
        d = r * diagonal
        t = thick * diagonal
        for a in (45, 135):
            ra = math.radians(a)
            ux, uy = math.cos(ra), math.sin(ra)
            px, py = -uy, ux
            draw.polygon([
                (cx + ux * d, cy + uy * d), (cx + px * t, cy + py * t),
                (cx - ux * d, cy - uy * d), (cx - px * t, cy - py * t)], fill=color)


def sparkle_layer(size, specs, blur=1.2):
    """specs: [(x, y, r, alpha, color)] -> RGBA glint layer."""
    layer = Image.new("RGBA", size, (255, 255, 255, 0))
    d = ImageDraw.Draw(layer)
    for (x, y, r, a, col) in specs:
        d.ellipse([x - r * 0.22, y - r * 0.22, x + r * 0.22, y + r * 0.22],
                  fill=with_alpha(col, a))
        four_point_star(d, x, y, r, max(1.0, r * 0.08), with_alpha(col, a), diagonal=0.45)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return layer


# ---------------------------------------------------------------------------
# The faceted-gem renderer (shared by gems, the crystal icon and cave crystals)
# ---------------------------------------------------------------------------

# Unit silhouettes. Deliberately one distinct cut per colour: colour-blind
# players (and anyone glancing at a busy cascade) can tell gems apart by
# outline alone, which is the single cheapest accessibility win in a match-3.
SHAPES = {
    "brilliant": normalize_shape(regular_polygon(10, rot_deg=18)),
    "cushion": normalize_shape(cut_corners(regular_polygon(4, rot_deg=45), 0.26)),
    "emerald": normalize_shape(cut_corners(rect_points(0.62, 1.0), 0.24)),
    "trillion": normalize_shape(cut_corners(regular_polygon(3, rot_deg=-90), 0.24)),
    "marquise": normalize_shape([
        (0.0, -1.0), (0.40, -0.55), (0.58, 0.0), (0.40, 0.55),
        (0.0, 1.0), (-0.40, 0.55), (-0.58, 0.0), (-0.40, -0.55)]),
    "kite": normalize_shape([
        (-0.54, -0.78), (0.54, -0.78), (0.94, -0.16), (0.0, 1.0), (-0.94, -0.16)]),
    "shard": normalize_shape([
        (0.0, -1.0), (0.34, -0.42), (0.46, 0.30), (0.0, 1.0),
        (-0.46, 0.30), (-0.34, -0.42)]),
}

# dark / base / light drive the facet ramp; glow is the outer bloom.
PALETTES = {
    "ruby":     dict(dark=hx("#4A0512"), base=hx("#E31440"), light=hx("#FFB3C2"), glow=hx("#FF2D55")),
    "sapphire": dict(dark=hx("#05184C"), base=hx("#1E5CE6"), light=hx("#A8D2FF"), glow=hx("#3A8CFF")),
    "emerald":  dict(dark=hx("#033A1D"), base=hx("#0FB55C"), light=hx("#A6FFCB"), glow=hx("#18E37D")),
    "topaz":    dict(dark=hx("#5C3702"), base=hx("#F5AE18"), light=hx("#FFF0B8"), glow=hx("#FFC93C")),
    "amethyst": dict(dark=hx("#2B0647"), base=hx("#9B31E3"), light=hx("#E7BCFF"), glow=hx("#C15CFF")),
    "diamond":  dict(dark=hx("#2E4C68"), base=hx("#C3DCF2"), light=hx("#FFFFFF"), glow=hx("#BEEEFF")),
    "crystal":  dict(dark=hx("#07485E"), base=hx("#38D9F2"), light=hx("#EAFFFF"), glow=hx("#84F4FF")),
    "cave_a":   dict(dark=hx("#180A46"), base=hx("#6B4BE0"), light=hx("#CDBBFF"), glow=hx("#8E6BFF")),
    "cave_b":   dict(dark=hx("#062F4A"), base=hx("#2FA8D8"), light=hx("#C9F3FF"), glow=hx("#5FD8FF")),
}

GEMS = [
    ("gem_0", "ruby", "brilliant"),
    ("gem_1", "sapphire", "cushion"),
    ("gem_2", "emerald", "emerald"),
    ("gem_3", "topaz", "trillion"),
    ("gem_4", "amethyst", "marquise"),
    ("gem_5", "diamond", "kite"),
]


def render_gem(palette, shape, size=256, ss=3, glow=True, fill=0.44, seed=7):
    """Renders one faceted gemstone as an RGBA sprite.

    The body is built in RGB (so pastes composite cleanly) and only gets its
    alpha at the very end from the silhouette mask; the outer bloom lives on its
    own layer underneath so it can spill past the silhouette.
    """
    rnd = random.Random(seed)
    S = size * ss
    cx = cy = S / 2.0
    R = S * fill
    dark, base, light = palette["dark"], palette["base"], palette["light"]

    # Three concentric rings: outer silhouette -> girdle -> table.
    rings = [place(shape, cx, cy, R * s) for s in (1.0, 0.70, 0.40)]
    n = len(shape)

    sil = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sil).polygon(rings[0], fill=255)

    body = Image.new("RGB", (S, S), base)
    d = ImageDraw.Draw(body)

    def facet_light(pts, bias, amp):
        gx, gy = centroid(pts)
        dx, dy = gx - cx, gy - cy
        m = math.hypot(dx, dy) or 1.0
        dot = (dx / m) * LIGHT_DIR[0] + (dy / m) * LIGHT_DIR[1]
        return bias + amp * dot + rnd.uniform(-0.035, 0.035)

    # Crown facets (outer -> girdle): the widest lighting range, they carry the
    # "cut" read.
    for i in range(n):
        quad = [rings[0][i], rings[0][(i + 1) % n], rings[1][(i + 1) % n], rings[1][i]]
        d.polygon(quad, fill=ramp(dark, base, light, facet_light(quad, 0.86, 0.54)))

    # Girdle band (girdle -> table): flatter, keeps the middle from going muddy.
    for i in range(n):
        quad = [rings[1][i], rings[1][(i + 1) % n], rings[2][(i + 1) % n], rings[2][i]]
        d.polygon(quad, fill=ramp(dark, base, light, facet_light(quad, 1.02, 0.30)))

    # Table, split into a radial star of triangles.
    for i in range(n):
        tri = [rings[2][i], rings[2][(i + 1) % n], (cx, cy)]
        d.polygon(tri, fill=ramp(dark, base, light, facet_light(tri, 1.14, 0.18)))

    # Global depth: darken toward the girdle so the stone reads as convex.
    shade = ImageChops.invert(radial_mask((S, S), (cx, cy), R * 1.05, power=1.35))
    body.paste(Image.new("RGB", (S, S), mix(dark, (0, 0, 0), 0.35)),
               (0, 0), shade.point(lambda v: clamp8(v * 0.55)))

    # Crisp facet edges — thin light seams are what actually sell "cut glass".
    seams = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ds = ImageDraw.Draw(seams)
    w = max(1, int(S * 0.006))
    seam_col = with_alpha(mix(light, (255, 255, 255), 0.35), 90)
    for i in range(n):
        ds.line([rings[0][i], rings[1][i]], fill=seam_col, width=w)
        ds.line([rings[1][i], rings[2][i]], fill=seam_col, width=w)
        ds.line([rings[2][i], (cx, cy)], fill=with_alpha(mix(light, (255, 255, 255), 0.35), 55), width=w)
    ds.polygon(rings[1], outline=seam_col, width=w)
    ds.polygon(rings[2], outline=with_alpha(mix(light, (255, 255, 255), 0.5), 120), width=w)
    body = Image.alpha_composite(body.convert("RGBA"), seams).convert("RGB")

    # Bounced light along the lower edge (opposite the key light).
    bounce = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    db = ImageDraw.Draw(bounce)
    db.ellipse([cx - R * 0.52, cy + R * 0.18, cx + R * 0.62, cy + R * 0.86],
               fill=with_alpha(light, 105))
    bounce = bounce.filter(ImageFilter.GaussianBlur(S * 0.045))
    body = Image.alpha_composite(body.convert("RGBA"), bounce).convert("RGB")

    # Rim: bright on the lit edge, dark on the shadow edge.
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rim)
    dr.polygon(rings[0], outline=with_alpha((255, 255, 255), 210), width=max(2, int(S * 0.016)))
    grad = _stop_column(S, [(0.0, (255, 255, 255)), (0.55, (60, 60, 60)), (1.0, (0, 0, 0))])
    grad = grad.resize((S, S), Image.BICUBIC).convert("L")
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), grad))
    dark_rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(dark_rim).polygon(rings[0], outline=with_alpha(mix(dark, (0, 0, 0), 0.4), 190),
                                     width=max(2, int(S * 0.014)))
    dark_grad = ImageOps.invert(grad)
    dark_rim.putalpha(ImageChops.multiply(dark_rim.getchannel("A"), dark_grad))
    body = Image.alpha_composite(body.convert("RGBA"), dark_rim)
    body = Image.alpha_composite(body, rim).convert("RGB")

    # Specular: one soft bloom plus a tight hot spot, both up-left.
    spec = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dsp = ImageDraw.Draw(spec)
    hx_, hy_ = cx + LIGHT_DIR[0] * R * 0.46, cy + LIGHT_DIR[1] * R * 0.46
    dsp.ellipse([hx_ - R * 0.34, hy_ - R * 0.26, hx_ + R * 0.34, hy_ + R * 0.26],
                fill=with_alpha((255, 255, 255), 120))
    spec = spec.filter(ImageFilter.GaussianBlur(S * 0.035))
    hot = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dh = ImageDraw.Draw(hot)
    dh.ellipse([hx_ - R * 0.17, hy_ - R * 0.115, hx_ + R * 0.17, hy_ + R * 0.115],
               fill=with_alpha((255, 255, 255), 210))
    hot = hot.filter(ImageFilter.GaussianBlur(S * 0.012))
    body = Image.alpha_composite(body.convert("RGBA"), spec)
    body = Image.alpha_composite(body, hot).convert("RGB")

    gem = body.convert("RGBA")
    gem.putalpha(sil)

    # Glint sits on top of the silhouette mask so its points can extend past the
    # stone — that little overshoot is most of the "sparkle" read.
    glint = sparkle_layer((S, S), [(hx_, hy_, R * 0.34, 195, (255, 255, 255))], blur=S * 0.006)
    gem = Image.alpha_composite(gem, glint)

    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if glow:
        bloom = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(bloom).polygon(place(shape, cx, cy, R * 1.05),
                                      fill=with_alpha(palette["glow"], 115))
        bloom = bloom.filter(ImageFilter.GaussianBlur(S * 0.05))
        out = Image.alpha_composite(out, bloom)
    out = Image.alpha_composite(out, gem)
    return out.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Gems + special overlays
# ---------------------------------------------------------------------------

def gen_gems(size=256, ss=3):
    outdir = os.path.join(ASSETS, "gems")
    written = []
    for idx, (name, pal, shape) in enumerate(GEMS):
        img = render_gem(PALETTES[pal], SHAPES[shape], size=size, ss=ss, seed=17 + idx * 5)
        written.append(save(img, os.path.join(outdir, name + ".png")))
    written.append(save(render_stripe_overlay(size, ss), os.path.join(outdir, "gem_stripe_overlay.png")))
    written.append(save(render_wrapped_overlay(size, ss), os.path.join(outdir, "gem_wrapped_overlay.png")))
    written.append(save(render_color_bomb(size, ss), os.path.join(outdir, "gem_bomb.png")))
    return written


def render_stripe_overlay(size=256, ss=3):
    """Horizontal shine band for STRIPED_H. Game code rotates it 90 deg for
    STRIPED_V, so it must be symmetric about both axes at 0 deg."""
    S = size * ss
    cy = S / 2.0
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    warm = (255, 251, 236)
    # Outer soft band.
    d.rectangle([0, cy - S * 0.155, S, cy + S * 0.155], fill=with_alpha(warm, 70))
    # Mid band.
    d.rectangle([0, cy - S * 0.085, S, cy + S * 0.085], fill=with_alpha(warm, 130))
    layer = layer.filter(ImageFilter.GaussianBlur(S * 0.022))

    core = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dc = ImageDraw.Draw(core)
    # Bright core plus two satellite rails => reads as a candy stripe, not a smear.
    dc.rectangle([0, cy - S * 0.028, S, cy + S * 0.028], fill=with_alpha((255, 255, 255), 240))
    dc.rectangle([0, cy - S * 0.075, S, cy - S * 0.058], fill=with_alpha((255, 255, 255), 190))
    dc.rectangle([0, cy + S * 0.058, S, cy + S * 0.075], fill=with_alpha((255, 255, 255), 190))
    core = core.filter(ImageFilter.GaussianBlur(S * 0.005))
    layer = Image.alpha_composite(layer, core)

    # Fade the extreme ends so the band doesn't die on a hard edge.
    fade = _stop_column(S, [(0.0, (0, 0, 0)), (0.08, (255, 255, 255)),
                            (0.92, (255, 255, 255)), (1.0, (0, 0, 0))])
    fade = fade.transpose(Image.ROTATE_270).resize((S, S), Image.BICUBIC).convert("L")
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), fade))

    # Arrow chevrons hinting at the direction of the blast.
    tips = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dt = ImageDraw.Draw(tips)
    for sgn, x0 in ((1, S * 0.10), (-1, S * 0.90)):
        for k in range(2):
            x = x0 + sgn * k * S * 0.075
            dt.polygon([(x, cy - S * 0.10), (x + sgn * S * 0.055, cy), (x, cy + S * 0.10)],
                       fill=with_alpha((255, 255, 255), 150 - k * 55))
    tips = tips.filter(ImageFilter.GaussianBlur(S * 0.004))
    layer = Image.alpha_composite(layer, tips)
    return layer.resize((size, size), Image.LANCZOS)


def render_wrapped_overlay(size=256, ss=3):
    """Glowing wrapper ring + candy twists, centre left clear so the base gem
    still shows through."""
    S = size * ss
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    inset = S * 0.115
    radius = S * 0.20
    box = [inset, inset, S - inset, S - inset]

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(box, radius=radius,
                                           outline=with_alpha(hx("#FFD36B"), 235),
                                           width=int(S * 0.075))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.035))
    layer = Image.alpha_composite(layer, glow)

    ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(ring)
    dr.rounded_rectangle(box, radius=radius, outline=with_alpha((255, 255, 255), 245),
                         width=int(S * 0.030))
    dr.rounded_rectangle([box[0] + S * 0.030, box[1] + S * 0.030,
                          box[2] - S * 0.030, box[3] - S * 0.030],
                         radius=radius * 0.8, outline=with_alpha(hx("#FFE9A8"), 170),
                         width=int(S * 0.012))
    ring = ring.filter(ImageFilter.GaussianBlur(S * 0.004))
    layer = Image.alpha_composite(layer, ring)

    # Wrapper twists at left and right, drawn as bow-tie triangle pairs.
    tw = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dt = ImageDraw.Draw(tw)
    cy = S / 2.0
    for sgn, x_in, x_out in ((-1, inset + S * 0.01, S * 0.015), (1, S - inset - S * 0.01, S - S * 0.015)):
        dt.polygon([(x_in, cy), (x_out, cy - S * 0.145), (x_out, cy + S * 0.145)],
                   fill=with_alpha((255, 255, 255), 230))
        dt.polygon([(x_in, cy), (x_out + sgn * -S * 0.005, cy - S * 0.075),
                    (x_out + sgn * -S * 0.005, cy + S * 0.075)],
                   fill=with_alpha(hx("#FFC24D"), 210))
    tw = tw.filter(ImageFilter.GaussianBlur(S * 0.005))
    layer = Image.alpha_composite(layer, tw)

    corners = [(inset + radius * 0.35, inset + radius * 0.35),
               (S - inset - radius * 0.35, inset + radius * 0.35),
               (inset + radius * 0.35, S - inset - radius * 0.35),
               (S - inset - radius * 0.35, S - inset - radius * 0.35)]
    layer = Image.alpha_composite(
        layer, sparkle_layer((S, S), [(x, y, S * 0.075, 200, (255, 255, 255)) for x, y in corners],
                             blur=S * 0.005))
    return layer.resize((size, size), Image.LANCZOS)


def render_color_bomb(size=256, ss=3):
    """Standalone prismatic orb — replaces the base sprite for COLOR_BOMB."""
    S = size * ss
    cx = cy = S / 2.0
    R = S * 0.42
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Rainbow bloom behind the orb.
    bloom = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    db = ImageDraw.Draw(bloom)
    for i in range(24):
        db.pieslice([cx - R * 1.14, cy - R * 1.14, cx + R * 1.14, cy + R * 1.14],
                    i * 15 - 90, (i + 1) * 15 - 90, fill=with_alpha(hsv(i / 24.0, 0.85, 1.0), 190))
    bloom = bloom.filter(ImageFilter.GaussianBlur(S * 0.055))
    out = Image.alpha_composite(out, bloom)

    sil = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sil).ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)

    body = Image.new("RGB", (S, S), hx("#0A0518"))
    grad = vertical_gradient((S, S), [(0.0, hx("#3A1560")), (0.5, hx("#160A2E")), (1.0, hx("#05020E"))])
    body.paste(grad, (0, 0))
    body.paste(Image.new("RGB", (S, S), hx("#2A0F4A")), (0, 0),
               radial_mask((S, S), (cx - R * 0.25, cy - R * 0.3), R * 1.1, power=1.5)
               .point(lambda v: clamp8(v * 0.6)))

    # Prismatic ring: hue sweep confined to an annulus so the core stays dark.
    hue = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dh = ImageDraw.Draw(hue)
    for i in range(36):
        dh.pieslice([cx - R, cy - R, cx + R, cy + R], i * 10 - 90, (i + 1) * 10 - 90,
                    fill=with_alpha(hsv(i / 36.0 + 0.05, 0.95, 1.0), 255))
    annulus = ImageChops.subtract(
        radial_mask((S, S), (cx, cy), R * 1.02, power=0.9),
        radial_mask((S, S), (cx, cy), R * 0.66, power=1.4))
    hue.putalpha(ImageChops.multiply(hue.getchannel("A"),
                                     annulus.point(lambda v: clamp8(v * 0.85))))
    hue = hue.filter(ImageFilter.GaussianBlur(S * 0.018))
    body = Image.alpha_composite(body.convert("RGBA"), hue).convert("RGB")

    # Faint facet spokes keep it in the same visual family as the normal gems.
    spokes = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dsp = ImageDraw.Draw(spokes)
    ring = place(SHAPES["brilliant"], cx, cy, R * 0.98)
    for p in ring:
        dsp.line([(cx, cy), p], fill=with_alpha((255, 255, 255), 45), width=max(1, int(S * 0.005)))
    dsp.polygon(place(SHAPES["brilliant"], cx, cy, R * 0.52),
                outline=with_alpha((255, 255, 255), 70), width=max(1, int(S * 0.006)))
    body = Image.alpha_composite(body.convert("RGBA"), spokes).convert("RGB")

    # Rim + specular, same light direction as every other gem.
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse([cx - R, cy - R, cx + R, cy + R],
                                outline=with_alpha((255, 255, 255), 200), width=int(S * 0.014))
    grad_l = _stop_column(S, [(0.0, (255, 255, 255)), (0.6, (40, 40, 40)), (1.0, (0, 0, 0))])
    grad_l = grad_l.resize((S, S), Image.BICUBIC).convert("L")
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), grad_l))
    body = Image.alpha_composite(body.convert("RGBA"), rim).convert("RGB")

    spec = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hxp, hyp = cx + LIGHT_DIR[0] * R * 0.48, cy + LIGHT_DIR[1] * R * 0.48
    ImageDraw.Draw(spec).ellipse([hxp - R * 0.26, hyp - R * 0.17, hxp + R * 0.26, hyp + R * 0.17],
                                 fill=with_alpha((255, 255, 255), 225))
    spec = spec.filter(ImageFilter.GaussianBlur(S * 0.014))
    body = Image.alpha_composite(body.convert("RGBA"), spec).convert("RGB")

    orb = body.convert("RGBA")
    orb.putalpha(sil)
    out = Image.alpha_composite(out, orb)
    out = Image.alpha_composite(out, sparkle_layer(
        (S, S), [(hxp, hyp, R * 0.5, 230, (255, 255, 255)),
                 (cx + R * 0.5, cy + R * 0.52, R * 0.26, 170, (255, 255, 255))],
        blur=S * 0.006))
    return out.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Particles
# ---------------------------------------------------------------------------

def gen_particles(size=64, ss=4):
    """White/greyscale only — Godot's particle material multiplies this by the
    per-gem colour at runtime, so any tint baked in here would double up."""
    S = size * ss
    cx = cy = S / 2.0
    layer = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    solid = Image.new("RGBA", (S, S), (255, 255, 255, 255))

    core = radial_mask((S, S), (cx, cy), S * 0.46, power=2.4)
    layer.paste(solid, (0, 0), core)
    halo = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    halo.paste(solid, (0, 0), radial_mask((S, S), (cx, cy), S * 0.5, power=1.1)
               .point(lambda v: clamp8(v * 0.35)))
    layer = Image.alpha_composite(halo, layer)

    star = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    four_point_star(ImageDraw.Draw(star), cx, cy, S * 0.48, S * 0.022, (255, 255, 255, 190))
    star = star.filter(ImageFilter.GaussianBlur(S * 0.012))
    layer = Image.alpha_composite(layer, star)

    img = layer.resize((size, size), Image.LANCZOS)
    return [save(img, os.path.join(ASSETS, "particles", "spark.png"))]


# ---------------------------------------------------------------------------
# Episode backgrounds
# ---------------------------------------------------------------------------

BG_W, BG_H = 1080, 1920


def _blob_cluster(draw, cx, cy, w, h, color, rnd, count=9):
    """Overlapping circles => soft organic canopy/cloud silhouette."""
    for _ in range(count):
        x = cx + rnd.uniform(-w * 0.5, w * 0.5)
        y = cy + rnd.uniform(-h * 0.35, h * 0.35)
        r = rnd.uniform(h * 0.42, h * 0.78)
        draw.ellipse([x - r, y - r * 0.9, x + r, y + r * 0.9], fill=color)


def _tree(draw, x, base_y, top_y, canopy_r, leaf_col, hi_col, trunk_col, rnd):
    """One stylised tree: tapered trunk + a canopy built from stacked lobes with
    a lighter cap, so the foliage layers read as volumes instead of flat bands."""
    tw = canopy_r * 0.16
    draw.rounded_rectangle([x - tw, top_y, x + tw, base_y], radius=tw, fill=trunk_col)
    lobes = ((0.0, 0.02, 1.00), (-0.66, 0.30, 0.70), (0.66, 0.30, 0.70),
             (-0.36, -0.46, 0.64), (0.38, -0.44, 0.60), (0.0, -0.72, 0.52))
    for (dx, dy, rf) in lobes:
        r = canopy_r * rf * rnd.uniform(0.92, 1.08)
        cx = x + canopy_r * dx
        cy = top_y + canopy_r * dy
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=leaf_col)
    for (dx, dy, rf) in ((-0.30, -0.58, 0.40), (0.14, -0.74, 0.30), (-0.62, -0.10, 0.28)):
        r = canopy_r * rf
        cx = x + canopy_r * dx
        cy = top_y + canopy_r * dy
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hi_col)


def _leaf(draw, x, y, angle_deg, length, width, color, curve=0.35):
    """Tapered, curved leaf/frond polygon."""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    steps = 14
    top, bottom = [], []
    for i in range(steps + 1):
        t = i / steps
        env = math.sin(math.pi * t) ** 0.85
        bend = curve * length * (t ** 2)
        bx = x + ux * length * t + px * bend
        by = y + uy * length * t + py * bend
        top.append((bx + px * width * env, by + py * width * env))
        bottom.append((bx - px * width * env, by - py * width * env))
    draw.polygon(top + bottom[::-1], fill=color)


def render_candy_forest(w=BG_W, h=BG_H, ss=2):
    """Episode 1: warm, sugary, welcoming."""
    W, H = w * ss, h * ss
    rnd = random.Random(101)
    img = vertical_gradient((W, H), [
        (0.00, hx("#FF9FD2")), (0.14, hx("#FFB9DF")), (0.32, hx("#FFC9A8")),
        (0.48, hx("#FFE29A")), (0.60, hx("#C8EC7E")), (0.78, hx("#4FB55E")),
        (1.00, hx("#125C33"))])

    # Sun bloom, upper right. Kept tight — a wide one washes the whole frame out.
    img.paste(Image.new("RGB", (W, H), hx("#FFF6C9")), (0, 0),
              radial_mask((W, H), (W * 0.78, H * 0.13), W * 0.40, power=2.2)
              .point(lambda v: clamp8(v * 0.60)))
    paste_rgba(img, radial_glow((W, H), (W * 0.78, H * 0.13), W * 0.18, hx("#FFFFFF"), 235, power=2.4))

    # Sun rays.
    rays = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rays)
    for i in range(14):
        a = math.radians(i * 25.7 + 8)
        L = W * 1.5
        spread = math.radians(4.5)
        ox, oy = W * 0.78, H * 0.13
        dr.polygon([(ox, oy),
                    (ox + math.cos(a - spread) * L, oy + math.sin(a - spread) * L),
                    (ox + math.cos(a + spread) * L, oy + math.sin(a + spread) * L)],
                   fill=with_alpha((255, 255, 255), 34))
    rays = rays.filter(ImageFilter.GaussianBlur(W * 0.012))
    paste_rgba(img, rays)

    # Candy clouds.
    clouds = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dc = ImageDraw.Draw(clouds)
    for cy_f, alpha, scale in ((0.10, 165, 1.0), (0.22, 135, 0.8), (0.31, 110, 0.65)):
        _blob_cluster(dc, W * rnd.uniform(0.15, 0.7), H * cy_f, W * 0.5 * scale,
                      H * 0.035 * scale, with_alpha(hx("#FFFFFF"), alpha), rnd, count=7)
    clouds = clouds.filter(ImageFilter.GaussianBlur(W * 0.006))
    paste_rgba(img, clouds)

    # Candy canes flanking the scene: striped rounded bars with a hook.
    for x_f, tilt in ((0.10, -6), (0.90, 7)):
        cane = Image.new("RGBA", (int(W * 0.20), int(H * 0.42)), (0, 0, 0, 0))
        cw, ch = cane.size
        shape = Image.new("L", (cw, ch), 0)
        dsh = ImageDraw.Draw(shape)
        bar_w = cw * 0.30
        dsh.rounded_rectangle([cw * 0.5 - bar_w / 2, ch * 0.28, cw * 0.5 + bar_w / 2, ch],
                              radius=bar_w / 2, fill=255)
        dsh.arc([cw * 0.5 - bar_w / 2, ch * 0.02, cw * 0.5 + bar_w * 2.0, ch * 0.55],
                180, 360, fill=255, width=int(bar_w))
        stripes = Image.new("RGBA", (cw, ch), with_alpha(hx("#FFFFFF"), 255))
        dst = ImageDraw.Draw(stripes)
        step = int(cw * 0.16)
        for i in range(-ch, cw + ch, step * 2):
            dst.polygon([(i, ch), (i + step, ch), (i + step + ch, 0), (i + ch, 0)],
                        fill=with_alpha(hx("#FF5C8A"), 255))
        stripes.putalpha(shape)
        stripes = stripes.rotate(tilt, resample=Image.BICUBIC, expand=True)
        paste_rgba(img, stripes, (int(W * x_f - stripes.width / 2), int(H * 0.30)))

    # Three depth layers: pale/hazy far -> saturated near, each on its own hill
    # so the frame has real front-to-back separation rather than one green mass.
    layers = [
        # (hill_y, hill_col, tree_y, canopy_r, leaf, highlight, trunk, count, alpha)
        (0.635, hx("#A9E0A4"), 0.618, 0.052, hx("#8FD48D"), hx("#B7EBAF"), hx("#B08A6A"), 6, 190),
        (0.760, hx("#5FBE6E"), 0.735, 0.072, hx("#3FA85C"), hx("#6FCE7C"), hx("#8A5A3B"), 5, 235),
        (0.900, hx("#2A8248"), 0.868, 0.098, hx("#1B7040"), hx("#39975A"), hx("#6B4128"), 4, 255),
    ]
    for (hy, hill_col, ty, cr_f, leaf, hi, trunk, count, alpha) in layers:
        lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        dl = ImageDraw.Draw(lay)
        # rolling hill silhouette
        for k in range(4):
            hx0 = W * (-0.15 + k * 0.42) + rnd.uniform(-W * 0.05, W * 0.05)
            hw = W * rnd.uniform(0.34, 0.52)
            hh = H * rnd.uniform(0.05, 0.09)
            dl.ellipse([hx0 - hw, H * hy - hh, hx0 + hw, H * hy + hh * 6],
                       fill=with_alpha(hill_col, alpha))
        for i in range(count):
            x = W * ((i + 0.5) / count) + rnd.uniform(-W * 0.07, W * 0.07)
            top = H * ty + rnd.uniform(-H * 0.018, H * 0.018)
            _tree(dl, x, H * (hy + 0.06), top, W * cr_f,
                  with_alpha(leaf, alpha), with_alpha(hi, alpha),
                  with_alpha(trunk, alpha), rnd)
        lay = lay.filter(ImageFilter.GaussianBlur(W * 0.003))
        paste_rgba(img, lay)

    # Gumdrops scattered on the near hill.
    candy = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dg = ImageDraw.Draw(candy)
    for _ in range(11):
        x = rnd.uniform(W * 0.03, W * 0.97)
        y = rnd.uniform(H * 0.90, H * 0.99)
        r = rnd.uniform(W * 0.016, W * 0.032)
        col = rnd.choice([hx("#FF6FA8"), hx("#FFD24A"), hx("#7FE3FF"), hx("#C77BFF")])
        dg.ellipse([x - r, y - r * 0.9, x + r, y + r * 0.9], fill=with_alpha(col, 255))
        dg.ellipse([x - r * 0.45, y - r * 0.62, x - r * 0.02, y - r * 0.22],
                   fill=with_alpha((255, 255, 255), 170))
    paste_rgba(img, candy)

    # Floating bokeh + sparkles for sugar-rush ambience.
    bok = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dbo = ImageDraw.Draw(bok)
    for _ in range(28):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H * 0.85)
        r = rnd.uniform(W * 0.006, W * 0.030)
        col = rnd.choice([hx("#FFFFFF"), hx("#FFD1E8"), hx("#FFF3B0"), hx("#B8F5C6")])
        dbo.ellipse([x - r, y - r, x + r, y + r], fill=with_alpha(col, rnd.randint(60, 150)))
    bok = bok.filter(ImageFilter.GaussianBlur(W * 0.004))
    paste_rgba(img, bok)
    paste_rgba(img, sparkle_layer((W, H), [
        (rnd.uniform(0, W), rnd.uniform(0, H * 0.8), rnd.uniform(W * 0.012, W * 0.035),
         rnd.randint(120, 210), (255, 255, 255)) for _ in range(16)], blur=W * 0.002))

    add_vignette(img, strength=0.34, radius_factor=0.80, tint=hx("#3A1030"))
    img = add_grain(img, 0.12)
    return img.resize((w, h), Image.LANCZOS)


def render_crystal_caves(w=BG_W, h=BG_H, ss=2):
    """Episode 2: cool, moody, glowing."""
    W, H = w * ss, h * ss
    rnd = random.Random(202)
    img = vertical_gradient((W, H), [
        (0.00, hx("#0B0630")), (0.22, hx("#221159")), (0.45, hx("#2E3C93")),
        (0.68, hx("#1F6E96")), (0.86, hx("#12496B")), (1.00, hx("#07182E"))])

    # Central light pool.
    img.paste(Image.new("RGB", (W, H), hx("#6FE3FF")), (0, 0),
              radial_mask((W, H), (W * 0.5, H * 0.46), W * 0.72, power=2.2)
              .point(lambda v: clamp8(v * 0.55)))
    paste_rgba(img, radial_glow((W, H), (W * 0.5, H * 0.46), W * 0.26, hx("#CFF7FF"), 150, power=2.6))

    # God rays slanting down from the cave mouth.
    rays = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rays)
    for i in range(9):
        x = W * (0.05 + i * 0.115)
        wdt = W * rnd.uniform(0.03, 0.075)
        dr.polygon([(x, 0), (x + wdt, 0), (x + wdt + W * 0.22, H), (x + W * 0.22, H)],
                   fill=with_alpha(hx("#9FE8FF"), rnd.randint(16, 34)))
    rays = rays.filter(ImageFilter.GaussianBlur(W * 0.018))
    paste_rgba(img, rays)

    # Stalactites hanging from the ceiling.
    stal = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(stal)
    for i in range(15):
        x = W * (i / 12.0 - 0.04) + rnd.uniform(-W * 0.03, W * 0.03)
        half = W * rnd.uniform(0.038, 0.088)
        length = H * rnd.uniform(0.07, 0.21)
        ds.polygon([(x - half, -H * 0.01), (x + half, -H * 0.01), (x, length)],
                   fill=with_alpha(mix(hx("#1B0F44"), hx("#4A3A9E"), rnd.random()), 235))
        ds.line([(x - half * 0.35, 0), (x, length * 0.92)],
                fill=with_alpha(hx("#B9C8FF"), 90), width=int(W * 0.004))
    paste_rgba(img, stal)

    # Crystal formations — reuses the gem renderer so the backdrop and the
    # playfield pieces are literally cut from the same code.
    for (x_f, y_f, scale, pal, rot) in (
            (0.13, 0.83, 0.46, "cave_a", -14), (0.24, 0.90, 0.30, "cave_b", 9),
            (0.05, 0.93, 0.34, "cave_b", 6), (0.86, 0.82, 0.50, "cave_b", 12),
            (0.74, 0.91, 0.32, "cave_a", -8), (0.95, 0.90, 0.30, "cave_a", 16),
            (0.44, 0.95, 0.26, "cave_b", -5), (0.60, 0.97, 0.22, "cave_a", 7)):
        px = int(W * scale)
        cr = render_gem(PALETTES[pal], SHAPES["shard"], size=px, ss=2, seed=int(x_f * 977))
        cr = cr.rotate(rot, resample=Image.BICUBIC, expand=True)
        paste_rgba(img, cr, (int(W * x_f - cr.width / 2), int(H * y_f - cr.height / 2)))

    # Floating motes + glints.
    motes = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dm = ImageDraw.Draw(motes)
    for _ in range(60):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        r = rnd.uniform(W * 0.002, W * 0.010)
        dm.ellipse([x - r, y - r, x + r, y + r],
                   fill=with_alpha(hx("#DDF7FF"), rnd.randint(70, 200)))
    motes = motes.filter(ImageFilter.GaussianBlur(W * 0.003))
    paste_rgba(img, motes)
    paste_rgba(img, sparkle_layer((W, H), [
        (rnd.uniform(0, W), rnd.uniform(0, H), rnd.uniform(W * 0.012, W * 0.040),
         rnd.randint(120, 220), (222, 246, 255)) for _ in range(20)], blur=W * 0.002))

    add_vignette(img, strength=0.55, radius_factor=0.74, tint=hx("#04021A"))
    img = add_grain(img, 0.14)
    return img.resize((w, h), Image.LANCZOS)


def render_sunset_beach(w=BG_W, h=BG_H, ss=2):
    """Episode 3: hot, hazy, retro-sunset."""
    W, H = w * ss, h * ss
    rnd = random.Random(303)
    horizon = int(H * 0.60)

    img = vertical_gradient((W, H), [
        (0.00, hx("#241056")), (0.18, hx("#5E1F80")), (0.34, hx("#B0308A")),
        (0.47, hx("#F0567A")), (0.55, hx("#FF8A4C")), (0.60, hx("#FFD07A"))])

    # Retro sun: disc + horizontal slits that widen toward the horizon.
    sun_cx, sun_cy, sun_r = W * 0.5, horizon - H * 0.075, W * 0.27
    paste_rgba(img, radial_glow((W, H), (sun_cx, sun_cy), sun_r * 2.6, hx("#FF9B4A"), 190, power=2.0))
    sun = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sun_grad = vertical_gradient((W, H), [(0.0, hx("#FFF3B0")), (0.5, hx("#FFC93C")), (1.0, hx("#FF5E7A"))])
    sun_grad = sun_grad.convert("RGBA")
    sun_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sun_mask).ellipse([sun_cx - sun_r, sun_cy - sun_r, sun_cx + sun_r, sun_cy + sun_r],
                                     fill=255)
    sun.paste(sun_grad, (0, 0), sun_mask)
    dsl = ImageDraw.Draw(sun)
    y = sun_cy + sun_r * 0.10
    gap = sun_r * 0.055
    while y < sun_cy + sun_r + gap * 4:
        dsl.rectangle([sun_cx - sun_r, y, sun_cx + sun_r, y + gap], fill=(0, 0, 0, 0))
        gap *= 1.28
        y += gap * 2.05
    paste_rgba(img, sun)

    # Water.
    water = vertical_gradient((W, H - horizon), [
        (0.00, hx("#FF9E5E")), (0.16, hx("#E0568C")), (0.45, hx("#7B2E86")),
        (0.75, hx("#3A1A66")), (1.00, hx("#180C3A"))])
    img.paste(water, (0, horizon))

    # Sun glitter path. Each row is broken into a few ragged segments — a solid
    # bar per row reads as a jetty/road, broken ones read as moving water.
    streaks = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dst = ImageDraw.Draw(streaks)
    yy = horizon + H * 0.004
    while yy < H:
        t = (yy - horizon) / float(H - horizon)
        half = W * (0.07 + t * 0.42) * rnd.uniform(0.82, 1.12)
        thick = H * (0.0018 + t * 0.0075)
        alpha = int(225 * (1.0 - t * 0.72))
        col = mix(hx("#FFF0BE"), hx("#FF9BB8"), t)
        left = sun_cx - half + rnd.uniform(-W * 0.03, W * 0.03) * t
        span = half * 2
        x = left
        while x < left + span:
            seg = span * rnd.uniform(0.10, 0.34)
            dst.rounded_rectangle([x, yy, min(x + seg, left + span), yy + thick],
                                  radius=thick / 2,
                                  fill=with_alpha(col, int(alpha * rnd.uniform(0.55, 1.0))))
            x += seg + span * rnd.uniform(0.03, 0.11)
        yy += thick + H * (0.005 + t * 0.014)
    streaks = streaks.filter(ImageFilter.GaussianBlur(W * 0.003))
    paste_rgba(img, streaks)

    # Wide, low-contrast swell lines so the water isn't a flat gradient.
    swell = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dsw = ImageDraw.Draw(swell)
    yy = horizon + H * 0.02
    while yy < H:
        t = (yy - horizon) / float(H - horizon)
        dsw.rounded_rectangle([rnd.uniform(-W * 0.1, W * 0.2), yy,
                               rnd.uniform(W * 0.8, W * 1.1), yy + H * 0.0025 * (1 + t * 3)],
                              radius=H * 0.002, fill=with_alpha(hx("#FFC7DA"), int(45 * (1 - t * 0.4))))
        yy += H * (0.012 + t * 0.05)
    swell = swell.filter(ImageFilter.GaussianBlur(W * 0.004))
    paste_rgba(img, swell)

    # Horizon haze band.
    haze = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(haze).rectangle([0, horizon - H * 0.03, W, horizon + H * 0.03],
                                   fill=with_alpha(hx("#FFD9A0"), 130))
    haze = haze.filter(ImageFilter.GaussianBlur(W * 0.03))
    paste_rgba(img, haze)

    # Palm silhouettes flanking the frame.
    palms = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dp = ImageDraw.Draw(palms)
    silh = with_alpha(hx("#25103F"), 250)
    # Foreground shore so the palms have something to stand on.
    dp.ellipse([-W * 0.45, H * 0.965, W * 1.45, H * 1.30], fill=silh)
    # `sway` is the total horizontal drift of the trunk top, expressed as a
    # fraction of the frame WIDTH — deriving it from the trunk height (which is
    # a fraction of H, and H is ~1.8x W here) throws the crown clean off-canvas.
    for (bx, by, sway, scale) in ((0.14, 1.02, -0.075, 1.0), (0.88, 1.03, 0.065, 0.88)):
        x0, y0 = W * bx, H * by
        trunk_h = H * 0.52 * scale
        pts_l, pts_r = [], []
        for k in range(15):
            t = k / 14.0
            tx = x0 + W * sway * (t ** 1.6)
            ty = y0 - trunk_h * t
            tw = W * (0.017 - 0.009 * t) * scale
            pts_l.append((tx - tw, ty))
            pts_r.append((tx + tw, ty))
        dp.polygon(pts_l + pts_r[::-1], fill=silh)
        cxp = (pts_l[-1][0] + pts_r[-1][0]) / 2.0
        cyp = pts_l[-1][1]
        for ang in (-172, -140, -108, -72, -40, -8, 20, 200):
            _leaf(dp, cxp, cyp, ang, W * 0.26 * scale, W * 0.034 * scale, silh,
                  curve=0.34 if ang < -90 else -0.34)
        dp.ellipse([cxp - W * 0.016, cyp - W * 0.016, cxp + W * 0.016, cyp + W * 0.016], fill=silh)
        # coconuts
        for (ox, oy) in ((-0.016, 0.012), (0.014, 0.020), (0.000, 0.028)):
            dp.ellipse([cxp + W * ox - W * 0.010, cyp + W * oy - W * 0.010,
                        cxp + W * ox + W * 0.010, cyp + W * oy + W * 0.010], fill=silh)
    paste_rgba(img, palms)

    # Birds + sparkles.
    birds = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dbd = ImageDraw.Draw(birds)
    for (bx, by, s) in ((0.30, 0.16, 1.0), (0.38, 0.21, 0.7), (0.24, 0.24, 0.55)):
        x, y = W * bx, H * by
        sp = W * 0.026 * s
        wgt = max(2, int(W * 0.004 * s))
        dbd.line([(x - sp, y), (x - sp * 0.4, y - sp * 0.5), (x, y)], fill=with_alpha(hx("#3A1B4F"), 200), width=wgt)
        dbd.line([(x, y), (x + sp * 0.4, y - sp * 0.5), (x + sp, y)], fill=with_alpha(hx("#3A1B4F"), 200), width=wgt)
    paste_rgba(img, birds)
    paste_rgba(img, sparkle_layer((W, H), [
        (rnd.uniform(0, W), rnd.uniform(0, H * 0.5), rnd.uniform(W * 0.010, W * 0.028),
         rnd.randint(90, 180), (255, 240, 210)) for _ in range(14)], blur=W * 0.002))

    add_vignette(img, strength=0.42, radius_factor=0.80, tint=hx("#1A0630"))
    img = add_grain(img, 0.12)
    return img.resize((w, h), Image.LANCZOS)


def gen_backgrounds():
    outdir = os.path.join(ASSETS, "backgrounds")
    return [
        save(render_candy_forest(), os.path.join(outdir, "candy_forest.png")),
        save(render_crystal_caves(), os.path.join(outdir, "crystal_caves.png")),
        save(render_sunset_beach(), os.path.join(outdir, "sunset_beach.png")),
    ]


# ---------------------------------------------------------------------------
# UI chrome
# ---------------------------------------------------------------------------

def render_panel(w=400, h=200, ss=3):
    W, H = w * ss, h * ss
    radius = int(W * 0.075)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([W * 0.03, H * 0.07, W * 0.97, H * 0.98],
                                             radius=radius, fill=with_alpha(hx("#160A33"), 165))
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(W * 0.014)))

    body = vertical_gradient((W, H), [(0.0, hx("#4B2C86")), (0.45, hx("#33206B")), (1.0, hx("#1E1148"))])
    body = body.convert("RGBA")
    mask = rounded_mask((W, H), radius, inset=int(W * 0.02))
    panel = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    panel.paste(body, (0, 0), mask)

    # Top gloss.
    gloss = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).rounded_rectangle([W * 0.045, H * 0.05, W * 0.955, H * 0.46],
                                            radius=radius * 0.8, fill=with_alpha((255, 255, 255), 42))
    gloss = gloss.filter(ImageFilter.GaussianBlur(W * 0.008))
    panel = Image.alpha_composite(panel, gloss)

    border = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    db = ImageDraw.Draw(border)
    db.rounded_rectangle([W * 0.02, H * 0.04, W * 0.98, H * 0.96], radius=radius,
                         outline=with_alpha(hx("#A98BFF"), 210), width=max(2, int(W * 0.008)))
    db.rounded_rectangle([W * 0.032, H * 0.065, W * 0.968, H * 0.935], radius=radius * 0.85,
                         outline=with_alpha((255, 255, 255), 60), width=max(1, int(W * 0.003)))
    panel = Image.alpha_composite(panel, border)

    out = Image.alpha_composite(out, panel)
    return out.resize((w, h), Image.LANCZOS)


def render_button(w=300, h=100, ss=3):
    W, H = w * ss, h * ss
    radius = int(H * 0.34)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    paste_rgba(out, radial_glow((W, H), (W / 2, H * 0.5), W * 0.44, hx("#FF9A3C"), 110, power=2.0))

    # Darker plate underneath => the button reads as a physical, pressable key.
    plate = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(plate).rounded_rectangle([W * 0.035, H * 0.20, W * 0.965, H * 0.94],
                                            radius=radius, fill=with_alpha(hx("#B03A1E"), 255))
    out = Image.alpha_composite(out, plate)

    face_box = [W * 0.035, H * 0.08, W * 0.965, H * 0.82]
    grad = vertical_gradient((W, H), [(0.0, hx("#FFD24A")), (0.42, hx("#FF9B2E")), (1.0, hx("#F2621F"))])
    face_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(face_mask).rounded_rectangle(face_box, radius=radius, fill=255)
    face = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    face.paste(grad.convert("RGBA"), (0, 0), face_mask)

    gloss = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).rounded_rectangle([W * 0.07, H * 0.13, W * 0.93, H * 0.44],
                                            radius=radius * 0.8, fill=with_alpha((255, 255, 255), 105))
    gloss = gloss.filter(ImageFilter.GaussianBlur(W * 0.006))
    face = Image.alpha_composite(face, gloss)

    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    de = ImageDraw.Draw(edge)
    de.rounded_rectangle(face_box, radius=radius, outline=with_alpha(hx("#FFF2C4"), 220),
                         width=max(2, int(H * 0.030)))
    edge = edge.filter(ImageFilter.GaussianBlur(H * 0.006))
    face = Image.alpha_composite(face, edge)

    out = Image.alpha_composite(out, face)
    out = Image.alpha_composite(out, sparkle_layer(
        (W, H), [(W * 0.14, H * 0.30, H * 0.20, 190, (255, 255, 255))], blur=H * 0.008))
    return out.resize((w, h), Image.LANCZOS)


def _star_points(cx, cy, r_out, r_in, rot_deg=-90):
    pts = []
    for i in range(10):
        a = math.radians(rot_deg + i * 36.0)
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def render_star(filled, size=64, ss=6):
    S = size * ss
    cx = cy = S / 2.0
    r_out = S * 0.42
    pts = _star_points(cx, cy, r_out, r_out * 0.46)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    if filled:
        glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(glow).polygon(_star_points(cx, cy, r_out * 1.14, r_out * 0.52),
                                     fill=with_alpha(hx("#FFC53C"), 175))
        out = Image.alpha_composite(out, glow.filter(ImageFilter.GaussianBlur(S * 0.045)))

        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).polygon(pts, fill=255)
        grad = vertical_gradient((S, S), [(0.0, hx("#FFF6C0")), (0.42, hx("#FFC93C")), (1.0, hx("#E8850F"))])
        star = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        star.paste(grad.convert("RGBA"), (0, 0), mask)

        inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(inner).polygon(_star_points(cx, cy - S * 0.03, r_out * 0.62, r_out * 0.28),
                                      fill=with_alpha((255, 255, 255), 95))
        star = Image.alpha_composite(star, inner.filter(ImageFilter.GaussianBlur(S * 0.02)))

        outline = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(outline).polygon(pts, outline=with_alpha(hx("#B85E06"), 230),
                                        width=max(2, int(S * 0.018)))
        star = Image.alpha_composite(star, outline)
        out = Image.alpha_composite(out, star)
        out = Image.alpha_composite(out, sparkle_layer(
            (S, S), [(cx - r_out * 0.30, cy - r_out * 0.34, r_out * 0.42, 210, (255, 255, 255))],
            blur=S * 0.006))
    else:
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).polygon(pts, fill=255)
        grad = vertical_gradient((S, S), [(0.0, hx("#5A5570")), (1.0, hx("#33304A"))])
        star = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        star.paste(grad.convert("RGBA"), (0, 0), mask)
        star.putalpha(ImageChops.multiply(star.getchannel("A"), Image.new("L", (S, S), 190)))
        outline = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(outline).polygon(pts, outline=with_alpha(hx("#8E88A8"), 235),
                                        width=max(2, int(S * 0.022)))
        out = Image.alpha_composite(out, star)
        out = Image.alpha_composite(out, outline)
    return out.resize((size, size), Image.LANCZOS)


def render_coin(size=48, ss=8):
    S = size * ss
    cx = cy = S / 2.0
    R = S * 0.44
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    paste_rgba(out, radial_glow((S, S), (cx, cy), R * 1.5, hx("#FFC93C"), 120, power=2.2))

    disc_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(disc_mask).ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
    grad = vertical_gradient((S, S), [(0.0, hx("#FFF0A8")), (0.40, hx("#FFC42E")), (1.0, hx("#C97A08"))])
    coin = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    coin.paste(grad.convert("RGBA"), (0, 0), disc_mask)

    d = ImageDraw.Draw(coin)
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=with_alpha(hx("#9C5C04"), 220),
              width=max(2, int(S * 0.030)))
    d.ellipse([cx - R * 0.76, cy - R * 0.76, cx + R * 0.76, cy + R * 0.76],
              outline=with_alpha(hx("#B87308"), 150), width=max(2, int(S * 0.020)))
    # Embossed gem glyph so the coin is not just a plain disc at 48px.
    d.polygon(place(SHAPES["kite"], cx, cy + R * 0.02, R * 0.42), fill=with_alpha(hx("#FFF3C0"), 235))
    d.polygon(place(SHAPES["kite"], cx, cy + R * 0.02, R * 0.42),
              outline=with_alpha(hx("#A96407"), 200), width=max(1, int(S * 0.012)))

    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse([cx - R * 0.72, cy - R * 0.82, cx + R * 0.10, cy - R * 0.28],
                                  fill=with_alpha((255, 255, 255), 150))
    shine = shine.filter(ImageFilter.GaussianBlur(S * 0.02))
    shine.putalpha(ImageChops.multiply(shine.getchannel("A"), disc_mask))
    coin = Image.alpha_composite(coin, shine)

    out = Image.alpha_composite(out, coin)
    return out.resize((size, size), Image.LANCZOS)


def gen_ui():
    outdir = os.path.join(ASSETS, "ui")
    written = [
        save(render_panel(), os.path.join(outdir, "panel_rounded.png")),
        save(render_button(), os.path.join(outdir, "button_primary.png")),
        save(render_star(True), os.path.join(outdir, "star_filled.png")),
        save(render_star(False), os.path.join(outdir, "star_empty.png")),
        save(render_coin(), os.path.join(outdir, "coin_icon.png")),
        # Currency crystal: same faceted renderer, cyan palette + narrow shard
        # silhouette so it never reads as one of the six playable gems.
        save(render_gem(PALETTES["crystal"], SHAPES["shard"], size=48, ss=8, fill=0.42, seed=91),
             os.path.join(outdir, "crystal_icon.png")),
    ]
    return written


# ---------------------------------------------------------------------------
# App icon + store graphics
# ---------------------------------------------------------------------------

def render_icon(size=512, ss=2):
    """Three overlapping gems on a radial burst. Deliberately only three large
    shapes: at 48px anything finer turns to mush."""
    S = size * ss
    img = Image.new("RGB", (S, S), hx("#3A0F63"))
    grad = vertical_gradient((S, S), [(0.0, hx("#FF3D9A")), (0.40, hx("#8A24DC")), (1.0, hx("#1B0A4E"))])
    img.paste(grad, (0, 0))
    img.paste(Image.new("RGB", (S, S), hx("#FF8AD0")), (0, 0),
              radial_mask((S, S), (S * 0.30, S * 0.22), S * 0.66, power=2.2)
              .point(lambda v: clamp8(v * 0.45)))

    rays = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rays)
    for i in range(16):
        a = math.radians(i * 22.5 + 11)
        spread = math.radians(6.0)
        L = S * 1.6
        dr.polygon([(S / 2, S / 2),
                    (S / 2 + math.cos(a - spread) * L, S / 2 + math.sin(a - spread) * L),
                    (S / 2 + math.cos(a + spread) * L, S / 2 + math.sin(a + spread) * L)],
                   fill=with_alpha((255, 255, 255), 26))
    paste_rgba(img, rays.filter(ImageFilter.GaussianBlur(S * 0.006)))
    paste_rgba(img, radial_glow((S, S), (S / 2, S * 0.54), S * 0.42, hx("#FFFFFF"), 90, power=2.4))

    img = img.convert("RGBA")
    # Kept inside ~0.06 of every edge so the launcher's corner mask never bites
    # into a gem.
    for (pal, shape, px_f, x_f, y_f, rot, seed) in (
            ("sapphire", "cushion", 0.45, 0.305, 0.40, -16, 3),
            ("topaz", "trillion", 0.44, 0.700, 0.38, 14, 4),
            ("ruby", "brilliant", 0.62, 0.500, 0.61, 0, 5)):
        px = int(S * px_f)
        g = render_gem(PALETTES[pal], SHAPES[shape], size=px, ss=2, seed=seed)
        if rot:
            g = g.rotate(rot, resample=Image.BICUBIC, expand=True)
        paste_rgba(img, g, (int(S * x_f - g.width / 2), int(S * y_f - g.height / 2)))

    img = Image.alpha_composite(img, sparkle_layer((S, S), [
        (S * 0.16, S * 0.17, S * 0.085, 225, (255, 255, 255)),
        (S * 0.86, S * 0.16, S * 0.055, 190, (255, 255, 255)),
        (S * 0.80, S * 0.80, S * 0.070, 200, (255, 255, 255)),
        (S * 0.14, S * 0.76, S * 0.045, 170, (255, 255, 255))], blur=S * 0.004))

    img = add_vignette(img.convert("RGB"), strength=0.26, radius_factor=0.78,
                       tint=hx("#1A0640"))
    img = ImageEnhance.Color(img).enhance(1.18).convert("RGBA")
    # Slight rounding so the icon looks intentional even where the launcher
    # doesn't apply its own mask.
    img.putalpha(rounded_mask((S, S), int(S * 0.20)))
    return img.resize((size, size), Image.LANCZOS)


def render_feature_graphic(w=1024, h=500, ss=2):
    """Play Store banner. Gem cluster lives right-of-centre; the left ~55% is
    kept quiet (and slightly darkened) as a title-text safe area."""
    W, H = w * ss, h * ss
    rnd = random.Random(707)
    # Left-to-right blend of the three episode palettes.
    img = horizontal_gradient((W, H), [
        (0.00, hx("#16A75E")), (0.15, hx("#D93E90")), (0.40, hx("#6B2FC4")),
        (0.66, hx("#2F4CC4")), (0.85, hx("#F0578F")), (1.00, hx("#FFA83C"))])
    img.paste(Image.new("RGB", (W, H), hx("#0E0733")), (0, 0),
              vertical_gradient((W, H), [(0.0, (14, 14, 14)), (1.0, (72, 72, 72))]).convert("L"))

    img.paste(Image.new("RGB", (W, H), hx("#FF6FC0")), (0, 0),
              radial_mask((W, H), (W * 0.74, H * 0.42), W * 0.44, power=2.0)
              .point(lambda v: clamp8(v * 0.5)))
    img.paste(Image.new("RGB", (W, H), hx("#3ED8FF")), (0, 0),
              radial_mask((W, H), (W * 0.10, H * 0.76), W * 0.32, power=2.0)
              .point(lambda v: clamp8(v * 0.42)))
    img.paste(Image.new("RGB", (W, H), hx("#FFB347")), (0, 0),
              radial_mask((W, H), (W * 0.16, H * 0.10), W * 0.26, power=2.2)
              .point(lambda v: clamp8(v * 0.34)))

    rays = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(rays)
    for i in range(18):
        a = math.radians(i * 20 + 6)
        spread = math.radians(3.5)
        L = W * 1.2
        ox, oy = W * 0.76, H * 0.46
        dr.polygon([(ox, oy),
                    (ox + math.cos(a - spread) * L, oy + math.sin(a - spread) * L),
                    (ox + math.cos(a + spread) * L, oy + math.sin(a + spread) * L)],
                   fill=with_alpha((255, 255, 255), 22))
    paste_rgba(img, rays.filter(ImageFilter.GaussianBlur(W * 0.004)))
    paste_rgba(img, radial_glow((W, H), (W * 0.76, H * 0.48), W * 0.20, hx("#FFFFFF"), 120, power=2.4))

    img = img.convert("RGBA")
    cluster = (
        ("amethyst", "marquise", 0.135, 0.615, 0.24, -18, 11),
        ("emerald", "emerald", 0.140, 0.905, 0.30, 12, 12),
        ("sapphire", "cushion", 0.165, 0.680, 0.68, -8, 13),
        ("diamond", "kite", 0.150, 0.855, 0.72, 10, 14),
        ("topaz", "trillion", 0.175, 0.930, 0.50, -6, 15),
        ("ruby", "brilliant", 0.235, 0.770, 0.50, 0, 16),
    )
    for (pal, shape, px_f, x_f, y_f, rot, seed) in cluster:
        px = int(H * px_f * 2.2)
        g = render_gem(PALETTES[pal], SHAPES[shape], size=px, ss=2, seed=seed)
        if rot:
            g = g.rotate(rot, resample=Image.BICUBIC, expand=True)
        paste_rgba(img, g, (int(W * x_f - g.width / 2), int(H * y_f - g.height / 2)))

    img = Image.alpha_composite(img, sparkle_layer((W, H), [
        (rnd.uniform(W * 0.58, W * 0.99), rnd.uniform(H * 0.05, H * 0.95),
         rnd.uniform(W * 0.006, W * 0.020), rnd.randint(140, 230), (255, 255, 255))
        for _ in range(18)] + [
        (rnd.uniform(0, W * 0.5), rnd.uniform(0, H), rnd.uniform(W * 0.004, W * 0.010),
         rnd.randint(70, 130), (255, 255, 255)) for _ in range(10)], blur=W * 0.002))

    img = img.convert("RGB")
    # Title safe area: a soft scrim keeps future text legible over the gradient.
    scrim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(scrim).rectangle([0, 0, W * 0.52, H], fill=with_alpha(hx("#0B0428"), 78))
    scrim = scrim.filter(ImageFilter.GaussianBlur(W * 0.05))
    paste_rgba(img, scrim)

    add_vignette(img, strength=0.26, radius_factor=0.86, tint=hx("#100430"))
    img = ImageEnhance.Color(img).enhance(1.16)
    img = add_grain(img, 0.10)
    return img.resize((w, h), Image.LANCZOS)


def gen_icons():
    icon = render_icon()
    return [save(icon, os.path.join(ASSETS, "icons", "icon.png"))]


def gen_store():
    icon = render_icon()
    return [
        save(icon, os.path.join(STORE, "icon-512.png")),
        save(render_feature_graphic(), os.path.join(STORE, "feature-graphic.png")),
    ]


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG", optimize=True)
    rel = os.path.relpath(path, ROOT)
    print("  %-44s %dx%d" % (rel, img.size[0], img.size[1]))
    return path


GROUPS = {
    "gems": gen_gems,
    "particles": gen_particles,
    "backgrounds": gen_backgrounds,
    "ui": gen_ui,
    "icons": gen_icons,
    "store": gen_store,
}


def main(argv):
    wanted = argv[1:] or list(GROUPS.keys())
    unknown = [g for g in wanted if g not in GROUPS]
    if unknown:
        print("Unknown group(s): %s\nAvailable: %s" % (", ".join(unknown), ", ".join(GROUPS)))
        return 2
    total = []
    for name in wanted:
        print("[%s]" % name)
        total.extend(GROUPS[name]())
    print("\nGenerated %d file(s)." % len(total))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
