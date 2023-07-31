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

# /START MOD: install osrm-backend dependencies
COMPILE_DEPS="bzip2-devel readline-devel wget"

if [ "${AUDITWHEEL_POLICY}" == "manylinux2014" ]; then
	PACKAGE_MANAGER=yum
elif [ "${AUDITWHEEL_POLICY}" == "manylinux_2_28" ]; then
	PACKAGE_MANAGER=dnf
else
	echo "Unsupported policy: '${AUDITWHEEL_POLICY}'"
	exit 1
fi

if [ "${PACKAGE_MANAGER}" == "yum" ]; then
	yum update
	yum -y install ${COMPILE_DEPS}
	yum clean all
	rm -rf /var/cache/yum
elif [ "${PACKAGE_MANAGER}" == "dnf" ]; then
	dnf update
 	dnf -y install --allowerasing ${COMPILE_DEPS}
 	dnf clean all
 	rm -rf /var/cache/yum
else
	echo "${PACKAGE_MANAGER} is not implemented"
	exit 1
fi

mkdir installs && cd installs

# Install TBB
TBB_VERSION=oneapi-tbb-2021.3.0
wget --tries 5 https://github.com/oneapi-src/oneTBB/releases/download/v2021.3.0/${TBB_VERSION}-lin.tgz -O onetbb.tgz
tar zxvf onetbb.tgz
cp -a ${TBB_VERSION}/lib/. /usr/local/lib/
cp -a ${TBB_VERSION}/include/. /usr/local/include/	
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/intel64/gcc4.8/

# Install Conan
pipx install conan==1.60.1

# Install osrm-backend &&
git clone https://github.com/Project-OSRM/osrm-backend.git --recursive --depth 1 &&
cd osrm-backend &&
mkdir build && cd build &&
cmake -DENABLE_CONAN=ON -DBUILD_ROUTED=OFF -DCMAKE_CXX_FLAGS="-Wno-array-bounds -Wno-uninitialized -Wno-free-nonheap-object" .. &&
make -j$(nproc) && make install &&
cd ../../

cd ../ && rm -rf install
# /END MOD

hardlink -cv /opt/_internal

# update system packages
LC_ALL=C ${MY_DIR}/update-system-packages.sh
