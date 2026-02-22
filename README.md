# Taskmaster

A completion gate for coding agents. Taskmaster blocks premature stop and
enforces a deterministic, parseable completion signal.

Supported modes:
- Codex CLI: session-log monitor + same-process continuation via expect PTY.
- Claude Code: native `Stop` hook command using `check-completion.sh`.

## Behavior

Taskmaster enforces a session-specific done token:

```text
TASKMASTER_DONE::<session_id>
```

If that token is missing when the agent tries to stop, Taskmaster blocks stop.

## Install

```bash
bash ~/.codex/skills/taskmaster/install.sh
```

This will:
- Ensure files are present under `~/.codex/skills/taskmaster/`
- Create launcher symlink `~/.codex/bin/codex-taskmaster`

## Codex Usage

```bash
codex-taskmaster [codex args]
```

Examples:

```bash
# Run with your normal codex defaults
codex-taskmaster

# Run with a prompt
codex-taskmaster "profile and fix import memory usage"

# Pass codex flags
codex-taskmaster -- --search
```

## Claude Usage (Stop Hook)

1. Make the skill visible to Claude and ensure hook script is executable:

```bash
mkdir -p ~/.claude/skills
ln -sfn ~/.codex/skills/taskmaster ~/.claude/skills/taskmaster
chmod +x ~/.claude/skills/taskmaster/check-completion.sh
```

2. Add a `Stop` hook in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/taskmaster/check-completion.sh"
          }
        ]
      }
    ]
  }
}
```

If your settings file uses direct hook events (without the `hooks` wrapper),
use the same `Stop` array at top level.

## Codex Direct Monitor Usage

If you only want read-only monitoring:

```bash
CODEX_TUI_RECORD_SESSION=1 \
CODEX_TUI_SESSION_LOG_PATH=/tmp/codex-session.jsonl \
codex

bash ~/.codex/skills/taskmaster/hooks/check-completion-codex.sh \
  --follow --log /tmp/codex-session.jsonl
```

## Configuration

- `TASKMASTER_MAX` (default `0`)
  - warning cap (`0` = unlimited warnings)
- `TASKMASTER_LOG_PATH`
  - optional fixed session log path for `codex-taskmaster`

Fixed behavior (not configurable):
- done token prefix is always `TASKMASTER_DONE`
- poll interval is always `1` second
- transport is expect-only
- expect bridge always uses bracketed paste with fixed submit timing

## Uninstall

```bash
bash ~/.codex/skills/taskmaster/uninstall.sh
```

## Notes

- Codex wrapper mode needs both variables:
  - `CODEX_TUI_RECORD_SESSION=1`
  - `CODEX_TUI_SESSION_LOG_PATH=<path>`
- The done token is session-specific, so automation can parse completion deterministically.
- For details, see `docs/SPEC.md`.

## Requirements

- `jq`
- `bash`
- Codex mode:
  - Codex CLI
  - `expect`
- Claude mode:
  - Claude Code with `Stop` hooks enabled

## License

MIT
