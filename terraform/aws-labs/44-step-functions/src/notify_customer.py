import json
import os
import boto3

sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def handler(event, context):
    print(f"Sending order confirmation for: {event['order_id']}")

    message = json.dumps(
        {
            "order_id": event["order_id"],
            "status": "CONFIRMED",
            "payment_id": event.get("payment_id", "N/A"),
            "total_amount": event["total_amount"],
            "customer_email": event["customer_email"],
        },
        indent=2,
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[Order Confirmed] {event['order_id']}",
        Message=message,
    )

    print(f"Notification sent for order {event['order_id']}")
    return {**event, "status": "COMPLETED", "notification_sent": True}
