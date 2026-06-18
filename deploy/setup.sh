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
