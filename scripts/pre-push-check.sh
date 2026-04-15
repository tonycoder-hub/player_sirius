#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "[1/4] git diff --check"
git diff --check

echo "[2/4] docs snapshot"
test -f docs/implementation-status.md
test -f docs/regression-checklist.md
test -f docs/ffmpeg-integration.md
test -f docs/smb-integration.md

echo "[3/4] native source snapshot"
test -f AppScope/entry/src/main/cpp/CMakeLists.txt
test -f AppScope/entry/src/main/cpp/native_player_bridge.cpp
test -f AppScope/entry/src/main/cpp/smb_client_bridge.cpp
test -d AppScope/entry/src/main/cpp/media_core
test -d third_party/libsmb2
test -f third_party/libsmb2/upstream/CMakeLists.txt

echo "[4/4] optional cmake configure/build"
cmake_bin=""
if command -v cmake >/dev/null 2>&1; then
  cmake_bin="$(command -v cmake)"
elif [ -x /home/linuxbrew/.linuxbrew/Cellar/cmake/4.3.1/bin/cmake ]; then
  cmake_bin="/home/linuxbrew/.linuxbrew/Cellar/cmake/4.3.1/bin/cmake"
fi

if [ -n "$cmake_bin" ]; then
  "$cmake_bin" -S AppScope/entry/src/main/cpp -B /tmp/player_sirius_native_cmake_check >/dev/null
  "$cmake_bin" --build /tmp/player_sirius_native_cmake_check --target smb_client_bridge native_player_bridge -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >/dev/null
  echo "cmake configure/build: ok"
else
  echo "cmake not found, skip configure"
fi

echo "pre-push checks: ok"
