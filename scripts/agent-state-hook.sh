#!/bin/sh
# Claude Code hook: writes the session's state to ~/Library/Application Support/Save Point/sessions/<session>.json,
# so Save Point knows what each agent is doing from Claude itself instead of guessing from the terminal title.
# Registered in ~/.claude/settings.json on UserPromptSubmit, PostToolUse, PermissionRequest, Notification, Stop, StopFailure,
# SessionStart and SessionEnd. Never blocks Claude: always exits 0 and prints nothing.
payload=$(cat)
[ -n "$payload" ] || exit 0
dir="$HOME/Library/Application Support/Save Point/sessions"
mkdir -p "$dir" 2>/dev/null || exit 0
printf '%s' "$payload" | PPID_OF_AGENT="$PPID" /usr/bin/python3 -I -c '
import json, os, sys, time
try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)
event, session = p.get("hook_event_name", ""), p.get("session_id", "")
if not session:
    sys.exit(0)
folder = os.path.expanduser("~/Library/Application Support/Save Point/sessions")
path = os.path.join(folder, session + ".json")
if event == "SessionEnd":
    try:
        os.remove(path)
    except OSError:
        pass
    sys.exit(0)
state = {"UserPromptSubmit": "working", "PostToolUse": "working", "PermissionRequest": "needsYou", "Notification": "needsYou",
         "Stop": "done", "StopFailure": "failed", "SessionStart": "idle"}.get(event)
if not state:
    sys.exit(0)
row = {"state": state, "event": event, "cwd": p.get("cwd") or os.getcwd(), "pid": int(os.environ.get("PPID_OF_AGENT", "0")),
       "worktreeId": os.environ.get("ORCA_WORKTREE_ID", ""), "paneKey": os.environ.get("ORCA_PANE_KEY", ""),
       "tabId": os.environ.get("ORCA_TAB_ID", ""), "item": os.environ.get("SAVEPOINT_ITEM", ""), "at": int(time.time())}
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(row, f)
os.replace(tmp, path)
' 2>/dev/null
exit 0
