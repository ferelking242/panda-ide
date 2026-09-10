#!/bin/bash
# ── install_claude_code.sh ──
# Installs Claude Code CLI using the Node.js/npm already provided by Panda.
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

# ── 1. Validate the terminal toolchain ──────────────────────────────────────
if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
  err "Node.js/npm are not installed in the Panda terminal."
  err "Open the terminal and run: panda update"
  exit 1
fi

NODE_VER=$(node --version 2>/dev/null | sed 's/^v//')
NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
  err "Node.js >= 18 is required, but the terminal has ${NODE_VER:-no version}."
  err "Open the terminal and run: panda update"
  exit 1
fi
ok "Using terminal Node.js v${NODE_VER} and npm $(npm --version)"

# ── 2. Install Claude Code ──────────────────────────────────────────────────
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
