#!/bin/bash
# Install packages that will be needed at runtime

# Stop at any error, show all commands
set -exuo pipefail

# Set build environment variables
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
# shellcheck source-path=SCRIPTDIR
source "${MY_DIR}/build_utils.sh"

# if a devel package is added to COMPILE_DEPS,
# make sure the corresponding library is added to RUNTIME_DEPS if applicable

# MOD: add Valhalla dependencies to manylinux_2_28 (AlmaLinux 8)
if [ "${OS_ID_LIKE}" = "rhel" ]; then
	COMPILE_DEPS=(bzip2-devel ncurses-devel readline-devel gdbm-devel libpcap-devel xz-devel openssl openssl-devel keyutils-libs-devel krb5-devel libcom_err-devel curl-devel uuid-devel libffi-devel kernel-headers libdb-devel perl-IPC-Cmd)
	if [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
		COMPILE_DEPS+=(libidn-devel libXft-devel)
	elif [ "${AUDITWHEEL_POLICY}" == "manylinux_2_28" ]; then
		COMPILE_DEPS+=(libidn-devel tk-devel)
	else
		COMPILE_DEPS+=(libidn2-devel tk-devel)
	fi
	COMPILE_DEPS+=(boost-devel sqlite-devel libspatialite-devel libcurl-devel luajit-devel geos-devel boost-devel gdal-devel)
	# install protobuf v3.21.1, not sure anymore why we're upgrading this?!
	git clone --recurse-submodules https://github.com/protocolbuffers/protobuf.git && cd protobuf
	git checkout v21.1  # aka 3.21.1
	git submodule update --init --recursive
	cmake -B build "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
	make -C build -j$(nproc)
	make -C build install
elif [ "${OS_ID_LIKE}" == "debian" ]; then
	COMPILE_DEPS=(libbz2-dev libncurses-dev libreadline-dev tk-dev libgdbm-dev libdb-dev libpcap-dev liblzma-dev openssl libssl-dev libkeyutils-dev libkrb5-dev comerr-dev libidn2-0-dev libcurl4-openssl-dev uuid-dev libffi-dev linux-headers-generic)
elif [ "${OS_ID_LIKE}" == "alpine" ]; then
	COMPILE_DEPS=(bzip2-dev ncurses-dev readline-dev tk-dev gdbm-dev libpcap-dev xz-dev openssl openssl-dev keyutils-dev krb5-dev libcom_err libidn-dev curl-dev util-linux-dev libffi-dev linux-headers)
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

manylinux_pkg_install "${COMPILE_DEPS[@]}"
manylinux_pkg_clean
