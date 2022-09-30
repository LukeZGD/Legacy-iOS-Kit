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
        python="$(which python3)"
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
        zenity="./resources/tools/zenity_macos"

    elif [[ $OSTYPE == "msys" ]]; then
        platform="win"
        platformver="$(cmd /c ver)"
        MPath+="$platform"
        bspatch="./resources/tools/bspatch_win"
        futurerestore="./resources/tools/futurerestore_win"
        python=/
    fi

    cherrybin="../$cherry/cherry"
    ideviceenterrecovery="$MPath/ideviceenterrecovery"
    ideviceinfo="$MPath/ideviceinfo"
    idevicerestore="./resources/tools/idevicerestore_$platform"
    idevicererestore="./resources/tools/idevicererestore_$platform"
    iproxy="$MPath/iproxy"
    ipsw="../resources/tools/ipsw_$platform"
    ipwndfu="$python ipwndfu"
    irecoverychk="$MPath/irecovery"
    irecovery="$irecoverychk"
    partialzip="./resources/tools/partialzip_$platform"
    ping="ping -c1"
    powdersn0w="../resources/tools/powdersn0w_$platform"
    pwnedDFU="./resources/tools/pwnedDFU_$platform"
    python2="$(which python2 2>/dev/null)"
    rmsigchks="$python rmsigchks.py"
    sha1sum="$(which sha1sum 2>/dev/null)"
    SimpleHTTPServer="$python -m SimpleHTTPServer 8888"
    SSH="-F ./resources/ssh_config"
    SCP="$(which scp) $SSH"
    SSH="$(which ssh) $SSH"
    tsschecker="./resources/tools/tsschecker_$platform"
    xpwntool="../resources/tools/xpwntool_$platform"

    if [[ $platform == "linux" ]]; then
        irecovery="env LD_LIBRARY_PATH=./resources/lib $irecovery"
        opensslver=$(openssl version | awk '{print $2}' | cut -c -3)
        if [[ $opensslver == "3"* ]]; then
            cherrybin="env LD_LIBRARY_PATH=../resources/lib $cherrybin"
        fi
        ipwndfu="$python2 ipwndfu"
        rmsigchks="$python2 rmsigchks.py"
        SimpleHTTPServer="$python -m http.server 8888"

    elif [[ $platform == "macos" ]]; then
        sha1sum="$(which shasum)"
        if (( ${platformver:0:2} > 11 )); then
            # for macOS 12 and newer
            python="/usr/bin/python3"
            ipwndfu="$python2 ipwndfu"
            rmsigchks="$python2 rmsigchks.py"
            SimpleHTTPServer="$python -m http.server 8888"
        fi
    elif [[ $platform == "win" ]]; then
        ping="ping -n 1"
        Log "WARNING - Using iOS-OTA-Downgrader on Windows is highly discouraged."
        Echo "* Please use it on Linux or macOS instead."
        Echo "* You may still continue, but you might encounter problems with restoring the device."
        sleep 3
        Input "Press Enter/Return to continue anyway (or press Ctrl+C to cancel)"
        read -s
    fi

    Log "Running on platform: $platform ($platformver)"
}

SaveExternal() {
    local Link
    local Name
    local SHA1
    if [[ $1 == "ipwndfu" ]]; then
        Link=https://github.com/LukeZGD/ipwndfu/archive/6e67c9e28a5f7f63f179dea670f7f858712350a0.zip
        Name=ipwndfu
        SHA1=61333249eb58faebbb380c4709384034ce0e019a
    elif [[ $1 == "ch3rryflower" ]]; then
        Link=https://web.archive.org/web/20210529174714if_/https://codeload.github.com/dora2-iOS/ch3rryflower/zip/316d2cdc5351c918e9db9650247b91632af3f11f
        Name=ch3rryflower
        SHA1=790d56db354151b9740c929e52c097ba57f2929d
    elif [[ $1 == "powdersn0w" ]]; then
        Link=https://dora2ios.github.io/download/konayuki/powdersn0w_v2.0b3.zip
        Name=powdersn0w
        SHA1=c733aac4a0833558ef9f5517f2a11ca547110b6e
    fi
    if [[ -d ./resources/$Name ]]; then
        return
    fi
    cd tmp
    SaveFile $Link $Name.zip $SHA1
    cd ../resources
    unzip -q ../tmp/$Name.zip -d .
    mv $Name* $Name
    cd ..
}

SaveFile() {
    Log "Downloading $2..."
    curl -L $1 -o $2
    local SHA1=$($sha1sum $2 | awk '{print $1}')
    if [[ $SHA1 != $3 ]]; then
        Error "Verifying $2 failed. The downloaded file may be corrupted or incomplete. Please run the script again" \
        "SHA1sum mismatch. Expected $3, got $SHA1"
    fi
}

InstallDepends() {
    local libimobiledevice

    mkdir resources/lib tmp 2>/dev/null
    cd resources
    cp lib/*.so.1.1 ../tmp 2>/dev/null
    rm -rf lib/*
    cp ../tmp/*.so.1.1 lib/ 2>/dev/null
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
        Echo "* Arch Linux repos do not ship python2, which is needed for ipwndfu"
        Echo "* If you need to use ipwndfu, python2 can be installed from the AUR"
        sudo pacman -Sy --noconfirm --needed base-devel bsdiff curl libimobiledevice openssh python udev unzip usbmuxd usbutils vim xmlstarlet zenity

    elif [[ -n $UBUNTU_CODENAME && $VERSION_ID == "2"* ]] ||
         (( DebianVer >= 11 )) || [[ $DebianVer == "sid" ]]; then
        [[ -n $UBUNTU_CODENAME ]] && sudo add-apt-repository -y universe
        sudo apt update
        sudo apt install -y bsdiff curl libimobiledevice6 openssh-client python2 python3 unzip usbmuxd usbutils xmlstarlet xxd zenity
        sudo systemctl enable --now udev systemd-udevd usbmuxd 2>/dev/null

    elif [[ $ID == "fedora" ]] && (( VERSION_ID >= 36 )); then
        ln -sf /usr/lib64/libbz2.so.1.* ../resources/lib/libbz2.so.1.0
        sudo dnf install -y bsdiff ca-certificates libimobiledevice openssl python2 python3 systemd udev usbmuxd vim-common xmlstarlet zenity
        sudo ln -sf /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-certificates.crt

    elif [[ $ID == "opensuse-tumbleweed" || $PRETTY_NAME == *"Leap 15.4" ]]; then
        [[ $ID == "opensuse-leap" ]] && ln -sf /lib64/libreadline.so.7 ../resources/lib/libreadline.so.8
        sudo zypper -n in bsdiff curl libimobiledevice-1_0-6 openssl python-base python3 usbmuxd vim xmlstarlet zenity

    elif [[ $platform == "macos" ]]; then
        xcode-select --install
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_macos.zip" "66a49e4f69757a3d9dc51109a8e4651020bfacb8")
        Echo "* iOS-OTA-Downgrader provides a copy of libimobiledevice and libirecovery by default"
        Echo "* In case that problems occur, try installing them from Homebrew or MacPorts"
        Echo "* The script will detect this automatically and will use the Homebrew/MacPorts versions of the tools"

    elif [[ $platform == "win" ]]; then
        pacman -Sy --noconfirm --needed ca-certificates curl openssh unzip zip
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_win.zip" "75ae3af3347b89107f0f6b7e41fde42e6ccdd404")
        if [[ ! $(ls ../resources/tools/*win*) ]]; then
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/tools_win.zip tools_win.zip b8b727b74d3bbba2093bef5a156e30cb29d6eac7
            Log "Extracting Windows tools..."
            unzip -oq tools_win.zip -d ../resources
        fi

    else
        Error "Distro not detected/supported by the install script." "See the repo README for supported OS versions/distros"
    fi

    if [[ $platform == "linux" ]]; then
        libimobiledevice=("https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/tools/libimobiledevice_linux.zip" "fc5e714adf6fa72328d3e1ddea4e633f370559a4")
        # from linux_fix script by Cryptiiiic
        sudo systemctl enable --now systemd-udevd usbmuxd 2>/dev/null
        echo "QUNUSU9OPT0iYWRkIiwgU1VCU1lTVEVNPT0idXNiIiwgQVRUUntpZFZlbmRvcn09PSIwNWFjIiwgQVRUUntpZFByb2R1Y3R9PT0iMTIyWzI3XXwxMjhbMC0zXSIsIE9XTkVSPSJyb290IiwgR1JPVVA9InVzYm11eGQiLCBNT0RFPSIwNjYwIiwgVEFHKz0idWFjY2VzcyIKCkFDVElPTj09ImFkZCIsIFNVQlNZU1RFTT09InVzYiIsIEFUVFJ7aWRWZW5kb3J9PT0iMDVhYyIsIEFUVFJ7aWRQcm9kdWN0fT09IjEzMzgiLCBPV05FUj0icm9vdCIsIEdST1VQPSJ1c2JtdXhkIiwgTU9ERT0iMDY2MCIsIFRBRys9InVhY2Nlc3MiCgoK" | base64 -d | sudo tee /etc/udev/rules.d/39-libirecovery.rules >/dev/null 2>/dev/null
        sudo chown root:root /etc/udev/rules.d/39-libirecovery.rules
        sudo chmod 0644 /etc/udev/rules.d/39-libirecovery.rules
        sudo udevadm control --reload-rules
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
    touch ../resources/first_run

    cd ..
    Log "Install script done! Please run the script again to proceed"
    Log "If your iOS device is plugged in, unplug and replug your device"
    ExitWin 0
}
