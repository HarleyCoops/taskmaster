# Taskmaster

A stop hook for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that prevents premature stopping and emits a deterministic, parseable completion signal.

## Behavior

Taskmaster blocks every stop attempt until the transcript contains an explicit done token:

```text
TASKMASTER_DONE::<session_id>
```

When the token is missing, Taskmaster returns a blocking hook response with a completion checklist and the exact signal line the agent must emit only when truly done.

## Install

```bash
git clone https://github.com/blader/taskmaster.git
cd taskmaster
bash install.sh
```

This will:
- Copy skill files to `~/.claude/skills/taskmaster/`
- Install the hook script at `~/.claude/skills/taskmaster/hooks/check-completion.sh`
- Register the stop hook in `~/.claude/settings.json`

Restart your coding agent after installing.

## Manual Install

1. Copy `SKILL.md` to `~/.claude/skills/taskmaster/SKILL.md`
2. Copy `check-completion.sh` to `~/.claude/skills/taskmaster/hooks/check-completion.sh`
3. Make it executable: `chmod +x ~/.claude/skills/taskmaster/hooks/check-completion.sh`
4. Add this hook entry to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/skills/taskmaster/hooks/check-completion.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Configuration

- `TASKMASTER_MAX` (default `0`)
  - `0`: infinite blocking until done token appears
  - `>0`: max block count before forced allow
- `TASKMASTER_DONE_PREFIX` (default `TASKMASTER_DONE`)
  - done token becomes `<prefix>::<session_id>`

## Uninstall

```bash
cd taskmaster
bash uninstall.sh
```

## Notes

- The done token is session-specific, so external automation can parse completion deterministically.
- For details, see `docs/SPEC.md`.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support
- `jq` (for installer and hook)
- `bash`

## License

MIT
