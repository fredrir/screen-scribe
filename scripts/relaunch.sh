#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="build/xcode/Build/Products/Debug/ScreenScribe.app"
binary="$app/Contents/MacOS/ScreenScribe"
log="build/dev-app.log"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Building ScreenScribe"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! ./scripts/build.sh Debug quiet; then
  echo ""
  echo "❌ Build failed — keeping the previous instance running."
  exit 1
fi

pkill -x ScreenScribe 2>/dev/null || true

for _ in {1..50}; do
  if ! pgrep -x ScreenScribe >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

mkdir -p build

INJECTION_DIRECTORIES="$PWD/ScreenScribe/Sources,$PWD/build/xcode/Logs/Build" \
  NSUnbufferedIO=YES \
  nohup "$binary" --restore-settings >>"$log" 2>&1 &

echo "✅ ScreenScribe is running (log: $log)"
