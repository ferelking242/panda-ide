#!/bin/bash
# ── install_lsp_servers.sh ──
# Installs all supported LSP servers for Panda IDE inside PRoot Debian ARM64.
# Run from Panda IDE terminal:  bash /root/.panda/scripts/install_lsp_servers.sh
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${CYAN}[lsp-install]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

if [ "$(id -u)" != "0" ]; then
  err "Must run as root."
  exit 1
fi

log "Starting LSP server installation..."

# ── 1. Node.js (required for most LSP servers) ──────────────────────────
if ! command -v node &>/dev/null; then
  log "Installing Node.js..."
  apt-get update -qq 2>/dev/null || true
  curl -fsSL https://deb.nodesource.com/setup_20.x 2>/dev/null | bash - 2>/dev/null || {
    warn "NodeSource failed, trying apt..."
    apt-get install -y -qq nodejs npm 2>/dev/null || true
  }
  apt-get install -y -qq nodejs 2>/dev/null || true
fi

if command -v node &>/dev/null; then
  ok "Node.js $(node --version) ready"
else
  err "Node.js not available — skipping npm-based LSP servers"
fi

# ── 2. npm-based LSP servers (all at once) ─────────────────────────────
if command -v npm &>/dev/null; then
  log "Installing npm LSP servers (typescript, json, html, css, yaml, bash, docker, markdown)..."
  npm install -g \
    typescript-language-server \
    typescript \
    vscode-langservers-extracted \
    yaml-language-server \
    bash-language-server \
    dockerfile-language-server-nodejs \
    markdown-language-server \
    2>&1 | tail -5

  ok "npm LSP servers installed"
else
  warn "npm not available — skipping npm-based LSP servers"
fi

# ── 3. Python LSP Server ───────────────────────────────────────────────
if command -v python3 &>/dev/null && command -v pip3 &>/dev/null; then
  log "Installing python-lsp-server..."
  pip3 install python-lsp-server 2>&1 | tail -3
  ok "Python LSP server installed"
elif command -v python3 &>/dev/null; then
  warn "pip3 not found — installing via get-pip..."
  python3 -m ensurepip 2>/dev/null || curl -sS https://bootstrap.pypa.io/get-pip.py | python3 2>/dev/null
  python3 -m pip install python-lsp-server 2>&1 | tail -3
  ok "Python LSP server installed"
else
  warn "Python3 not available — skipping Python LSP server"
fi

# ── 4. clangd (C/C++) ──────────────────────────────────────────────────
if ! command -v clangd &>/dev/null; then
  log "Installing clangd..."
  apt-get install -y -qq clangd 2>/dev/null || true
fi

if command -v clangd &>/dev/null; then
  ok "clangd $(clangd --version 2>/dev/null | head -1) ready"
else
  warn "clangd not available"
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
ok "════════════════════════════════════════════════"
ok "  LSP server installation complete!"
ok ""
ok "  Installed servers:"

check_server() {
  local cmd=$1
  local name=$2
  if command -v "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $name"
  else
    echo -e "  ${RED}✗${NC} $name (not installed)"
  fi
}

check_server typescript-language-server "TypeScript/JavaScript"
check_server vscode-json-language-server "JSON"
check_server vscode-html-language-server "HTML"
check_server vscode-css-language-server "CSS"
check_server pylsp "Python"
check_server clangd "C/C++"
check_server bash-language-server "Bash"
check_server docker-langserver "Dockerfile"
check_server yaml-language-server "YAML"
check_server markdown-language-server "Markdown"

ok "════════════════════════════════════════════════"
