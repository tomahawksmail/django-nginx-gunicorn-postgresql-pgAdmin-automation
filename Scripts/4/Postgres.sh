#!/usr/bin/env bash
# Automate PostgreSQL database and user creation with YAML or interactive prompts

set -e
CONFIG_FILE="db_setup.yaml"

# === Function: read from YAML ===
function yaml_read() {
  local key=$1
  if [[ -f "$CONFIG_FILE" ]]; then
    grep -E "^${key}:" "$CONFIG_FILE" | awk -F': ' '{print $2}' | tr -d '"'
  fi
}

# === Function: ask if empty ===
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

# === Load from YAML or fallback ===
DBNAME=$(yaml_read dbname)
DBUSER=$(yaml_read dbuser)
DBPASS=$(yaml_read dbpass)
ENCODING=$(yaml_read encoding)
ISOLATION=$(yaml_read isolation)
TIMEZONE=$(yaml_read timezone)

# === Ask interactively if missing ===
ask_if_empty DBNAME "Enter database name" "mydb"
ask_if_empty DBUSER "Enter database username" "myuser"
ask_if_empty DBPASS "Enter password for $DBUSER" "changeme"
ask_if_empty ENCODING "Enter client encoding" "utf8"
ask_if_empty ISOLATION "Enter default transaction isolation" "read committed"
ask_if_empty TIMEZONE "Enter default timezone" "UTC"

# === Run SQL commands ===
SQL=$(cat <<EOF
CREATE DATABASE "$DBNAME";
CREATE USER "$DBUSER" WITH PASSWORD '$DBPASS';
ALTER ROLE "$DBUSER" SET client_encoding TO '$ENCODING';
ALTER ROLE "$DBUSER" SET default_transaction_isolation TO '$ISOLATION';
ALTER ROLE "$DBUSER" SET timezone TO '$TIMEZONE';
GRANT ALL PRIVILEGES ON DATABASE "$DBNAME" TO "$DBUSER";
EOF
)

echo "📦 Creating database and user in PostgreSQL..."
echo "$SQL" | sudo -u postgres psql

echo "✅ Database '$DBNAME' and user '$DBUSER' created successfully."
