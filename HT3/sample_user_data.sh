#!/bin/bash
set -euo pipefail

STUDENT_ID="student@example.com"
MARKER="EC2-HT3-OK"
CHECK_SCRIPT="/usr/local/bin/ht3-check.sh"
WEB_ROOT="/var/www/html"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nginx cron

id -u devops >/dev/null 2>&1 || useradd -m -s /bin/bash devops

cat > "$CHECK_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail

STUDENT_ID="student@example.com"
MARKER="EC2-HT3-OK"
WEB_ROOT="/var/www/html"
HOSTNAME_VALUE="$(hostname)"
UPDATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

nginx_active=false
nginx_enabled=false
devops_user_exists=false
index_html_exists=false

if systemctl is-active --quiet nginx; then
  nginx_active=true
fi

if systemctl is-enabled --quiet nginx; then
  nginx_enabled=true
fi

if id devops >/dev/null 2>&1; then
  devops_user_exists=true
fi

if [ -f "$WEB_ROOT/index.html" ]; then
  index_html_exists=true
fi

cat > "$WEB_ROOT/check.json" <<JSON
{
  "task": "HT3",
  "marker": "$MARKER",
  "student": "$STUDENT_ID",
  "hostname": "$HOSTNAME_VALUE",
  "updated_at_utc": "$UPDATED_AT_UTC",
  "checks": {
    "nginx_active": $nginx_active,
    "nginx_enabled": $nginx_enabled,
    "devops_user_exists": $devops_user_exists,
    "index_html_exists": $index_html_exists
  }
}
JSON
EOF

chmod 755 "$CHECK_SCRIPT"

cat > "$WEB_ROOT/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>HT3 EC2 Check</title>
</head>
<body>
  <h1>$MARKER</h1>
  <p>Student: $STUDENT_ID</p>
  <p>Hostname: <code>$(hostname)</code></p>
  <p>Check endpoint: <a href="/check.json">/check.json</a></p>
</body>
</html>
EOF

systemctl enable nginx
systemctl restart nginx
systemctl enable cron
systemctl restart cron

"$CHECK_SCRIPT"

cat > /etc/cron.d/ht3-check <<EOF
* * * * * root $CHECK_SCRIPT
EOF

chmod 644 /etc/cron.d/ht3-check
