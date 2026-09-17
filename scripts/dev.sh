#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/xcode/Build/Products/Debug/ScreenScribe.app"
binary="$app/Contents/MacOS/ScreenScribe"
log="build/dev-app.log"

cleanup() {
  pkill -x ScreenScribe 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "        🔨 Building ScreenScribe"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./scripts/build.sh Debug

pkill -x ScreenScribe 2>/dev/null || true
for _ in {1..50}; do
  if ! pgrep -x ScreenScribe >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

mkdir -p build
: >"$log"

INJECTION_DIRECTORIES="$PWD/ScreenScribe/Sources,$PWD/build/xcode/Logs/Build" \
  NSUnbufferedIO=YES \
  nohup "$binary" --restore-settings >>"$log" 2>&1 &

cat <<'EOF'

Stop:                                 Ctrl-C
EOF

tail -n +1 -f "$log"
