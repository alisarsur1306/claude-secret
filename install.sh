#!/bin/bash
# Install (or update / uninstall) the /secret skill for Claude Code.
#
#   ./install.sh               install or update
#   ./install.sh --uninstall   remove the skill (Keychain secrets are kept)
#
# Installs into ${CLAUDE_CONFIG_DIR:-~/.claude}/skills/secret. Touches nothing else.

set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/skill"
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CONFIG_DIR/skills/secret"

say()  { printf '%s\n' "$*"; }
fail() { printf 'install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "macOS only — the skill stores secrets in the macOS Keychain."
[ -f "$SRC/SKILL.md" ] || fail "run this from a clone of the repo (missing skill/SKILL.md)"

if [ "${1:-}" = "--uninstall" ]; then
  case "$DEST" in */skills/secret) ;; *) fail "refusing to remove unexpected path: $DEST" ;; esac
  if [ -d "$DEST" ]; then
    rm -r -- "$DEST"
    say "Removed $DEST"
  else
    say "Not installed at $DEST"
  fi
  say "Your saved secrets are still in the Keychain (service \"claude-secret\")."
  say "Remove them in Keychain Access.app (search \"Claude secret\") if you no longer need them."
  exit 0
fi

command -v security >/dev/null || fail "'security' (macOS Keychain CLI) not found"
command -v perl >/dev/null     || fail "perl not found (ships with macOS)"

mkdir -p "$DEST/bin"
cp "$SRC/SKILL.md" "$DEST/SKILL.md"
cp "$SRC/bin/secret" "$SRC/bin/secret-phone.py" "$DEST/bin/"
chmod 755 "$DEST/bin/secret" "$DEST/bin/secret-phone.py"

# SKILL.md refers to ~/.claude/skills/secret; point it at a custom config dir if one is set.
if [ "$CONFIG_DIR" != "$HOME/.claude" ]; then
  esc=$(printf '%s' "$DEST" | sed 's/[&|]/\\&/g')
  sed -i '' "s|~/.claude/skills/secret|$esc|g" "$DEST/SKILL.md"
fi

say "Installed /secret skill -> $DEST"

# Optional dependencies for the phone link (/secret NAME phone)
missing=""
command -v python3 >/dev/null     || missing="$missing python3"
command -v cloudflared >/dev/null || missing="$missing cloudflared"
if [ -n "$missing" ]; then
  say ""
  say "Optional: the phone link needs:$missing"
  say "  brew install$missing"
fi

say ""
say "Start a new Claude Code session, then try:  /secret MY_TOKEN"
