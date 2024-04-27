#!/bin/bash

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
source $MY_DIR/build_utils.sh

mkdir /opt/python
for PREFIX in $(find /opt/_internal/ -mindepth 1 -maxdepth 1 \( -name 'cpython*' -o -name 'pypy*' \)); do
	${MY_DIR}/finalize-one.sh ${PREFIX}
done

# create manylinux-interpreters script
cat <<EOF > /usr/local/bin/manylinux-interpreters
#!/bin/bash

set -euo pipefail

/opt/python/cp310-cp310/bin/python $MY_DIR/manylinux-interpreters.py "\$@"
EOF
chmod 755 /usr/local/bin/manylinux-interpreters

MANYLINUX_INTERPRETERS_NO_CHECK=1 /usr/local/bin/manylinux-interpreters ensure "$@"

# Create venv for auditwheel & certifi
TOOLS_PATH=/opt/_internal/tools
/opt/python/cp310-cp310/bin/python -m venv --without-pip ${TOOLS_PATH}

# Install certifi and pipx
/opt/python/cp310-cp310/bin/python -m pip --python ${TOOLS_PATH}/bin/python install -U --require-hashes -r ${MY_DIR}/requirements-base-tools.txt

# Make pipx available in PATH,
# Make sure when root installs apps, they're also in the PATH
cat <<EOF > /usr/local/bin/pipx
#!/bin/bash

set -euo pipefail

if [ \$(id -u) -eq 0 ]; then
	export PIPX_HOME=/opt/_internal/pipx
	export PIPX_BIN_DIR=/usr/local/bin
fi
${TOOLS_PATH}/bin/pipx "\$@"
EOF
chmod 755 /usr/local/bin/pipx

# Our openssl doesn't know how to find the system CA trust store
#   (https://github.com/pypa/manylinux/issues/53)
# And it's not clear how up-to-date that is anyway
# So let's just use the same one pip and everyone uses
ln -s $(${TOOLS_PATH}/bin/python -c 'import certifi; print(certifi.where())') /opt/_internal/certs.pem
# If you modify this line you also have to modify the versions in the Dockerfiles:
export SSL_CERT_FILE=/opt/_internal/certs.pem

# install other tools with pipx
pushd $MY_DIR/requirements-tools
for TOOL_PATH in $(find . -type f); do
	TOOL=$(basename ${TOOL_PATH})
	pipx install --pip-args="--require-hashes -r" ${TOOL}
done
popd

# We do not need the precompiled .pyc and .pyo files.
clean_pyc /opt/_internal

# remove cache
rm -rf /root/.cache
rm -rf /tmp/* || true

# /MOD START: install valhalla and osrm dependencies
if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ] || [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	PACKAGE_MANAGER=yum
	COMPILE_DEPS="boost-devel sqlite-devel libspatialite-devel protobuf-devel libcurl-devel luajit-devel geos-devel boost-devel"
elif [ "${AUDITWHEEL_POLICY}" == "manylinux_2_24" ]; then
	PACKAGE_MANAGER=apt
	# valhalla
	COMPILE_DEPS="libspatialite-dev libgeos-dev libluajit-5.1-dev libcurl4-openssl-dev libgeos++-dev libboost-all-dev"
	# install protobuf v3.21.1
	git clone https://github.com/protocolbuffers/protobuf.git && cd protobuf
	git checkout v21.1  # aka 3.21.1
	git submodule update --init --recursive
	cmake -B build "-DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=true"
	make -C build -j$(nproc)
	make -C build install
elif [ "${AUDITWHEEL_POLICY}" == "manylinux_2_28" ]; then
	PACKAGE_MANAGER=dnf
	# valhalla
	COMPILE_DEPS="libcurl-devel luajit-devel geos-devel libspatialite-devel boost-devel"
	# install protobuf v3.21.1, not sure anymore why we're doing this?!
	git clone --recurse-submodules https://github.com/protocolbuffers/protobuf.git && cd protobuf
	git checkout v21.1  # aka 3.21.1
	git submodule update --init --recursive
	cmake -B build "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
	make -C build -j$(nproc)
	make -C build install
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

if [ "${PACKAGE_MANAGER}" == "yum" ]; then
	yum -y install ${COMPILE_DEPS}
	yum clean all
	rm -rf /var/cache/yum
elif [ "${PACKAGE_MANAGER}" == "apt" ]; then
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -qq -y --no-install-recommends ${COMPILE_DEPS}
	apt-get clean -qq
	rm -rf /var/lib/apt/lists/*
elif [ "${PACKAGE_MANAGER}" == "dnf" ]; then
	dnf -y update
	dnf -y install epel-release
	dnf -y update
 	dnf -y install --allowerasing ${COMPILE_DEPS}
 	dnf clean all
 	rm -rf /var/cache/dnf
else
	echo "${PACKAGE_MANAGER} is not implemented"
	exit 1
fi


hardlink -cv /opt/_internal

# update system packages
LC_ALL=C ${MY_DIR}/update-system-packages.sh
