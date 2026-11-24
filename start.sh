#!/bin/bash
# Starts the GlowUps demo at http://localhost:8080
cd "$(dirname "$0")"
PORT=${1:-8080}
echo "GlowUps demo running at http://localhost:$PORT  (press Ctrl+C to stop)"
( sleep 1; open "http://localhost:$PORT" ) &
python3 -m http.server "$PORT"
