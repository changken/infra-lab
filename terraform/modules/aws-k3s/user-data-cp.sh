#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================="
echo "Starting K3s control plane setup at $(date)"
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

# Install K3s server (use EIP for TLS SAN)
echo "[3/4] Installing K3s server..."
PUBLIC_IP="${public_ip}"
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san "$PUBLIC_IP" \
  --node-external-ip "$PUBLIC_IP" \
  --node-name "${hostname}"

# Wait for K3s to generate node token, then write to SSM
echo "[4/4] Writing node token to SSM..."
until [ -f /var/lib/rancher/k3s/server/node-token ]; do
  echo "Waiting for K3s token file..."
  sleep 2
done

aws ssm put-parameter \
  --name "/k3s-lab/node-token" \
  --value "$(cat /var/lib/rancher/k3s/server/node-token)" \
  --type SecureString \
  --region "${aws_region}" \
  --overwrite

echo "========================================="
echo "Setup complete at $(date)"
echo "EIP: ${public_ip}"
echo "To get kubeconfig:"
echo "  tailscale ssh ubuntu@${hostname} 'sudo cat /etc/rancher/k3s/k3s.yaml'"
echo "========================================="
