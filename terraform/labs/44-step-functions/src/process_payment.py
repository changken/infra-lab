import json
import random


class PaymentRetryableError(Exception):
    """Transient payment gateway error — Step Functions will retry."""
    pass


class PaymentFailedError(Exception):
    """Permanent payment failure — Step Functions routes to failure branch."""
    pass


def handler(event, context):
    print(f"Processing payment for order: {event['order_id']}, amount: {event['total_amount']}")

    roll = random.random()

    # 15% chance of transient error (Retry block will catch this)
    if roll < 0.15:
        raise PaymentRetryableError("Payment gateway timeout — please retry")

    # Additional 10% chance of permanent failure
    if roll < 0.25:
        raise PaymentFailedError(f"Card declined for order {event['order_id']}")

    payment_id = f"PAY-{event['order_id'].upper()}-{context.aws_request_id[:8].upper()}"
    print(f"Payment succeeded: {payment_id}")
    return {**event, "status": "PAYMENT_PROCESSED", "payment_id": payment_id}
