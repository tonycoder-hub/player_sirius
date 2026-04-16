$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$image = if ($env:PLAYER_SIRIUS_DOCKER_IMAGE) { $env:PLAYER_SIRIUS_DOCKER_IMAGE } else { 'ubuntu:latest' }
$mirror = if ($env:PLAYER_SIRIUS_APT_MIRROR) { $env:PLAYER_SIRIUS_APT_MIRROR } else { 'http://mirrors.aliyun.com/ubuntu' }

$containerScript = @"
set -euo pipefail
if [ -f /etc/apt/sources.list ]; then
  sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|$mirror|g' \
    -e 's|http://security.ubuntu.com/ubuntu|$mirror|g' \
    -e 's|https://mirrors.aliyun.com/ubuntu|$mirror|g' \
    /etc/apt/sources.list
fi
if ls /etc/apt/sources.list.d/*.sources >/dev/null 2>&1; then
  sed -i \
    -e 's|http://archive.ubuntu.com/ubuntu|$mirror|g' \
    -e 's|http://security.ubuntu.com/ubuntu|$mirror|g' \
    -e 's|https://mirrors.aliyun.com/ubuntu|$mirror|g' \
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
"@

docker run --rm `
  -v "${repoRoot}:/workspace" `
  -w /workspace `
  $image `
  bash -lc $containerScript
