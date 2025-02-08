#!/usr/bin/env bash

set -e

#
# Configurable variables
#

MOBY_VERSION="v27.5.1"
CLI_VERSION="v27.5.1"
BUILDX_VERSION="v0.20.1"
COMPOSE_VERSION="v2.32.4"

#
# Usage dialog
#

SCRIPT_VERSION="v0.3"
SCRIPT_NAME="$(basename "${0}")"
echo "${SCRIPT_NAME} ${SCRIPT_VERSION} - Docker build script for CoreELEC systems"
case "${1}" in
  build )
    echo "Building Docker"
    ;;
  clean )
    echo "Cleaning up build directory"
    rm -rf build
    exit 0
    ;;
  * )
    echo "Usage:"
    echo "  ${SCRIPT_NAME} build \$XARCH           Build docker for specified 'uname -m' like architecture or local one."
    echo "  ${SCRIPT_NAME} clean                   Cleanup"
    echo "  ${SCRIPT_NAME} --help                  Display this help message."
    exit 0
    ;;
esac

#
# Buildx check
#

if ! docker info 2>/dev/null | grep buildx &>/dev/null; then
  echo "'docker buildx' support is required"
  exit 1
fi

UNAME="${2:-$(uname -m)}"
if [ -z "${UNAME##*x86_64*}" ]; then
  XARCH="amd64"
elif [ -z "${UNAME##*aarch64*}" ]; then
  XARCH="arm64"
elif [ -z "${UNAME##*armv[7-8]*}" ]; then
  XARCH="armhf"
elif [ -z "${UNAME##*armv6*}" ]; then
  XARCH="armel"
else
  echo "Cannot convert architecture from 'uname -m', using it directly"
  XARCH="${UNAME}"
fi

echo "MOBY VERSION: ${MOBY_VERSION}"
echo "CLI VERSION: ${CLI_VERSION}"
echo "BUILDX VERSION: ${BUILDX_VERSION}"
echo "COMPOSE VERSION: ${COMPOSE_VERSION}"
echo "XARCH: ${XARCH}"

#
# Helpers
#

pushd () { command pushd "$@" > /dev/null; }
popd () { command popd "$@" > /dev/null; }

#
# Script directory
#

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd "${SCRIPT_DIR}"

#
# Preparing environment and build directory
#

mkdir -p "build"
pushd build

#
# Repo Cloning
#

GIT_CLONE="git clone -c advice.detachedHead=false --depth 1 --single-branch"

if [ ! -d "moby" ]; then
  ${GIT_CLONE} --branch "${MOBY_VERSION}" -- "https://github.com/moby/moby.git" moby
  timeout 2 patch -p0 < "${SCRIPT_DIR}/src/patch/patch_daemon_unix_go.patch" || true
fi

if [ ! -d "cli" ]; then
  ${GIT_CLONE} --branch "${CLI_VERSION}" -- "https://github.com/docker/cli.git" cli
fi

if [ ! -d "buildx" ]; then
  ${GIT_CLONE} --branch "${BUILDX_VERSION}" -- "https://github.com/docker/buildx.git" buildx
fi

if [ ! -d "compose" ]; then
  ${GIT_CLONE} --branch "${COMPOSE_VERSION}" -- "https://github.com/docker/compose.git" compose
fi

#
# Compile
#

pushd "moby"
MOBY_VERSION="$(git describe --match 'v[0-9]*' --dirty='.m' --always --tags)"
rm -rf "bundles"
docker buildx bake --progress=plain --set "*.platform=$XARCH" all
popd

pushd "cli"
rm -rf "build"
docker buildx bake --progress=plain --set "*.platform=$XARCH"
popd

pushd "buildx"
rm -rf "bin"
docker buildx bake --progress=plain --set "*.platform=$XARCH"
popd

pushd "compose"
rm -rf "bin"
docker buildx bake --progress=plain --set *.platform=$XARCH
popd

#
# Packaging
#

rm -rf "storage"
mkdir -p "storage" "storage/.docker" "storage/.docker/bin" "storage/.docker/cli-plugins" "storage/.docker/data-root"
cp -Rp "${SCRIPT_DIR}/src/config" "storage/.config"
cp -Rp "moby/bundles/binary/." "storage/.docker/bin"
cp -Rp "cli/build/." "storage/.docker/bin"
cp -Rp "buildx/bin/build/." "storage/.docker/cli-plugins"
cp -Rp "compose/bin/build/." "storage/.docker/cli-plugins"

pushd "storage/.docker/bin"
ln -fs "../cli-plugins/docker-compose" "docker-compose"
popd

mkdir -p "out"
TIME_NOW=$(date +"%Y%m%d")
tar Jcvf "out/docker_${MOBY_VERSION}_coreelec_${XARCH}_${TIME_NOW}.tar.xz" "storage"

popd
popd

echo "Building is done"
