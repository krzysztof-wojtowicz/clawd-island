#!/bin/bash
# Sends fake Claude Code hook/statusline events to the running app (skill: simulate-claude-events).
# Usage: scripts/simulate.sh <scenario> [session_id=sim-1]   (scenario "usage" takes a percent instead)
set -euo pipefail

config="$HOME/Library/Application Support/ClawdNotch/config.json"
port=47474
token=""
if [[ -f "$config" ]]; then
    port="$(plutil -extract port raw -o - "$config" 2>/dev/null || echo 47474)"
    token="$(plutil -extract token raw -o - "$config" 2>/dev/null || true)"
fi

# post <path> <json>: failures are reported but never abort a scenario.
post() {
    curl -s -o /dev/null -w "%{http_code} $1\n" --max-time 1 -X POST "http://127.0.0.1:$port$1" \
        -H "Content-Type: application/json" -H "X-Clawd-Token: $token" --data-binary "$2" \
        || echo "app not reachable on port $port" >&2
}

# hook <event> <session> [extra json fields]
hook() {
    post /hook "{\"hook_event_name\":\"$1\",\"session_id\":\"$2\",\"cwd\":\"/tmp/$2\"${3:+,$3}}"
}

# start <session>: SessionStart has no http hooks, so production delivers it via the bridge's /session-meta.
start() {
    post /session-meta "{\"session_id\":\"$1\",\"cwd\":\"/tmp/$1\",\"source\":\"startup\"}"
}

scenario="${1:-}"
sid="${2:-sim-1}"

# Session ids are pasted into JSON unescaped, so keep them to a safe alphabet.
[[ "$scenario" == usage || "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "session_id may contain only [A-Za-z0-9_-]" >&2; exit 1; }

case "$scenario" in
    start)      start "$sid" ;;
    think)      hook UserPromptSubmit "$sid" '"prompt":"simulated"' ;;
    tool)       hook PreToolUse "$sid" '"tool_name":"Bash","tool_input":{},"tool_use_id":"t1"' ;;
    text)       for i in 1 2 3 4 5; do hook MessageDisplay "$sid" "\"index\":$i,\"final\":false"; sleep 0.2; done ;;
    permission) hook PermissionRequest "$sid" '"tool_name":"Bash","tool_input":{}' ;;
    done)       hook Stop "$sid" '"stop_hook_active":false' ;;
    fail)       hook StopFailure "$sid" ;;
    end)        hook SessionEnd "$sid" '"reason":"prompt_input_exit"' ;;
    usage)
        pct="${2:-37}"
        [[ "$pct" =~ ^[0-9]+$ ]] || { echo "usage percent must be an integer" >&2; exit 1; }
        post /statusline "{\"session_id\":\"sim-1\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":$pct,\"resets_at\":$(( $(date +%s) + 3600 ))},\"seven_day\":{\"used_percentage\":19,\"resets_at\":$(( $(date +%s) + 86400 ))}}}"
        ;;
    turn)
        start "$sid"; sleep 1
        hook UserPromptSubmit "$sid"; sleep 2
        hook PreToolUse "$sid" '"tool_name":"Read"'; sleep 1
        hook PostToolUse "$sid" '"tool_name":"Read"'; sleep 1.5
        for i in 1 2 3; do hook MessageDisplay "$sid"; sleep 0.3; done
        sleep 1; hook Stop "$sid"
        ;;
    tools)
        hook UserPromptSubmit "$sid"; sleep 1
        hook PreToolUse "$sid" '"tool_name":"Bash","tool_input":{},"tool_use_id":"t1"'; sleep 4
        hook PostToolUse "$sid" '"tool_name":"Bash","tool_input":{},"tool_use_id":"t1"'; sleep 1
        hook Stop "$sid"
        ;;
    compact)
        hook UserPromptSubmit "$sid"; sleep 1
        hook PreCompact "$sid" '"trigger":"auto"'; sleep 6
        post /session-meta "{\"session_id\":\"$sid\",\"cwd\":\"/tmp/$sid\",\"source\":\"compact\"}"
        ;;
    multi)
        start sim-a; hook UserPromptSubmit sim-a
        start sim-b; hook PreToolUse sim-b '"tool_name":"Edit"'
        start sim-c; hook Stop sim-c
        ;;
    burst)
        start "$sid"
        end=$(( $(date +%s) + 10 ))
        while (( $(date +%s) < end )); do
            for i in $(seq 1 50); do hook MessageDisplay "$sid" >/dev/null & done
            wait; sleep 1
        done
        ;;
    *)
        echo "usage: $0 {start|think|tool|tools|compact|text|permission|done|fail|end|turn|multi|burst} [session_id] | usage <percent>" >&2
        exit 1
        ;;
esac
