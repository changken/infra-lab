#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================="
echo "Starting K3s worker setup at $(date)"
echo "========================================="

# Set hostname
hostnamectl set-hostname "${hostname}"

# Update system
echo "[1/4] Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Tailscale
echo "[2/4] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up \
  --authkey="${tailscale_auth_key}" \
  --ssh \
  --hostname="${hostname}" \
  --accept-routes

# Poll SSM for K3s token (max 10 minutes: 60 retries x 10s)
echo "[3/4] Waiting for K3s token from SSM..."
TOKEN=""
for i in $(seq 1 60); do
  TOKEN=$(aws ssm get-parameter \
    --name "/k3s-lab/node-token" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "${aws_region}" 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then
    echo "Token received on attempt $i"
    break
  fi
  echo "Waiting for K3s token... ($i/60)"
  sleep 10
done

if [ -z "$TOKEN" ]; then
  echo "ERROR: timed out waiting for K3s token after 10 minutes"
  exit 1
fi

# Join K3s cluster via CP private IP
echo "[4/4] Joining K3s cluster..."
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${cp_private_ip}:6443" \
  K3S_TOKEN="$TOKEN" \
  sh -s - agent \
  --node-name "${hostname}"

echo "========================================="
echo "Setup complete at $(date)"
echo "Node ${hostname} joined cluster at ${cp_private_ip}"
echo "========================================="
