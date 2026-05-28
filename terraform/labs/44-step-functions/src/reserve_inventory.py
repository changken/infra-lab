import json


class InsufficientInventoryError(Exception):
    pass


def handler(event, context):
    print(f"Reserving inventory for order: {event['order_id']}")

    for item in event.get("items", []):
        sku = item.get("sku", "UNKNOWN")
        quantity = item.get("quantity", 1)
        # SKUs ending in "OOS" (out-of-stock) or quantity > 10 trigger failure
        if sku.endswith("OOS") or quantity > 10:
            raise InsufficientInventoryError(
                f"Insufficient inventory for SKU {sku}: requested {quantity}, available 0"
            )

    reservation_id = f"RES-{event['order_id']}"
    print(f"Inventory reserved: {reservation_id}")
    return {**event, "status": "INVENTORY_RESERVED", "reservation_id": reservation_id}
