extends Node

## Autoload singleton. Ships in v1 as a no-op — no ad network wired up yet.
## TODO(launch-blocker): implement a real AdMob-backed version once Prudhvi has
## created an AdMob account + app entry for GemCascade and can supply real ad
## unit IDs. See TODO.md.

func is_rewarded_ad_ready() -> bool:
	return false

## Exactly one of on_reward_earned / on_failed_or_cancelled fires.
func show_rewarded_ad(on_reward_earned: Callable, on_failed_or_cancelled: Callable) -> void:
	on_failed_or_cancelled.call()
