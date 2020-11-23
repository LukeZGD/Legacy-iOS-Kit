#!/bin/bash
export libipatcher=0
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig

# This script can be used to compile tools used by iOS-OTA-Downgrader for Linux

function Clone {
    git clone $3 https://github.com/$1/$2
}

function Compile {
    Clone $1 $2 $3
    cd $2
    [[ $2 == libipatcher ]] && git checkout v1
    if [[ $2 == libimobiledevice ]]; then
        ./autogen.sh
    elif [[ -e autogen.sh ]]; then
        ./autogen.sh --enable-static --disable-shared
    fi
    make
    sudo make install
    cd ..
}

. /etc/os-release
if [[ ! -z $UBUNTU_CODENAME ]]; then
    sudo apt update
    sudo apt install -y libtool automake g++ python-dev libzip-dev libcurl4-openssl-dev cmake libssl-dev libusb-1.0-0-dev libreadline-dev libbz2-dev libpng-dev pkg-config git
elif [[ $ID == fedora ]]; then
    sudo dnf install automake gcc-g++ libcurl-devel libusb-devel libtool libzip-devel make openssl-devel pkgconf-pkg-config readline-devel
fi

Compile matteyeux partial-zip #partialzip_linux
Compile lzfse lzfse
Compile libimobiledevice libplist
Compile libimobiledevice libusbmuxd
Compile libimobiledevice libimobiledevice
Compile LukeZGD libirecovery #irecovery_linux
Compile LukeZGD libgeneral
Compile LukeZGD libfragmentzip
Compile LukeZGD img4tool

if [[ $libipatcher != 0 ]]; then
    Clone Merculous xpwn
    cd xpwn
    sudo python3 install.py
    cd ..
    Compile tihmstar libipatcher --recursive
fi

Compile tihmstar tsschecker --recursive #tsschecker_linux
Compile LukeZGD futurerestore --recursive #futurerestore2_linux

mkdir tools
cp partial-zip/partialzip tools/partialzip_linux
cp libirecovery/tools/irecovery tools/irecovery_linux
cp tsschecker/tsschecker/tsschecker tools/tsschecker_linux
cp futurerestore/futurerestore/futurerestore tools/futurerestore2_linux
