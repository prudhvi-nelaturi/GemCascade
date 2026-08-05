extends Node

## Autoload singleton. Ships in v1 as a no-op — no real store connection, no
## SKUs are purchasable. TODO(launch-blocker): implement a real Play
## Billing-backed version once at least one in-app product (a Crystals pack)
## is configured in Play Console. See TODO.md.

func is_purchased(sku: String) -> bool:
	return false

func purchase(sku: String, on_success: Callable, on_failed_or_cancelled: Callable) -> void:
	on_failed_or_cancelled.call()
