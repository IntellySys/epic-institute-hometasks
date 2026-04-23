#!/bin/bash
# Elastic IP association script for ASG Spot instances.
# Run at boot via Launch Template user data.
# Requires ec2:DescribeAddresses, ec2:DescribeInstances,
# ec2:AssociateAddress, ec2:DisassociateAddress on the instance IAM role.

EIP_ALLOC_ID="eipalloc-xxxxxxxx"  # Replace with your EIP Allocation ID

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/dynamic/instance-identity/document \
  | grep region | awk -F\" '{print $4}')

ASSOC_ID=$(aws ec2 describe-addresses \
  --allocation-ids "$EIP_ALLOC_ID" \
  --region "$REGION" \
  --query "Addresses[0].AssociationId" \
  --output text)

if [ "$ASSOC_ID" != "None" ] && [ -n "$ASSOC_ID" ]; then
  aws ec2 disassociate-address --association-id "$ASSOC_ID" --region "$REGION"
fi

aws ec2 associate-address \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$EIP_ALLOC_ID" \
  --region "$REGION"
