#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_PATH="${FACEFUSION_OUTPUT_PATH:-storage/output}"
TEMP_PATH="${FACEFUSION_TEMP_PATH:-storage/temp}"
JOBS_PATH="${FACEFUSION_JOBS_PATH:-storage/jobs}"
THREADS="${FACEFUSION_THREADS:-1}"

mkdir -p "$OUTPUT_PATH" "$TEMP_PATH" "$JOBS_PATH" .assets

export GRADIO_SERVER_NAME="0.0.0.0"
export GRADIO_SERVER_PORT="${PORT:-7860}"
export GRADIO_ANALYTICS_ENABLED="0"

# Heroku kills the dyno if nothing listens on $PORT within 60s.
# Model download happens before the UI binds, so hold the port first.
python - <<'PY' &
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(os.environ.get("PORT", "7860"))
body = b"FaceFusion is starting and downloading models. Refresh this page in a few minutes.\n"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return

ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
PY
HOLDER=$!

cleanup() {
  kill "$HOLDER" >/dev/null 2>&1 || true
  wait "$HOLDER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

python facefusion.py force-download --download-scope lite --execution-providers cpu || true

cleanup
trap - EXIT
sleep 1

exec python facefusion.py run \
  --execution-providers cpu \
  --execution-thread-count "$THREADS" \
  --video-memory-strategy strict \
  --download-scope lite \
  --output-path "$OUTPUT_PATH" \
  --temp-path "$TEMP_PATH" \
  --jobs-path "$JOBS_PATH" \
  --log-level info
