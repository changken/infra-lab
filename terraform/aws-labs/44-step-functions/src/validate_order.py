import json
import re


class InvalidOrderError(Exception):
    pass


def handler(event, context):
    print(f"Validating order: {json.dumps(event)}")

    required_fields = ["order_id", "customer_email", "items", "total_amount"]
    for field in required_fields:
        if field not in event:
            raise InvalidOrderError(f"Missing required field: {field}")

    if not re.match(r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$", event["customer_email"]):
        raise InvalidOrderError(f"Invalid email format: {event['customer_email']}")

    if not isinstance(event["items"], list) or len(event["items"]) == 0:
        raise InvalidOrderError("Order must contain at least one item")

    if not isinstance(event["total_amount"], (int, float)) or event["total_amount"] <= 0:
        raise InvalidOrderError(f"Invalid total_amount: {event['total_amount']}")

    print(f"Order {event['order_id']} passed validation")
    return {**event, "status": "VALIDATED"}
