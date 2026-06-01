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
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install AWS CLI v2
echo "[2/5] Installing AWS CLI v2..."
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
apt-get install -y unzip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Install K3s server (use EIP for TLS SAN)
echo "[3/5] Installing K3s server..."
PUBLIC_IP="${public_ip}"
curl -sfL https://get.k3s.io | sh -s - server \
  --tls-san "$PUBLIC_IP" \
  --node-external-ip "$PUBLIC_IP" \
  --node-name "${hostname}"

# Wait for K3s to generate node token, then write to SSM
echo "[4/5] Writing node token to SSM..."
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

# Install Tailscale
echo "[5/5] Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
TAILSCALE_KEY=$(aws ssm get-parameter \
  --name "/k3s-lab/tailscale-auth-key" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "${aws_region}")
tailscale up \
  --authkey="$TAILSCALE_KEY" \
  --ssh \
  --hostname="${hostname}" \
  --accept-routes \
  --timeout 2m \
  || echo "[WARN] Tailscale setup failed — K3s is running, connect via EC2 console if needed"

echo "========================================="
echo "Setup complete at $(date)"
echo "EIP: ${public_ip}"
echo "To get kubeconfig:"
echo "  tailscale ssh ubuntu@${hostname} 'sudo cat /etc/rancher/k3s/k3s.yaml'"
echo "========================================="
