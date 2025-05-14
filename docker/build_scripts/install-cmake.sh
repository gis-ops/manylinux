#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
# shellcheck source-path=SCRIPTDIR
source "${MY_DIR}/build_utils.sh"

# Install cmake
check_var "${CMAKE_ROOT}"
check_var "${CMAKE_HASH}"
check_var "${CMAKE_DOWNLOAD_URL}"

fetch_source "${CMAKE_ROOT}.tar.gz" "${CMAKE_DOWNLOAD_URL}"
check_sha256sum "${CMAKE_ROOT}.tar.gz" "${CMAKE_HASH}"
tar -zxf "${CMAKE_ROOT}.tar.gz"
pushd "${CMAKE_ROOT}"
./bootstrap
DESTDIR=/manylinux-rootfs make install -j$(nproc)
popd
rm -rf "${CMAKE_ROOT}" "${CMAKE_ROOT}.tar.gz"

# Strip what we can
strip_ /manylinux-rootfs

# Install
cp -rlf /manylinux-rootfs/* /

# Remove temporary rootfs
rm -rf /manylinux-rootfs

hash -r
cmake --version
