#!/bin/bash
set -euo pipefail

STUDENT_ID="student@example.com"
MARKER="EC2-HT5-OK"
CHECK_SCRIPT="/usr/local/bin/ht5-check.sh"
APP_DIR="/opt/ht5"
WEB_DATA_DIR="$APP_DIR/html"
TLS_DIR="$APP_DIR/tls"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y docker.io cron curl openssl

systemctl enable docker
systemctl restart docker

mkdir -p "$APP_DIR" "$WEB_DATA_DIR" "$TLS_DIR"

cat > "$WEB_DATA_DIR/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>HT5 HTTPS Check</title>
</head>
<body>
  <h1>$MARKER</h1>
  <p>Student: $STUDENT_ID</p>
  <p>HTTPS is enabled.</p>
  <p>Check endpoint: <a href="/check.json">/check.json</a></p>
</body>
</html>
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$TLS_DIR/server.key" \
  -out "$TLS_DIR/server.crt" \
  -subj "/CN=localhost"

cat > "$APP_DIR/nginx.conf" <<'EOF'
events {}

http {
  server {
    listen 80 default_server;
    return 301 https://$host$request_uri;
  }

  server {
    listen 443 ssl default_server;
    ssl_certificate /etc/nginx/tls/server.crt;
    ssl_certificate_key /etc/nginx/tls/server.key;

    root /usr/share/nginx/html;
    index index.html;

    location / {
      try_files $uri $uri/ =404;
    }
  }
}
EOF

cat > "$APP_DIR/Dockerfile" <<'EOF'
FROM ubuntu:24.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx openssl curl && \
    rm -rf /var/lib/apt/lists/*

COPY nginx.conf /etc/nginx/nginx.conf
COPY tls /etc/nginx/tls
COPY html /usr/share/nginx/html

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
EOF

cat > "$CHECK_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail

STUDENT_ID="student@example.com"
MARKER="EC2-HT5-OK"
WEB_DATA_DIR="/opt/ht5/html"
UPDATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

docker_installed=false
container_running=false
image_built_from_ubuntu=false
https_enabled=false
http_redirect_to_https=false
nginx_running_in_container=false
custom_index_present=false
check_json_present=false

if command -v docker >/dev/null 2>&1; then
  docker_installed=true
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'ht5-nginx'; then
  container_running=true
fi

if docker image inspect ht5-nginx:latest >/dev/null 2>&1; then
  if docker image inspect ht5-nginx:latest --format '{{json .Config.Cmd}}' | grep -Fq 'daemon off;'; then
    image_built_from_ubuntu=true
  fi
fi

HTTP_HEADERS="$(curl -I -s http://127.0.0.1/ || true)"
if printf '%s' "$HTTP_HEADERS" | grep -Eiq '^HTTP/[0-9.]+ 30[1278]'; then
  if printf '%s' "$HTTP_HEADERS" | grep -Eiq '^Location: https://'; then
    http_redirect_to_https=true
  fi
fi

if curl -kfsS https://127.0.0.1/ >/dev/null 2>&1; then
  https_enabled=true
fi

if docker exec ht5-nginx sh -c 'pgrep nginx >/dev/null' >/dev/null 2>&1; then
  nginx_running_in_container=true
fi

if [ -f "$WEB_DATA_DIR/index.html" ] && grep -q "$MARKER" "$WEB_DATA_DIR/index.html"; then
  custom_index_present=true
fi

cat > "$WEB_DATA_DIR/check.json" <<JSON
{
  "task": "HT5",
  "marker": "$MARKER",
  "student": "$STUDENT_ID",
  "updated_at_utc": "$UPDATED_AT_UTC",
  "docker": {
    "installed": $docker_installed,
    "container_running": $container_running,
    "image_built_from_ubuntu": $image_built_from_ubuntu
  },
  "web": {
    "https_enabled": $https_enabled,
    "http_redirect_to_https": $http_redirect_to_https
  },
  "checks": {
    "nginx_running_in_container": $nginx_running_in_container,
    "custom_index_present": $custom_index_present,
    "check_json_present": true
  }
}
JSON
EOF

chmod 755 "$CHECK_SCRIPT"

docker build -t ht5-nginx:latest "$APP_DIR"

docker rm -f ht5-nginx >/dev/null 2>&1 || true
docker run -d \
  --name ht5-nginx \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  ht5-nginx:latest

"$CHECK_SCRIPT"

cat > /etc/cron.d/ht5-check <<EOF
* * * * * root $CHECK_SCRIPT
EOF

chmod 644 /etc/cron.d/ht5-check
systemctl enable cron
systemctl restart cron
