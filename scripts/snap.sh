#!/bin/zsh
# Usage: scripts/snap.sh <name> [json-command-before]  → /tmp/isla-<name>.png
TOKEN=$(defaults read dev.joinal.isla localAPIToken)
PORT=$(defaults read dev.joinal.isla localAPIPort 2>/dev/null || echo 9999)
[[ -n "$2" ]] && { echo "$2" | sed "s/TOKEN/$TOKEN/" | nc -w 1 127.0.0.1 $PORT >/dev/null; sleep ${3:-1.0}; }
echo "{\"token\":\"$TOKEN\",\"command\":\"snapshot\",\"path\":\"/tmp/isla-$1.png\"}" | nc -w 2 127.0.0.1 $PORT
