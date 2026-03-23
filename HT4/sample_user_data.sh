#!/bin/bash
set -euo pipefail

STUDENT_ID="student@example.com"
MARKER="EC2-HT4-OK"
CHECK_SCRIPT="/usr/local/bin/ht4-check.sh"
WEB_ROOT="/var/www/html"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nginx cron awscli jq

id -u devops >/dev/null 2>&1 || useradd -m -s /bin/bash devops

cat > "$CHECK_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail

STUDENT_ID="student@example.com"
MARKER="EC2-HT4-OK"
WEB_ROOT="/var/www/html"
UPDATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

TOKEN="$(curl -fsS -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')"
MAC="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/mac)"
INSTANCE_ID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)"
HOSTNAME_VALUE="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/hostname)"
AZ="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)"
SUBNET_ID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/subnet-id)"
VPC_ID="$(curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/vpc-id)"
REGION="${AZ::-1}"

INSTANCE_PROFILE_ATTACHED=false
if curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/info >/dev/null 2>&1; then
  INSTANCE_PROFILE_ATTACHED=true
fi

nginx_active=false
nginx_enabled=false
devops_user_exists=false
custom_vpc_used=false
public_subnet_count_ok=false
private_subnet_count_ok=false
private_subnets_without_igw_default_route=false
imdsv2_used=true

if systemctl is-active --quiet nginx; then
  nginx_active=true
fi

if systemctl is-enabled --quiet nginx; then
  nginx_enabled=true
fi

if id devops >/dev/null 2>&1; then
  devops_user_exists=true
fi

VPC_CIDR="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"
SUBNET_CIDR="$(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$SUBNET_ID" --query 'Subnets[0].CidrBlock' --output text)"

if [ "$VPC_CIDR" != "172.31.0.0/16" ]; then
  custom_vpc_used=true
fi

SUBNETS_JSON="$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --output json)"
ROUTE_TABLES_JSON="$(aws ec2 describe-route-tables --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --output json)"

COUNTS="$(python3 - "$SUBNETS_JSON" "$ROUTE_TABLES_JSON" <<'PY'
import json
import sys

subnets = json.loads(sys.argv[1])["Subnets"]
route_tables = json.loads(sys.argv[2])["RouteTables"]

main_route_table = None
explicit = {}
for route_table in route_tables:
    for assoc in route_table.get("Associations", []):
        if assoc.get("Main"):
            main_route_table = route_table
        subnet_id = assoc.get("SubnetId")
        if subnet_id:
            explicit[subnet_id] = route_table

def has_igw_default(route_table):
    for route in route_table.get("Routes", []):
        if route.get("DestinationCidrBlock") == "0.0.0.0/0" and route.get("GatewayId", "").startswith("igw-"):
            return True
    return False

public_count = 0
private_count = 0
private_without_igw = True

for subnet in subnets:
    subnet_id = subnet["SubnetId"]
    route_table = explicit.get(subnet_id, main_route_table or {})
    is_public = has_igw_default(route_table)
    if is_public:
        public_count += 1
    else:
        private_count += 1
        private_without_igw = private_without_igw and True

print(json.dumps({
    "public": public_count,
    "private": private_count,
    "total": len(subnets),
    "private_without_igw": private_without_igw
}))
PY
)"

PUBLIC_SUBNET_COUNT="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["public"])' "$COUNTS")"
PRIVATE_SUBNET_COUNT="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["private"])' "$COUNTS")"
TOTAL_SUBNET_COUNT="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["total"])' "$COUNTS")"
PRIVATE_NO_IGW="$(python3 -c 'import json,sys; print("true" if json.loads(sys.argv[1])["private_without_igw"] else "false")' "$COUNTS")"

if [ "$PUBLIC_SUBNET_COUNT" = "2" ]; then
  public_subnet_count_ok=true
fi

if [ "$PRIVATE_SUBNET_COUNT" = "2" ]; then
  private_subnet_count_ok=true
fi

if [ "$PRIVATE_NO_IGW" = "true" ]; then
  private_subnets_without_igw_default_route=true
fi

cat > "$WEB_ROOT/check.json" <<JSON
{
  "task": "HT4",
  "marker": "$MARKER",
  "student": "$STUDENT_ID",
  "hostname": "$HOSTNAME_VALUE",
  "updated_at_utc": "$UPDATED_AT_UTC",
  "network": {
    "vpc_id": "$VPC_ID",
    "vpc_cidr": "$VPC_CIDR",
    "subnet_id": "$SUBNET_ID",
    "subnet_cidr": "$SUBNET_CIDR",
    "availability_zone": "$AZ",
    "public_subnet_count": $PUBLIC_SUBNET_COUNT,
    "private_subnet_count": $PRIVATE_SUBNET_COUNT,
    "total_subnet_count": $TOTAL_SUBNET_COUNT
  },
  "iam": {
    "instance_profile_attached": $INSTANCE_PROFILE_ATTACHED
  },
  "checks": {
    "nginx_active": $nginx_active,
    "nginx_enabled": $nginx_enabled,
    "devops_user_exists": $devops_user_exists,
    "imdsv2_used": $imdsv2_used,
    "custom_vpc_used": $custom_vpc_used,
    "public_subnet_count_ok": $public_subnet_count_ok,
    "private_subnet_count_ok": $private_subnet_count_ok,
    "private_subnets_without_igw_default_route": $private_subnets_without_igw_default_route
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
  <title>HT4 EC2 Network Check</title>
</head>
<body>
  <h1>$MARKER</h1>
  <p>Student: $STUDENT_ID</p>
  <p>VPC and subnet details are available in <a href="/check.json">/check.json</a></p>
</body>
</html>
EOF

systemctl enable nginx
systemctl restart nginx
systemctl enable cron
systemctl restart cron

"$CHECK_SCRIPT"

cat > /etc/cron.d/ht4-check <<EOF
* * * * * root $CHECK_SCRIPT
EOF

chmod 644 /etc/cron.d/ht4-check
