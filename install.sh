#!/bin/bash

function ubuntu {
    sudo apt update
    sudo apt -y install bsdiff curl ifuse libimobiledevice-utils libzip4 usbmuxd
}

function ubuntu1804 {
    sudo apt -y install binutils
    mkdir tmp
    cd tmp
    apt download -o=dir::cache=. libcurl3
    ar x libcurl3* data.tar.xz
    tar xf data.tar.xz
    sudo cp -L usr/lib/x86_64-linux-gnu/libcurl.so.4 /usr/lib/libcurl.so.3
    if [ $(uname -m) == 'x86_64' ]
    then
        mtype='amd64'
    else
        mtype='i386'
    fi
    curl -L -# http://mirrors.edge.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1_${mtype}.deb -o libpng12.deb
    sudo dpkg -i libpng12.deb
    cd ..
    rm -rf tmp
}

function arch {
    sudo pacman -Sy --noconfirm bsdiff curl ifuse libcurl-compat libimobiledevice libpng12 libzip openssh openssl-1.0 usbmuxd usbutils
    sudo ln -sf /usr/lib/libzip.so.5 /usr/lib/libzip.so.4
}

clear
echo "******* 32bit-OTA-Downgrader *******"
echo "           - by LukeZGD             "
echo
echo "Install dependencies"
select opt in "Ubuntu 16.04" "Ubuntu 18.04" "Arch Linux"; do
    case $opt in
        "Ubuntu 16.04" ) ubuntu; break;;
        "Ubuntu 18.04" ) ubuntu; ubuntu1804; break;;
        "Arch Linux" ) arch; break;;
    esac
done
echo
echo "Install script done"
