#!/usr/bin/env bash
#
# Taskmaster installer for Codex
#
# Installs Taskmaster scripts into ~/.codex/skills/taskmaster and creates
# a convenience launcher at ~/.codex/bin/codex-taskmaster.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$HOME/.codex/skills/taskmaster"
BIN_DIR="$HOME/.codex/bin"
LAUNCHER_LINK="$BIN_DIR/codex-taskmaster"
CODEX_SHIM_LINK="$BIN_DIR/codex"

safe_copy() {
  local src="$1"
  local dst="$2"

  if [[ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" == "$(cd "$(dirname "$dst")" && pwd)/$(basename "$dst")" ]]; then
    return 0
  fi
  cp "$src" "$dst"
}

echo "Installing Taskmaster for Codex..."

# 1) Copy skill files
mkdir -p "$SKILL_DIR/hooks"
mkdir -p "$SKILL_DIR/docs"

safe_copy "$SCRIPT_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"
safe_copy "$SCRIPT_DIR/README.md" "$SKILL_DIR/README.md"
safe_copy "$SCRIPT_DIR/LICENSE" "$SKILL_DIR/LICENSE"
safe_copy "$SCRIPT_DIR/docs/SPEC.md" "$SKILL_DIR/docs/SPEC.md"
safe_copy "$SCRIPT_DIR/install.sh" "$SKILL_DIR/install.sh"
safe_copy "$SCRIPT_DIR/uninstall.sh" "$SKILL_DIR/uninstall.sh"

safe_copy "$SCRIPT_DIR/run-taskmaster-codex.sh" "$SKILL_DIR/run-taskmaster-codex.sh"
safe_copy "$SCRIPT_DIR/check-completion.sh" "$SKILL_DIR/check-completion.sh"
safe_copy "$SCRIPT_DIR/hooks/check-completion.sh" "$SKILL_DIR/hooks/check-completion.sh"
safe_copy "$SCRIPT_DIR/hooks/check-completion-codex.sh" "$SKILL_DIR/hooks/check-completion-codex.sh"
safe_copy "$SCRIPT_DIR/hooks/inject-continue-codex.sh" "$SKILL_DIR/hooks/inject-continue-codex.sh"
safe_copy "$SCRIPT_DIR/hooks/run-codex-expect-bridge.exp" "$SKILL_DIR/hooks/run-codex-expect-bridge.exp"

chmod +x "$SKILL_DIR/install.sh"
chmod +x "$SKILL_DIR/uninstall.sh"
chmod +x "$SKILL_DIR/run-taskmaster-codex.sh"
chmod +x "$SKILL_DIR/check-completion.sh"
chmod +x "$SKILL_DIR/hooks/check-completion.sh"
chmod +x "$SKILL_DIR/hooks/check-completion-codex.sh"
chmod +x "$SKILL_DIR/hooks/inject-continue-codex.sh"
chmod +x "$SKILL_DIR/hooks/run-codex-expect-bridge.exp"

echo "  Installed skill files to $SKILL_DIR"

# 2) Create convenience launcher symlink
mkdir -p "$BIN_DIR"
ln -sf "$SKILL_DIR/run-taskmaster-codex.sh" "$LAUNCHER_LINK"
echo "  Linked launcher at $LAUNCHER_LINK"
ln -sf "$SKILL_DIR/run-taskmaster-codex.sh" "$CODEX_SHIM_LINK"
echo "  Linked shim at $CODEX_SHIM_LINK"

echo ""
echo "Done."
echo ""
echo "Usage:"
echo "  codex-taskmaster [codex args]"
echo ""
echo "If '$BIN_DIR' is not on PATH, add this to your shell profile:"
echo "  export PATH=\"\$HOME/.codex/bin:\$PATH\""
