# TODO — GemCascade 💎

Status: **complete, tested core game.** Match/cascade/special-gem engine, 24
sim-balanced levels across 3 episodes, full meta-progression (level map, shop,
economy, boosters), juice (particles/shake/combo popups/star-reveal), and a verified
headless Android export pipeline all work end-to-end (629 passing assertions across 3
test suites). What's left, roughly in priority order.

---

## 🔴 Before any real launch (the stubs)

- [ ] **Rewarded ads (AdMob).** `scripts/ads/NoOpAdManager` always reports "not ready."
      Needs Prudhvi's own AdMob account + a GemCascade app entry + real ad unit IDs,
      then a real `AndroidAdManager` implementation.
- [ ] **In-app purchases.** `scripts/billing/NoOpBillingManager` — no real SKUs. Needs
      at least one Crystals pack configured in Play Console, then a Play Billing-backed
      implementation.
- [ ] **Real device testing.** All testing so far is headless (no emulator/display in
      this dev environment) — confirm touch feel, animation timing, performance, and
      screen-size scaling on an actual phone before shipping. `BoardView.gd`'s animation
      timing constants are explicitly flagged by the agent who built them as needing a
      real-device tuning pass.
- [ ] **Generate a release keystore + signed `.aab`.** See EXPORT_SETUP.md — the debug
      export pipeline is verified working; release signing is the next mechanical step.

## 🟠 Retention (highest-impact next feature)

- [ ] **Daily bonus / streak.** GemCascade currently has no "come back tomorrow" hook
      beyond wanting to beat your best score or continue the level map — the single
      strongest retention lever in ChaiTapriTycoon and worth porting here.
- [ ] **Push notifications** for the daily bonus, once it exists.
- [ ] **More levels.** 24 is enough to prove the loop, not enough to sustain D30 — hit
      games run 100+. `scripts_gen`-style tooling for level authoring (or another bot-
      simulated batch like the first 24) is the way to scale this without hand-tuning
      each one blind.

## 🌐 Community & social (shared portfolio playbook)

- [ ] **Leaderboard** (global + friends) — Firebase/Supabase free tier, same
      cheapest-hook approach as the rest of the portfolio. Pick one across all three
      games, don't hand-roll servers.
- [ ] **Weekly tournament / seasonal reset.**
- [ ] **Friend invites / referral** via WhatsApp share.

**Sequencing:** prove single-player retention first (D7 > ~10%) before building any of
the above.

## 🟡 Game design & balance

- [ ] **Real-device balance pass.** The 24 levels were calibrated via ~6,000 simulated
      bot games (see `levels/LEVEL_DESIGN_NOTES.md`), not human playtests — a bot's
      "optimal-ish" play isn't identical to how a real player experiences difficulty.
      Expect to retune move limits / thresholds after the first real playtests.
- [ ] **More special-gem combos.** The current combo matrix (striped+striped,
      striped+wrapped, wrapped+wrapped, color-bomb combos) covers the genre basics;
      hit games often add more exotic combos over time.
- [ ] **Reinforced/multi-hit blockers** for variety (currently blockers clear in one
      exact-cell match — see the note in `LevelData.gd` before changing this, it's a
      calibrated design decision, not an oversight).

## 🟢 Polish

- [ ] **`panel_rounded.png`/`button_primary.png` are generated but currently unused** —
      the UI layer uses `StyleBoxFlat` per-screen colors instead (each card is a
      different saturated color; one tinted 9-patch couldn't carry that). Either wire
      these textures in somewhere they'd actually help, or drop them from
      `gen_assets.py` to avoid generating unused assets.
- [ ] **Capture real gameplay screenshots** for the Play Store listing — none exist yet.
      Once running on a real device or via the Godot editor's play window, capture a
      few from actual gameplay (not the store's promotional icon/feature-graphic art).

## 📋 Ship & measure

- [ ] Generate a release keystore, build the signed `.aab` (see EXPORT_SETUP.md).
- [ ] Play Console: Internal testing → Closed testing (12 testers / 14 days, same
      per-app requirement as the rest of the portfolio) → Production. See
      [PLAYSTORE.md](PLAYSTORE.md).
- [ ] Drive ~100-300 installs from Reels/WhatsApp.
- [ ] Watch retention — **D7 is the go/no-go**: >~10% = tune & push, <~10% = kill and
      move to the next portfolio concept.

## ⚠️ Policy

- [ ] **Avoid real-money/wagering mechanics** — India restricted/banned online
      money-gaming (~2025). Coins/Crystals stay earn-or-buy-only, never cashable out;
      verify current official rules before adding anything money-game-adjacent.

---

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the code is organized,
[EXPORT_SETUP.md](EXPORT_SETUP.md) for the Android build toolchain, and
[README.md](README.md) for run instructions + the retention framework.
