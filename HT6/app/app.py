from flask import Flask, jsonify
import os

app = Flask(__name__)
VERSION = os.getenv("APP_VERSION", "1.0")


@app.route("/")
def home():
    return f"Hello from Flask app v{VERSION}\n"


@app.route("/health")
def health():
    return jsonify({"status": "ok", "version": VERSION})


@app.route("/secret-check")
def secret_check():
    """
    Used by the checkup script to verify the build-time secret
    was NOT baked into the final image.
    """
    secret_path = "/run/secrets/app_secret"
    if os.path.exists(secret_path):
        return jsonify({
            "leaked": True,
            "message": "FAIL — secret file exists inside the running container",
        }), 500
    return jsonify({
        "leaked": False,
        "message": "PASS — secret is not present at runtime",
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
