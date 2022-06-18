#!/bin/bash

SetToolPaths() {
    local Detect="Detected libimobiledevice and libirecovery installed from "
    MPath="./resources/libimobiledevice_"
    cherrymac="./resources/ch3rryflower/Tools/macos/UNTETHERED"

    if [[ $OSTYPE == "linux"* ]]; then
        . /etc/os-release 2>/dev/null
        platform="linux"
        platformver="$PRETTY_NAME"
        MPath+="$platform"
        bspatch="$(which bspatch)"
        cherry="./resources/ch3rryflower/Tools/ubuntu/UNTETHERED"
        futurerestore="./resources/tools/futurerestore_linux"
        python="$(which python2)"
        xmlstarlet="$(which xmlstarlet)"
        zenity="$(which zenity)"

    elif [[ $OSTYPE == "darwin"* ]]; then
        platform="macos"
        platformver="${1:-$(sw_vers -productVersion)}"
        MPath+="$platform"
        if [[ -e /usr/local/bin/idevicedate && -e /usr/local/bin/irecovery ]]; then
            Detect+="Homebrew (Intel Mac)"
            MPath="/usr/local/bin"
        elif [[ -e /opt/homebrew/bin/idevicedate && -e /opt/homebrew/bin/irecovery ]]; then
            Detect+="Homebrew (Apple Silicon)"
            MPath="/opt/homebrew/bin"
        elif [[ -e /opt/local/bin/idevicedate && -e /opt/local/bin/irecovery ]]; then
            Detect+="MacPorts"
            MPath="/opt/local/bin"
        else
            Detect=
        fi
        [[ -n $Detect ]] && Log "$Detect"
        bspatch="/usr/bin/bspatch"
        cherry="$cherrymac"
        futurerestore="./resources/tools/futurerestore_macos_$(uname -m)"
        [[ ! -e $futurerestore ]] && futurerestore="./resources/tools/futurerestore_macos_arm64"
        ipwnder32="./resources/tools/ipwnder32_macos"
        ipwnder_lite="./resources/tools/ipwnder_macos"
        python="/usr/bin/python"
        xmlstarlet=/
        zenity="./resources/tools/zenity_macos"

    elif [[ $OSTYPE == "msys" ]]; then
        platform="win"
        platformver="$(cmd /c ver)"
        MPath+="$platform"
        bspatch="./resources/tools/bspatch_win"
        futurerestore="./resources/tools/futurerestore_win"
        python=/
    fi

    if [[ $platform != "win" ]]; then
        expect="$(which expect)"
    fi
    ideviceenterrecovery="$MPath/ideviceenterrecovery"
    ideviceinfo="$MPath/ideviceinfo"
    idevicerestore="./resources/tools/idevicerestore_$platform"
    iproxy="$MPath/iproxy"
    ipsw="../resources/tools/ipsw_$platform"
    ipwndfu="$python ipwndfu"
    irecoverychk="$MPath/irecovery"
    irecovery="$irecoverychk"
    irecovery2="../tools/irecovery_$platform"
    partialzip="./resources/tools/partialzip_$platform"
    ping="ping -c1"
    pwnedDFU="$cherry/pwnedDFU"
    rmsigchks="$python rmsigchks.py"
    SimpleHTTPServer="$python -m SimpleHTTPServer 8888"
    SSH="-F ./resources/ssh_config"
    SCP="$(which scp) $SSH"
    SSH="$(which ssh) $SSH"
    tsschecker="./resources/tools/tsschecker_$platform"

    if [[ $platform == "linux" ]]; then
        # these need to run as root for device detection
        expect="sudo $expect"
        futurerestore="sudo $futurerestore"
        idevicerestore="sudo LD_LIBRARY_PATH=./resources/lib $idevicerestore"
        ipwndfu="sudo $ipwndfu"
        irecovery="sudo LD_LIBRARY_PATH=./resources/lib $irecovery"
        irecovery2="sudo LD_LIBRARY_PATH=./resources/lib $irecovery2"
        pwnedDFU="sudo $pwnedDFU"
        rmsigchks="sudo $rmsigchks"
    elif [[ $platform == "macos" ]]; then
        # for macOS 12.3 and newer
        if (( ${platformver:0:2} > 11 )) && [[ -z $python ]]; then
            python="/usr/bin/python3"
            ipwndfu="$(which python2) ipwndfu"
            rmsigchks="$(which python2) rmsigchks.py"
            SimpleHTTPServer="$python -m http.server 8888"
        fi
    else
        ping="ping -n 1"
        zenity="./resources/tools/zenity_$platform"
    fi

    Log "Running on platform: $platform ($platformver)"
}

SaveExternal() {
    if [[ -d ./resources/$2 ]]; then
        return
    fi
    cd tmp
    SaveFile $1 $2.zip $3
    cd ../resources
    unzip -q ../tmp/$2.zip -d .
    mv $2* $2
    cd ..
}

SaveFile() {
    Log "Downloading $2..."
    curl -L $1 -o $2
    local SHA1=$(shasum $2 | awk '{print $1}')
    if [[ $SHA1 != $3 ]]; then
        Error "Verifying $2 failed. The downloaded file may be corrupted or incomplete. Please run the script again" \
        "SHA1sum mismatch. Expected $3, got $SHA1"
    fi
}

InstallDepends() {
    local libimobiledevice

    mkdir resources/lib tmp 2>/dev/null
    cd resources
    cp lib/*.so.1.1 ../tmp
    rm -rf ipwndfu lib/*
    cp ../tmp/*.so.1.1 lib/
    cd ../tmp

    Log "Installing dependencies..."
    if [[ $platform == "linux" ]]; then
        Echo "* iOS-OTA-Downgrader will be installing dependencies from your distribution's package manager"
        Echo "* Enter your user password when prompted"
        Input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
        read -s
    fi

    if [[ -e /etc/debian_version ]]; then
        DebianVer=$(cat /etc/debian_version)
        if [[ $DebianVer == *"sid" ]]; then
            DebianVer="sid"
        else
            DebianVer="$(echo $DebianVer | cut -c -2)"
        fi
    fi

    if [[ $ID == "arch" || $ID_LIKE == "arch" || $ID == "artix" ]]; then
        sudo pacman -Sy --noconfirm --needed base-devel bsdiff curl expect libimobiledevice openssh python2 unzip usbutils vim xmlstarlet zenity

    elif [[ -n $UBUNTU_CODENAME && $VERSION_ID == "2"* ]] ||
         (( DebianVer >= 11 )) || [[ $DebianVer == "sid" ]]; then
        [[ -n $UBUNTU_CODENAME ]] && sudo add-apt-repository -y universe
        sudo apt update
        sudo apt install -y bsdiff curl expect libimobiledevice6 openssh-client python2 unzip usbmuxd usbutils xmlstarlet xxd zenity

    elif [[ $ID == "fedora" ]] && (( VERSION_ID >= 33 )); then
        ln -sf /usr/lib64/libbz2.so.1.* ../resources/lib/libbz2.so.1.0
        sudo dnf install -y bsdiff expect libimobiledevice perl-Digest-SHA python2 vim-common xmlstarlet zenity

    elif [[ $ID == "opensuse-tumbleweed" || $PRETTY_NAME == *"Leap 15.3" || $PRETTY_NAME == *"Leap 15.4" ]]; then
        libimobiledevice="libimobiledevice-1_0-6"
        if [[ $PRETTY_NAME == *"Leap"* ]]; then
            ln -sf /lib64/libreadline.so.7 ../resources/lib/libreadline.so.8
            [[ $VERSION == "15.3" ]] && libimobiledevice="libimobiledevice6"
        fi
        sudo zypper -n in bsdiff curl expect $libimobiledevice python-base vim xmlstarlet zenity

    elif [[ $platform == "macos" ]]; then
        xcode-select --install
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_macos.zip" "66a49e4f69757a3d9dc51109a8e4651020bfacb8")
        Echo "* iOS-OTA-Downgrader provides a copy of libimobiledevice and libirecovery by default"
        Echo "* In case that problems occur, try installing them from Homebrew"
        Echo "* The script will detect this automatically and will use the Homebrew versions of the tools"
        Echo "* Install using this command: 'brew install libimobiledevice libirecovery'"

    elif [[ $platform == "win" ]]; then
        pacman -Sy --noconfirm --needed ca-certificates curl openssh unzip zip
        SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/tools_win.zip tools_win.zip a34cbce38d89f96b97e62199aece78a58dd00e15
        Log "Extracting Windows tools..."
        unzip -oq tools_win.zip -d ../resources
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_win.zip" "75ae3af3347b89107f0f6b7e41fde42e6ccdd404")

    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi

    if [[ $platform == "linux" ]]; then
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_linux.zip" "fc5e714adf6fa72328d3e1ddea4e633f370559a4")
    fi

    if [[ ! -d ../resources/libimobiledevice_$platform && $MPath == "./resources"* ]]; then
        SaveFile ${libimobiledevice[0]} libimobiledevice.zip ${libimobiledevice[1]}
        mkdir ../resources/libimobiledevice_$platform
        Log "Extracting libimobiledevice..."
        unzip -q libimobiledevice.zip -d ../resources/libimobiledevice_$platform
        chmod +x ../resources/libimobiledevice_$platform/*
    elif [[ $MPath != "./resources"* ]]; then
        mkdir ../resources/libimobiledevice_$platform
    fi

    cd ..
    Log "Install script done! Please run the script again to proceed"
}
