#!/bin/sh

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
apt-get update

apt-get install -y \
    bash \
    nginx \
    vim-tiny \
    libboost-serialization1.54.0 \
    libboost-program-options1.54.0 \
    libboost-system1.54.0 \
    libboost-thread1.54.0 \
    libboost-regex1.54.0 \
    libboost-locale1.54.0 \
    libboost-date-time1.54.0 \
    libboost-iostreams1.54.0 \
    libboost-python1.54.0 \
    libboost-filesystem1.54.0 \
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
    unzip \
    unrar-free \
    libstdc++6 \
    python-tk \


# Drop all static libs from /usr. not required and big
# find /usr/lib -type f -name '*.a' -print -delete

# Drop the statically linked Python images
rm -f /usr/lib/python2.7/config-x86_64-linux-gnu/*.a

# Final cleanup
apt-get purge -y vim 'language-pack-*' iso-codes python-software-properties software-properties-common rsync cpp gcc gcc-4.8 cpp-4.8
apt-get autoremove -y --purge
apt-get clean -y

# Make sure en_US.UTF-8 is available
locale-gen en_US.UTF-8

# Python stuff cleanup
# rm .pycs and rebuild them on boot
find /usr/local/lib/python2.7/dist-packages -name '*.pyc' -delete
install -m 555 /source/rebuild_pycs.py  /usr/local/bin/
cat >/etc/my_init.d/10-rebuild_pycs.sh <<BIF
#!/bin/bash

/usr/local/bin/rebuild_pycs.py &
BIF

chmod +x /etc/my_init.d/10-rebuild_pycs.sh

rm -rf /root/.cache /var/lib/apt/lists/* /tmp/* /var/tmp/* 2>/dev/null || true
rm -rf /usr/share/man*  2>/dev/null || true
# drop everything but keep copyright/licenses
find /usr/share/doc -type f ! -name copyright -delete 2>/dev/null || true
find /usr/share/doc -type d -empty -delete
# that's magnificent...
find /var/log -type f -name '*.log' -exec bash -c '</dev/null >{}' \;
