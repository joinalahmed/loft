#!/bin/zsh
# Claude Code hook → Loft island.
# Reads the hook JSON on stdin and shows a message in the notch. Works for
# Notification, Stop, SubagentStop and PermissionRequest-style events.
#
# settings.json:
#   "hooks": {
#     "Notification": [{ "hooks": [{ "type": "command", "command": "/path/to/loft/scripts/claude-code/loft-notify.sh" }] }],
#     "Stop":         [{ "hooks": [{ "type": "command", "command": "/path/to/loft/scripts/claude-code/loft-notify.sh" }] }]
#   }
TOKEN=$(defaults read dev.joinal.loft localAPIToken 2>/dev/null) || exit 0
PORT=$(defaults read dev.joinal.loft localAPIPort 2>/dev/null || echo 9191)
INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | /usr/bin/plutil -extract hook_event_name raw -o - - 2>/dev/null)
MSG=$(printf '%s' "$INPUT" | /usr/bin/plutil -extract message raw -o - - 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | /usr/bin/plutil -extract cwd raw -o - - 2>/dev/null)
PROJECT=${CWD:t}
case "$EVENT" in
  Stop)         TITLE="Claude finished"; SUB="${PROJECT:-Ready for you}"; SYM="checkmark.circle.fill" ;;
  SubagentStop) TITLE="Subagent finished"; SUB="$PROJECT"; SYM="checkmark.circle" ;;
  Notification) TITLE="Claude Code"; SUB="${MSG:-Needs your attention}"; SYM="sparkles" ;;
  *)            TITLE="Claude Code"; SUB="${MSG:-$EVENT}"; SYM="sparkles" ;;
esac
/usr/bin/python3 -c 'import json,sys; print(json.dumps({"token":sys.argv[1],"title":sys.argv[2],"subtitle":sys.argv[3],"symbol":sys.argv[4],"duration":5}))' \
  "$TOKEN" "$TITLE" "$SUB" "$SYM" | nc -w 1 127.0.0.1 "$PORT" >/dev/null 2>&1
exit 0
