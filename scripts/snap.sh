#!/bin/zsh
# Usage: scripts/snap.sh <name> [json-command-before]  → /tmp/loft-<name>.png
TOKEN=$(defaults read dev.joinal.loft localAPIToken)
PORT=$(defaults read dev.joinal.loft localAPIPort 2>/dev/null || echo 9191)
[[ -n "$2" ]] && { echo "$2" | sed "s/TOKEN/$TOKEN/" | nc -w 1 127.0.0.1 $PORT >/dev/null; sleep ${3:-1.0}; }
echo "{\"token\":\"$TOKEN\",\"command\":\"snapshot\",\"mode\":\"layer\",\"path\":\"/tmp/loft-$1.png\"}" | nc -w 2 127.0.0.1 $PORT
