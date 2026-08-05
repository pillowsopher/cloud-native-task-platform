#!/bin/bash
set -e
ACCOUNT_ID="$1"
REGION="ap-south-1"

aws s3 sync "s3://uptime-monitor-deploy-manifests-${ACCOUNT_ID}/manifests/" /tmp/manifests
sudo k3s kubectl apply -f /tmp/manifests

aws ecr get-login-password --region "$REGION" | \
  sudo k3s kubectl create secret docker-registry ecr-registry-credentials \
    --docker-server="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com" \
    --docker-username=AWS \
    --docker-password-stdin \
    -n uptime-monitor \
    --dry-run=client -o yaml | sudo k3s kubectl apply -f -
