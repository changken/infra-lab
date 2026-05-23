import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    SNS 訂閱者 Lambda。
    SNS 直接推送呼叫 Lambda（Push 模型），和 SQS Event Source Mapping（Pull 模型）不同。
    SNS 的 event 結構：Records[].Sns.{Message, Subject, MessageAttributes}
    """
    records = event.get("Records", [])
    logger.info(f"收到 {len(records)} 筆 SNS 訊息")

    for record in records:
        sns = record["Sns"]
        subject = sns.get("Subject", "(no subject)")
        message = sns.get("Message", "")
        attributes = sns.get("MessageAttributes", {})

        # 嘗試解析 JSON message body
        try:
            payload = json.loads(message)
        except json.JSONDecodeError:
            payload = message

        logger.info(f"Subject: {subject}")
        logger.info(f"Message: {payload}")
        logger.info(f"Attributes: {attributes}")

    return {"statusCode": 200, "processed": len(records)}
