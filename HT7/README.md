# HT7 — EC2 Cost Optimisation: AMI + Launch Template + Auto Scaling Group

> **Prerequisites:** EC2 instance from HT6 with Docker, Docker Compose, and the Flask + Nginx stack installed and running.

## Goal

Replace your always-on EC2 instance with a cost-optimized Auto Scaling Group that:

- Boots from a pre-baked AMI (no more user data install scripts)
- Uses **Spot instances** (Epic accounts) or **On-Demand** (private/free-tier accounts)
- Can scale to zero when not needed
- Keeps a stable public IP via Elastic IP (Epic accounts)

---

## Checklist

### What students must do

| Task | Verified by |
|---|---|
| Create AMI from your HT6 EC2 instance (status = available) | Screenshot |
| Terminate the original instance | Screenshot |
| Create Launch Template with correct settings | Screenshot |
| *(Epic accounts only)* Allocate Elastic IP and add userdata script | Screenshot |
| Create Auto Scaling Group with correct capacity and purchase options | Screenshot |
| Confirm a new instance launches from the ASG and is reachable | Screenshot |
| Submit the public IP of the ASG-managed instance | Instructor check |

---

## Part 1 — Bake an AMI from Your Existing Instance

Use your existing EC2 instance from HT6 — do not create a new one. Docker, Docker Compose, and the Flask + Nginx stack are already installed and running on it.

> **Warning — verify before baking.** The AMI captures your instance exactly as it is. If anything is misconfigured, it will be frozen into every future instance the ASG launches. Before creating the AMI, confirm:
> - All HT6 steps are complete and the Flask + Nginx stack is reachable on port 80
> - Nginx (from HT5) is configured in **enabled** mode — check that the site symlink exists in `/etc/nginx/sites-enabled/`
> - Docker and Docker Compose services start automatically on boot (`systemctl is-enabled docker`)
>
> Fix any issues on the running instance first, then proceed to create the AMI.
>
> **Note:** If you discover autostart or configuration issues after the ASG is already running, you can fix them on the ASG-launched instance, create a new AMI, update the Launch Template to point to the new AMI (new version), and do an Instance Refresh in the ASG — no need to redo everything from scratch.

### 1.1 Create an AMI

Wait until both EC2 status checks are green, then:

1. Select your running instance in the EC2 console
2. Click **Actions → Image and templates → Create image**
3. Give it a descriptive name (e.g., `my-app-ami-v1`)
4. Keep all other defaults and click **Create image**

Wait until the AMI status changes to **available** in **EC2 → AMIs**.

**Checkpoint 1b.** Screenshot of the AMI with status **available**.

### 1.3 Terminate the original instance

Once the AMI is available, terminate the EC2 instance — it is no longer needed. Everything is now baked into the AMI.

---

## Part 2 — Create a Launch Template

Go to **EC2 → Launch Templates → Create launch template**.

Use the same settings as your previous EC2 instance:
- **AMI:** select the AMI you just created
- **Instance type:** `t2.micro`
- **Key pair:** your existing key pair
- **Security group:** your existing security group
- **IAM instance profile:** your existing role

**No user data is needed** — all packages are already in the AMI.

### Storage

In the storage section, set the volume size to **20 GB** (the AMI snapshot is 10 GB; the launch template overrides it to give the running instance more working space).

### Public IP setting

> This is the most important network setting — get it wrong and your instances will be unreachable.

Open **Advanced network configuration** and set **Auto-assign public IP** according to your account type:

| Account type | Setting |
|---|---|
| **Private accounts (free tier)** | **Auto-assign public IP = Enable** |
| **Epic institute accounts** | **Auto-assign public IP = Disable** (Elastic IP script handles it) |

**Private accounts:** that is all you need in the launch template — skip Part 3 entirely.

**Epic institute accounts:** set it to Disable and continue to Part 3.

**Checkpoint 2.** Screenshot of the launch template summary page after creation.

---

## Part 3 — Elastic IP Setup (Epic Institute Accounts Only)

> **Private accounts (free tier): skip this entire section.**

When an ASG replaces a Spot instance, the new instance gets a different public IP. An Elastic IP (EIP) gives you one fixed address that automatically follows your instance.

### 3.1 Add IAM permissions

Add the following permissions to the IAM role attached to your EC2 instances:

```
ec2:DescribeAddresses
ec2:DescribeInstances
ec2:AssociateAddress
ec2:DisassociateAddress
```

### 3.2 Allocate an Elastic IP

Go to **EC2 → Elastic IPs → Allocate Elastic IP address**. Keep all defaults and click **Allocate**.

Copy the **Allocation ID** from the result (format: `eipalloc-xxxxxxxxxxxxxxxxx`) — you will need it in the next step.

**Checkpoint 3a.** Screenshot of the allocated Elastic IP with its Allocation ID.

### 3.3 Add the userdata script to the Launch Template

Edit your Launch Template (create a new version) and paste the script below into the **User data** field under **Advanced details**. Replace `eipalloc-xxxxxxxx` with your actual Allocation ID.

The script is also provided as `userdata-eip.sh` in this folder.

```bash
#!/bin/bash

EIP_ALLOC_ID="eipalloc-xxxxxxxx"  # Replace with your EIP Allocation ID

# Get IMDSv2 token
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Get the instance ID and region
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/dynamic/instance-identity/document \
  | grep region | awk -F\" '{print $4}')

# If the EIP is already associated with another instance, disassociate it first
ASSOC_ID=$(aws ec2 describe-addresses \
  --allocation-ids "$EIP_ALLOC_ID" \
  --region "$REGION" \
  --query "Addresses[0].AssociationId" \
  --output text)

if [ "$ASSOC_ID" != "None" ] && [ -n "$ASSOC_ID" ]; then
  aws ec2 disassociate-address --association-id "$ASSOC_ID" --region "$REGION"
fi

# Associate the EIP with this instance
aws ec2 associate-address \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$EIP_ALLOC_ID" \
  --region "$REGION"
```

The AWS CLI is already installed in the AMI — no need to install it again in userdata.

**Checkpoint 3b.** Screenshot of the new Launch Template version with user data filled in.

---

## Part 4 — Create the Auto Scaling Group

Go to **EC2 → Auto Scaling Groups → Create Auto Scaling group**.

### Step 1 — Select Launch Template

Choose the launch template you created. If you have multiple versions, select the latest one (with the EIP userdata for Epic accounts).

### Step 2 — Instance type requirements

Click **Override launch template** under **Instance type requirements**:

| Account type | Instance types to add |
|---|---|
| **Private accounts** | `t2.micro` only |
| **Epic institute accounts** | `t2.micro`, `t3.micro`, `t3a.micro` |

In **Purchase options**:

| Account type | Setting |
|---|---|
| **Private accounts** | 100% On-Demand |
| **Epic institute accounts** | 100% Spot |

In the **Network** section, select **all available public subnets** in your VPC.

### Step 3 — Configure advanced options

Keep all defaults.

### Step 4 — Configure group size and scaling

Set the capacity:

| Setting | Value |
|---|---|
| Desired capacity | `1` |
| Minimum capacity | `0` |
| Maximum capacity | `1` |

- No scaling policies
- Enable **Cost optimization** (instance scale-in protection: off)

### Step 5 — Notifications

Keep defaults (skip).

### Step 6 — Add tags

Add a **Name** tag so your ASG-launched instances appear with a recognizable name in the console.

### Step 7 — Review and create

**Checkpoint 4.** Screenshot of the ASG after creation showing 1 instance running and its public IP (or Elastic IP for Epic accounts).

---

## Verification

Once the ASG launches an instance, confirm it is reachable:

```bash
# Verify your app is running (replace with your actual IP)
curl http://<YOUR_PUBLIC_IP>/
curl http://<YOUR_PUBLIC_IP>/health
```

**Checkpoint 5.** Screenshot of the ASG-managed instance details page and a browser or curl response from your app.

---

## Submission

Submit the **public IP** of your ASG-managed instance (the Elastic IP for Epic accounts, or the auto-assigned public IP for private accounts).

---

## Advanced Tips

### Why Launch Templates over Launch Configurations

AWS deprecated Launch Configurations. Launch Templates support:

- **Versioning** — multiple versions with safe rollbacks (`$Latest`, `$Default`, or a specific number)
- **Instance type flexibility** — override at the ASG level without modifying the template
- **Mixed purchase options** — Spot + On-Demand in one ASG
- **IMDSv2 enforcement** — require token-based metadata for security

### Spot Instance Interruptions

Spot instances can be reclaimed with a **2-minute warning**. To reduce risk:

- Use **Capacity-Optimized** allocation strategy — AWS picks from the fullest pool
- Enable **Capacity Rebalancing** — AWS proactively replaces at-risk instances
- Diversify instance types across 3–5 similar sizes (`t2.micro`, `t3.micro`, `t3a.micro`)

### Scheduled Scaling to Zero

If your server only needs to run during working hours, use **Scheduled Actions**:

- Scale up: Desired = 1 at 08:00 Monday–Friday
- Scale down: Desired = 0 at 20:00 Monday–Friday

This alone reduces compute costs by **60–70%** compared to a 24/7 instance.

### EBS Size Strategy

The AMI snapshot is 10 GB (minimal — just OS + packages). The Launch Template sets the running volume to 20 GB. This keeps snapshot storage costs low while giving instances adequate working space.

### IMDSv2

The EIP userdata script already uses IMDSv2 (token-based metadata requests). Enforce it in the Launch Template under **Advanced details → Metadata version = V2 only** to prevent SSRF-based credential theft.
