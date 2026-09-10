#!/bin/bash
# ── install_lsp_servers.sh ──
# Installs common LSP servers inside PRoot Debian ARM64.
# TypeScript/JavaScript, HTML, CSS, JSON, Bash, Python, Dockerfile
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
  err "This script must run as root."
  exit 1
fi

log "Installing LSP servers for Panda IDE..."

# ── 1. Update package lists for non-Node tools ──
apt-get update -qq 2>/dev/null || warn "apt update had warnings"

# ── 2. Validate terminal Node.js/npm ──
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

# ── 3. TypeScript + JSON + HTML + CSS (via terminal npm) ──
log "Installing TypeScript LSP..."
npm install -g typescript-language-server typescript 2>&1 | tail -2
ok "TypeScript LSP installed"

log "Installing HTML/CSS/JSON LSP servers..."
npm install -g vscode-langservers-extracted 2>&1 | tail -2
ok "HTML/CSS/JSON LSP servers installed"

# ── 4. Bash LSP ──
log "Installing Bash LSP..."
npm install -g bash-language-server 2>&1 | tail -2
ok "Bash LSP installed"

# ── 5. Dockerfile LSP ──
log "Installing Dockerfile LSP..."
npm install -g dockerfile-language-server-nodejs 2>&1 | tail -2
ok "Dockerfile LSP installed"

# ── 6. YAML LSP ──
log "Installing YAML LSP..."
npm install -g yaml-language-server 2>&1 | tail -2
ok "YAML LSP installed"

# ── 7. Python LSP ──
log "Installing Python LSP..."
if command -v pip3 &>/dev/null; then
  pip3 install python-lsp-server 2>&1 | tail -2
  ok "Python LSP installed"
elif command -v python3 &>/dev/null; then
  python3 -m pip install python-lsp-server 2>&1 | tail -2
  ok "Python LSP installed"
else
  warn "Python not found, skipping Python LSP"
fi

# ── 8. clangd (C/C++) ──
log "Installing clangd (C/C++)..."
apt-get install -y -qq clangd 2>/dev/null || warn "clangd install failed"
ok "clangd installed"

echo ""
ok "════════════════════════════════════════════════"
ok "  LSP servers installed!"
ok "  Restart the editor to activate LSP."
ok "════════════════════════════════════════════════"
echo ""
echo "Installed servers:"
typescript-language-server --version 2>/dev/null && echo "  TypeScript ✓"
vscode-json-language-server --version 2>/dev/null && echo "  JSON ✓"
vscode-html-language-server --version 2>/dev/null && echo "  HTML ✓"
vscode-css-language-server --version 2>/dev/null && echo "  CSS ✓"
bash-language-server --version 2>/dev/null && echo "  Bash ✓"
clangd --version 2>/dev/null && echo "  C/C++ ✓"
