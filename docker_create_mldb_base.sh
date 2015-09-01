#!/bin/bash
# Copyright (c) 2015 Datacratic Inc.  All rights reserved.
set -e
set -x

progname=$(basename $0)

CIDFILE=$(mktemp -u -t $progname.cid.XXXXXX)  # Race me!
BASE_IMG="quay.io/datacratic/baseimage:0.9.17"
IMG_NAME="quay.io/datacratic/mldb_base:14.04"

BUILD_DOCKER_DIR="/mnt/build"

function on_exit {
  if [ -n "$CIDFILE" ]; then
      rm -f "$CIDFILE" || true
  fi
}
trap on_exit EXIT

function usage {
cat <<EOF >&2
$progname [-b base_image] [-i image_name] [-w pip_wheelhouse_url]

    -b base_image               Base image to use ($BASE_IMG)
    -i image_name               Name of the resulting image ($IMG_NAME)
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
    w)
      PIP_WHEELHOUSE="-f $OPTARG"
      ;;
    *)
      usage
      exit
      ;;
  esac
done

docker run -i --cidfile "$CIDFILE" -v $PWD:$BUILD_DOCKER_DIR:ro "$BASE_IMG" bash -c 'cat > /tmp/command-to-run && chmod +x /tmp/command-to-run && exec /tmp/command-to-run' <<EOF
set -e
set -x
echo "deb http://archive.ubuntu.com/ubuntu trusty main universe" >/etc/apt/sources.list
echo "deb http://security.ubuntu.com/ubuntu/ trusty-security universe main multiverse restricted" >> /etc/apt/sources.list
echo "deb http://mirror.pnl.gov/ubuntu/ trusty-updates universe main multiverse restricted" >> /etc/apt/sources.list
echo "deb http://mirror.pnl.gov/ubuntu/ trusty-backports universe main multiverse restricted" >> /etc/apt/sources.list
apt-get update
apt-get upgrade -y
apt-get install -y python-software-properties software-properties-common
add-apt-repository -y ppa:nginx/stable
#add-apt-repository -y ppa:ubuntu-toolchain-r/test
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
    libboost-all-dev \
    libgoogle-perftools4 \
    liblzma5 \
    libbz2-1.0 \
    libcrypto++9 \
    libv8-3.14.5 \
    libcurlpp0 \
    libcurl3 \
    libssh2-1 \
    liburcu1 \
    libpython2.7 \
    libgit2-0 \
    libicu52 \
    liblapack3gf \
    libblas3gf \
    libevent-1.4-2 \
    libidn11 \
    python-tk \
    unzip \
    unrar-free \
    libstdc++6

# no need, but do we want to strip base?
## strip all libs
#strip /usr/local/lib/*.so*
## drop static libs
#find /usr/local/lib -type f -name "*.a" -delete
#rm -rf /usr/local/lib/{node,node_modules}
#ldconfig
#echo "/usr/local contents:"
#ls /usr/local

# Python dependencies
apt-get install -y python-pip
pip install -U pip setuptools || true  # https://github.com/pypa/pip/issues/3045
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
