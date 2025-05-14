#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
# shellcheck source-path=SCRIPTDIR
source "${MY_DIR}/build_utils.sh"

check_var "${PRIME_ROOT}"
check_var "${PRIME_DOWNLOAD_URL}"

# fetch the sources and install
PRIME_VERSION=${PRIME_ROOT#*-}
curl -fsSL -o "${PRIME_ROOT}.tar.gz" "${PRIME_DOWNLOAD_URL}/${PRIME_VERSION}.tar.gz"
tar -zxf "${PRIME_ROOT}.tar.gz"
pushd "${PRIME_ROOT}"
./autogen.sh
DESTDIR=/manylinux-rootfs do_standard_install
popd
rm -rf "${PRIME_ROOT}" "${PRIME_ROOT}.tar.gz"

# Strip what we can
strip_ /manylinux-rootfs

# Install
cp -rlf /manylinux-rootfs/* /

# Remove temporary rootfs
rm -rf /manylinux-rootfs

hash -r
