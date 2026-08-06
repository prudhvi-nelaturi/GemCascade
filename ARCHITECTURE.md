# Architecture — GemCascade 💎

An endless-progression match-3 puzzle built in Godot 4.7 (GDScript). Pure grid/level
logic is kept separate from rendering and from the meta-progression UI, mirroring the
"logic separate from rendering/storage" philosophy used across the whole game
portfolio (GlassRush's `GameEngine.java`, ChaiTapriTycoon's `engine.js`).

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Engine | Godot 4.7.1 | Free, mature 2D engine with native particles/tweens/shaders — the direct lever for "more colored, more dopamine" vs. GlassRush's flat `ShapeRenderer` shapes |
| Language | GDScript | Godot's native scripting language; `.tscn`/`.tres` are plain text, fully authorable without the editor GUI |
| Art tooling | Python + Pillow | Real gradient/glow/facet rendering for procedural art — a step up from GlassRush's hand-rolled stdlib PNG writer |
| Persistence | Godot `ConfigFile` (`user://save.cfg`) | Local save; no backend, same $0-hosting philosophy as the rest of the portfolio |
| Export | `godot --headless --export-debug/--export-release` | No Android Studio, no emulator in this dev environment — see [EXPORT_SETUP.md](EXPORT_SETUP.md) for the (nontrivial) one-time setup |

No backend, no accounts, no third-party ad/billing SDK wired yet (see stubs below).

---

## Module layout

```
GemCascade/
├── project.godot           autoloads: Economy, AdManager, BillingManager, LevelManager
├── scripts/
│   ├── board/               Board.gd, GemData.gd, GemTypes.gd — pure grid logic
│   ├── level/                LevelData.gd (Resource), LevelManager.gd (autoload)
│   ├── economy/               Economy.gd (autoload)
│   ├── ads/, billing/         AdManager.gd / BillingManager.gd (autoloads, NoOp stubs)
│   ├── gameplay/              GameplayController.gd, BoardView.gd, GemView.gd, GemArt.gd, GameplayHud.gd
│   ├── ui/                    MainMenu, LevelMap, Shop, Settings, LevelComplete, LevelFail + UITheme
│   └── tests/                 run_tests.gd, run_gameplay_smoke.gd, run_ui_smoke.gd
├── scenes/                  MainMenu.tscn, LevelMap.tscn, Gameplay.tscn, Shop.tscn, Settings.tscn, LevelComplete.tscn, LevelFail.tscn
├── levels/                  level_001.tres .. level_024.tres + LEVEL_DESIGN_NOTES.md
├── assets/                  generated gems/particles/backgrounds/ui/icons (via scripts_gen/gen_assets.py)
├── scripts_gen/gen_assets.py  Pillow-based art generator — the visual design surface
├── store/, docs/            Play Store graphics + privacy policy (GitHub Pages)
└── build/                   signed release .aab lands here (gitignored)
```

---

## `scripts/board/` — pure grid logic, no rendering

`Board.gd` (`class_name Board extends RefCounted`) owns a 2D grid of `GemData` (color +
special-kind). Key API:

- `fill_initial()` — fills with no pre-existing matches, retrying until at least one
  legal move exists (`has_any_valid_move()`); `shuffle()` re-scrambles a stuck board.
- `try_swap(r1,c1,r2,c2)` — adjacency + match validation, auto-reverts illegal swaps.
  Swapping a special gem always "succeeds" (it detonates instead of matching).
- `find_matches()` — scans rows/columns for runs ≥3, then **merges overlapping runs of
  the same color into groups** so an L/T-shaped match (a horizontal run crossing a
  vertical run) is seen as one connected shape, not two separate matches. This is what
  makes special-gem shape classification (striped vs. wrapped vs. color bomb) correct.
- `resolve_all()` — the full cascade loop: find matches → clear + create specials →
  detonate any specials swept into the clear (chain reaction) → gravity + refill →
  repeat until stable. Returns one event Dictionary per cascade tier (`cleared`,
  `specials_created`, `color_counts`, `cascade_index`) so the rendering layer can
  animate each tier separately and escalate juice by cascade depth.
- `detonate_combo(r1,c1,r2,c2)` — the explicit "two specials swapped together" blast
  (color bomb + color bomb clears the whole board; color bomb + anything clears that
  color; striped/wrapped combos union their detonation areas). `try_swap()` alone
  wouldn't catch this case since no color-match forms.

**GameplayController.gd does NOT call `resolve_all()` directly** — it drives cascades
one tier at a time (`find_matches()` → animate → gravity → repeat) so it can decide new
gem colors and time animations per tier, while still mirroring `resolve_all()`'s exact
scoring/cascade-index semantics.

---

## `scripts/level/` — objectives, deliberately decoupled from Economy

`LevelData.gd` (`Resource`, `.tres` per level) is the level design surface: grid size,
gem-type count, move limit, objective type (`SCORE` / `COLLECT_COLOR` / `CLEAR_BLOCKERS`),
target, blocker cell layout, star thresholds.

`LevelManager.gd` (autoload) tracks the *runtime* state of the current level — moves,
score, objective progress — and emits `level_won(stars, score, coins_earned)` /
`level_lost`. **It deliberately does not touch the `Economy` autoload itself** — crediting
a win is the integration layer's job (see below), which is what keeps `LevelManager`
testable with a bare `.new()` instance and no autoload bootstrap required.

**Blocker-clear rule (previously ambiguous, now fixed):** a blocker is cleared by an
**exact-cell** match — one of a cascade step's `cleared` cells is the blocker's own
cell, not merely adjacent to it. All 24 levels are calibrated against this rule
(verified via ~6,000 simulated bot games). See the comment in `LevelData.gd` if this
ever needs revisiting — changing it requires rebalancing every `CLEAR_BLOCKERS` level.

---

## Economy crediting — who pays out, exactly once

Both `GameplayController.gd` and `scripts/ui/LevelComplete.gd` are capable of calling
`Economy.record_level_result()` / `Economy.unlock_next_level()`. Exactly one of them
does it per win, decided at **runtime**:

- `GameplayController._go_to_result_scene()` hands the win payload to
  `LevelCompleteScreen.pending_result` (a static var) if that scene declares the
  contract. `LevelComplete.gd`'s `_ready()` then credits Economy itself, exactly once.
- If the target scene doesn't exist or doesn't implement `pending_result`,
  `GameplayController._credit_economy_once()` credits it directly as a fallback (also
  used for the in-scene fallback result panel if `LevelComplete.tscn` is ever missing).

This runtime probe (rather than a hardcoded assumption of which side owns it) is what
prevents a double-payout bug that showed up during integration — two agents building
the gameplay screen and the meta-UI screen in parallel each initially assumed *they*
owned crediting. Don't "simplify" this by hardcoding one side without checking both
`GameplayController.gd` and `LevelComplete.gd`'s current logic first.

---

## `scripts/gameplay/` — the playable screen

Entry contract: set `GameplayController.pending_level_number = N` then
`get_tree().change_scene_to_file("res://scenes/Gameplay.tscn")`.

`BoardView.gd` keeps a sprite mirror of the grid so it can animate *between* board
states rather than snapping instantly: tween-based swap/shake-back, staggered
clear+particle-burst per cascade tier, gravity/fall tweens, pop-in for newly created
specials, screen shake + full-screen flash scaled by cascade depth, an escalating combo
popup. `GemArt.gd` resolves gem/overlay textures from `assets/gems/` with procedural
fallbacks so the scene runs even before art assets exist.

Both control schemes are supported: drag-to-steer and tap-tap (tap a gem, tap an
adjacent gem). Boosters (`Economy.BOOSTER_EXTRA_MOVES/HAMMER/COLOR_BOMB_START`) are
wired in; a stuck board (`not board.has_any_valid_move()`) triggers `board.shuffle()`
with a toast.

---

## `scripts/ui/` — meta-progression

Screens are built in code (data-driven off episode colors, live currency, live
progress) rather than hand-authored in `.tscn` files — editing large scene files
without the editor GUI is far more error-prone than composing layout procedurally.
Shared `UITheme` (palette, buttons, tweens, toasts) and small procedural icon helpers
(`StarIcon`, `LockIcon`, `CircleIcon`, `BurstRing`) keep the six screens visually
consistent. `LevelComplete.tscn`'s star-reveal (stars landing one at a time with
shockwave rings + confetti) is the single highest-effort "dopamine moment" screen —
treat it as the benchmark for polish elsewhere.

Handoff contracts (all consumed/cleared on read, so a reload can't double-credit or
inherit stale state):
```
GameplayController.pending_level_number = int
LevelCompleteScreen.pending_result = {"level_number": int, "stars": int, "score": int, "coins_earned": int}
LevelFailScreen.pending_result     = {"level_number": int, "score": int, "progress": float}
LevelFailScreen.pending_level_number = int   # fallback if pending_result is empty
LevelMapScreen.focus_level_number  = int     # 0 = auto (furthest unlocked episode)
```

---

## `scripts/ads/`, `scripts/billing/`

`AdManager`/`BillingManager` interfaces + `NoOpAdManager`/`NoOpBillingManager` — what
ships in v1. Real AdMob/Play Billing implementations are launch-blocker TODOs (need
Prudhvi's own AdMob account + a configured in-app product — can't be created on his
behalf). See [TODO.md](TODO.md).

---

## Testing — three independent suites, no external framework

Same "hand-rolled assert runner" philosophy as GlassRush's plain-JUnit choice, just
without even JUnit since GDScript isn't the JVM:

- `scripts/tests/run_tests.gd` — pure logic: `Board`, `LevelData`, `LevelManager`,
  `Economy` (all instantiated standalone via `load(...).new()`, no autoload bootstrap
  needed — this is *why* `LevelManager` was deliberately decoupled from `Economy`).
  311+ assertions, includes boundary/edge-case coverage (corner detonations, T-shapes,
  shuffle invariants) verified via deliberate mutation testing (bugs injected on
  purpose, confirmed the relevant test catches each one).
- `scripts/tests/run_gameplay_smoke.gd` — instantiates the real `Gameplay.tscn` scene
  and drives it: both input gestures, all three boosters, blocker accounting, reshuffle,
  win/loss handoff, exactly-once economy crediting, all 24 levels booting and fitting
  the viewport. 282 assertions.
- `scripts/tests/run_ui_smoke.gd` — opens each meta-UI scene headless, probes control
  rects for viewport overflow. 36 assertions. **Note:** `godot --headless --check-only`
  cannot validate any script that touches an autoload (autoloads aren't registered in
  that mode) — that's why these are real instantiate-and-run smoke tests, not just
  static syntax checks.

Run all three before considering any change to core systems done:
```bash
godot --headless --script res://scripts/tests/run_tests.gd
godot --headless --script res://scripts/tests/run_gameplay_smoke.gd
godot --headless --script res://scripts/tests/run_ui_smoke.gd
```

If you add any new `class_name` script, run `godot --headless --editor --quit-after 1`
once first — Godot's global class-name cache is stale otherwise and new class names
resolve as "Identifier not found" parse errors that look like real bugs but aren't.

---

## Notable decisions

- **Combo builds on shatter/cascade, not on merely surviving** — same risk/reward
  philosophy as GlassRush: a cascade chain is a skill/luck outcome worth rewarding, not
  an automatic tick.
- **`LevelManager` has zero Economy dependency** — a deliberate architecture choice made
  after discovering autoload globals aren't resolvable when a script is unit-tested
  outside the running project tree in `--script` mode. This is *why* it's cleanly
  testable; don't reintroduce an `Economy` reference into `LevelManager.gd` without
  re-checking this.
- **`GemColor` is not named `Color`** — Godot has a built-in `Color` (RGBA) class;
  naming the gem-color enum `Color` inside `GemTypes` caused unresolvable parser
  ambiguity. Keep it `GemColor`.
- **Each gem color gets a different facet cut** (round/cushion/emerald/trillion/marquise/
  kite), not just a different fill color — the cheapest accessibility win available in a
  match-3 (colorblind players can tell gems apart by silhouette).
- **`store/.gdignore`** exists so the Play Store listing graphics (feature graphic etc.)
  don't get imported as game textures and bundled into the shipped APK.

---

## Run & verify

```bash
godot --headless --script res://scripts/tests/run_tests.gd
godot --headless --script res://scripts/tests/run_gameplay_smoke.gd
godot --headless --script res://scripts/tests/run_ui_smoke.gd
godot --headless --export-debug "Android" build/debug-check.apk   # see EXPORT_SETUP.md first
```
