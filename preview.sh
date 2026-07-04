#!/bin/bash
set -euo pipefail

PORT="${1:-8000}"

while lsof -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; do
  PORT=$((PORT + 1))
done

echo "Serving on http://localhost:$PORT"
exec python3 -m http.server "$PORT"
