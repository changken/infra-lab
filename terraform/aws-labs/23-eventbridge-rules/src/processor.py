import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    Event Pattern 觸發的 Lambda。
    EventBridge 傳入的 event 就是原始事件 JSON，不像 SNS 包了一層 Records[]。
    """
    source = event.get("source", "unknown")
    detail_type = event.get("detail-type", "unknown")
    detail = event.get("detail", {})

    logger.info(f"收到事件 | source={source} | detail-type={detail_type}")
    logger.info(f"Detail: {json.dumps(detail)}")

    # EventBridge 事件結構：
    # {
    #   "version": "0",
    #   "id": "uuid",
    #   "source": "myapp.orders",
    #   "detail-type": "order.created",
    #   "time": "2026-05-23T...",
    #   "region": "us-east-1",
    #   "detail": { "order_id": "...", "status": "pending" }
    # }

    order_id = detail.get("order_id", "N/A")
    status = detail.get("status", "N/A")
    logger.info(f"處理訂單 order_id={order_id} status={status}")

    return {"statusCode": 200, "order_id": order_id}
