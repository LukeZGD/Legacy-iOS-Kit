#!/bin/bash

SetToolPaths() {
    if [[ $OSTYPE == "linux"* ]]; then
        . /etc/os-release 2>/dev/null
        platform="linux"
        platformver="$PRETTY_NAME"
    
        futurerestore1="sudo LD_PRELOAD=./resources/lib/libcurl.so.3 LD_LIBRARY_PATH=./resources/lib ./resources/tools/futurerestore1_linux"
        futurerestore2="sudo LD_LIBRARY_PATH=./resources/lib ./resources/tools/futurerestore2_linux"
        idevicerestore="sudo LD_LIBRARY_PATH=./resources/lib ./resources/tools/idevicerestore_linux"
        python="$(which python2)"
        ipwndfu="sudo $python ipwndfu"
        rmsigchks="sudo $python rmsigchks.py"
        SimpleHTTPServer="sudo $python -m SimpleHTTPServer 80"

    elif [[ $OSTYPE == "darwin"* ]]; then
        platform="macos"
        platformver="${1:-$(sw_vers -productVersion)}"
    
        futurerestore1="./resources/tools/futurerestore1_macos"
        futurerestore2="./resources/tools/futurerestore2_macos"
        idevicerestore="./resources/tools/idevicerestore_macos"
        ipwnder32="./resources/tools/ipwnder32_macos"
        python="/usr/bin/python"
        ipwndfu="$python ipwndfu"
        rmsigchks="$python rmsigchks.py"
        SimpleHTTPServer="$python -m SimpleHTTPServer 80"
    fi
    bspatch="$(which bspatch)"
    git="$(which git)"
    ideviceenterrecovery="./resources/libimobiledevice_$platform/ideviceenterrecovery"
    ideviceinfo="./resources/libimobiledevice_$platform/ideviceinfo"
    iproxy="./resources/libimobiledevice_$platform/iproxy"
    ipsw="./tools/ipsw_$platform"
    irecoverychk="./resources/libimobiledevice_$platform/irecovery"
    irecovery="$irecoverychk"
    [[ $platform == "linux" ]] && irecovery="sudo LD_LIBRARY_PATH=./resources/lib $irecovery"
    partialzip="./resources/tools/partialzip_$platform"
    SSH="-F ./resources/ssh_config"
    SCP="$(which scp) $SSH"
    SSH="$(which ssh) $SSH"
    tsschecker="./resources/tools/tsschecker_$platform"
    
    Log "Running on platform: $platform ($platformver)"
}

SaveExternal() {
    local ExternalURL="https://github.com/LukeZGD/$1.git"
    local External=$1
    [[ $1 == "iOS-OTA-Downgrader-Keys" ]] && External="firmware"
    cd resources
    if [[ ! -d $External || ! -d $External/.git ]]; then
        Log "Downloading $External..."
        rm -rf $External
        $git clone $ExternalURL $External
    fi
    if [[ ! -e $External/README.md || ! -d $External/.git ]]; then
        rm -rf $External
        Error "Downloading/updating $1 failed. Please run the script again"
    fi
    cd ..
}

SaveFile() {
    curl -L $1 -o $2
    if [[ $(shasum $2 | awk '{print $1}') != $3 ]]; then
        Error "Verifying failed. Please run the script again" "./restore.sh Install"
    fi
}

SavePkg() {
    if [[ ! -d ../saved/lib ]]; then
        Log "Downloading packages..."
        SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/depends2_linux.zip depends_linux.zip 38cf1db21c9aba88f0de95a1a7959ac2ac53c464
        mkdir -p ../saved/lib
        unzip depends_linux.zip -d ../saved/lib
    fi
    cp ../saved/lib/* .
}


InstallDepends() {
    local libimobiledevice
    
    mkdir resources/lib tmp 2>/dev/null
    cd resources
    rm -rf firmware ipwndfu lib/*
    cd ../tmp
    
    Log "Installing dependencies..."
    if [[ $ID == "arch" || $ID_LIKE == "arch" ]]; then
        sudo pacman -Syu --noconfirm --needed base-devel bsdiff curl libcurl-compat libpng12 libimobiledevice libzip openssh openssl-1.0 python2 unzip usbutils
        ln -sf /usr/lib/libcurl.so.3 ../resources/lib/libcurl.so.3
        ln -sf /usr/lib/libzip.so.5 ../resources/lib/libzip.so.4
    
    elif [[ ! -z $UBUNTU_CODENAME && $VERSION_ID == "2"* ]] ||
         [[ $PRETTY_NAME == "Debian GNU/Linux bullseye/sid" ]]; then
        [[ ! -z $UBUNTU_CODENAME ]] && sudo add-apt-repository -y universe
        sudo apt update
        sudo apt install -y bsdiff curl git libimobiledevice6 openssh-client python2 usbmuxd usbutils
        SavePkg
        cp libcrypto.so.1.0.0 libcurl.so.3 libpng12.so.0 libssl.so.1.0.0 ../resources/lib
        if [[ $PRETTY_NAME == "Debian GNU/Linux bullseye/sid" || $VERSION_ID != "20"* ]]; then
            sudo apt install -y libzip4
        else
            cp libzip.so.4 ../resources/lib
        fi
    
    elif [[ $ID == "fedora" ]] && (( $VERSION_ID >= 33 )); then
        sudo dnf install -y bsdiff git libimobiledevice libpng12 libzip perl-Digest-SHA python2
        SavePkg
        cp libcrypto.so.1.0.0 libssl.so.1.0.0 ../resources/lib
        ln -sf /usr/lib64/libzip.so.5 ../resources/lib/libzip.so.4
        ln -sf /usr/lib64/libbz2.so.1.* ../resources/lib/libbz2.so.1.0
    
    elif [[ $ID == "opensuse-tumbleweed" || $PRETTY_NAME == "openSUSE Leap 15.3" ]]; then
        if [[ $ID == "opensuse-tumbleweed" ]]; then
            libimobiledevice="libimobiledevice-1_0-6"
        else
            libimobiledevice="libimobiledevice6"
            ln -sf /lib64/libreadline.so.7 ../resources/lib/libreadline.so.8
        fi
        sudo zypper -n in bsdiff curl git $libimobiledevice libpng12-0 libopenssl1_0_0 libzip5 python-base
        ln -sf /usr/lib64/libzip.so.5 ../resources/lib/libzip.so.4
    
    elif [[ $platform == "macos" ]]; then
        xcode-select --install
        libimobiledevice=("https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.14/libimobiledevice.1.2.1-r1116-osx-x64.zip" "328e809dea350ae68fb644225bbf8469c0f0634b")
    
    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi
    
    if [[ $platform == "linux" ]]; then
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_linux.zip" "4344b3ca95d7433d5a49dcacc840d47770ba34c4")
    fi
    
    if [[ ! -d ../resources/libimobiledevice_$platform ]]; then
        SaveFile ${libimobiledevice[0]} libimobiledevice.zip ${libimobiledevice[1]}
        mkdir ../resources/libimobiledevice_$platform
        unzip libimobiledevice.zip -d ../resources/libimobiledevice_$platform
        chmod +x ../resources/libimobiledevice_$platform/*
    fi
    
    cd ..
    Log "Install script done! Please run the script again to proceed"
    exit 0
}
