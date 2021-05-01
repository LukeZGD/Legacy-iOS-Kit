#!/bin/bash
trap 'echo "Exiting..."' EXIT

export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig

echo "This script can be used to compile tools used by iOS-OTA-Downgrader for Linux"

Clone() {
    git clone $3 https://github.com/$1/$2
}

Compile() {
    [[ $3 == --recursive ]] && Clone $1 $2 $3 || Clone $1 $2
    cd $2
    [[ -e autogen.sh ]] && ./autogen.sh $3 $4
    make
    sudo make install
    cd ..
}

. /etc/os-release
if [[ $UBUNTU_CODENAME != "focal" ]]; then
    echo "This compile script supports Ubuntu 20.04 only"
    exit 1
fi

sudo apt update
sudo apt install -y libtool automake g++ python-dev libzip-dev libcurl4-openssl-dev cmake libssl-dev libusb-1.0-0-dev libreadline-dev libbz2-dev libpng-dev pkg-config git

Compile matteyeux partial-zip #partialzip_linux
Compile lzfse lzfse
Compile libimobiledevice libplist
Compile libimobiledevice libusbmuxd
Compile libimobiledevice libimobiledevice
Compile LukeZGD libirecovery #irecovery_linux
Compile LukeZGD libgeneral --enable-static --disable-shared
Compile LukeZGD libfragmentzip --enable-static --disable-shared
Compile LukeZGD img4tool --enable-static --disable-shared
Compile tihmstar tsschecker --recursive #tsschecker_linux
Compile LukeeGD futurerestore --recursive #futurerestore2_linux

mkdir tools
cp partial-zip/partialzip tools/partialzip_linux
cp libirecovery/tools/irecovery tools/irecovery_linux
cp tsschecker/tsschecker/tsschecker tools/tsschecker_linux
cp futurerestore/futurerestore/futurerestore tools/futurerestore2_linux

echo "Done"
