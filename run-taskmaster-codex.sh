#!/usr/bin/env bash
#
# Run Codex with Taskmaster same-process continuation.
#
# Supported transports:
# - tmux: inject into a tmux pane (same process)
# - expect: inject via managed PTY queue (same process)
#
# No resume/restart fallback is used.
#
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
  SOURCE_PATH="$(readlink "$SOURCE_PATH")"
  [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="$SOURCE_DIR/$SOURCE_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
INJECTOR="$SCRIPT_DIR/hooks/inject-continue-codex-tmux.sh"
EXPECT_BRIDGE="$SCRIPT_DIR/hooks/run-codex-expect-bridge.exp"
ORIGINAL_ARGS=("$@")

resolve_real_codex_bin() {
  local candidate
  local wrapper_path="$SOURCE_PATH"
  local wrapper_cmd="$HOME/.codex/bin/codex-taskmaster"
  local codex_shim="$HOME/.codex/bin/codex"

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    case "$candidate" in
      "$wrapper_path"|"$wrapper_cmd"|"$codex_shim")
        continue
        ;;
    esac
    echo "$candidate"
    return 0
  done < <(which -a codex 2>/dev/null | awk '!seen[$0]++')

  return 1
}

if [[ ! -x "$INJECTOR" ]]; then
  echo "Missing executable injector script: $INJECTOR" >&2
  exit 4
fi

if [[ ! -x "$EXPECT_BRIDGE" ]]; then
  echo "Missing executable expect bridge: $EXPECT_BRIDGE" >&2
  exit 4
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found in PATH." >&2
  exit 4
fi

REAL_CODEX_BIN="${TASKMASTER_REAL_CODEX_BIN:-}"
if [[ -z "$REAL_CODEX_BIN" ]]; then
  REAL_CODEX_BIN="$(resolve_real_codex_bin || true)"
fi
if [[ -z "$REAL_CODEX_BIN" ]] || [[ ! -x "$REAL_CODEX_BIN" ]]; then
  echo "Could not resolve real codex binary. Set TASKMASTER_REAL_CODEX_BIN." >&2
  exit 4
fi

is_known_subcommand() {
  case "$1" in
    exec|e|review|login|logout|mcp|mcp-server|app-server|app|completion|sandbox|debug|apply|a|resume|fork|cloud|features|help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Pass through for non-interactive codex command families and generic help/version.
for arg in ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}; do
  case "$arg" in
    -h|--help|-V|--version)
      exec "$REAL_CODEX_BIN" "${ORIGINAL_ARGS[@]}"
      ;;
  esac
done

first_non_option=""
for arg in ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}; do
  if [[ "$arg" == "--" ]]; then
    break
  fi
  if [[ "$arg" == -* ]]; then
    continue
  fi
  first_non_option="$arg"
  break
done
if [[ -n "$first_non_option" ]] && is_known_subcommand "$first_non_option"; then
  exec "$REAL_CODEX_BIN" "${ORIGINAL_ARGS[@]}"
fi

DONE_PREFIX="${TASKMASTER_DONE_PREFIX:-TASKMASTER_DONE}"
AUTORESUME="${TASKMASTER_AUTORESUME:-1}"
AUTORESUME_MAX="${TASKMASTER_AUTORESUME_MAX:-0}" # 0 means unlimited
POLL_INTERVAL="${TASKMASTER_POLL_INTERVAL:-0.5}"
MODE_RAW="${TASKMASTER_MODE:-auto}" # auto | tmux | expect
CUSTOM_LOG_PATH="${TASKMASTER_LOG_PATH:-}"
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      CUSTOM_LOG_PATH="${2:-}"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        PASSTHROUGH_ARGS+=("$1")
        shift
      done
      ;;
    *)
      PASSTHROUGH_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "$AUTORESUME" == "1" ]] && ! command -v jq >/dev/null 2>&1; then
  echo "jq is required when TASKMASTER_AUTORESUME=1." >&2
  exit 4
fi

resolve_tmux_pane() {
  local pane_hint
  local tty_path
  local candidates

  if ! command -v tmux >/dev/null 2>&1; then
    return 1
  fi

  pane_hint="${TASKMASTER_TMUX_PANE:-${TMUX_PANE:-}}"
  if [[ -n "$pane_hint" ]]; then
    echo "$pane_hint"
    return 0
  fi

  if [[ -n "${TMUX:-}" ]]; then
    pane_hint="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
    if [[ -n "$pane_hint" ]]; then
      echo "$pane_hint"
      return 0
    fi
  fi

  tty_path="$(tty 2>/dev/null || true)"
  if [[ -n "$tty_path" && "$tty_path" != "not a tty" ]]; then
    pane_hint="$(tmux list-panes -a -F '#{pane_id}\t#{pane_tty}' 2>/dev/null | awk -v tty="$tty_path" -F '\t' '$2==tty { print $1; exit }')"
    if [[ -n "$pane_hint" ]]; then
      echo "$pane_hint"
      return 0
    fi
  fi

  candidates="$({ tmux list-panes -a -F '#{pane_id}\t#{session_attached}\t#{pane_active}' 2>/dev/null || true; } | awk -F '\t' '$2 > 0 && $3 == 1 { print $1 }')"
  if [[ -n "$candidates" ]]; then
    if [[ "$(wc -l <<<"$candidates" | tr -d ' ')" -eq 1 ]]; then
      pane_hint="$(head -n 1 <<<"$candidates")"
      if [[ -n "$pane_hint" ]]; then
        echo "$pane_hint"
        return 0
      fi
    fi
  fi

  candidates="$({ tmux list-panes -a -F '#{pane_id}\t#{session_attached}' 2>/dev/null || true; } | awk -F '\t' '$2 > 0 { print $1 }')"
  if [[ -n "$candidates" ]]; then
    if [[ "$(wc -l <<<"$candidates" | tr -d ' ')" -eq 1 ]]; then
      pane_hint="$(head -n 1 <<<"$candidates")"
      if [[ -n "$pane_hint" ]]; then
        echo "$pane_hint"
        return 0
      fi
    fi
  fi

  return 1
}

resolve_transport() {
  local pane

  case "$MODE_RAW" in
    ""|auto)
      pane="$(resolve_tmux_pane || true)"
      if [[ -n "$pane" ]]; then
        echo "tmux"
        return 0
      fi
      if command -v expect >/dev/null 2>&1; then
        echo "expect"
        return 0
      fi
      echo "[TASKMASTER] no same-process transport available (tmux pane not detected and expect missing)." >&2
      return 1
      ;;
    tmux|same-process|same_process)
      echo "tmux"
      return 0
      ;;
    expect|pty)
      echo "expect"
      return 0
      ;;
    *)
      echo "[TASKMASTER] unsupported TASKMASTER_MODE='$MODE_RAW'. Use auto|tmux|expect." >&2
      return 1
      ;;
  esac
}

build_log_path() {
  local timestamp

  if [[ -n "$CUSTOM_LOG_PATH" ]]; then
    echo "$CUSTOM_LOG_PATH"
    return 0
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$-1"
  echo "$HOME/.codex/log/taskmaster-session-${timestamp}.jsonl"
}

prepare_log_env() {
  local log_path="$1"
  mkdir -p "$(dirname "$log_path")"
  : > "$log_path"
  export CODEX_TUI_RECORD_SESSION=1
  export CODEX_TUI_SESSION_LOG_PATH="$log_path"
}

run_initial_codex() {
  if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
    "$REAL_CODEX_BIN" "${PASSTHROUGH_ARGS[@]}"
  else
    "$REAL_CODEX_BIN"
  fi
}

cleanup_background() {
  local pid="$1"
  if [[ -n "$pid" ]]; then
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

run_tmux_mode() {
  local pane
  local log_path
  local injector_pid=""
  local codex_exit=0

  if ! command -v tmux >/dev/null 2>&1; then
    echo "[TASKMASTER] tmux mode requested but tmux is not installed." >&2
    return 4
  fi

  pane="$(resolve_tmux_pane || true)"
  if [[ -z "$pane" ]]; then
    echo "[TASKMASTER] no tmux pane detected." >&2
    echo '[TASKMASTER] set explicitly: TASKMASTER_TMUX_PANE="$(tmux display-message -p '\''#{pane_id}'\'')" codex' >&2
    return 4
  fi

  if ! tmux list-panes -a -F '#{pane_id}' | grep -Fxq "$pane"; then
    echo "[TASKMASTER] tmux pane not found: $pane" >&2
    return 4
  fi

  log_path="$(build_log_path)"
  prepare_log_env "$log_path"

  if [[ "$AUTORESUME" == "1" ]]; then
    "$INJECTOR" \
      --follow \
      --log "$log_path" \
      --pane "$pane" \
      --done-prefix "$DONE_PREFIX" \
      --poll-interval "$POLL_INTERVAL" \
      --max-injections "$AUTORESUME_MAX" &
    injector_pid="$!"
    echo "[TASKMASTER] mode=tmux same-process (pane=$pane)" >&2
  else
    echo "[TASKMASTER] AUTORESUME=0; running codex without auto-injection." >&2
  fi

  run_initial_codex || codex_exit=$?
  cleanup_background "$injector_pid"
  return "$codex_exit"
}

run_expect_mode() {
  local log_path
  local queue_dir
  local injector_pid=""
  local codex_exit=0

  if ! command -v expect >/dev/null 2>&1; then
    echo "[TASKMASTER] expect mode requested but expect is not installed." >&2
    return 4
  fi

  log_path="$(build_log_path)"
  prepare_log_env "$log_path"

  queue_dir="$(mktemp -d "${TMPDIR:-/tmp}/taskmaster-emit.XXXXXX")"

  if [[ "$AUTORESUME" == "1" ]]; then
    "$INJECTOR" \
      --follow \
      --log "$log_path" \
      --emit-dir "$queue_dir" \
      --done-prefix "$DONE_PREFIX" \
      --poll-interval "$POLL_INTERVAL" \
      --max-injections "$AUTORESUME_MAX" &
    injector_pid="$!"
    echo "[TASKMASTER] mode=expect same-process (queue=$queue_dir)" >&2
  else
    echo "[TASKMASTER] AUTORESUME=0; running codex without auto-injection." >&2
  fi

  if [[ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]]; then
    "$EXPECT_BRIDGE" "$queue_dir" "$REAL_CODEX_BIN" "${PASSTHROUGH_ARGS[@]}" || codex_exit=$?
  else
    "$EXPECT_BRIDGE" "$queue_dir" "$REAL_CODEX_BIN" || codex_exit=$?
  fi

  cleanup_background "$injector_pid"
  rm -rf "$queue_dir"

  return "$codex_exit"
}

TRANSPORT="$(resolve_transport)"
case "$TRANSPORT" in
  tmux)
    run_tmux_mode
    ;;
  expect)
    run_expect_mode
    ;;
  *)
    echo "[TASKMASTER] internal transport error: $TRANSPORT" >&2
    exit 4
    ;;
esac

exit $?
