import json
import urllib.parse

import boto3

s3 = boto3.client("s3")


def handler(event, context):
    results = []

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        size = record["s3"]["object"]["size"]

        print(f"New file: s3://{bucket}/{key} ({size} bytes)")

        info = {"bucket": bucket, "key": key, "size": size}

        # 讀取檔案內容（純文字檔）
        try:
            obj = s3.get_object(Bucket=bucket, Key=key)
            content = obj["Body"].read().decode("utf-8")
            preview = content[:200]
            print(f"Content preview: {preview}")
            info["preview"] = preview
        except Exception as e:
            print(f"Could not read file content: {e}")
            info["error"] = str(e)

        results.append(info)

    return {"statusCode": 200, "processed": len(results), "files": results}
