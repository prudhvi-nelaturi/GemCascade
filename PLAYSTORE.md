# Play Store Launch Kit — GemCascade

Everything needed to ship. Build is produced locally via
`godot --headless --export-release "Android" build/GemCascade-v1.0.0.aab` (see
[EXPORT_SETUP.md](EXPORT_SETUP.md) for the one-time machine setup this needs); the
console steps below are done at [play.google.com/console](https://play.google.com/console)
with `prudhvinelaturi29@gmail.com` (same account as NexusHub, ChaiTapriTycoon, and
GlassRush).

## ⚠️ The path to production (same as the rest of the portfolio)

Personal dev accounts must pass a closed test **per app** before production:

1. **Create app** in Play Console → upload the `.aab` to **Internal testing** (instant,
   no review wait) → sanity-check on a real device.
2. Promote to **Closed testing** → recruit **12 testers** who stay opted in **14
   consecutive days**. (Reuse the tester group from the rest of the portfolio.)
3. After 14 days → **Apply for production** → full rollout.

## App details

| Field | Value |
|---|---|
| App name | `GemCascade` |
| Package | `com.prudhvinelaturi.gemcascade` |
| Default language | English (India) — `en-IN` |
| App or game | Game |
| Category | Puzzle |
| Free/paid | Free |
| Contains ads | **No** (none integrated yet — update this when AdMob lands, see TODO.md) |
| In-app purchases | No |
| Privacy policy URL | `https://prudhvi-nelaturi.github.io/GemCascade/privacy.html` |
| Contact email | `prudhvinelaturi29@gmail.com` |

## Store listing copy

**Short description** (70/80 chars):
> Match, cascade, combo. 24 levels across 3 dazzling worlds.

**Full description:**

> 💎 Swap. Match. Cascade. Combo.
>
> GemCascade is a fast, colorful match-3 puzzle — swap gems to match 3 or more,
> chain cascades for bigger combos, and blast through 24 hand-tuned levels across
> three glittering worlds.
>
> 🔮 SHATTER OR CASCADE
> Match 4 for a striped gem that clears a whole row or column. Match 5 in an L or T
> for a wrapped gem that blasts a 3×3 area. Match 5 in a line for a color bomb that
> clears every gem of one color. Combine two specials for an even bigger blast.
>
> 🗺️ THREE WORLDS, 24 LEVELS
> Journey from Candy Forest to Crystal Caves to Sunset Beach. Every level is a
> different challenge — hit a score target, collect specific gems, or clear every
> blocker — with 1-3 stars to chase on each one.
>
> ⚡ BOOST YOUR RUN
> Earn coins from every level and spend them on boosters: extra moves, a hammer to
> clear a stuck gem, or a starting color bomb for levels that need a head start.
>
> ✨ FREE & OFFLINE
> No account. No internet needed. Just you, the gems, and how far your cascades can go.
>
> How high can your combo climb?

## Graphics checklist

| Asset | Spec | File |
|---|---|---|
| App icon | 512×512 PNG | `store/icon-512.png` ✅ |
| Feature graphic | 1024×500 PNG | `store/feature-graphic.png` ✅ |
| Phone screenshots | ≥2, PNG/JPG, 16:9 or 9:16 | **Not yet captured** — take these from a real device or the Godot editor's play window running actual gameplay. See TODO.md. |

## Console questionnaires

**Content rating (IARC):** questionnaire → Game. Answer **No** to everything: no
violence (matching colored gems, not characters), no sexuality, no language, no
controlled substances, no gambling (coins/crystals are earned in-game only, never
cashed out), no user interaction/UGC, no data sharing, no location. Expected rating:
Everyone / 3+.

**Data safety:** "Does your app collect or share any of the required user data types?"
→ **No**. All progress is stored locally on-device via Godot's `ConfigFile`; no
analytics, no ads, no accounts. (Matches the privacy policy. Update BOTH when
ads/analytics land.)

**Target audience:** 13+ (do NOT tick under-13 — opts into the Families program and
its extra requirements).

**App access:** All functionality is available without special access (no login).

**Ads declaration:** No ads.

## Upload path

Console UI: Internal testing → Create release → upload the `.aab` from
`build/GemCascade-v1.0.0.aab` → roll out.

## Release notes (v1.0.0)

> First release! Match gems, chain cascades, blast through specials, and climb from
> Candy Forest to Crystal Caves to Sunset Beach across 24 levels.

## Post-launch reminders

- When AdMob is added: flip "Contains ads" to Yes, update data safety + privacy policy.
- Play Console → Statistics is the retention dashboard: **D7 > ~10% = keep pushing;
  below = tune or move to the next portfolio experiment.**
- `version/code` must be bumped manually per release (`export_presets.cfg`
  `preset.0.options` → `version/code`) — no CI auto-increment set up for this project.
