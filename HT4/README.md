# Hometask 4

## Goal

Build a custom network for EC2 and prove the result through automatic checks instead of screenshots.

This task extends Hometask 3. You will create your own VPC, place an EC2 instance into one of its public subnets, and update the EC2 role so the instance can validate the network configuration by itself.

## Requirements

1. If you still have a running EC2 instance from Hometask 3, terminate it.
2. Create a VPC named `epic-network`.
3. Use a non-default custom VPC CIDR.
4. Create:
   - 2 public subnets
   - 2 private subnets
5. Create and attach route tables correctly.
6. Private subnets must **not** have a default route to an Internet Gateway.
7. Launch an EC2 instance in one of the new public subnets.
8. Use a new security group for this instance.
9. Use the same approach as in Hometask 3:
   - install and configure `nginx` through **User data**
   - create a user named `devops`
   - expose a custom `index.html`
   - expose `/check.json`
10. Create or update an EC2 role for Session Manager access.
11. Update that same role by attaching a custom read-only EC2 policy so the instance can inspect its own network environment.
12. Your User data script must use:
   - IMDSv2 to get instance metadata
   - AWS CLI to inspect VPC and subnet information
13. Your User data must create `/usr/local/bin/ht4-check.sh` and run it at least once during provisioning.
14. Your User data must configure a cron job that refreshes `/var/www/html/check.json` every minute.

## Required IAM Policy

Create a customer-managed IAM policy from `ec2_network_read_policy.json` in this folder and attach it to the same EC2 role that provides Session Manager access.

## What must be visible remotely

When I open `http://<public-ip>/`, I must see a custom page.

The page must contain:
- your name or email
- the marker string `EC2-HT4-OK`
- the VPC ID
- the subnet ID
- the path `/check.json`

When I open `http://<public-ip>/check.json`, I must receive valid JSON with the following structure:

```json
{
  "task": "HT4",
  "marker": "EC2-HT4-OK",
  "student": "student@example.com",
  "hostname": "ip-172-31-0-10",
  "updated_at_utc": "2026-03-23T18:10:00Z",
  "network": {
    "vpc_id": "vpc-123456",
    "vpc_cidr": "10.20.0.0/16",
    "subnet_id": "subnet-123456",
    "subnet_cidr": "10.20.1.0/24",
    "availability_zone": "eu-central-1a",
    "public_subnet_count": 2,
    "private_subnet_count": 2,
    "total_subnet_count": 4
  },
  "iam": {
    "instance_profile_attached": true
  },
  "checks": {
    "nginx_active": true,
    "nginx_enabled": true,
    "devops_user_exists": true,
    "imdsv2_used": true,
    "custom_vpc_used": true,
    "public_subnet_count_ok": true,
    "private_subnet_count_ok": true,
    "private_subnets_without_igw_default_route": true
  }
}
```

## Submission

Submit only:
- the public IP of your EC2 instance

## How it will be checked

The submission will be checked automatically.

The checker will verify:
- `http://<public-ip>/` returns HTTP 200
- the main page contains `EC2-HT4-OK`
- the main page contains your student identifier
- `http://<public-ip>/check.json` returns valid JSON
- JSON contains the required fields
- the EC2 instance reports a custom VPC and subnet
- the instance profile is attached
- the VPC contains 4 subnets in total
- the VPC contains 2 public and 2 private subnets
- private subnets do not have a default route to an Internet Gateway
- all required checks in JSON are `true`

## Notes

- Do not submit screenshots.
- Do not configure the server manually after launch.
- If the instance is restarted, your public IP may change.
- The sample User data script is a reference implementation. You still need to create the VPC, subnets, route tables, and IAM role/policy in AWS.
