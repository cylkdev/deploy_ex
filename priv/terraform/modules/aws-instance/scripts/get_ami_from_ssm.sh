#!/usr/bin/env bash
set -euo pipefail

AMI_ID="$(aws ssm get-parameters \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-arm64 \
  --region us-west-1 \
  --query "Parameters[0].Value" \
  --output text)"

printf '{"ami_id":"%s"}\n' "$AMI_ID"
