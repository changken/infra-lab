import json
import os
import socket


def handler(event, context):
    host = os.environ["REDIS_HOST"]
    port = int(os.environ.get("REDIS_PORT", "6379"))

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect((host, port))

        # Redis RESP 協定：送出 PING 指令
        # RESP 格式：*<參數數量>\r\n$<字串長度>\r\n<字串>\r\n
        sock.send(b"*1\r\n$4\r\nPING\r\n")
        response = sock.recv(256).decode("utf-8").strip()
        sock.close()

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "status": "success",
                    "redis_host": host,
                    "redis_port": port,
                    "response": response,  # 期望：+PONG
                }
            ),
        }

    except socket.timeout:
        return {
            "statusCode": 500,
            "body": json.dumps(
                {
                    "status": "error",
                    "message": f"Timeout connecting to {host}:{port}",
                    "hint": "Security Group 或 Subnet 設定錯誤",
                }
            ),
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"status": "error", "message": str(e)}),
        }
