#!/bin/bash
# Copyright (c) 2015 Datacratic Inc.  All rights reserved.
set -e
set -x

progname=$(basename $0)

CIDFILE=$(mktemp -u -t $progname.cid.XXXXXX)  # Race me!
BASE_IMG="quay.io/datacratic/baseimage:0.9.9"
IMG_NAME="quay.io/datacratic/mldb_base"

PLATFORM_DEPS_DOCKER_DIR="/mnt/local"
BUILD_DOCKER_DIR="/mnt/build"

function on_exit {
  if [ -n "$CIDFILE" ]; then
      rm -f "$CIDFILE" || true
  fi
}
trap on_exit EXIT

function usage {
cat <<EOF >&2
$progname [-b base_image] [-i image_name] -p platform-deps_source_dir [-w pip_wheelhouse_url]

    -b base_image               Base image to use ($BASE_IMG)
    -i image_name               Name of the resulting image ($IMG_NAME)
    -p platform-deps_source_dir Directory holding the platform-deps binaries
    -w pip_wheelhouse_url       URL to use a a pip wheelhouse

EOF
}

while getopts "b:p:i:w:" opt; do
  case $opt in
    b)
      BASE_IMG="$OPTARG"
      ;;
    i)
      IMG_NAME="$OPTARG"
      ;;
    p)
      PLATFORM_DEPS_BIN_DIR="$OPTARG"
      ;;
    w)
      PIP_WHEELHOUSE="-f $OPTARG"
      ;;
    *)
      usage
      exit
      ;;
  esac
done

if [ -z "$PLATFORM_DEPS_BIN_DIR" ]; then
    echo 'Missing required option: -p' >&2
    usage
    exit 1
fi


docker run -i --cidfile "$CIDFILE" -v $PLATFORM_DEPS_BIN_DIR:$PLATFORM_DEPS_DOCKER_DIR:ro -v $PWD:$BUILD_DOCKER_DIR:ro "$BASE_IMG" bash -c 'cat > /tmp/command-to-run && chmod +x /tmp/command-to-run && exec /tmp/command-to-run' <<EOF
set -e
set -x
echo "deb http://archive.ubuntu.com/ubuntu precise main universe" >/etc/apt/sources.list
echo "deb http://security.ubuntu.com/ubuntu/ precise-security universe main multiverse restricted" >> /etc/apt/sources.list
echo "deb http://mirror.pnl.gov/ubuntu/ precise-updates universe main multiverse restricted" >> /etc/apt/sources.list
echo "deb http://mirror.pnl.gov/ubuntu/ precise-backports universe main multiverse restricted" >> /etc/apt/sources.list
apt-get update
apt-get upgrade -y
apt-get install -y python-software-properties software-properties-common
add-apt-repository -y ppa:nginx/stable
add-apt-repository -y ppa:ubuntu-toolchain-r/test
apt-get update

apt-get install -y \
    bash \
    binutils \
    git \
    sudo \
    tcpdump \
    python-dev \
    nginx \
    vim-tiny \
    libgsasl7 \
    libbz2-1.0 \
    liblzma5 \
    libcrypto++9 \
    libicu48 \
    libace-6.0.1 \
    liblapack3gf \
    libblas3gf \
    libevent-1.4-2 \
    libcppunit-1.12-1 \
    libidn11 \
    librtmp0 \
    python-tk \
    libstdc++6

# Platform deps
cp -a -v -d  $PLATFORM_DEPS_DOCKER_DIR/lib /usr/local
# strip all libs
strip /usr/local/lib/*.so*
# drop static libs
find /usr/local/lib -type f -name "*.a" -delete
rm -rf /usr/local/lib/{node,node_modules}
ldconfig
echo "/usr/local contents:"
ls /usr/local

# Python dependencies
apt-get install -y python-pip
pip install -U pip==6.0.8 setuptools
pip2 install -U $PIP_WHEELHOUSE -r $BUILD_DOCKER_DIR/python_requirements.txt

# Final cleanup
apt-get purge -y vim locales iso-codes python-software-properties software-properties-common cpp gcc gcc-4.6
apt-get autoremove -y --purge
apt-get clean -y

# Python stuff cleanup
# rm .pycs and rebuild them on boot
find /usr/local/lib/python2.7/dist-packages -name '*.pyc' -delete
install -m 555 $BUILD_DOCKER_DIR/mldb_base/rebuild_pycs.py  /usr/local/bin/
cat >/etc/my_init.d/10-rebuild_pycs.sh <<BIF
#!/bin/bash

/usr/local/bin/rebuild_pycs.py &
BIF
chmod +x /etc/my_init.d/10-rebuild_pycs.sh
# Remove extra data...
rm -rf /usr/local/lib/python2.7/dist-packages/bokeh/server/tests/data
rm -rf /usr/local/lib/python2.7/dist-packages/matplotlib/tests/baseline_images
# Strip libs
find /usr/local/lib/python2.7 -type f -name "*so" -exec strip {} \;

rm -rf /root/.cache /var/lib/apt/lists/* /tmp/* /var/tmp/* 2>/dev/null || true
rm -rf /usr/share/man*  2>/dev/null || true
# drop everything but keep copyright/licenses
find /usr/share/doc -type f ! -name copyright -delete 2>/dev/null || true
find /usr/share/doc -type d -empty -delete
# that's magnificent...
find /var/log -type f -name '*.log' -exec bash -c '</dev/null >{}' \;
EOF

CID=$(cat "$CIDFILE")
echo $CID
docker commit $CID "$IMG_NAME"
docker rm $CID
