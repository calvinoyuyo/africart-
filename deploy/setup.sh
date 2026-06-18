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
