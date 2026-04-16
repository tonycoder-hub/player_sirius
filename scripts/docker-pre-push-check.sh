#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${PLAYER_SIRIUS_DOCKER_IMAGE:-ubuntu:latest}"
mirror="${PLAYER_SIRIUS_APT_MIRROR:-http://mirrors.aliyun.com/ubuntu}"

docker run --rm \
  -v "${repo_root}:/workspace" \
  -w /workspace \
  "$image" \
  bash -lc "
    set -euo pipefail
    if [ -f /etc/apt/sources.list ]; then
      sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|${mirror}|g' \
        -e 's|http://security.ubuntu.com/ubuntu|${mirror}|g' \
        -e 's|https://mirrors.aliyun.com/ubuntu|${mirror}|g' \
        /etc/apt/sources.list
    fi
    if ls /etc/apt/sources.list.d/*.sources >/dev/null 2>&1; then
      sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|${mirror}|g' \
        -e 's|http://security.ubuntu.com/ubuntu|${mirror}|g' \
        -e 's|https://mirrors.aliyun.com/ubuntu|${mirror}|g' \
        /etc/apt/sources.list.d/*.sources
    fi
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      cmake \
      g++ \
      git \
      libnode-dev \
      make
    git config --global --add safe.directory /workspace
    git config --global core.autocrlf true
    bash scripts/pre-push-check.sh
  "
