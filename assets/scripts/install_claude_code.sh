#!/bin/bash
# ── install_claude_code.sh ──
# Installs Node.js 20 LTS + npm + Claude Code CLI inside PRoot Debian ARM64.
# Run from Panda IDE terminal:  bash /root/.panda/scripts/install_claude_code.sh
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${CYAN}[claude-install]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

# ── 0. Preflight ────────────────────────────────────────────────────────────
if [ "$(id -u)" != "0" ]; then
  err "This script must run as root (sudo or PRoot -0)."
  exit 1
fi

log "Starting Claude Code installation..."

# ── 1. Update apt ───────────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -qq 2>/dev/null || warn "apt update had warnings (non-fatal)"

# ── 2. Install curl if missing ──────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
  log "Installing curl..."
  apt-get install -y -qq curl ca-certificates >/dev/null 2>&1
fi

# ── 3. Check existing Node.js ──────────────────────────────────────────────
NEED_NODE=true
if command -v node &>/dev/null; then
  NODE_VER=$(node --version 2>/dev/null | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
    ok "Node.js v${NODE_VER} already installed (>= 18)"
    NEED_NODE=false
  else
    warn "Node.js v${NODE_VER} is too old (need >= 18). Will upgrade."
  fi
fi

if [ "$NEED_NODE" = true ]; then
  log "Installing Node.js 20 LTS..."

  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64) NODE_ARCH="linux-arm64" ;;
    armv7l)  NODE_ARCH="linux-armv7l" ;;
    x86_64)  NODE_ARCH="linux-x64" ;;
    *)       NODE_ARCH="linux-arm64"; warn "Unknown arch $ARCH, defaulting to arm64" ;;
  esac

  # Try NodeSource first, fall back to direct binary download
  if curl -fsSL https://deb.nodesource.com/setup_20.x 2>/dev/null | bash - 2>/dev/null; then
    apt-get install -y -qq nodejs >/dev/null 2>&1
  else
    warn "NodeSource failed, downloading binary directly..."
    NODE_VERSION="20.18.1"
    NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz"
    cd /tmp
    curl -fSL "$NODE_URL" -o node.tar.xz 2>/dev/null
    tar -xJf node.tar.xz -C /usr/local --strip-components=1
    rm -f node.tar.xz
    cd -
  fi

  if command -v node &>/dev/null; then
    ok "Node.js $(node --version) installed"
  else
    err "Node.js installation failed!"
    exit 1
  fi
fi

# ── 4. Ensure npm is available ──────────────────────────────────────────────
if ! command -v npm &>/dev/null; then
  log "Installing npm..."
  apt-get install -y -qq npm 2>/dev/null || {
    warn "apt npm failed, using corepack..."
    corepack enable 2>/dev/null || true
  }
fi

if command -v npm &>/dev/null; then
  ok "npm $(npm --version) ready"
else
  err "npm not found!"
  exit 1
fi

# ── 5. Install Claude Code ──────────────────────────────────────────────────
log "Installing Claude Code (npm install -g @anthropic-ai/claude-code)..."
npm install -g @anthropic-ai/claude-code 2>&1 | tail -5

if command -v claude &>/dev/null || [ -f /usr/local/bin/claude ] || [ -f /usr/bin/claude ]; then
  echo ""
  ok "════════════════════════════════════════════════"
  ok "  Claude Code installed successfully!"
  ok "  Run:  claude"
  ok "════════════════════════════════════════════════"
  echo ""
  claude --version 2>/dev/null || true
else
  # npm global bin might not be in PATH
  NPM_BIN=$(npm config get prefix 2>/dev/null)/bin
  if [ -f "$NPM_BIN/claude" ]; then
    export PATH="$NPM_BIN:$PATH"
    ok "Claude Code installed at $NPM_BIN/claude"
    ok "Add to PATH: export PATH=\"$NPM_BIN:\$PATH\""
  else
    err "Claude Code binary not found after install."
    warn "Try: npm list -g --depth=0"
    exit 1
  fi
fi
