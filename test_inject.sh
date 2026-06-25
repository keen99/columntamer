#!/bin/zsh
# Test load ColumnTamer dylib into live Finder via lldb.
set -eu
DYLIB="$1"
PID=$(pgrep -x Finder)
if [[ -z "$PID" ]]; then echo "no Finder"; exit 1; fi
echo "Finder PID=$PID"
sudo lldb -p "$PID" \
  -o "expr (void*)dlopen(\"$DYLIB\", 2)" \
  -o "expr (char*)dlerror()" \
  -o "continue" \
  -o "detach" \
  -o quit
