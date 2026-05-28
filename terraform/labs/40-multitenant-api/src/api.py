import boto3
import json
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def lambda_handler(event, context):
    # API GW JWT Authorizer 已驗證 token，並將 claims 注入到 requestContext
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]

    # custom:tenant_id 是 Cognito User Pool 的自訂屬性
    # 若用戶沒有設定 custom:tenant_id，回退到 sub（Cognito 唯一用戶 ID）
    # 生產環境應強制要求 custom:tenant_id，此處保留 fallback 以利測試
    tenant_id = claims.get("custom:tenant_id") or claims["sub"]

    method = event["requestContext"]["http"]["method"]
    path = event["requestContext"]["http"]["path"]

    print(f"[REQUEST] {method} {path} tenant={tenant_id}")

    if method == "GET" and path == "/items":
        return get_items(tenant_id)
    elif method == "POST" and path == "/items":
        body = json.loads(event.get("body") or "{}")
        return create_item(tenant_id, body)
    else:
        return build_response(404, {"error": "Not found"})


def get_items(tenant_id):
    result = table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key("pk").eq(f"TENANT#{tenant_id}")
    )
    items = [
        {
            "item_id": item["sk"].replace("ITEM#", ""),
            **{k: v for k, v in item.items() if k not in ("pk", "sk")},
        }
        for item in result.get("Items", [])
    ]
    print(f"[GET] tenant={tenant_id} count={len(items)}")
    return build_response(200, {"tenant_id": tenant_id, "count": len(items), "items": items})


def create_item(tenant_id, body):
    item_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    table.put_item(
        Item={
            "pk": f"TENANT#{tenant_id}",
            "sk": f"ITEM#{item_id}",
            "name": body.get("name", "unnamed"),
            "data": body.get("data", {}),
            "created_at": now,
        }
    )
    print(f"[CREATE] tenant={tenant_id} item_id={item_id}")
    return build_response(201, {"item_id": item_id, "tenant_id": tenant_id, "created_at": now})


def build_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, cls=DecimalEncoder),
    }
