#!/bin/zsh
# Claude Code PermissionRequest hook → approve or deny from the notch.
# Shows "Allow / Deny" buttons in the island; waits up to 2 minutes. No answer
# (timeout or Loft not running) falls through to Claude Code's normal prompt.
#
# settings.json:
#   "hooks": { "PermissionRequest": [{ "hooks": [{ "type": "command",
#       "command": "~/code/notchy/scripts/claude-code/loft-approve.sh", "timeout": 130 }] }] }
TOKEN=$(defaults read dev.joinal.loft localAPIToken 2>/dev/null) || exit 0
PORT=$(defaults read dev.joinal.loft localAPIPort 2>/dev/null || echo 9999)
INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | /usr/bin/plutil -extract tool_name raw -o - - 2>/dev/null)
DETAIL=$(printf '%s' "$INPUT" | /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin); i=d.get("tool_input",{})
print(i.get("command") or i.get("file_path") or i.get("url") or i.get("pattern") or d.get("message") or "")' 2>/dev/null)
REQ=$(/usr/bin/python3 -c 'import json,sys; print(json.dumps({"token":sys.argv[1],"command":"ask","title":"Claude: "+sys.argv[2],"subtitle":sys.argv[3],"symbol":"terminal.fill","options":["Allow","Deny"],"timeout":120}))' "$TOKEN" "${TOOL:-tool}" "$DETAIL")
ANSWER=$(/usr/bin/python3 - "$PORT" "$REQ" <<'PY' 2>/dev/null
import json, socket, sys
try:
    s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=3)
    s.settimeout(125)
    s.sendall((sys.argv[2] + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(4096)
        if not chunk: break
        buf += chunk
    print(json.loads(buf.decode() or "{}").get("answer") or "")
except Exception:
    print("")
PY
)
case "$ANSWER" in
  Allow) printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n' ;;
  Deny)  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Loft"}}}\n' ;;
  *)     ;;  # no decision → Claude Code shows its own prompt
esac
exit 0
