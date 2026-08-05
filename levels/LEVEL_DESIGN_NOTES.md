# GemCascade — Level Design Notes

24 hand-tuned levels across 3 episodes of 8. Each level is a `LevelData`
resource at `levels/level_XXX.tres`; this doc explains *why* the numbers are
what they are so the curve can be re-tuned without reverse-engineering it from
24 files.

## Two engine facts that drive every number here

**1. Score is `cleared_gems * 60 * (1 + cascade_index * 0.5)`.**
Cascades — not raw clears — are the scoring lever. A tier-2 cascade pays double
a tier-0 one, so score targets implicitly ask the player to set up chains.

**2. A SCORE level ends the *instant* `score >= objective_target`.**
This is the non-obvious one. `LevelManager._check_end_conditions()` fires on
every cascade step, so on a SCORE level the run stops the moment the target is
crossed — the final score is always `target + overshoot from the last step`.

That has a sharp consequence for stars: **a 3-star threshold set below the
target would be awarded on literally every win.** So on SCORE levels the 3-star
bar is set *above* `objective_target` (roughly +10-18%), reachable only when the
winning move is a fat multi-tier cascade that blows through the line rather than
creeping over it. 1- and 2-star bars sit below target as progress markers.
On COLLECT_COLOR / CLEAR_BLOCKERS levels score accrues independently of the
objective, so thresholds there are scaled off the move budget instead.

## How the thresholds were calibrated

Not guessed — measured. A throwaway harness drove the real `Board` engine for
~6,000 simulated games (a random-legal-move bot as a skill *floor*, and a
colour-hunting bot as a rough skill *ceiling*). Three findings reshaped the
numbers:

**Colour count dominates scoring rate.** ~600-630 score/move on 5-colour boards
versus only ~370-440 on 6-colour boards. Dropping one colour is a far bigger
difficulty swing than it looks, which is why `gem_type_count` is the primary
early-game training wheel and the main "breather" lever later.

**COLLECT_COLOR targets have a hard ceiling far lower than intuition suggests.**
Even a bot actively hunting the objective colour only nets **~0.95 target
gems/move on a 6-colour board** (~1.5 on 5-colour). The first draft of this set
used 1.7-2.1 gems/move and simulated at a **0% win rate across six levels** —
they were not hard, they were unwinnable. Targets now run 0.92/move (L10, the
first 6-colour collect level) up to 1.15/move (L24, the finale), which sits
under the estimated human ceiling of ~1.25 while still demanding focused play.

**Corner cells are structurally unreachable.** L11's original layout put blockers
in the four true board corners and simulated at a 30% win rate for reasons that
have nothing to do with intended difficulty — corners simply participate in
fewer matches. The brackets are now inset one cell, which preserves the visual
read and lifts it to ~92%.

Star bars are then set so the bot's *median* run lands on **2 stars**, leaving
3 stars as a genuine skill bar rather than a participation trophy.

## Episode structure

| Episode | Levels | Role |
| --- | --- | --- |
| **Candy Forest** | 1-8 | Onboarding. 5 colours, roomy move budgets. Introduces one objective type at a time: SCORE (1-2), COLLECT_COLOR (3), CLEAR_BLOCKERS (5). Level 7 is the first 6-colour board — a deliberate step, not a drift. |
| **Crystal Caves** | 9-16 | 6 colours become the norm. Blocker patterns get geometrically awkward, collect ratios tighten. Grid size starts varying (9x9 at 12, 7x7 at 15). |
| **Sunset Beach** | 17-24 | Tight budgets and the hardest ratios. Level 22 is the squeeze point (18 moves, 6 colours). Level 23 spreads its blockers widest. Level 24 is the hardest level in the game. |

## Pacing principles applied

- **Sawtooth, not a ramp.** Difficulty steps up then briefly releases, so the
  curve has texture. Explicit breathers: **L9** (opens Crystal Caves by dropping
  back to 5 colours right after the L8 episode finale), **L14** (5 colours), and
  **L20** (big forgiving 9x9 at 5 colours, sitting between the hard L19 and the
  even harder L21/L22). Each breather follows a spike.
- **Never two consecutive levels with the same objective type.** No two adjacent
  levels share an objective, so consecutive sessions always feel different.
- **Grid variety for texture.** 19 levels are 8x8; 7x7 appears at L6 and L15
  (smaller, more frantic, fewer escape routes) and 9x9 at L12, L20, L23 (longer,
  more cascade-friendly).
- **Every blocker layout is a distinct, intentional shape** — no random scatter.

## The resulting curve, measured

Bot win rate per level (colour-hunting bot, 40 runs each). Lower = harder. This
is a *proxy*, not a human difficulty prediction — the bot is deliberately crude,
so treat the shape as signal and the absolute numbers as a floor.

| Episode | L1 | L2 | L3 | L4 | L5 | L6 | L7 | L8 | avg |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Candy Forest (1-8) | 100 | 100 | 90 | 100 | 100 | 80 | 98 | 93 | **95%** |
| Crystal Caves (9-16) | 100 | 50 | 93 | 95 | 50 | 98 | 100 | 55 | **80%** |
| Sunset Beach (17-24) | 60 | 100 | 28 | 95 | 35 | 45 | 100 | 20 | **60%** |

The episode averages fall 95% -> 80% -> 60%, and the sawtooth is visible inside
each episode rather than being a smooth slide. The finale (L24, 20%) is the
hardest level in the set, as intended.

## Objective mix

10 SCORE / 8 COLLECT_COLOR / 6 CLEAR_BLOCKERS. All six gem colours are used as
COLLECT targets, and no colour is used twice in a row. Note DIAMOND (index 5)
can only be a target on a 6-colour board — `Board._random_color()` rolls
`0..gem_type_count-1`, so asking for DIAMOND on a 5-colour level would be
literally unwinnable. Only L16 uses it, and L16 is 6-colour.

## Blocker patterns

| Level | Grid | Cells | Shape |
| --- | --- | --- | --- |
| 5 | 8x8 | 6 | 2x3 slab dead centre — the teaching layout, maximally reachable |
| 8 | 8x8 | 8 | Two 2x2 clusters on opposite diagonals — splits attention |
| 11 | 8x8 | 12 | Four L-brackets, inset one cell — true corners proved unreachable |
| 15 | 7x7 | 8 | Checkerboard patch — no two blockers adjacent, so no cheap multi-clears |
| 18 | 8x8 | 12 | Fat plus through the centre — dense, rewards vertical clears |
| 23 | 9x9 | 12 | Diamond ring radius 3 — the finale; spread wide, no single move helps twice |

> **Open dependency — read before implementing `GameplayController`.**
> `LevelData`'s doc comment says a blocker clears when a match happens **on or
> adjacent to** its cell, but `GameplayController` did not exist when these
> levels were authored, so the rule is spec-only. It matters a lot:
>
> | | clears on exact cell | clears on cell **or adjacent** |
> | --- | --- | --- |
> | Typical blocker level length | most of the move budget | 2-5 moves |
> | Median end-of-level score | ~5,800-10,000 | ~1,000-2,900 |
>
> With the adjacent rule a 6-15 cell layout evaporates almost immediately, which
> is why the blocker levels are the easiest beats in the set under that reading.
> **The star thresholds on the six blocker levels are calibrated for the
> exact-cell reading**, because that is the one under which a 6-15 cell layout
> (the brief's range) produces a full-length level. If the broader adjacent rule
> ships as written, those six levels need both higher blocker counts and lower
> star thresholds — otherwise they finish in three moves and award zero stars.

## All 24 levels

| # | Episode | Grid | Colours | Moves | Objective | Key numbers | Stars (1/2/3) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Candy Forest | 8x8 | 5 | 25 | SCORE | score 2,500 | 1,200 / 2,000 / 3,200 |
| 2 | Candy Forest | 8x8 | 5 | 24 | SCORE | score 3,200 | 1,400 / 2,400 / 3,900 |
| 3 | Candy Forest | 8x8 | 5 | 25 | COLLECT_COLOR | 28x EMERALD (1.12/move) | 4,000 / 6,600 / 10,500 |
| 4 | Candy Forest | 8x8 | 5 | 22 | SCORE | score 4,000 | 1,800 / 3,000 / 4,600 |
| 5 | Candy Forest | 8x8 | 5 | 22 | CLEAR_BLOCKERS | 6 blockers — 2x3 centre slab | 3,500 / 5,900 / 9,200 |
| 6 | Candy Forest | 7x7 | 5 | 20 | COLLECT_COLOR | 22x TOPAZ (1.10/move) | 2,900 / 4,800 / 7,800 |
| 7 | Candy Forest | 8x8 | 6 | 22 | SCORE | score 5,000 | 2,250 / 3,750 / 5,500 |
| 8 | Candy Forest | 8x8 | 6 | 20 | CLEAR_BLOCKERS | 8 blockers — two 2x2 clusters, opposite diagonals | 3,200 / 5,400 / 8,400 |
| 9 | Crystal Caves | 8x8 | 5 | 24 | SCORE | score 5,500 | 2,500 / 4,100 / 6,100 |
| 10 | Crystal Caves | 8x8 | 6 | 24 | COLLECT_COLOR | 22x SAPPHIRE (0.92/move) | 3,400 / 5,700 / 8,900 |
| 11 | Crystal Caves | 8x8 | 6 | 24 | CLEAR_BLOCKERS | 12 blockers — four inset L-brackets | 3,800 / 6,500 / 10,000 |
| 12 | Crystal Caves | 9x9 | 6 | 26 | SCORE | score 8,000 | 3,600 / 6,000 / 8,800 |
| 13 | Crystal Caves | 8x8 | 6 | 22 | COLLECT_COLOR | 22x AMETHYST (1.00/move) | 3,300 / 5,500 / 8,600 |
| 14 | Crystal Caves | 8x8 | 5 | 20 | SCORE | score 6,000 | 2,700 / 4,500 / 6,900 |
| 15 | Crystal Caves | 7x7 | 6 | 20 | CLEAR_BLOCKERS | 8 blockers — checkerboard patch (7x7) | 2,800 / 4,600 / 7,200 |
| 16 | Crystal Caves | 8x8 | 6 | 20 | COLLECT_COLOR | 21x DIAMOND (1.05/move) | 3,100 / 5,200 / 8,100 |
| 17 | Sunset Beach | 8x8 | 6 | 22 | SCORE | score 7,500 | 3,400 / 5,600 / 8,200 |
| 18 | Sunset Beach | 8x8 | 6 | 22 | CLEAR_BLOCKERS | 12 blockers — fat plus through centre | 3,500 / 5,900 / 9,200 |
| 19 | Sunset Beach | 8x8 | 6 | 20 | COLLECT_COLOR | 21x RUBY (1.05/move) | 3,100 / 5,200 / 8,100 |
| 20 | Sunset Beach | 9x9 | 5 | 26 | SCORE | score 9,500 | 4,300 / 7,100 / 10,800 |
| 21 | Sunset Beach | 8x8 | 6 | 22 | COLLECT_COLOR | 24x EMERALD (1.09/move) | 3,500 / 5,900 / 9,200 |
| 22 | Sunset Beach | 8x8 | 6 | 18 | SCORE | score 7,000 | 3,100 / 5,250 / 7,700 |
| 23 | Sunset Beach | 9x9 | 6 | 24 | CLEAR_BLOCKERS | 12 blockers — diamond ring, radius 3 (9x9) | 4,100 / 6,900 / 10,800 |
| 24 | Sunset Beach | 8x8 | 6 | 20 | COLLECT_COLOR | 23x SAPPHIRE (1.15/move) | 3,400 / 5,600 / 8,800 |

*Generated data — edit the `.tres` files directly, or the generator that
produced them, and keep this table in sync.*
