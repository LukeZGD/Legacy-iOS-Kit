#!/bin/bash

SetToolPaths() {
    # SetToolPaths does exactly what the function name does - set path to tools used by the script
    # It also sets the platform variable to "macos" or "linux"
    # This is used on the main function
    
    if [[ $OSTYPE == "linux"* ]]; then
        . /etc/os-release 2>/dev/null # source os-release to get distribution (and version if needed)
        platform="linux"
        
        futurerestore1="sudo LD_PRELOAD=./resources/lib/libcurl.so.3 LD_LIBRARY_PATH=resources/lib ./resources/tools/futurerestore1_linux"
        futurerestore2="sudo LD_LIBRARY_PATH=./resources/lib ./resources/tools/futurerestore2_linux"
        ideviceenterrecovery="$(which ideviceenterrecovery)"
        ideviceinfo="$(which ideviceinfo)"
        idevicerestore="sudo LD_LIBRARY_PATH=./resources/lib ./resources/tools/idevicerestore_linux"
        iproxy="$(which iproxy)"
        ipsw="env LD_LIBRARY_PATH=./lib ./tools/ipsw_linux"
        irecoverychk="./resources/libirecovery/bin/irecovery"
        irecovery="sudo LD_LIBRARY_PATH=./resources/lib $irecoverychk"
        partialzip="./resources/tools/partialzip_linux"
        python="$(which python2)"
        tsschecker="env LD_LIBRARY_PATH=./resources/lib ./resources/tools/tsschecker_linux"
        if [[ $UBUNTU_CODENAME == "bionic" ]] || [[ $VERSION == "10 (buster)" ]] ||
           [[ $PRETTY_NAME == "openSUSE Leap 15.2" ]]; then
            futurerestore2="${futurerestore2}_bionic"
            idevicerestore="${idevicerestore}_bionic"
        fi

    elif [[ $OSTYPE == "darwin"* ]]; then
        macver=${1:-$(sw_vers -productVersion)} # get macOS version
        platform="macos"
        
        futurerestore1="./resources/tools/futurerestore1_macos"
        futurerestore2="./resources/tools/futurerestore2_macos"
        ideviceenterrecovery="./resources/libimobiledevice/ideviceenterrecovery"
        ideviceinfo="./resources/libimobiledevice/ideviceinfo"
        idevicerestore="./resources/tools/idevicerestore_macos"
        iproxy="./resources/libimobiledevice/iproxy"
        ipsw="./tools/ipsw_macos"
        ipwnder32="./resources/tools/ipwnder32_macos"
        irecoverychk="./resources/libimobiledevice/irecovery"
        irecovery="$irecoverychk"
        partialzip="./resources/tools/partialzip_macos"
        python="/usr/bin/python"
        tsschecker="./resources/tools/tsschecker_macos"
    fi
    bspatch="$(which bspatch)"
    git="$(which git)"
    SSH="-F ./resources/ssh_config"
    SCP="$(which scp) $SSH"
    SSH="$(which ssh) $SSH"
    
    Log "Depends: Running in $platform platform"
}

Compile() {
    Log "Compiling $2..."
    $git clone --depth 1 https://github.com/$1/$2.git
    cd $2
    ./autogen.sh --prefix="$(cd ../.. && pwd)/resources/$2"
    make install
    cd ..
    sudo rm -rf $2
}

SaveExternal() {
    ExternalURL="https://github.com/LukeZGD/$1.git"
    External=$1
    [[ $1 == "iOS-OTA-Downgrader-Keys" ]] && External="firmware"
    cd resources
    if [[ ! -d $External ]] || [[ ! -d $External/.git ]]; then
        Log "Downloading $External..."
        rm -rf $External
        $git clone $ExternalURL $External
    #else
    #    Log "Updating $External..."
    #    cd $External
    #    $git pull 2>/dev/null
    #    cd ..
    fi
    if [[ ! -e $External/README.md ]] || [[ ! -d $External/.git ]]; then
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


InstallDependencies() {
    mkdir tmp 2>/dev/null
    cd resources
    rm -rf firmware ipwndfu lib/* libimobiledevice* libirecovery
    cd ../tmp
    
    Log "Installing dependencies..."
    if [[ $ID == "arch" ]] || [[ $ID_LIKE == "arch" ]]; then
        # Arch
        sudo pacman -Syu --noconfirm --needed base-devel bsdiff curl libcurl-compat libpng12 libimobiledevice libusbmuxd libzip openssh openssl-1.0 python2 unzip usbmuxd usbutils
        ln -sf /usr/lib/libcurl.so.3 ../resources/lib/libcurl.so.3
        ln -sf /usr/lib/libzip.so.5 ../resources/lib/libzip.so.4
    
    elif [[ $UBUNTU_CODENAME == "bionic" ]] || [[ $UBUNTU_CODENAME == "focal" ]] ||
         [[ $UBUNTU_CODENAME == "groovy" ]] || [[ $UBUNTU_CODENAME == "hirsute" ]] ||
         [[ $VERSION == "10 (buster)" ]] || [[ $PRETTY_NAME == "Debian GNU/Linux bullseye/sid" ]]; then
        # Ubuntu, Debian
        [[ ! -z $UBUNTU_CODENAME ]] && sudo add-apt-repository universe
        sudo apt update
        sudo apt install -y autoconf automake bsdiff build-essential curl git libglib2.0-dev libimobiledevice6 libimobiledevice-utils libreadline-dev libtool-bin libusb-1.0-0-dev libusbmuxd-tools openssh-client usbmuxd usbutils
        SavePkg
        cp libcrypto.so.1.0.0 libcurl.so.3 libssl.so.1.0.0 ../resources/lib
        if [[ $UBUNTU_CODENAME == "bionic" ]] || [[ $VERSION == "10 (buster)" ]]; then
            sudo apt install -y libzip4 python
            cp libpng12.so.0 libzip.so.5 ../resources/lib
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/tools_linux_bionic.zip tools_linux_bionic.zip 959abbafacfdaddf87dd07683127da1dab6c835f
            unzip tools_linux_bionic.zip -d ../resources/tools
        elif [[ $PRETTY_NAME == "Debian GNU/Linux bullseye/sid" ]] || [[ $UBUNTU_CODENAME == "hirsute" ]]; then
            sudo apt install -y libzip4 python2
            cp libpng12.so.0 libzip.so.5 ../resources/lib
        else
            sudo apt install -y libzip5 python2
            cp libpng12.so.0 libzip.so.4 ../resources/lib
        fi
        if [[ $UBUNTU_CODENAME == "focal" ]]; then
            ln -sf /usr/lib/x86_64-linux-gnu/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
            ln -sf /usr/lib/x86_64-linux-gnu/libplist.so.3 ../resources/lib/libplist-2.0.so.3
            ln -sf /usr/lib/x86_64-linux-gnu/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        fi
    
    elif [[ $ID == "fedora" ]]; then
        # Fedora
        sudo dnf install -y automake binutils bsdiff git libimobiledevice-utils libpng12 libtool libusb-devel libusbmuxd-utils make libzip perl-Digest-SHA python2 readline-devel
        SavePkg
        cp libcrypto.so.1.0.0 libssl.so.1.0.0 ../resources/lib
        if (( $VERSION_ID <= 32 )); then
            ln -sf /usr/lib64/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
            ln -sf /usr/lib64/libplist.so.3 ../resources/lib/libplist-2.0.so.3
            ln -sf /usr/lib64/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        fi
        ln -sf /usr/lib64/libzip.so.5 ../resources/lib/libzip.so.4
        ln -sf /usr/lib64/libbz2.so.1.* ../resources/lib/libbz2.so.1.0
    
    elif [[ $ID == "opensuse-tumbleweed" ]] || [[ $PRETTY_NAME == "openSUSE Leap 15.2" ]]; then
        # openSUSE
        [[ $ID == "opensuse-tumbleweed" ]] && iproxy="libusbmuxd-tools" || iproxy="iproxy libzip5"
        sudo zypper -n in automake bsdiff gcc git imobiledevice-tools $iproxy libimobiledevice libpng12-0 libopenssl1_0_0 libusb-1_0-devel libtool make python-base readline-devel
        ln -sf /usr/lib64/libimobiledevice.so.6 ../resources/lib/libimobiledevice-1.0.so.6
        ln -sf /usr/lib64/libplist.so.3 ../resources/lib/libplist-2.0.so.3
        ln -sf /usr/lib64/libusbmuxd.so.6 ../resources/lib/libusbmuxd-2.0.so.6
        ln -sf /usr/lib64/libzip.so.5 ../resources/lib/libzip.so.4
    
    elif [[ $OSTYPE == "darwin"* ]]; then
        # macOS
        #imobiledevicenet=$(curl -s https://api.github.com/repos/libimobiledevice-win32/imobiledevice-net/releases/latest | grep browser_download_url | cut -d '"' -f 4 | awk '/osx-x64/ {print $1}')
        xcode-select --install
        #curl -L $imobiledevicenet -o libimobiledevice.zip
        SaveFile https://github.com/libimobiledevice-win32/imobiledevice-net/releases/download/v1.3.14/libimobiledevice.1.2.1-r1116-osx-x64.zip libimobiledevice.zip 328e809dea350ae68fb644225bbf8469c0f0634b
        
    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi
    
    if [[ $platform == linux ]]; then
        Compile LukeZGD libirecovery
        ln -sf ../libirecovery/lib/libirecovery.so.3 ../resources/lib/libirecovery-1.0.so.3
        ln -sf ../libirecovery/lib/libirecovery.so.3 ../resources/lib/libirecovery.so.3
    else
        mkdir ../resources/libimobiledevice
        unzip libimobiledevice.zip -d ../resources/libimobiledevice
        chmod +x ../resources/libimobiledevice/*
    fi
    
    Log "Install script done! Please run the script again to proceed"
    exit
}
