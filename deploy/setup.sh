#!/bin/bash
# =============================================================
# AfriCart VPS Setup Script
# Bootstraps a fresh Ubuntu 24.04 VPS to run AfriCart
# Usage: bash deploy/setup.sh
# =============================================================

set -e
set -o pipefail

# -------------------------------------------------------------
# COLOURS — for readable terminal output
# -------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# -------------------------------------------------------------
# LOGGING FUNCTIONS
# -------------------------------------------------------------
log()    { echo -e "${GREEN}[AfriCart]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section(){ echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# -------------------------------------------------------------
# SANITY CHECKS — fail early if environment is wrong
# -------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  error "Please run as root: sudo bash deploy/setup.sh"
fi

if ! grep -q "Ubuntu" /etc/os-release; then
  error "This script is designed for Ubuntu only"
fi

log "AfriCart setup starting..."
log "Timestamp: $(date)"
# =============================================================
# SECTION 2: SYSTEM UPDATE + ESSENTIALS
# =============================================================
section "Updating system packages"

apt-get update -y
apt-get upgrade -y

log "Installing essential packages..."
apt-get install -y \
  curl \
  git \
  ufw \
  unzip \
  build-essential \
  ca-certificates \
  gnupg \
  lsb-release

log "System update complete"
# =============================================================
# SECTION 3: NODE.JS VIA NVM
# =============================================================
section "Installing Node.js 20 via NVM"

NVM_VERSION="v0.39.7"
NODE_VERSION="20"
NVM_DIR="/root/.nvm"

if [ -d "$NVM_DIR" ]; then
  warn "NVM already installed, skipping..."
else
  log "Downloading NVM $NVM_VERSION..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash
fi

# Load NVM into current shell session
export NVM_DIR="$NVM_DIR"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install Node if not already present
if nvm list | grep -q "v$NODE_VERSION"; then
  warn "Node.js $NODE_VERSION already installed, skipping..."
else
  log "Installing Node.js $NODE_VERSION..."
  nvm install $NODE_VERSION
  nvm use $NODE_VERSION
  nvm alias default $NODE_VERSION
fi

log "Node version: $(node -v)"
log "NPM version: $(npm -v)"
# =============================================================
# SECTION 4: MYSQL SETUP
# =============================================================
section "Setting up MySQL"

DB_NAME="africart"
DB_USER="africart_user"
DB_PASS="africart_$(openssl rand -hex 8)"

if systemctl is-active --quiet mysql; then
  warn "MySQL already running, skipping install..."
else
  log "Installing MySQL server..."
  apt-get install -y mysql-server
  systemctl start mysql
  systemctl enable mysql
fi

log "Creating database and user..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

log "MySQL ready"
log "Database : $DB_NAME"
log "User     : $DB_USER"
log "Password : $DB_PASS"

# Save credentials to a temp file so we can write .env later
mkdir -p /tmp/africart-install
echo "DB_NAME=$DB_NAME" > /tmp/africart-install/db.conf
echo "DB_USER=$DB_USER" >> /tmp/africart-install/db.conf
echo "DB_PASS=$DB_PASS" >> /tmp/africart-install/db.conf
# =============================================================
# SECTION 5: PM2 + FIREWALL + NGINX
# =============================================================
section "Installing PM2"

if command -v pm2 &> /dev/null; then
  warn "PM2 already installed, skipping..."
else
  npm install -g pm2
  pm2 startup systemd -u root --hp /root
fi

log "PM2 version: $(pm2 -v)"

# -------------------------------------------------------------
section "Configuring UFW Firewall"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw --force enable

log "Firewall active"
ufw status

# -------------------------------------------------------------
section "Detecting available ports"

find_free_port() {
  local port=$1
  while ss -tln | grep -q ":$port "; do
    port=$((port + 1))
  done
  echo $port
}

WEB_PORT=$(find_free_port 3000)
API_PORT=$(find_free_port 3001)

if [ "$API_PORT" -eq "$WEB_PORT" ]; then
  API_PORT=$(find_free_port $((WEB_PORT + 1)))
fi

log "Storefront will run on port: $WEB_PORT"
log "API will run on port: $API_PORT"

# -------------------------------------------------------------
section "Installing Nginx"

if command -v nginx &> /dev/null; then
  warn "Nginx already installed, skipping..."
else
  apt-get install -y nginx
  systemctl start nginx
  systemctl enable nginx
fi

# Write Nginx reverse proxy config for AfriCart
cat > /etc/nginx/sites-available/africart <<NGINXCONF
server {
    listen 80;
    server_name _;

    # Storefront (Next.js)
    location / {
        proxy_pass http://localhost:$WEB_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    # API (Node/Express)
    location /api/ {
        proxy_pass http://localhost:$API_PORT/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINXCONF

# Enable the site
ln -sf /etc/nginx/sites-available/africart /etc/nginx/sites-enabled/africart
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

log "Nginx configured and running"
# =============================================================
# SECTION 6: CLONE REPO + INSTALL DEPENDENCIES
# =============================================================
section "Cloning AfriCart repository"

INSTALL_DIR="/var/www/africart"
REPO_URL="https://github.com/calvinoyuyo/africart-.git"

if [ -d "$INSTALL_DIR" ]; then
  warn "AfriCart already exists at $INSTALL_DIR, pulling latest..."
  cd "$INSTALL_DIR" && git pull
else
  git clone "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

log "Installing frontend dependencies..."
npm install

log "Installing backend dependencies..."
cd "$INSTALL_DIR/server" && npm install

cd "$INSTALL_DIR"
log "Dependencies installed"

# =============================================================
# SECTION 7: WRITE .ENV + RUN MIGRATIONS + START WITH PM2
# =============================================================
section "Configuring environment"

# Load the DB credentials we saved in Section 4
source /tmp/africart-install/db.conf

# Write root .env (Next.js frontend)
cat > "$INSTALL_DIR/.env" <<ENVFILE
DATABASE_URL="mysql://$DB_USER:$DB_PASS@localhost:3306/$DB_NAME"
NEXTAUTH_SECRET="$(openssl rand -hex 32)"
NEXTAUTH_URL="http://localhost:$WEB_PORT"
NEXT_PUBLIC_API_BASE_URL="http://localhost:$API_PORT"
ENVFILE

# Write server .env (Express backend)
cat > "$INSTALL_DIR/server/.env" <<SERVERENV
DATABASE_URL="mysql://$DB_USER:$DB_PASS@localhost:3306/$DB_NAME"
PORT=$API_PORT
NODE_ENV=production
SERVERENV

log ".env files written"

section "Running database migrations"
cd "$INSTALL_DIR"
npx prisma migrate deploy

section "Starting AfriCart with PM2"
cd "$INSTALL_DIR"

# Build Next.js
npm run build

# Start backend API
pm2 start server/app.js --name "africart-api"

# Start frontend
pm2 start npm --name "africart-web" -- start -- -p $WEB_PORT

pm2 save

# =============================================================
# SECTION 8: SUCCESS SUMMARY
# =============================================================
SERVER_IP=$(curl -s ifconfig.me)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  AfriCart is live!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Store URL   : ${BLUE}http://$SERVER_IP${NC}"
echo -e "  Admin panel : ${BLUE}http://$SERVER_IP/admin${NC}"
echo -e "  API         : ${BLUE}http://$SERVER_IP/api${NC}"
echo ""
echo -e "  DB Name     : $DB_NAME"
echo -e "  DB User     : $DB_USER"
echo -e "  DB Password : $DB_PASS"
echo ""
echo -e "${YELLOW}  Save your DB password — it won't be shown again${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Clean up temp files
rm -rf /tmp/africart-install
