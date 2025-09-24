#!/usr/bin/env bash

CONFIG_FILE="./CertBotConfig.yaml"

# === Check if running as root ===
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

# === Check if certbot is installed ===
if ! command -v certbot >/dev/null 2>&1; then
  echo "Certbot not found. Installing..."
  if [[ -f /etc/debian_version ]]; then
    apt update
    apt install -y certbot python3-certbot-nginx
  elif [[ -f /etc/redhat-release ]]; then
    yum install -y certbot python3-certbot-nginx
  else
    echo "Unsupported OS. Please install certbot manually."
    exit 1
  fi
fi

# === Check if yq is installed (for YAML parsing) ===
if ! command -v yq >/dev/null 2>&1; then
  echo "yq not found. Installing..."
  if [[ -f /etc/debian_version ]]; then
    apt update
    apt install -y yq
  elif [[ -f /etc/redhat-release ]]; then
    yum install -y epel-release
    yum install -y yq
  else
    echo "Unsupported OS. Please install 'yq' manually."
    exit 1
  fi
fi

# === Load config from YAML if exists ===
if [[ -f "$CONFIG_FILE" ]]; then
  DOMAIN=$(yq -r '.domain // empty' "$CONFIG_FILE")
  EMAIL=$(yq -r '.email // empty' "$CONFIG_FILE")
fi

# === If not in config, ask user ===
if [[ -z "$DOMAIN" ]]; then
  read -rp "Enter your domain name (example.com): " DOMAIN
fi
DOMAIN_WWW="www.$DOMAIN"

if [[ -z "$EMAIL" ]]; then
  read -rp "Enter your email for Let's Encrypt notifications: " EMAIL
fi

# === Request certificate ===
echo "Requesting certificate for: $DOMAIN and $DOMAIN_WWW"
certbot --nginx \
  -d "$DOMAIN" -d "$DOMAIN_WWW" \
  --email "$EMAIL" \
  --agree-tos \
  --non-interactive

# === Show installed certificates ===
certbot certificates

# === Setup Auto-Renew ===
echo "Setting up automatic renewal..."

if systemctl list-timers | grep -q certbot; then
  echo "Systemd timer for certbot already active."
else
  echo "No systemd timer found, adding cron job."
  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
  echo "Cron job added: daily renewal attempt at 03:00."
fi

echo "✅ Setup complete! Your certificate will auto-renew."
