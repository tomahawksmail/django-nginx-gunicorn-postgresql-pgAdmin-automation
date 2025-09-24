#!/usr/bin/env bash

# === Check if running as root ===
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (sudo)."
  exit 1
fi

# === Check if certbot is installed ===
if ! command -v certbot >/dev/null 2>&1; then
  echo "Certbot not found. Installing..."
  # Try OS detection
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

# === Ask for domain name ===
read -rp "Enter your domain name (example.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
  echo "No domain entered. Exiting."
  exit 1
fi

# === Build domain list (root + www) ===
DOMAIN_WWW="www.$DOMAIN"

# === Ask for email ===
read -rp "Enter your email for Let's Encrypt notifications: " EMAIL

if [[ -z "$EMAIL" ]]; then
  echo "No email entered. Exiting."
  exit 1
fi

# === Run Certbot ===
echo "Requesting certificate for: $DOMAIN and $DOMAIN_WWW"
certbot --nginx \
  -d "$DOMAIN" -d "$DOMAIN_WWW" \
  --email "$EMAIL" \
  --agree-tos \
  --non-interactive

# === Show certs installed ===
certbot certificates
