# HT9 — Lambda: Elastic IP Auto-Association on ASG Launch

> **Prerequisites:** HT7 completed — an Auto Scaling Group with a Launch Template and an Elastic IP already allocated. This task applies to **Epic institute accounts only** (those using Spot instances with EIP).

## Goal

Replace the userdata shell script from HT7 with an event-driven Lambda function that automatically associates your Elastic IP whenever the ASG launches a new instance.

---

## Why Lambda Instead of Userdata?

In HT7, the EIP association was done by a shell script baked into the Launch Template userdata. That works, but has real problems:

| | Userdata script | Lambda + EventBridge |
|---|---|---|
| **Runs inside the instance** | Yes — if it crashes, the instance boots without a public IP | No — runs externally, instance is unaffected |
| **Failure visibility** | Silent: you find out when SSH stops working | CloudWatch Logs: full output, error traces, retries |
| **Updating logic** | Requires a new AMI or new Launch Template version | Edit the Lambda function — no AMI rebuild |
| **IAM permissions on EC2** | The instance role needs EC2 permissions | The Lambda execution role holds the permissions instead |
| **Race conditions** | Script runs while instance is still booting | Lambda fires on `EC2 Instance Launch Successful` — instance is ready |

The Lambda approach is the production pattern: decoupled, observable, and independently deployable.

---

## Checklist

### Warm-up

| Task | Verified by |
|---|---|
| Deploy and invoke Hello World Lambda via Function URL | Screenshot |
| Deploy and invoke Lambda Environment Explorer | Screenshot |

### Main task (Epic accounts)

| Task | Verified by |
|---|---|
| Create Lambda function with EIP association code | Screenshot |
| Attach correct IAM execution role | Screenshot |
| Set `EIP_ALLOC_ID` environment variable | Screenshot |
| Create EventBridge rule targeting your ASG | Screenshot |
| Remove userdata script from HT7 Launch Template | Screenshot |
| Trigger the flow (terminate ASG instance, wait for replacement) | Screenshot of EIP associated with new instance |

---

## Part 1 — Warm-up: Hello World Lambda

### 1.1 Create the function

Go to **Lambda → Create function**:
- **Author from scratch**
- **Runtime:** Python 3.12
- **Architecture:** x86_64 (or arm64 — both work)

Replace the default code with:

```python
import random

def lambda_handler(event, context):
    words = ["wonderful", "beautiful", "exciting", "amazing", "fantastic"]
    random_word = random.choice(words)

    content = f"""
    <style>
        body {{
            font-family: sans-serif;
            text-align: center;
            background-color: #f0f0f0;
        }}
        h1 {{
            color: #333;
            font-size: 2em;
            margin-top: 100px;
        }}
    </style>
    <h1>Hello world! This is a {random_word} day!</h1>
    """

    return {
        "statusCode": 200,
        "body": content,
        "headers": {"Content-Type": "text/html"}
    }
```

### 1.2 Add a Function URL

Go to your function → **Configuration → Function URL → Create function URL**:
- **Auth type:** NONE (public)

Open the URL in a browser — you should see an HTML page with a random word.

**Checkpoint 1.** Screenshot of the Function URL response in a browser.

---

## Part 2 — Warm-up: Lambda Environment Explorer

Create a second Lambda function with the code below. It uses the AWS SDK to inspect the runtime environment.

```python
import boto3
import os
import subprocess

def lambda_handler(event, context):
    sts = boto3.client('sts')
    account_id = sts.get_caller_identity()['Account']

    region = os.environ.get('AWS_REGION', 'Unknown')
    lambda_task_root = os.environ.get('LAMBDA_TASK_ROOT', 'Unknown')
    lambda_runtime_dir = os.environ.get('LAMBDA_RUNTIME_DIR', 'Unknown')
    tmp_dir = os.environ.get('TMPDIR', '/tmp')

    def run_cmd(cmd):
        try:
            return subprocess.check_output(cmd, text=True)
        except Exception as e:
            return f"Error: {e}"

    html_content = f"""
    <html>
        <head>
            <title>AWS Lambda Info</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                pre {{ background-color: #f5f5f5; padding: 10px; border-radius: 5px; }}
            </style>
        </head>
        <body>
            <h1>AWS Lambda Info</h1>
            <p><strong>Account:</strong> {account_id}</p>
            <p><strong>Region:</strong> {region}</p>
            <p><strong>LAMBDA_TASK_ROOT:</strong> {lambda_task_root}</p>
            <p><strong>LAMBDA_RUNTIME_DIR:</strong> {lambda_runtime_dir}</p>
            <p><strong>TMPDIR:</strong> {tmp_dir}</p>
            <h3>Root filesystem (/)</h3>
            <pre>{run_cmd(['ls', '-la', '/'])}</pre>
            <h3>/tmp directory</h3>
            <pre>{run_cmd(['ls', '-la', tmp_dir])}</pre>
        </body>
    </html>
    """

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": html_content
    }
```

This function calls `sts:GetCallerIdentity`. Add the following inline policy to its execution role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

Add a Function URL (auth: NONE) and open it in a browser.

**Checkpoint 2.** Screenshot of the environment explorer output in a browser.

---

## Part 3 — EIP Auto-Association via Lambda + EventBridge

### 3.1 Update the Launch Template from HT7 — remove the userdata script

Go to **EC2 → Launch Templates → your HT7 template → Actions → Modify template (Create new version)**. Clear the **User data** field completely and save.

Update the ASG to use the new template version: go to your **Auto Scaling Group → Edit → Launch template version → Latest**.

> The userdata script was the only thing that associated the EIP at boot. Once you remove it, new instances will launch without a public IP — until the Lambda in this task takes over. Complete Part 3 before terminating any instances.

### 3.2 Create the Lambda function

Go to **Lambda → Create function → Author from scratch**:
- **Runtime:** Python 3.12
- **Name:** `eip-auto-associate` (or similar)

Paste the following code:

```python
import boto3
import os

def lambda_handler(event, context):
    if event.get("detail-type") != "EC2 Instance Launch Successful":
        print("Ignoring non-launch event")
        return {"statusCode": 200, "body": "Ignored"}

    allocation_id = os.environ['EIP_ALLOC_ID']
    instance_id = event['detail']['EC2InstanceId']

    ec2_global = boto3.client('ec2')
    response = ec2_global.describe_instances(InstanceIds=[instance_id])
    region = response['Reservations'][0]['Instances'][0]['Placement']['AvailabilityZone'][:-1]
    ec2 = boto3.client('ec2', region_name=region)

    addr_desc = ec2.describe_addresses(AllocationIds=[allocation_id])
    assoc_id = addr_desc['Addresses'][0].get('AssociationId')

    if assoc_id:
        print(f"Disassociating existing EIP: {assoc_id}")
        ec2.disassociate_address(AssociationId=assoc_id)

    print(f"Associating EIP {allocation_id} with {instance_id}")
    ec2.associate_address(
        InstanceId=instance_id,
        AllocationId=allocation_id
    )

    return {
        'statusCode': 200,
        'body': f"Associated EIP {allocation_id} with {instance_id}"
    }
```

### 3.3 Configure the IAM execution role

Go to your function → **Configuration → Permissions → click the execution role link** → **Add permissions → Create inline policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAddresses",
        "ec2:DisassociateAddress",
        "ec2:AssociateAddress",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3.4 Set the environment variable

Go to your function → **Configuration → Environment variables → Edit → Add**:

| Key | Value |
|---|---|
| `EIP_ALLOC_ID` | your allocation ID (e.g., `eipalloc-xxxxxxxxxxxxxxxxx`) |

### 3.5 Create the EventBridge rule

Go to **EventBridge → Rules → Create rule**:
- **Event bus:** default
- **Rule type:** Rule with an event pattern

Use the following event pattern (replace `<your-asg-name>` with your actual ASG name):

```json
{
  "source": ["aws.autoscaling"],
  "detail-type": ["EC2 Instance Launch Successful"],
  "detail": {
    "AutoScalingGroupName": ["<your-asg-name>"]
  }
}
```

Set the **target** to your Lambda function (`eip-auto-associate`).

### 3.6 Test the full flow

Terminate the current ASG instance from the EC2 console. The ASG will launch a replacement.

Once the new instance appears:
1. Open **Lambda → your function → Monitor → View CloudWatch logs** — confirm the function ran and printed `Associating EIP ...`
2. Open **EC2 → Elastic IPs** — confirm the EIP is now associated with the new instance ID
3. SSH or curl your Elastic IP — confirm the server is reachable

**Checkpoint 3.** Screenshot of the CloudWatch log confirming EIP association, and the Elastic IPs page showing the new instance ID.

---

## Submission

Submit:
- The **Elastic IP address** of your ASG instance (same IP as HT7 — it should not have changed)
- A screenshot of the Lambda CloudWatch log showing a successful EIP association on ASG launch
