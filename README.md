# GemCascade 💎

An endless-progression match-3 puzzle. Portfolio experiment #3 in the "earn money by
leveraging AI" / game-portfolio plan (experiment #1 is
[Chai Tapri Tycoon](https://github.com/prudhvi-nelaturi/chaiTapriTycoon), idle-merge;
experiment #2 is [GlassRush](https://github.com/prudhvi-nelaturi/GlassRush), an arcade
smasher). Built in **Godot 4.7 (GDScript)** — a deliberate step up in both engine and
genre ambition: "more complex, more colored, more dopamine" than the prior two.

## The loop

Swap adjacent gems to match 3+ of the same color. Matches clear, gems cascade down,
new ones spawn from the top. Match 4 in a line creates a **striped** gem (clears a row
or column); match 5 in an L/T shape creates a **wrapped** gem (clears a 3×3 blast);
match 5 in a line creates a **color bomb** (clears every gem of one color). Combine two
specials together for a bigger blast. Cascading chains and shattering specials build a
**combo multiplier**; dodging via a safe match resets nothing — cascades are the whole
point.

Levels have one of three objectives (score target / collect N of a color / clear all
blockers) within a move limit, star-rated 0-3, spread across 3 themed episodes (Candy
Forest → Crystal Caves → Sunset Beach) on a level map. Earn **coins** per level, spend
them in the Shop on boosters (extra moves, a hammer, a starting color bomb) and
**crystals** are reserved for future IAP.

## Run it

No Android emulator in this dev environment — the fastest way to iterate is running the
project directly in the Godot editor on a real machine, or via the desktop debugger:

```bash
cd "GemCascade"
godot .                      # opens in the editor, press Play
```

Run the test suites (pure logic + integration smoke tests, no display needed):

```bash
godot --headless --script res://scripts/tests/run_tests.gd            # 311+ core logic tests
godot --headless --script res://scripts/tests/run_gameplay_smoke.gd   # 282 gameplay integration tests
godot --headless --script res://scripts/tests/run_ui_smoke.gd         # 36 UI smoke tests
```

Build an Android APK/AAB — see [EXPORT_SETUP.md](EXPORT_SETUP.md) for the one-time
machine setup (this took real effort to get working headlessly; don't redo that work).

## Code map

- `scripts/board/` — `Board.gd` (grid state, match-detection, cascade resolution,
  special-gem creation/detonation — pure logic, no rendering) + `GemData.gd`/`GemTypes.gd`.
- `scripts/level/` — `LevelData.gd` (the level design surface, one `.tres` per level) +
  `LevelManager.gd` (objective tracking, win/lose — deliberately has no Economy
  dependency, stays testable in isolation).
- `scripts/economy/Economy.gd` — coins/crystals/boosters + persistence, autoload singleton.
- `scripts/gameplay/` — `GameplayController.gd` + `BoardView.gd` + `GemView.gd`/`GemArt.gd`
  + `GameplayHud.gd` — the actual playable screen: input, animation, juice (particles,
  screen shake, combo popups).
- `scripts/ui/` — MainMenu, LevelMap, Shop, Settings, LevelComplete, LevelFail + shared
  `UITheme`/icon helpers.
- `scripts/ads/`, `scripts/billing/` — `AdManager`/`BillingManager` interfaces + `NoOp`
  implementations. **Stubbed for v1** — see [TODO.md](TODO.md).
- `levels/` — 24 hand-authored (and bot-simulated for balance) level resources across 3
  episodes. See `levels/LEVEL_DESIGN_NOTES.md` for the difficulty-curve reasoning.
- `scripts_gen/gen_assets.py` — Pillow-based generator for every gem/particle/background/
  UI/icon asset. Re-runnable any time the art needs tweaking.
- `scripts/tests/` — three independent test suites (core logic, gameplay integration, UI
  smoke), no external test framework, hand-rolled assert runners.

## What's stubbed (wire before real launch)

See [TODO.md](TODO.md) — rewarded ads, IAP for Crystals, and real device/touch-feel
testing are the big ones, same "flag before launch" discipline as the rest of the
portfolio.

## The only metric that matters: retention

Ship to a Play Store closed track, drive installs from Reels/WhatsApp, watch the curve.
Same D1/D7/D30 retention bar as the rest of the portfolio — see
[ChaiTapriTycoon's README](https://github.com/prudhvi-nelaturi/chaiTapriTycoon) for the
target numbers. **If a few tuning passes can't get D7 over ~10%, kill it and try the
next concept** — that's the portfolio plan working, not failing.

## India policy note

No real-money/wagering mechanics — India restricted/banned online money-gaming (~2025
legislation). Coins/Crystals are earned or (eventually) purchased outright for cosmetic/
convenience items only, never cashable out; verify current official rules before adding
anything money-game-adjacent.
