from flask import Flask
import os

app = Flask(__name__)


@app.route("/")
def hello():
    version = os.environ.get("APP_VERSION", "dev")
    return f"Hello from CodeBuild Lab! version={version}\n"


@app.route("/health")
def health():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
