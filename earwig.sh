#!/usr/bin/env bash
#
# earwig.sh — convenience controller for the Earwig menu-bar app.
#
# Usage:
#   ./earwig.sh start            Build if needed, then launch Earwig (menu bar)
#   ./earwig.sh stop             Quit the running Earwig
#   ./earwig.sh restart          Stop, then start
#   ./earwig.sh status           Show whether Earwig is running
#   ./earwig.sh build            Rebuild and sign Earwig.app
#   ./earwig.sh rebuild          Build, then restart (use after code changes)
#   ./earwig.sh logs             Follow the live log (Ctrl-C to stop watching)
#   ./earwig.sh diarize <file>   Print detected speakers for an audio file
#   ./earwig.sh process <file>   Transcribe+diarize a file into a markdown note
#   ./earwig.sh enroll-me <meeting> <label>   Register your own voice from a meeting
#   ./earwig.sh name <meeting> <label> <name> Name + enroll a speaker; re-render the note
#   ./earwig.sh identities                    List enrolled voices
#   ./earwig.sh forget <name>                 Remove an enrolled voice
#
set -euo pipefail

# Always operate relative to this script's directory, so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$SCRIPT_DIR/Earwig.app"
BIN="$APP/Contents/MacOS/Earwig"
PROC_MATCH="Earwig.app/Contents/MacOS/Earwig"
LOG="$HOME/Library/Application Support/Earwig/earwig.log"

is_running() { pgrep -f "$PROC_MATCH" >/dev/null 2>&1; }

running_pid() { pgrep -f "$PROC_MATCH" 2>/dev/null | head -1; }

ensure_built() {
    if [ ! -x "$BIN" ]; then
        echo "Earwig.app not found — building first…"
        do_build
    fi
}

do_build() {
    echo "Building Earwig.app…"
    ( cd "$SCRIPT_DIR" && ./build.sh )
}

do_start() {
    if is_running; then
        echo "Earwig is already running (pid $(running_pid))."
        return 0
    fi
    ensure_built
    open "$APP"
    sleep 1
    if is_running; then
        echo "Earwig started (pid $(running_pid)). Look for the icon in your menu bar."
    else
        echo "Earwig did not start — check the log: ./earwig.sh logs"
        return 1
    fi
}

do_stop() {
    if ! is_running; then
        echo "Earwig is not running."
        return 0
    fi
    echo "Stopping Earwig (pid $(running_pid))…"
    pkill -f "$PROC_MATCH" || true
    sleep 1
    if is_running; then
        echo "Still running — forcing…"
        pkill -9 -f "$PROC_MATCH" || true
        sleep 1
    fi
    is_running && { echo "Could not stop Earwig."; return 1; } || echo "Stopped."
}

do_status() {
    if is_running; then
        echo "Earwig is RUNNING (pid $(running_pid))."
    else
        echo "Earwig is STOPPED."
    fi
}

do_logs() {
    if [ ! -f "$LOG" ]; then
        echo "No log yet at: $LOG"
        echo "(It is created the first time Earwig runs.)"
        return 0
    fi
    echo "Following $LOG — press Ctrl-C to stop watching."
    tail -n 30 -f "$LOG"
}

require_file() {
    if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
        echo "Error: this command needs an audio file path." >&2
        echo "Example: ./earwig.sh $ACTION /path/to/recording.m4a" >&2
        exit 1
    fi
    if [ ! -f "$1" ]; then
        echo "Error: file not found: $1" >&2
        exit 1
    fi
}

usage() {
    sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

ACTION="${1:-help}"
shift || true

case "$ACTION" in
    start)    do_start ;;
    stop)     do_stop ;;
    restart)  do_stop; do_start ;;
    build)    do_build ;;
    rebuild)  do_build; do_stop; do_start ;;
    status)   do_status ;;
    logs|log) do_logs ;;
    diarize)    require_file "${1:-}"; ensure_built; "$BIN" --test-diarize "$1" ;;
    process)    require_file "${1:-}"; ensure_built; "$BIN" --process "$1" ;;
    enroll-me)
        if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
            echo "Usage: ./earwig.sh enroll-me <meeting> <label>" >&2; exit 1
        fi
        ensure_built; "$BIN" --enroll-me "$1" "$2" ;;
    name)
        if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: ./earwig.sh name <meeting> <label> <name>" >&2; exit 1
        fi
        ensure_built; "$BIN" --name "$1" "$2" "$3" ;;
    identities) ensure_built; "$BIN" --identities ;;
    forget)
        if [ -z "${1:-}" ]; then
            echo "Usage: ./earwig.sh forget <name>" >&2; exit 1
        fi
        ensure_built; "$BIN" --forget "$1" ;;
    help|-h|--help|"") usage ;;
    *)        echo "Unknown command: $ACTION"; echo; usage; exit 1 ;;
esac
