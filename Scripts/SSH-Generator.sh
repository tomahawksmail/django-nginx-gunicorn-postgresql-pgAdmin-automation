#!/usr/bin/env bash
# Automated SSH key setup for Ubuntu server

set -e

# === CONFIG / DEFAULTS ===
KEY_TYPE="ed25519"
KEY_FILE="$HOME/.ssh/id_${KEY_TYPE}"
SSH_USER=""
SSH_HOST=""
SSH_PORT=22
DISABLE_PASSWORD_AUTH="no"   # set to "yes" to disable password logins after key setup

# === FUNCTIONS ===
function ask_if_empty() {
  local varname=$1
  local prompt=$2
  local default=$3
  local value="${!varname}"

  if [[ -z "$value" ]]; then
    read -rp "$prompt [${default}]: " input
    if [[ -z "$input" ]]; then
      eval "$varname='$default'"
    else
      eval "$varname='$input'"
    fi
  fi
}

# === ASK USER ===
ask_if_empty SSH_USER "Enter SSH username" "ubuntu"
ask_if_empty SSH_HOST "Enter SSH server (IP or hostname)" "server.example.com"
ask_if_empty SSH_PORT "Enter SSH port" "22"

# === GENERATE SSH KEY IF NOT EXIST ===
if [[ ! -f "$KEY_FILE" ]]; then
  echo "🔑 Generating new SSH key: $KEY_FILE"
  ssh-keygen -t "$KEY_TYPE" -f "$KEY_FILE" -C "$USER@$(hostname)" -N ""
else
  echo "✅ SSH key already exists: $KEY_FILE"
fi

# === COPY KEY TO SERVER ===
echo "📤 Copying public key to $SSH_USER@$SSH_HOST ..."
ssh-copy-id -i "${KEY_FILE}.pub" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST"

# === TEST LOGIN ===
echo "🧪 Testing key-based login..."
ssh -i "$KEY_FILE" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "echo '✅ Key-based login works on $(hostname)'"

# === HARDEN SSH (OPTIONAL) ===
if [[ "$DISABLE_PASSWORD_AUTH" == "yes" ]]; then
  echo "⚙️  Disabling password authentication on server..."
  ssh -i "$KEY_FILE" -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl reload sshd"
  echo "🚫 Password authentication disabled. Keep this key safe!"
fi

echo "🎉 Done! You can now connect using:"
echo "ssh -i $KEY_FILE -p $SSH_PORT $SSH_USER@$SSH_HOST"
