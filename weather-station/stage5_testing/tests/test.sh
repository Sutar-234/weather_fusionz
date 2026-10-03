#!/bin/sh
set -e
make -s
./weather &
PID=$!
sleep 4
OUT=$(./weather-cli)
echo "$OUT"
echo "$OUT" | grep -q "Temperature" || { echo FAIL; kill $PID; exit 1; }
kill -INT $PID
wait $PID 2>/dev/null || true
echo PASS
