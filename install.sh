#!/bin/bash

function ubuntu {
    sudo apt update
    sudo apt -y install bsdiff curl ifuse libimobiledevice-utils libzip4 usbmuxd
}

function arch {
    sudo pacman -Sy --noconfirm bsdiff libcurl-compat libpng12 libzip openssl-1.0 usbmuxd usbutils
    sudo ln -sf /usr/lib/libzip.so.5 /usr/lib/libzip.so.4
}

clear
echo "******* 32bit-OTA-Downgrader *******"
echo "           - by LukeZGD             "
echo
echo "Install dependencies"
select opt in "Ubuntu 16.04" "Arch Linux"; do
    case $opt in
        "Ubuntu 16.04" ) ubuntu; break;;
        "Arch Linux" ) arch; break;;
    esac
done
