#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export WEB_CONCURRENCY=1

OUTPUT_PATH="${FACEFUSION_OUTPUT_PATH:-storage/output}"
TEMP_PATH="${FACEFUSION_TEMP_PATH:-storage/temp}"
JOBS_PATH="${FACEFUSION_JOBS_PATH:-storage/jobs}"
THREADS="${FACEFUSION_THREADS:-1}"

mkdir -p "$OUTPUT_PATH" "$TEMP_PATH" "$JOBS_PATH" .assets

export GRADIO_SERVER_NAME="0.0.0.0"
export GRADIO_SERVER_PORT="${PORT:-7860}"
export GRADIO_ANALYTICS_ENABLED="0"
export PATH="/app/.apt/usr/bin:${HOME}/.apt/usr/bin:${PATH}"

# Heroku kills the dyno if nothing listens on $PORT within 60s.
python - <<'PY' &
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(os.environ.get("PORT", "7860"))
body = b"FaceFusion is starting. ffmpeg and models download on first boot. Refresh in a few minutes.\n"

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

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffmpeg is not on PATH; downloading a static build"
  python - <<'PY'
import io
import os
import stat
import urllib.request
import zipfile

dest = "/tmp/ffmpeg-static"
os.makedirs(dest, exist_ok=True)
urls = {
    "ffmpeg": "https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffmpeg-6.1-linux-64.zip",
    "ffprobe": "https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffprobe-6.1-linux-64.zip",
}
for name, url in urls.items():
    target = os.path.join(dest, name)
    if os.path.isfile(target) and os.access(target, os.X_OK):
        continue
    print("downloading " + name, flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "facefusion-heroku"})
    with urllib.request.urlopen(request, timeout=180) as response:
        payload = response.read()
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        archive.extract(name, dest)
    mode = os.stat(target).st_mode
    os.chmod(target, mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
print("ffmpeg static dir " + dest, flush=True)
PY
  export PATH="/tmp/ffmpeg-static:${PATH}"
fi

echo "ffmpeg: $(command -v ffmpeg)"
echo "ffprobe: $(command -v ffprobe)"
ffmpeg -version | head -n 1

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
