#!/usr/bin/env bash
#
# Codex Taskmaster monitor (session-log based).
#
# Codex TUI does not currently support arbitrary writable event hooks. This
# script watches CODEX_TUI_SESSION_LOG_PATH and applies a read-only completion
# check on each `task_complete` event.
#
# Exit codes:
#   0 = done token observed for this session
#   2 = session ended (or analysis finished) without done token
#   3 = no `task_complete` events observed
#   4 = invalid usage / prerequisites
#
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check-completion-codex.sh --log <session_log.jsonl> [--follow] [--quiet]
  check-completion-codex.sh [--follow] [--quiet]

Options:
  --log <path>   Path to CODEX_TUI_SESSION_LOG_PATH file.
  --follow       Follow live updates until session_end (default: analyze once).
  --quiet        Suppress warnings and summary output.
  -h, --help     Show help.

Env:
  CODEX_TUI_SESSION_LOG_PATH  Default log path when --log is omitted.
  TASKMASTER_MAX              Max warning count before warning suppression.
EOF
}

LOG_PATH="${CODEX_TUI_SESSION_LOG_PATH:-}"
FOLLOW=0
QUIET=0
POLL_INTERVAL="1"
DONE_PREFIX="TASKMASTER_DONE"
MAX_WARNINGS="${TASKMASTER_MAX:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      LOG_PATH="${2:-}"
      shift 2
      ;;
    --follow)
      FOLLOW=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 4
      ;;
  esac
done

if [[ -z "$LOG_PATH" ]]; then
  echo "Missing log path. Set --log or CODEX_TUI_SESSION_LOG_PATH." >&2
  exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 4
fi

SESSION_ID=""
SESSION_ENDED=0
DONE_FOUND=0
TASK_COMPLETE_COUNT=0
WARNING_COUNT=0
SUPPRESSION_NOTED=0

done_token_hint() {
  if [[ -n "$SESSION_ID" ]]; then
    printf "%s::%s" "$DONE_PREFIX" "$SESSION_ID"
  else
    printf "%s::<session_id>" "$DONE_PREFIX"
  fi
}

is_done_text() {
  local text="$1"
  [[ -n "$text" ]] || return 1

  if [[ -n "$SESSION_ID" ]]; then
    [[ "$text" == *"${DONE_PREFIX}::${SESSION_ID}"* ]]
  else
    [[ "$text" == *"${DONE_PREFIX}::"* ]]
  fi
}

emit_warning() {
  [[ "$QUIET" -eq 1 ]] && return

  if [[ "$MAX_WARNINGS" -gt 0 && "$WARNING_COUNT" -gt "$MAX_WARNINGS" ]]; then
    if [[ "$SUPPRESSION_NOTED" -eq 0 ]]; then
      echo "[TASKMASTER] warning limit reached; suppressing further warnings." >&2
      SUPPRESSION_NOTED=1
    fi
    return
  fi

  echo "[TASKMASTER] task_complete without done token: $(done_token_hint)" >&2
  echo "[TASKMASTER] continue working; emit token only when truly complete." >&2
}

process_line() {
  local line="$1"
  [[ -n "$line" ]] || return

  local kind msg_type msg_text sid
  kind="$(jq -r '.kind // empty' <<<"$line" 2>/dev/null || true)"

  case "$kind" in
    codex_event)
      msg_type="$(jq -r '.payload.msg.type // empty' <<<"$line" 2>/dev/null || true)"
      case "$msg_type" in
        session_configured)
          sid="$(jq -r '.payload.msg.session_id // empty' <<<"$line" 2>/dev/null || true)"
          if [[ -n "$sid" && "$sid" != "null" ]]; then
            SESSION_ID="$sid"
          fi
          ;;
        task_complete|turn_complete)
          TASK_COMPLETE_COUNT=$((TASK_COMPLETE_COUNT + 1))
          msg_text="$(jq -r '.payload.msg.last_agent_message // ""' <<<"$line" 2>/dev/null || true)"
          if is_done_text "$msg_text"; then
            DONE_FOUND=1
          else
            WARNING_COUNT=$((WARNING_COUNT + 1))
            emit_warning
          fi
          ;;
        agent_message)
          msg_text="$(jq -r '.payload.msg.message // ""' <<<"$line" 2>/dev/null || true)"
          if is_done_text "$msg_text"; then
            DONE_FOUND=1
          fi
          ;;
        agent_message_delta|agent_message_content_delta)
          msg_text="$(jq -r '.payload.msg.delta // ""' <<<"$line" 2>/dev/null || true)"
          if is_done_text "$msg_text"; then
            DONE_FOUND=1
          fi
          ;;
      esac
      ;;
    session_end)
      SESSION_ENDED=1
      ;;
  esac
}

process_chunk() {
  local chunk="$1"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    process_line "$line"
  done <<<"$chunk"
}

if [[ "$FOLLOW" -eq 1 ]]; then
  while [[ ! -f "$LOG_PATH" ]]; do
    sleep "$POLL_INTERVAL"
  done
elif [[ ! -f "$LOG_PATH" ]]; then
  echo "Log path does not exist: $LOG_PATH" >&2
  exit 4
fi

OFFSET=0

while true; do
  if [[ ! -f "$LOG_PATH" ]]; then
    if [[ "$FOLLOW" -eq 1 ]]; then
      sleep "$POLL_INTERVAL"
      continue
    fi
    echo "Log path does not exist: $LOG_PATH" >&2
    exit 4
  fi

  local_size="$(wc -c <"$LOG_PATH" 2>/dev/null || echo 0)"
  if [[ "$local_size" -lt "$OFFSET" ]]; then
    OFFSET=0
  fi

  if [[ "$local_size" -gt "$OFFSET" ]]; then
    chunk="$(tail -c +"$((OFFSET + 1))" "$LOG_PATH" 2>/dev/null || true)"
    process_chunk "$chunk"
    OFFSET="$local_size"
  fi

  if [[ "$FOLLOW" -eq 0 ]]; then
    break
  fi

  if [[ "$SESSION_ENDED" -eq 1 ]]; then
    break
  fi

  sleep "$POLL_INTERVAL"
done

if [[ "$DONE_FOUND" -eq 1 ]]; then
  if [[ "$QUIET" -eq 0 ]]; then
    echo "[TASKMASTER] done token detected: $(done_token_hint)" >&2
  fi
  exit 0
fi

if [[ "$TASK_COMPLETE_COUNT" -eq 0 ]]; then
  if [[ "$QUIET" -eq 0 ]]; then
    echo "[TASKMASTER] no task_complete events observed." >&2
  fi
  exit 3
fi

if [[ "$QUIET" -eq 0 ]]; then
  echo "[TASKMASTER] completion token missing at session end: $(done_token_hint)" >&2
fi
exit 2
