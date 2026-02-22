# Taskmaster
## Product & Technical Specification

**Version**: 4.2.0  
**Scope**:
- `taskmaster/check-completion.sh`
- `taskmaster/hooks/inject-continue-codex.sh`
- `taskmaster/hooks/run-codex-expect-bridge.exp`
- `taskmaster/run-taskmaster-codex.sh`
- `taskmaster/install.sh`
- `taskmaster/uninstall.sh`

## 1. Goal

Prevent premature agent stopping and provide a deterministic, machine-parseable
completion signal.

Taskmaster enforces explicit completion through a done-token contract and
continuation/hook feedback when that contract is not satisfied.

## 2. Completion Contract

A run is considered complete only when assistant output includes:

```text
TASKMASTER_DONE::<session_id>
```

- `<session_id>` is session-scoped.
- The line must be emitted only when work is truly complete.
- Automation can parse this line as the authoritative completion marker.

## 3. Architecture

### 3.1 Codex Wrapper Path

`run-taskmaster-codex.sh`:

1. Resolves real Codex binary and enables session logging.
2. Starts queue-emitter injector (`hooks/inject-continue-codex.sh`).
3. Runs Codex in managed expect PTY (`hooks/run-codex-expect-bridge.exp`).
4. On incomplete turn (missing done token), injector emits continuation prompt
   files and expect bridge injects them into the same running process.

### 3.2 Claude Stop-Hook Path

`check-completion.sh`:

1. Executes as Claude `Stop` hook command.
2. Verifies done token in session transcript.
3. If missing, returns a blocking decision with compliance instructions.
4. If present, allows stop.

### 3.3 Queue Emitter

`hooks/inject-continue-codex.sh`:

- Follows Codex session log.
- Handles `task_complete` / `turn_complete` events.
- Dedupe by turn-id/signature.
- Writes continuation payloads as `inject.*.txt` queue files.

### 3.4 Expect Bridge

`hooks/run-codex-expect-bridge.exp`:

- Polls queue files.
- Injects payload into the same Codex PTY via bracketed paste.
- Submits prompt with Enter after fixed short delay.

## 4. Installation Behavior

`install.sh` auto-detects Codex and/or Claude and installs matching targets.
`uninstall.sh` auto-detects and removes matching targets.

Override knobs:
- `TASKMASTER_INSTALL_TARGET=auto|codex|claude|both`
- `TASKMASTER_UNINSTALL_TARGET=auto|codex|claude|both`

## 5. Configuration

Configurable:
- `TASKMASTER_MAX` (default `0`): warning cap in stop-hook checks.

Fixed:
- done token prefix: `TASKMASTER_DONE`
- poll interval: `1` second
- Codex transport: expect only
- expect payload mode + submit timing

## 6. Operational Notes

- Enforcement is same-process for Codex and stop-hook based for Claude.
- There is no standalone monitor-only mode in this design.
