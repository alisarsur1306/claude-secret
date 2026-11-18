#!/bin/bash
# Install (or update / uninstall) the /secret skill for Claude Code.
# Works on macOS and on Windows (run it from Git Bash, which Claude Code uses).
#
#   ./install.sh               install or update
#   ./install.sh --uninstall   remove the skill (saved secrets are kept)
#
# Installs into ${CLAUDE_CONFIG_DIR:-~/.claude}/skills/secret. Touches nothing else.

set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/skill"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CONFIG_DIR/skills/secret"
FILES="secret secret-phone.py secret-win.ps1"

say()  { printf '%s\n' "$*"; }
fail() { printf 'install: %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin)               OS=mac ;;
  MINGW*|MSYS*|CYGWIN*) OS=win ;;
  *) fail "unsupported OS — needs macOS, or Windows with Git Bash" ;;
esac

[ -f "$SRC/SKILL.md" ] || fail "run this from a clone of the repo (missing skill/SKILL.md)"

if [ "${1:-}" = "--uninstall" ]; then
  case "$DEST" in */skills/secret) ;; *) fail "refusing to remove unexpected path: $DEST" ;; esac
  if [ -d "$DEST" ]; then
    rm -r -- "$DEST"
    say "Removed $DEST"
  else
    say "Not installed at $DEST"
  fi
  if [ "$OS" = mac ]; then
    say "Saved secrets stay in the Keychain (search \"Claude secret\" in Keychain Access.app)."
  else
    say "Saved secrets stay in Credential Manager (Windows Credentials, \"claude-secret:*\")."
  fi
  exit 0
fi

if [ "$OS" = mac ]; then
  command -v security >/dev/null || fail "'security' (macOS Keychain CLI) not found"
else
  command -v powershell.exe >/dev/null || fail "powershell.exe not found"
fi
command -v perl >/dev/null || fail "perl not found (ships with macOS and Git for Windows)"

mkdir -p "$DEST/bin"
cp "$SRC/SKILL.md" "$DEST/SKILL.md"
for f in $FILES; do cp "$SRC/bin/$f" "$DEST/bin/$f"; done
chmod 755 "$DEST/bin/secret" "$DEST/bin/secret-phone.py"

# SKILL.md refers to ~/.claude/skills/secret; point it at a custom config dir if one is set.
if [ "$CONFIG_DIR" != "$HOME/.claude" ]; then
  esc=$(printf '%s' "$DEST" | sed 's/[&|]/\\&/g')
  sed "s|~/.claude/skills/secret|$esc|g" "$DEST/SKILL.md" > "$DEST/SKILL.md.tmp"
  mv "$DEST/SKILL.md.tmp" "$DEST/SKILL.md"
fi

say "Installed /secret skill -> $DEST"

# Optional dependencies for the phone link (/secret NAME phone)
missing=""
python3 -c 'import sys' >/dev/null 2>&1 || python -c 'import sys' >/dev/null 2>&1 \
  || py -c 'import sys' >/dev/null 2>&1 || missing="$missing python"
command -v cloudflared >/dev/null 2>&1 || missing="$missing cloudflared"
if [ -n "$missing" ]; then
  say ""
  say "Optional: the phone link needs:$missing"
  if [ "$OS" = mac ]; then
    say "  brew install$missing" | sed 's/ python/ python3/'
  else
    say "  winget install Python.Python.3.12 Cloudflare.cloudflared   (install what is missing)"
  fi
fi

say ""
say "Start a new Claude Code session, then try:  /secret MY_TOKEN"
