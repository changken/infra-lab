import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    通知服務 Worker。
    和 inventory_worker 收到同一筆 SNS 訊息，但執行不同業務邏輯。
    這就是 Fan-out 的意義：一份資料，多個消費者各自獨立處理。
    """
    for record in event.get("Records", []):
        sns_envelope = json.loads(record["body"])
        message = json.loads(sns_envelope["Message"])

        order_id = message.get("order_id", "N/A")
        customer_email = message.get("customer_email", "N/A")
        total = message.get("total", 0)

        logger.info(f"[通知] 訂單 {order_id} 成立，寄送確認信給 {customer_email}")
        logger.info(f"  金額: ${total}")
        # 實際情境：呼叫 SES / SNS Email / 第三方郵件服務

    return {"statusCode": 200}
