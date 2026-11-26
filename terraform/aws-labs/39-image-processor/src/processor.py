import boto3
import json
import os
import urllib.parse
from datetime import datetime, timezone

s3 = boto3.client("s3")
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]

# 生產環境可替換為 Pillow 實作真實縮圖，此 lab 聚焦架構而非影像運算
def lambda_handler(event, context):
    # EventBridge 的事件格式與直接 S3 觸發不同（detail 層）
    detail = event["detail"]
    input_bucket = detail["bucket"]["name"]
    input_key = urllib.parse.unquote_plus(detail["object"]["key"])
    object_size = detail["object"].get("size", 0)

    print(f"[RECEIVED] s3://{input_bucket}/{input_key} ({object_size} bytes)")

    # 避免重複處理：若已在 processed/ 前綴下則跳過
    if input_key.startswith("processed/"):
        print("[SKIP] Already processed prefix, ignoring.")
        return {"status": "skipped"}

    # 讀取原始檔案
    response = s3.get_object(Bucket=input_bucket, Key=input_key)
    content_type = response["ContentType"]
    body = response["Body"].read()

    # ── 模擬處理（生產環境在此加入 Pillow resize / watermark 邏輯）──
    processed_at = datetime.now(timezone.utc).isoformat()
    output_key = f"processed/{input_key}"

    # 寫入 Output Bucket
    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=output_key,
        Body=body,
        ContentType=content_type,
        Metadata={
            "source-bucket": input_bucket,
            "source-key": input_key,
            "processed-at": processed_at,
            "original-size": str(object_size),
        },
    )

    # 產生 sidecar metadata JSON（方便下游服務查詢處理結果）
    metadata_key = f"processed/{input_key}.metadata.json"
    s3.put_object(
        Bucket=OUTPUT_BUCKET,
        Key=metadata_key,
        Body=json.dumps(
            {
                "source_bucket": input_bucket,
                "source_key": input_key,
                "output_bucket": OUTPUT_BUCKET,
                "output_key": output_key,
                "content_type": content_type,
                "original_size_bytes": object_size,
                "processed_at": processed_at,
            },
            indent=2,
        ),
        ContentType="application/json",
    )

    print(f"[OK] → s3://{OUTPUT_BUCKET}/{output_key}")
    print(f"[OK] → s3://{OUTPUT_BUCKET}/{metadata_key}")

    return {
        "status": "success",
        "output_key": output_key,
        "metadata_key": metadata_key,
    }
