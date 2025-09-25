#!/usr/bin/env bash
# Automate PostgreSQL DB + user creation, Django project, Gunicorn + Nginx
# Uses YAML config or interactive prompts

set -e
CONFIG_FILE="db_setup.yaml"

# === Functions ===
yaml_read() {
  local key=$1
  [[ -f "$CONFIG_FILE" ]] && grep -E "^${key}:" "$CONFIG_FILE" | awk -F': ' '{print $2}' | tr -d '"'
}

ask_if_empty() {
  local varname=$1 prompt=$2 default=$3
  local value="${!varname}"
  if [[ -z "$value" ]]; then
    read -rp "$prompt [${default}]: " input
    eval "$varname='${input:-$default}'"
  fi
}

# === Load from YAML ===
DBNAME=$(yaml_read dbname)
DBUSER=$(yaml_read dbuser)
DBPASS=$(yaml_read dbpass)
ENCODING=$(yaml_read encoding)
ISOLATION=$(yaml_read isolation)
TIMEZONE=$(yaml_read timezone)
PROJECT_NAME=$(yaml_read project_name)
DOMAIN=$(yaml_read domain)
PROJECT_DIR=$(yaml_read project_dir)
SYSTEM_USER=$(yaml_read system_user)
PYTHON_BIN=$(yaml_read python_bin)

# === Ask interactively if missing ===
ask_if_empty DBNAME "Enter database name" "mydb"
ask_if_empty DBUSER "Enter database username" "myuser"
ask_if_empty DBPASS "Enter password for $DBUSER" "changeme"
ask_if_empty ENCODING "Enter client encoding" "utf8"
ask_if_empty ISOLATION "Enter default transaction isolation" "read committed"
ask_if_empty TIMEZONE "Enter default timezone" "UTC"
ask_if_empty PROJECT_NAME "Enter Django project name" "hellogjango"
ask_if_empty DOMAIN "Enter domain for Nginx vhost" "hellogjango.local"
ask_if_empty PROJECT_DIR "Enter Django project directory" "/var/www/$PROJECT_NAME"
ask_if_empty SYSTEM_USER "Enter system user for Gunicorn" "www-data"
ask_if_empty PYTHON_BIN "Enter Python binary path" "python3"

# === PostgreSQL ===
SQL=$(cat <<EOF
CREATE DATABASE "$DBNAME";
CREATE USER "$DBUSER" WITH PASSWORD '$DBPASS';
ALTER ROLE "$DBUSER" SET client_encoding TO '$ENCODING';
ALTER ROLE "$DBUSER" SET default_transaction_isolation TO '$ISOLATION';
ALTER ROLE "$DBUSER" SET timezone TO '$TIMEZONE';
GRANT ALL PRIVILEGES ON DATABASE "$DBNAME" TO "$DBUSER";
EOF
)
echo "📦 Creating PostgreSQL DB and user..."
echo "$SQL" | sudo -u postgres psql
echo "✅ Database '$DBNAME' and user '$DBUSER' created."

# === Project folder + venv ===
echo "📂 Creating project folder and virtual environment..."
sudo mkdir -p "$PROJECT_DIR"
sudo chown -R "$USER":"$USER" "$PROJECT_DIR"

if [[ ! -d "$PROJECT_DIR/venv" ]]; then
    $PYTHON_BIN -m venv "$PROJECT_DIR/venv"
fi

source "$PROJECT_DIR/venv/bin/activate"
pip install --upgrade pip
pip install django gunicorn psycopg2-binary

# Create Django project if missing
if [[ ! -d "$PROJECT_DIR/$PROJECT_NAME" ]]; then
    django-admin startproject "$PROJECT_NAME" "$PROJECT_DIR"
fi

# Update settings.py to use PostgreSQL
SETTINGS="$PROJECT_DIR/$PROJECT_NAME/settings.py"
sed -i "s/'ENGINE': 'django.db.backends.sqlite3'/'ENGINE': 'django.db.backends.postgresql'/" "$SETTINGS"
sed -i "s/'NAME': BASE_DIR \/ 'db.sqlite3'/'NAME': '$DBNAME'/" "$SETTINGS"
sed -i "/'NAME':/a\        'USER': '$DBUSER',\n        'PASSWORD': '$DBPASS',\n        'HOST': 'localhost',\n        'PORT': '5432'," "$SETTINGS"

python manage.py migrate
python manage.py collectstatic --noinput
deactivate

# === Gunicorn systemd service ===
SERVICE_FILE="/etc/systemd/system/$PROJECT_NAME.service"
echo "⚙️  Creating Gunicorn systemd service..."
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=gunicorn daemon for $PROJECT_NAME
After=network.target

[Service]
User=$SYSTEM_USER
Group=$SYSTEM_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/gunicorn \\
          --access-logfile - \\
          --workers 3 \\
          --bind unix:$PROJECT_DIR/$PROJECT_NAME.sock \\
          $PROJECT_NAME.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now "$PROJECT_NAME"

# === Nginx vhost ===
NGINX_FILE="/etc/nginx/sites-available/$PROJECT_NAME"
echo "🌐 Creating Nginx vhost..."
sudo tee "$NGINX_FILE" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        root $PROJECT_DIR;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$PROJECT_DIR/$PROJECT_NAME.sock;
    }
}
EOF

sudo ln -sf "$NGINX_FILE" /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "🎉 Setup finished! Visit http://$DOMAIN"
