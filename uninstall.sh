#!/usr/bin/env bash
#
# Taskmaster uninstaller for Codex
#
# Removes the Taskmaster skill directory and launcher symlink.
#
set -euo pipefail

SKILL_DIR="$HOME/.codex/skills/taskmaster"
LAUNCHER_LINK="$HOME/.codex/bin/codex-taskmaster"
CODEX_SHIM_LINK="$HOME/.codex/bin/codex"

echo "Uninstalling Taskmaster for Codex..."

# 1) Remove skill directory
if [ -d "$SKILL_DIR" ]; then
  rm -rf "$SKILL_DIR"
  echo "  Removed $SKILL_DIR"
else
  echo "  Skill directory not found (already removed)"
fi

# 2) Remove launcher symlink
if [ -L "$LAUNCHER_LINK" ] || [ -f "$LAUNCHER_LINK" ]; then
  rm -f "$LAUNCHER_LINK"
  echo "  Removed $LAUNCHER_LINK"
else
  echo "  Launcher not found (already removed)"
fi

if [ -L "$CODEX_SHIM_LINK" ] || [ -f "$CODEX_SHIM_LINK" ]; then
  rm -f "$CODEX_SHIM_LINK"
  echo "  Removed $CODEX_SHIM_LINK"
else
  echo "  Shim not found (already removed)"
fi

echo ""
echo "Done. Taskmaster has been uninstalled."
