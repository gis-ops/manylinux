#!/bin/bash

# Stop at any error, show all commands
set -exuo pipefail

# Get script directory
MY_DIR=$(dirname "${BASH_SOURCE[0]}")

# Get build utilities
source $MY_DIR/build_utils.sh

mkdir /opt/python
for PREFIX in $(find /opt/_internal/ -mindepth 1 -maxdepth 1 \( -name 'cpython*' -o -name 'pypy*' \)); do
	# Some python's install as bin/python3. Make them available as
	# bin/python.
	if [ -e ${PREFIX}/bin/python3 ] && [ ! -e ${PREFIX}/bin/python ]; then
		ln -s python3 ${PREFIX}/bin/python
	fi
	${PREFIX}/bin/python -m ensurepip
	if [ -e ${PREFIX}/bin/pip3 ] && [ ! -e ${PREFIX}/bin/pip ]; then
		ln -s pip3 ${PREFIX}/bin/pip
	fi
	PY_VER=$(${PREFIX}/bin/python -c "import sys; print('.'.join(str(v) for v in sys.version_info[:2]))")
	# Since we fall back on a canned copy of pip, we might not have
	# the latest pip and friends. Upgrade them to make sure.
	${PREFIX}/bin/pip install -U --require-hashes -r ${MY_DIR}/requirements${PY_VER}.txt
	# Create a symlink to PREFIX using the ABI_TAG in /opt/python/
	ABI_TAG=$(${PREFIX}/bin/python ${MY_DIR}/python-tag-abi-tag.py)
	ln -s ${PREFIX} /opt/python/${ABI_TAG}
	# Make versioned python commands available directly in environment.
	if [[ "${PREFIX}" == *"/pypy"* ]]; then
		ln -s ${PREFIX}/bin/python /usr/local/bin/pypy${PY_VER}
	else
		ln -s ${PREFIX}/bin/python /usr/local/bin/python${PY_VER}
	fi
done

# Create venv for auditwheel & certifi
TOOLS_PATH=/opt/_internal/tools
/opt/python/cp310-cp310/bin/python -m venv $TOOLS_PATH
source $TOOLS_PATH/bin/activate

# Install default packages
pip install -U --require-hashes -r $MY_DIR/requirements3.10.txt
# Install certifi and pipx
pip install -U --require-hashes -r $MY_DIR/requirements-base-tools.txt

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
ln -s $(python -c 'import certifi; print(certifi.where())') /opt/_internal/certs.pem
# If you modify this line you also have to modify the versions in the Dockerfiles:
export SSL_CERT_FILE=/opt/_internal/certs.pem

# Deactivate the tools virtual environment
deactivate

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

# /MOD START: install valhalla and osrm dependencies
if [ "${AUDITWHEEL_POLICY}" == "manylinux2010" ] || [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	PACKAGE_MANAGER=yum
	COMPILE_DEPS="boost-devel sqlite-devel libspatialite-devel protobuf-devel libcurl-devel luajit-devel geos-devel"
elif [ "${AUDITWHEEL_POLICY}" == "manylinux_2_24" ]; then
	PACKAGE_MANAGER=apt
	# valhalla
	COMPILE_DEPS="libspatialite-dev libgeos-dev libluajit-5.1-dev libcurl4-openssl-dev libgeos++-dev"
	# install protobuf v3.21.1
	git clone https://github.com/protocolbuffers/protobuf.git && cd protobuf
	git checkout v21.1  # aka 3.21.1
	git submodule update --init --recursive
	cmake -B build "-DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=true"
	make -C build -j$(nproc)
	make -C build install
elif [ "${AUDITWHEEL_POLICY}" == "manylinux_2_28" ]; then
	PACKAGE_MANAGER=dnf
	# valhalla, skip mjolnir deps for now
	COMPILE_DEPS="libcurl-devel luajit-devel geos-devel libspatialite-devel"
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
 	dnf -y install --allowerasing ${COMPILE_DEPS}
 	dnf clean all
 	rm -rf /var/cache/yum
else
	echo "${PACKAGE_MANAGER} is not implemented"
	exit 1
fi


hardlink -cv /opt/_internal

# update system packages
LC_ALL=C ${MY_DIR}/update-system-packages.sh
