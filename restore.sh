#!/usr/bin/env bash

device_disable_bbupdate="iPad2,3" # Disable baseband update for this device. You can also change this to your device if needed.
ipsw_openssh=1 # If this value is 1, OpenSSH will be added to custom IPSW. (8.4.1 daibutsu and 6.1.3 p0sixspwn only)

print() {
    echo "${color_B}${1}${color_N}"
}

input() {
    echo "${color_Y}[Input] ${1}${color_N}"
}

log() {
    echo "${color_G}[Log] ${1}${color_N}"
}

warn() {
    echo "${color_Y}[WARNING] ${1}${color_N}"
}

error() {
    echo -e "${color_R}[Error] ${1}\n${color_Y}${*:2}${color_N}"
    exit 1
}

pause() {
    input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
    read -s
}

clean() {
    rm -rf "$(dirname "$0")/tmp/"* "$(dirname "$0")/iP"*/ "$(dirname "$0")/tmp/"
    if [[ $device_sudoloop == 1 ]]; then
        sudo rm -rf /tmp/futurerestore /tmp/*.json "$(dirname "$0")/tmp/"* "$(dirname "$0")/iP"*/ "$(dirname "$0")/tmp/"
        sudo systemctl restart usbmuxd
    fi
}

clean_and_exit() {
    if [[ $platform == "windows" ]]; then
        input "Press Enter/Return to exit."
        read -s
    fi
    kill $httpserver_pid $iproxy_pid $sudoloop_pid $usbmuxd_pid 2>/dev/null
    clean
}

bash_version=$(/usr/bin/env bash -c 'echo ${BASH_VERSINFO[0]}')
if (( bash_version < 5 )); then
    error "Your bash version ($bash_version) is too old. Install a newer version of bash to continue." \
    "* For macOS users, install bash, libimobiledevice, and libirecovery from Homebrew or MacPorts" \
    $'\n* For Homebrew: brew install bash libimobiledevice libirecovery' \
    $'\n* For MacPorts: sudo port install bash libimobiledevice libirecovery'
fi

display_help() {
    echo '******* iOS-OTA-Downgrader *******
 - Downgrader script by LukeZGD -

Usage: ./restore.sh [Options]

NOTE: CLI implementation is NOT COMPLETE (yet)

List of options:
    --debug                   For script debugging (set -x and debug mode)
    --device-ecid [ECID]      Provide device ECID (must be decimal)
    --device-type [Type]      Provide device type (eg. iPad2,1)
    --entry-device            Enable manual device and ECID entry
    --help                    Display this help message
    --no-color                Disable colors for script output
    --no-device               Enable no device mode
    --no-version-check        Disable script version checking
    --sudoloop                Run some tools as root for device detection

For 32-bit devices:
    --kdfu                    Place device in kDFU mode

For devices compatible with downgrades (see README):
    --custom-ipsw [version]   Create custom IPSW for provided iOS version
    --downgrade [version]     Downgrade/Restore to provided iOS version
    --ipsw [IPSW path]        Set path to IPSW
    --ipsw-verbose            Enable verbose boot option (iPhone 4 only)
    --jailbreak               Enable jailbreak option
    --memory                  Enable memory option for creating IPSW
    --save-blobs [version]    Save OTA blobs for provided iOS version
    --shsh [SHSH path]        Set path to SHSH

    * For jailbreak option on 8.4.1, also provide [jailbreak] (etasonjb | daibutsu)
    * For "Other" downgrades with SHSH, provide "Other" without quotes as version
    * Default IPSW path: <script location>/name_of_ipswfile.ipsw
    * Default SHSH path: <script location>/saved/shsh/name_of_blobfile.shsh(2)
    '
}

set_tool_paths() {
    : '
    sets variables: platform, platform_ver, dir
    also checks architecture (linux) and macos version
    also set distro, debian_ver, ubuntu_ver, fedora_ver variables for linux

    list of tools set here:
    bspatch, jq, ping, scp, ssh, sha1sum (for macos: shasum -a 1), sha256sum (for macos: shasum -a 256), zenity

    these ones "need" sudo for linux arm, not for others:
    futurerestore, gaster, idevicerestore, idevicererestore, ipwnder, irecovery

    tools set here will be executed using:
    $name_of_tool

    the rest of the tools not listed here will be executed using:
    "$dir/$name_of_tool"
    '

    if [[ $OSTYPE == "linux"* ]]; then
        . /etc/os-release
        platform="linux"
        platform_ver="$PRETTY_NAME"
        dir="../bin/linux/"

        # architecture check
        if [[ $(uname -m) == "a"* && $(getconf LONG_BIT) == 64 ]]; then
            dir+="arm64"
        elif [[ $(uname -m) == "a"* ]]; then
            dir+="armhf"
        elif [[ $(uname -m) == "x86_64" ]]; then
            dir+="x86_64"
        else
            error "Your architecture ($(uname -m)) is not supported."
        fi

        # version check
        if [[ -e /etc/debian_version ]]; then
            debian_ver=$(cat /etc/debian_version)
            if [[ $debian_ver == *"sid" ]]; then
                debian_ver="sid"
            else
                debian_ver="$(echo "$debian_ver" | cut -c -2)"
            fi
        fi
        if [[ -n $UBUNTU_CODENAME ]]; then
            ubuntu_ver="$(echo "$VERSION_ID" | cut -c -2)"
        fi
        if [[ $ID == "fedora" || $ID == "nobara" ]]; then
            fedora_ver=$VERSION_ID
        fi

        # distro check
        if [[ $ID == "arch" || $ID_LIKE == "arch" || $ID == "artix" ]]; then
            distro="arch"
        elif (( ubuntu_ver >= 22 )) || (( debian_ver >= 12 )) || [[ $debian_ver == "sid" ]]; then
            distro="debian"
        elif (( fedora_ver >= 36 )); then
            distro="fedora"
        elif [[ $ID == "opensuse-tumbleweed" ]]; then
            distro="opensuse"
        else
            error "Distro not detected/supported. See the repo README for supported OS versions/distros"
        fi

        jq="$(which jq)"
        ping="ping -c1"
        zenity="$(which zenity)"

        # live cd/usb check
        if [[ $(id -u $USER) == 999 || $USER == "liveuser" ]]; then
            live_cdusb=1
            log "Linux Live CD/USB detected."
            if [[ $(pwd) == "/home"* ]]; then
                df . -h
                if [[ $(lsblk -o label | grep -c "casper-rw") == 1 || $(lsblk -o label | grep -c "persistence") == 1 ]]; then
                    log "Detected iOS-OTA-Downgrader running on persistent storage."
                else
                    warn "Detected iOS-OTA-Downgrader running on temporary storage."
                    print "* You may run out of space and get errors during the downgrade process."
                    print "* Please move iOS-OTA-Downgrader to an external drive that is NOT used for the live USB."
                    print "* This means using another external HDD/flash drive to store iOS-OTA-Downgrader on."
                    print "* To be able to use one USB drive only, make sure to enable Persistent Storage for the live USB."
                    pause
                fi
            fi
        fi

        # sudoloop check
        if [[ $(uname -m) == "x86_64" && -e ../resources/sudoloop && $device_sudoloop != 1 ]]; then
            local opt
            log "Previous run failed to detect iOS device."
            print "* You may enable sudoloop mode, which will run some tools as root."
            read -p "$(input 'Enable sudoloop mode? (y/N) ')" opt
            if [[ $opt == 'Y' || $opt == 'y' ]]; then
                device_sudoloop=1
            fi
        fi
        if [[ $(uname -m) == "a"* || $device_sudoloop == 1 || $live_cdusb == 1 ]]; then
            if [[ $live_cdusb != 1 ]]; then
                print "* Enter your user password when prompted"
            fi
            sudo -v
            (while true; do sudo -v; sleep 60; done) &
            sudoloop_pid=$!
            futurerestore="sudo "
            gaster="sudo "
            idevicerestore="sudo "
            idevicererestore="sudo "
            ipwnder="sudo "
            irecovery="sudo "
            irecovery2="sudo "
            sudo chmod +x $dir/*
            sudo systemctl stop usbmuxd
            sudo usbmuxd -p -f &>/dev/null &
            usbmuxd_pid=$!
        fi

    elif [[ $OSTYPE == "darwin"* ]]; then
        platform="macos"
        platform_ver="${1:-$(sw_vers -productVersion)}"
        dir="../bin/macos"

        # macos version check
        if [[ $(echo "$platform_ver" | cut -c -2) == 10 ]]; then
            local mac_ver=$(echo "$platform_ver" | cut -c 4-)
            mac_ver=${mac_ver%.*}
            if (( mac_ver < 13 )); then
                error "Your macOS version ($platform_ver) is not supported." \
                "* You need to be on macOS 10.13 or newer to continue."
            fi
        fi

        bspatch="$(which bspatch)"
        futurerestore="$dir/futurerestore_$(uname -m)"
        if [[ ! -e $futurerestore ]]; then
            futurerestore="$dir/futurerestore_arm64"
        fi
        ideviceenterrecovery="$(which ideviceenterrecovery)"
        ideviceinfo="$(which ideviceinfo)"
        iproxy="$(which iproxy)"
        irecovery="$(which irecovery)"
        ping="ping -c1"
        sha1sum="$(which shasum) -a 1"
        sha256sum="$(which shasum) -a 256"

        if [[ -z $ideviceinfo || -z $irecovery ]]; then
            error "Install bash, libimobiledevice and libirecovery from Homebrew or MacPorts to continue." \
            "* For Homebrew: brew install bash libimobiledevice libirecovery" \
            $'\n* For MacPorts: sudo port install bash libimobiledevice libirecovery'
        fi

    elif [[ $OSTYPE == "msys" ]]; then
        platform="windows"
        platform_ver="$(uname)"
        dir="../bin/windows"

        ping="ping -n 1"

        warn "Using iOS-OTA-Downgrader on Windows is not recommended."
        # itunes version check
        local itunes_ver="Unknown"
        if [[ -e "/c/Program Files/iTunes/iTunes.exe" ]]; then
            itunes_ver=$(powershell "(Get-Item -path 'C:\Program Files\iTunes\iTunes.exe').VersionInfo.ProductVersion")
        elif [[ -e "/c/Program Files (x86)/iTunes/iTunes.exe" ]]; then
            itunes_ver=$(powershell "(Get-Item -path 'C:\Program Files (x86)\iTunes\iTunes.exe').VersionInfo.ProductVersion")
        fi
        log "iTunes version: $itunes_ver"
        if [[ $(echo "$itunes_ver" | cut -c -2) == 12 ]]; then
            itunes_ver=$(echo "$itunes_ver" | cut -c 4-)
            itunes_ver=${itunes_ver%%.*}
            if (( itunes_ver > 6 )); then
                warn "Detected a newer iTunes version."
                print "* Please downgrade iTunes to 12.6.5, 12.4.3, or older."
                print "* You may still continue, but you might encounter issues with restoring the device."
                pause
            fi
        fi
    else
        error "Your platform ($OSTYPE) is not supported." "* Supported platforms: Linux, macOS, Windows"
    fi
    log "Running on platform: $platform ($platform_ver)"
    rm ../resources/sudoloop 2>/dev/null
    if [[ $device_sudoloop != 1 || $platform != "linux" ]]; then
        chmod +x $dir/*
    fi

    # common
    if [[ $platform != "macos" ]]; then
        bspatch="$dir/bspatch"
        futurerestore+="$dir/futurerestore"
        ideviceenterrecovery="$dir/ideviceenterrecovery"
        ideviceinfo="$dir/ideviceinfo"
        iproxy="$dir/iproxy"
        irecovery+="$dir/irecovery"
        sha1sum="$(which sha1sum)"
        sha256sum="$(which sha256sum)"
    fi
    if [[ $platform != "linux" ]]; then
        jq="$dir/jq"
        zenity="$dir/zenity"
    fi
    gaster+="$dir/gaster"
    idevicerestore+="$dir/idevicerestore"
    idevicererestore+="$dir/idevicererestore"
    ipwnder+="$dir/ipwnder"
    irecovery2+="$dir/irecovery2"
    scp="scp -F ../resources/ssh_config"
    ssh="ssh -F ../resources/ssh_config"
}

install_depends() {
    log "Installing dependencies..."
    rm "../resources/firstrun" 2>/dev/null

    if [[ $platform == "linux" ]]; then
        print "* iOS-OTA-Downgrader will be installing dependencies from your distribution's package manager"
        print "* Enter your user password when prompted"
        pause
    elif [[ $platform == "windows" ]]; then
        print "* iOS-OTA-Downgrader will be installing dependencies from MSYS2"
        print "* You may have to run the script more than once. If the prompt exits on its own, just run restore.cmd again"
        pause
    fi

    if [[ $distro == "arch" ]]; then
        sudo pacman -Sy --noconfirm --needed base-devel curl jq libimobiledevice openssh python udev unzip usbmuxd usbutils vim zenity zip

    elif [[ $distro == "debian" ]]; then
        if [[ -n $ubuntu_ver ]]; then
            sudo add-apt-repository -y universe
        fi
        sudo apt update
        sudo apt install -y curl jq libimobiledevice6 libirecovery-common libssl3 openssh-client python3 unzip usbmuxd usbutils xxd zenity zip
        sudo systemctl enable --now udev systemd-udevd usbmuxd 2>/dev/null

    elif [[ $distro == "fedora" ]]; then
        sudo dnf install -y ca-certificates jq libimobiledevice openssl python3 systemd udev usbmuxd vim-common zenity zip
        sudo ln -sf /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-certificates.crt

    elif [[ $distro == "opensuse" ]]; then
        sudo zypper -n in curl jq libimobiledevice-1_0-6 openssl-3 python3 usbmuxd unzip vim zenity zip

    elif [[ $platform == "macos" ]]; then
        xcode-select --install

    elif [[ $platform == "windows" ]]; then
        popd
        rm -rf "$(dirname "$0")/tmp"
        pacman -Syu --noconfirm --needed ca-certificates curl libcurl libopenssl openssh openssl unzip zip
        mkdir "$(dirname "$0")/tmp"
        pushd "$(dirname "$0")/tmp"
    fi

    uname > "../resources/firstrun"
    if [[ $platform == "linux" ]]; then
        # from linux_fix script by Cryptiiiic
        sudo systemctl enable --now systemd-udevd usbmuxd 2>/dev/null
        echo "QUNUSU9OPT0iYWRkIiwgU1VCU1lTVEVNPT0idXNiIiwgQVRUUntpZFZlbmRvcn09PSIwNWFjIiwgQVRUUntpZFByb2R1Y3R9PT0iMTIyWzI3XXwxMjhbMC0zXSIsIE9XTkVSPSJyb290IiwgR1JPVVA9InVzYm11eGQiLCBNT0RFPSIwNjYwIiwgVEFHKz0idWFjY2VzcyIKCkFDVElPTj09ImFkZCIsIFNVQlNZU1RFTT09InVzYiIsIEFUVFJ7aWRWZW5kb3J9PT0iMDVhYyIsIEFUVFJ7aWRQcm9kdWN0fT09IjEzMzgiLCBPV05FUj0icm9vdCIsIEdST1VQPSJ1c2JtdXhkIiwgTU9ERT0iMDY2MCIsIFRBRys9InVhY2Nlc3MiCgoK" | base64 -d | sudo tee /etc/udev/rules.d/39-libirecovery.rules >/dev/null 2>/dev/null
        sudo chown root:root /etc/udev/rules.d/39-libirecovery.rules
        sudo chmod 0644 /etc/udev/rules.d/39-libirecovery.rules
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        echo "$distro" > "../resources/firstrun"
    fi

    log "Install script done! Please run the script again to proceed"
    log "If your iOS device is plugged in, unplug and replug your device"
    exit
}

version_check() {
    local version_current
    local version_latest

    pushd .. >/dev/null

    if [[ -d .git ]]; then
        if [[ $platform == "macos" ]]; then
            version_current="$(date -r $(git log -1 --format="%at") +%Y-%m-%d)-$(git rev-parse HEAD | cut -c -7)"
        else
            version_current="$(date -d @$(git log -1 --format="%at") --rfc-3339=date)-$(git rev-parse HEAD | cut -c -7)"
        fi
    elif [[ -e ./resources/git_hash ]]; then
        version_current="$(cat ./resources/git_hash)"
    else
        log ".git directory and git_hash file not found, cannot determine version."
        if [[ $no_version_check != 1 ]]; then
            error "Your copy of iOS-OTA-Downgrader is downloaded incorrectly. Do not use the \"Code\" button in GitHub." \
            "* Please download iOS-OTA-Downgrader using git clone or from GitHub releases: https://github.com/LukeZGD/iOS-OTA-Downgrader/releases"
        fi
    fi

    if [[ -n $version_current ]]; then
        print "* Version: $version_current"
    fi

    if [[ $no_version_check == 1 ]]; then
        warn "No version check flag detected, update check will be disabled and no support may be provided."
    else
        log "Checking for updates..."
        version_latest=$(curl https://api.github.com/repos/LukeZGD/iOS-OTA-Downgrader/releases/latest 2>/dev/null | grep "latest/iOS-OTA-Downgrader_complete" | cut -c 131- | cut -c -18)
        if [[ -z $version_latest ]]; then
            warn "Failed to check for updates. GitHub may be down or blocked by your network."
        elif [[ $version_latest != "$version_current" ]]; then
            if (( $(echo $version_current | cut -c -10 | sed -e 's/-//g') >= $(echo $version_latest | cut -c -10 | sed -e 's/-//g') )); then
                warn "Current version is newer/different than remote ($version_latest)"
            elif [[ $(echo $version_current | cut -c 12-) != $(echo $version_latest | cut -c 12-) ]]; then
                print "* A newer version of iOS-OTA-Downgrader is available."
                print "* Current version: $version_current"
                print "* Latest version:  $version_latest"
                print "* Please download/pull the latest version before proceeding."
                exit
            fi
        fi
    fi

    popd >/dev/null
}

device_get_info() {
    : '
    usage: device_get_info (no arguments)
    sets the variables: device_mode, device_type, device_ecid, device_vers, device_udid, device_model, device_fw_dir,
    device_use_vers, device_use_build, device_use_bb, device_use_bb_sha1, device_latest_vers, device_latest_build,
    device_latest_bb, device_latest_bb_sha1, device_proc
    '

    log "Getting device info..."
    if  [[ $device_argmode == "none" ]]; then
        log "No device mode is enabled."
        device_mode="none"
        device_vers="Unknown"
    fi

    $ideviceinfo -s >/dev/null
    if [[ $? == 0 ]]; then
        device_mode="Normal"
    fi

    if [[ -z $device_mode ]]; then
        device_mode="$($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-)"
    fi

    if [[ -z $device_mode ]]; then
        local error_msg=$'* Make sure to also trust this computer by selecting "Trust" at the pop-up.'
        [[ $platform != "linux" ]] && error_msg+=$'\n* Double-check if the device is being detected by iTunes/Finder.'
        [[ $platform == "macos" ]] && error_msg+=$'\n* Make sure to have libimobiledevice and libirecovery installed from Homebrew/MacPorts before retrying.'
        if [[ $platform == "linux" ]]; then
            error_msg+=$'\n* Try running the script again and enable sudoloop mode.'
            touch ../resources/sudoloop
        fi
        error_msg+=$'\n* For more details, read the "Troubleshooting" wiki page in GitHub.\n* Troubleshooting link: https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting'
        error "No device found! Please connect the iOS device to proceed." "$error_msg"
    fi

    case $device_mode in
        "DFU" | "Recovery" )
            local ProdCut=7 # cut 7 for ipod/ipad
            device_type=$($irecovery -qv 2>&1 | grep "Connected to iP" | cut -c 14-)
            if [[ $(echo "$device_type" | cut -c 3) == 'h' ]]; then
                ProdCut=9 # cut 9 for iphone
            fi
            device_type=$(echo "$device_type" | cut -c -$ProdCut)
            device_ecid=$((16#$($irecovery -q | grep "ECID" | cut -c 9-))) # converts hex ecid to dec
            device_vers=$(echo "/exit" | $irecovery -s | grep "iBoot-")
            [[ -z $device_vers ]] && device_vers="Unknown"
            ;;

        "Normal" )
            device_type=$($ideviceinfo -s -k ProductType)
            [[ -z $device_type ]] && device_type=$($ideviceinfo -k ProductType)
            device_ecid=$($ideviceinfo -s -k UniqueChipID)
            device_vers=$($ideviceinfo -s -k ProductVersion)
            device_udid=$($ideviceinfo -s -k UniqueDeviceID)
            ;;
    esac

    # enable manual entry
    if [[ -n $device_argmode ]]; then
        log "Manual device entry is enabled."
        device_type=
        device_ecid=
    fi

    if [[ -z $device_type ]]; then
        read -p "$(input 'Enter device type (eg. iPad2,1): ')" device_type
    fi
    if [[ -z $device_ecid ]]; then
        read -p "$(input 'Enter device ECID (must be decimal): ')" device_ecid
    fi

    device_fw_dir="../resources/firmware/$device_type"
    device_model="$(cat $device_fw_dir/hwmodel)"
    if [[ -z $device_model ]]; then
        print "* Device: $device_type in $device_mode mode"
        print "* iOS Version: $device_vers"
        print "* ECID: $device_ecid"
        echo
        error "Device model not found. Device type ($device_type) is possibly invalid or not supported."
    fi

    device_use_bb=0
    device_latest_bb=0
    # set device_proc (what processor the device has)
    case $device_type in
        iPhone3,[123] )
            device_proc=4 # A4
            ;;

        iPad2,[1234567] | iPad3,[123] | iPhone4,1 | iPod5,1 )
            device_proc=5 # A5
            ;;

        iPad3,[456] | iPhone5,[1234] )
            device_proc=6 # A6
            ;;

        iPad4,[123456789] | iPhone6,[12] )
            device_proc=7 # A7
            ;;

        iPhone7,[12] | iPod7,1 )
            device_proc=8 # A8
            ;;
    esac
    # set device_use_vers, device_use_build (where to get the baseband and manifest from for ota/other)
    # for a7/a8 other restores 11.3+, device_latest_vers and device_latest_build are used
    case $device_type in
        iPhone3,[123] )
            device_use_vers="7.1.2"
            device_use_build="11D257"
            ;;

        iPad2,[1245] | iPad3,1 | iPod5,1 )
            device_use_vers="9.3.5"
            device_use_build="13G36"
            ;;

        iPad2,[367] | iPad3,[23] | iPhone4,1 )
            device_use_vers="9.3.6"
            device_use_build="13G37"
            ;;

        iPad3,[56] | iPhone5,[12] )
            device_use_vers="10.3.4"
            device_use_build="14G61"
            ;;

        iPad3,4 | iPad4,[12345] | iPhone5,[34] | iPhone6,[12] )
            device_use_vers="10.3.3"
            device_use_build="14G60"
            ;;&

        iPad4,[123456789] | iPhone6,[12] | iPhone7,[12] | iPod7,1 )
            device_latest_vers="12.5.7"
            device_latest_build="16H81"
            ;;
    esac
    # set device_use_bb, device_use_bb_sha1 (what baseband to use for ota/other)
    # for a7/a8 other restores 11.3+, device_latest_bb and device_latest_bb_sha1 are used
    case $device_type in
        iPhone3,[12] ) # XMM6180 7.1.2
            device_use_bb="ICE3_04.12.09_BOOT_02.13.Release.bbfw"
            device_use_bb_sha1="007365a5655ac2f9fbd1e5b6dba8f4be0513e364"
            ;;

        iPad2,2 ) # XMM6180 9.3.5
            device_use_bb="ICE3_04.12.09_BOOT_02.13.Release.bbfw"
            device_use_bb_sha1="e6f54acc5d5652d39a0ef9af5589681df39e0aca"
            ;;

        iPhone3,3 ) # MDM6600 7.1.2
            device_use_bb="Phoenix-3.0.04.Release.bbfw"
            device_use_bb_sha1="a507ee2fe061dfbf8bee7e512df52ade8777e113"
            ;;

        iPad2,3 ) # MDM6600 9.3.6
            device_use_bb="Phoenix-3.6.03.Release.bbfw"
            device_use_bb_sha1="8d4efb2214344ea8e7c9305392068ab0a7168ba4"
            ;;

        iPad2,[67] ) # MDM9615 9.3.6
            device_use_bb="Mav5-11.80.00.Release.bbfw"
            device_use_bb_sha1="aa52cf75b82fc686f94772e216008345b6a2a750"
            ;;

        iPad3,[23] ) # MDM9600
            device_use_bb="Mav4-6.7.00.Release.bbfw"
            device_use_bb_sha1="a5d6978ecead8d9c056250ad4622db4d6c71d15e"
            ;;

        iPhone4,1 ) # MDM6610
            device_use_bb="Trek-6.7.00.Release.bbfw"
            device_use_bb_sha1="22a35425a3cdf8fa1458b5116cfb199448eecf49"
            ;;

        iPad3,[56] | iPhone5,[12] ) # MDM9615 10.3.4 (32bit)
            device_use_bb="Mav5-11.80.00.Release.bbfw"
            device_use_bb_sha1="8951cf09f16029c5c0533e951eb4c06609d0ba7f"
            ;;

        iPad4,[235] | iPhone5,[34] | iPhone6,[12] ) # MDM9615 10.3.3 (5C, 5S, air, mini2)
            device_use_bb="Mav7Mav8-7.60.00.Release.bbfw"
            device_use_bb_sha1="f397724367f6bed459cf8f3d523553c13e8ae12c"
            ;;&

        iPad4,[235689] | iPhone6,[12] ) # MDM9615 12.5.7
            device_latest_bb="Mav7Mav8-10.80.02.Release.bbfw"
            device_latest_bb_sha1="f5db17f72a78d807a791138cd5ca87d2f5e859f0"
            ;;

        iPhone7,[12] ) # MDM9625
            device_latest_bb="Mav10-7.80.04.Release.bbfw"
            device_latest_bb_sha1="7ec8d734da78ca2bb1ba202afdbb6fe3fd093cb0"
            ;;
    esac
    # disable baseband update for these devices ipad 2 cellular
    case $device_type in
        iPad2,[23] ) device_disable_bbupdate=$device_type
    esac
    # if latest vers is not set, copy use vers to latest
    if [[ -z $device_latest_vers || -z $device_latest_build ]]; then
        device_latest_vers=$device_use_vers
        device_latest_build=$device_use_build
        device_latest_bb=$device_use_bb
        device_latest_bb_sha1=$device_use_bb_sha1
    fi

    print "* Device: $device_type (${device_model}ap) in $device_mode mode"
    print "* iOS Version: $device_vers"
    print "* ECID: $device_ecid"
    echo
}

device_find_mode() {
    # usage: device_find_mode {DFU,Recovery,Restore} {Timeout (default: 24 for linux, 4 for other)}
    # finds device in given mode, and sets the device_mode variable
    local usb
    local timeout=4
    local i=0
    local device_in

    case $1 in
        "DFU" ) usb=1227;;
        "Recovery" ) usb=1281;;
        "Restore" ) usb=1297;;
    esac

    if [[ -n $2 ]]; then
        timeout=$2
    elif [[ $platform == "linux" ]]; then
        timeout=24
    fi

    log "Finding device in $1 mode..."
    while (( i < timeout )); do
        if [[ $platform == "linux" ]]; then
            device_in=$(lsusb | grep -c "05ac:$usb")
        elif [[ $1 == "Restore" && $($ideviceinfo -s) ]]; then
            device_in=1
        elif [[ $($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-) == "$1" ]]; then
            device_in=1
        fi

        if [[ $device_in == 1 ]]; then
            log "Found device in $1 mode."
            device_mode="$1"
            break
        fi
        sleep 1
        ((i++))
    done

    if [[ $device_in != 1 ]]; then
        if [[ $timeout != 1 ]]; then
            touch ../resources/sudoloop
            error "Failed to find device in $1 mode (Timed out). Please run the script again."
        fi
        return 1
    fi
}

device_sshpass() {
    # ask for device password and use sshpass for scp and ssh
    local pass=$1
    if [[ -z $pass ]]; then
        read -s -p "$(input 'Enter the root password of your iOS device: ')" pass
        echo
    fi
    if [[ -z $pass ]]; then
        pass="alpine"
    fi
    scp="$dir/sshpass -p $pass $scp"
    ssh="$dir/sshpass -p $pass $ssh"
}

device_enter_mode() {
    # usage: device_enter_mode {Recovery, DFU, kDFU, pwnDFU}
    # attempt to enter given mode, and device_find_mode function will then set device_mode variable
    local opt
    case $1 in
        "Recovery" )
            if [[ $device_mode == "Normal" ]]; then
                print "* The device needs to be in recovery/DFU mode before proceeding."
                read -p "$(input 'Send device to recovery mode? (Y/n):')" opt
                if [[ $opt == 'n' || $opt == 'N' ]]; then
                    exit
                fi
                log "Entering recovery mode..."
                $ideviceenterrecovery "$device_udid" >/dev/null
                device_find_mode Recovery
            elif [[ $device_mode == "DFU" ]]; then
                log "Device is in DFU mode, cannot enter recovery mode"
                return
            fi
            ;;

        "DFU" )
            if [[ $device_mode == "Normal" ]]; then
                device_enter_mode Recovery
            elif [[ $device_mode == "DFU" ]]; then
                return
            fi
            # DFU Helper for recovery mode
            print "* Get ready to enter DFU mode."
            read -p "$(input 'Select Y to continue, N to exit recovery mode (Y/n) ')" opt
            if [[ $opt == 'N' || $opt == 'n' ]]; then
                log "Exiting recovery mode."
                $irecovery -n
                exit
            fi
            print "* Hold TOP and HOME buttons for 10 seconds."
            for i in {10..01}; do
                echo -n "$i "
                sleep 1
            done
            echo -e "\n$(print '* Release TOP button and hold HOME button for 8 seconds.')"
            for i in {08..01}; do
                echo -n "$i "
                sleep 1
            done
            echo
            device_find_mode DFU
            ;;

        "kDFU" )
            local sendfiles=()
            local device_det=$(echo "$device_vers" | cut -c 1)

            if [[ $device_mode != "Normal" ]]; then
                # cannot enter kdfu if not in normal mode, attempt pwndfu instead
                device_enter_mode pwnDFU
                return
            fi

            patch_ibss
            log "Running iproxy for SSH..."
            $iproxy 2222 22 >/dev/null &
            iproxy_pid=$!
            sleep 2

            log "Please read the message below:"
            print "1. Make sure to have installed the requirements from Cydia."
            print "  - Only proceed if you have followed the steps in the GitHub wiki."
            print "  - You will be prompted to enter the root password of your iOS device."
            print "  - The default root password is \"alpine\""
            print "  - Do not worry that your input is not visible, it is still being entered."
            print "2. Afterwards, the device will disconnect and its screen will stay black."
            print "  - Proceed to either press the TOP/HOME button, or unplug and replug the device."
            pause

            echo "chmod +x /tmp/kloader*" > kloaders
            if [[ $device_det == 1 ]]; then
                echo '[[ $(uname -a | grep -c "MarijuanARM") == 1 ]] && /tmp/kloader_hgsp /tmp/pwnediBSS || \
                /tmp/kloader /tmp/pwnediBSS' >> kloaders
                sendfiles+=("../resources/kloader_hgsp")
                sendfiles+=("../resources/kloader")
            elif [[ $device_det == 5 ]]; then
                echo "/tmp/kloader5 /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader5")
            else
                echo "/tmp/kloader /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader")
            fi
            sendfiles+=("kloaders" "pwnediBSS")

            device_sshpass
            log "Entering kDFU mode..."
            print "* This may take a while, but should not take longer than a minute."
            if [[ $device_det == 1 ]]; then
                print "* If the script seems to be stuck here, try to start over from step 1 the GitHub wiki."
            fi
            $scp -P 2222 ${sendfiles[@]} root@127.0.0.1:/tmp
            if [[ $? == 0 ]]; then
                $ssh -p 2222 root@127.0.0.1 "bash /tmp/kloaders" &
            else
                warn "Failed to connect to device via USB SSH."
                if [[ $platform == "linux" ]]; then
                    print "* Try running \"sudo systemctl restart usbmuxd\" before retrying USB SSH."
                fi
                if [[ $device_det == 1 ]]; then
                    print "* Try to re-install both OpenSSH and Dropbear, reboot, re-jailbreak, and try again."
                    print "* Alternatively, place your device in DFU mode (see \"Troubleshooting\" wiki page for details)"
                    print "* Troubleshooting link: https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting#dfu-advanced-menu-for-32-bit-devices"
                elif [[ $device_det == 5 ]]; then
                    print "* Try to re-install OpenSSH, reboot, and try again."
                else
                    print "* Try to re-install OpenSSH, reboot, re-jailbreak, and try again."
                    print "* Alternatively, you may use kDFUApp from my Cydia repo (see \"Troubleshooting\" wiki page for details)"
                    print "* Troubleshooting link: https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting#dfu-advanced-menu-kdfu-mode"
                fi
                input "Press Enter/Return to try again with Wi-Fi SSH (or press Ctrl+C to cancel and try again)"
                read -s
                log "Will try again with Wi-Fi SSH..."
                print "* Make sure that your iOS device and PC/Mac are on the same network."
                print "* To get your device's IP Address, go to: Settings -> Wi-Fi/WLAN -> tap the 'i' next to your network name"
                local IPAddress
                read -p "$(input 'Enter the IP Address of your device:') " IPAddress
                $scp ${sendfiles[@]} root@$IPAddress:/tmp
                if [[ $? != 0 ]]; then
                    error "Failed to connect to device via SSH, cannot continue."
                fi
                $ssh root@$IPAddress "bash /tmp/kloaders" &
            fi

            local attempt=1
            local device_in
            while (( attempt < 6 )); do
                log "Finding device in kDFU mode... (Attempt $attempt)"
                if [[ $($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-) == "DFU" ]]; then
                    device_in=1
                fi
                if [[ $device_in == 1 ]]; then
                    log "Found device in kDFU mode."
                    device_mode="DFU"
                    break
                fi
                print "* You may also try to unplug and replug your device"
                ((attempt++))
            done
            if (( attempt >= 6 )); then
                error "Failed to find device in kDFU mode. Please run the script again"
            fi
            kill $iproxy_pid
            ;;

        "pwnDFU" )
            local irec_pwned
            local tool_pwned

            if [[ $device_type == "iPhone3,1" && $device_target_vers != "7.1.2" && $mode == "downgrade" ]]; then
                print "* Note that kDFU mode will NOT work for iPhone4Down downgrades!"
            fi

            if [[ $platform == "windows" ]]; then
                print "* Make sure that your device is in PWNED DFU or kDFU mode."
                print "* For 32-bit devices, pwned iBSS/kDFU must be already booted."
                print "* For A7 devices, signature checks must be already disabled."
                if [[ $device_mode == "DFU" ]]; then
                    pause
                    return
                elif [[ $device_mode == "Recovery" ]]; then
                    print "* If you do not know what you are doing, exit now and restart your device in normal mode."
                    read -p "$(input 'Select Y to exit recovery mode (Y/n) ')" opt
                    if [[ $opt != 'N' && $opt != 'n' ]]; then
                        log "Exiting recovery mode."
                        $irecovery -n
                    fi
                fi
                exit
            fi

            irec_pwned=$($irecovery -q | grep -c "PWND")
            if [[ $device_mode == "DFU" && $mode != "pwned-ibss" && $device_proc != 4 ]] && (( device_proc < 7 )); then
                print "* Select Y if your device is in pwned iBSS/kDFU mode."
                print "* Select N to place device to pwned DFU mode using ipwndfu/ipwnder."
                read -p "$(input 'Is your device already in pwned iBSS/kDFU mode? (y/N): ')" opt
                if [[ $opt == "Y" || $opt == "y" ]]; then
                    log "Pwned iBSS/kDFU mode specified by user."
                    return
                fi
            elif [[ $irec_pwned == 1 ]] && (( device_proc >= 7 )); then
                return
            fi

            if [[ $device_proc == 5 ]]; then
                print "* DFU mode for A5 device - Make sure that your device is in PWNED DFU mode."
                print "* You need to have an Arduino and USB Host Shield to proceed for PWNED DFU mode."
                print "* If you do not know what you are doing, select N and restart your device in normal mode."
                read -p "$(input 'Is your device in PWNED DFU mode using synackuk checkm8-a5? (y/N): ')" opt
                if [[ $opt != "Y" && $opt != "y" ]]; then
                    local error_msg=$'\n* Please put the device in normal mode and jailbroken before proceeding.'
                    error_msg+=$'\n* Exit DFU mode by holding the TOP and HOME buttons for 15 seconds.'
                    error_msg+=$'\n* For usage of kDFU/pwnDFU, read the "Troubleshooting" wiki page in GitHub'
                    error "32-bit A5 device is not in PWNED DFU mode." "$error_msg"
                fi
                device_ipwndfu send_ibss
                return
            fi

            device_enter_mode DFU

            if [[ $device_proc == 6 && $platform != "macos" ]]; then
                # A6 linux uses ipwndfu
                device_ipwndfu pwn
            elif [[ $device_proc == 7 ]]; then
                # A7 uses gaster or ipwnder
                opt="$ipwnder"
                if [[ $platform != "macos" ]]; then
                    opt+=" -p"
                fi
                if [[ $platform != "macos" ]] || [[ $platform == "macos" && $(uname -m) == "x86_64" ]]; then
                    input "PwnDFU Tool Option"
                    print "* Select tool to be used for entering pwned DFU mode."
                    print "* This option is set to ipwnder by default (1)."
                    input "Select your option:"
                    select opt2 in "ipwnder" "gaster"; do
                        case $opt2 in
                            "gaster" ) opt="$gaster pwn"; break;;
                            * ) break;;
                        esac
                    done
                fi
                log "Placing device to pwnDFU mode using: $opt"
                $opt
                tool_pwned=$?
            else
                # A4/A6 uses ipwnder
                opt="-p"
                if [[ $platform == "macos" ]]; then
                    opt=
                fi
                log "Placing device to pwnDFU mode using ipwnder"
                $ipwnder $opt
                tool_pwned=$?
            fi
            irec_pwned=$($irecovery -q | grep -c "PWND")
            # irec_pwned is instances of "PWND" in serial, must be 1
            # tool_pwned is error code of pwn tool, must be 0
            if [[ $irec_pwned != 1 && $tool_pwned != 0 ]]; then
                error "Failed to enter pwnDFU mode. Please run the script again." \
                "* Exit DFU mode first by holding the TOP and HOME buttons for about 15 seconds."
            fi

            if [[ $platform == "macos" && $opt != "$gaster pwn" ]]; then
                return
            fi

            if [[ $device_proc == 7 ]]; then
                device_ipwndfu rmsigchks
            elif [[ $device_proc != 4 ]]; then
                device_ipwndfu send_ibss
            fi
            ;;
    esac
}

device_ipwndfu() {
    local tool_pwned=0
    local mac_ver=0
    local python2=$(which python2 2>/dev/null)

    if [[ $1 == "send_ibss" ]]; then
        patch_ibss
        cp pwnediBSS ../resources/ipwndfu/
    fi

    if [[ $platform == "macos" ]]; then
        mac_ver=$(echo "$platform_ver" | cut -c -2)
    fi
    if [[ $platform == "macos" ]] && (( mac_ver < 12 )); then
        python2=/usr/bin/python
    elif [[ -e $HOME/.pyenv/versions/2.7.18/bin/python2 ]]; then
        log "python2 from pyenv detected"
        python2=
        if [[ $device_sudoloop == 1 ]]; then
            python2="sudo "
        fi
        python2+="$HOME/.pyenv/versions/2.7.18/bin/python2"
    elif [[ -z $python2 ]]; then
        error "Python 2 is not installed, cannot continue. Make sure to have python2 installed to use ipwndfu." \
        "* You may install python2 from pyenv: pyenv install 2.7.18"
    fi

    device_enter_mode DFU
    if [[ ! -d ../resources/ipwndfu ]]; then
        download_file https://github.com/LukeZGD/ipwndfu/archive/6e67c9e28a5f7f63f179dea670f7f858712350a0.zip ipwndfu.zip 61333249eb58faebbb380c4709384034ce0e019a
        unzip -q ipwndfu.zip -d ../resources
        mv ../resources/ipwndfu*/ ../resources/ipwndfu/
    fi

    pushd ../resources/ipwndfu/
    case $1 in
        "send_ibss" )
            log "Sending iBSS..."
            $python2 ipwndfu -l pwnediBSS
            tool_pwned=$?
            rm pwnediBSS
            if [[ $tool_pwned != 0 ]]; then
                error "Failed to send iBSS. Your device has likely failed to enter PWNED DFU mode." \
                "* Please exit DFU and (re-)enter PWNED DFU mode before retrying."
            fi
            ;;

        "pwn" )
            log "Placing device to pwnDFU Mode using ipwndfu"
            $python2 ipwndfu -p
            tool_pwned=$?
            if [[ $tool_pwned != 0 ]]; then
                error "Failed to enter pwnDFU mode. Please run the script again." \
                "* Exit DFU mode first by holding the TOP and HOME buttons for about 15 seconds."
            fi
            ;;

        "rmsigchks" )
            log "Running rmsigchks..."
            $python2 rmsigchks.py
            ;;
    esac
    popd
}

main_menu() {
    # provides a menu to set the variable mode {downgrade, restore-latest, save-ota-blobs, custom-ipsw, kdfu, remove4, ramdisk4}
    local menu_items=()
    local tmp_items=()
    if [[ $device_mode != "none" ]]; then
        tmp_items+=("Downgrade Device")
        # Restore to latest on Linux/Windows only
        if [[ $platform != "macos" ]]; then
            tmp_items+=("Restore to Latest iOS")
        fi
        # kDFU/pwned iBSS for 32-bit only
        if (( device_proc < 7 )); then
            if [[ $device_mode == "Normal" ]]; then
                tmp_items+=("Put Device in kDFU Mode")
            else
                tmp_items+=("Send Pwned iBSS")
            fi
            tmp_items+=("Save Onboard Blobs")
        fi
        # Options for iPhone 4 GSM only
        if [[ $device_type == "iPhone3,1" ]]; then
            tmp_items+=("Disable/Enable Exploit" "SSH Ramdisk")
        fi
    fi
    # Save OTA blobs for A5, A6, A7 only
    if [[ $device_proc != 4 && $device_proc != 8 ]]; then
        tmp_items+=("Save OTA Blobs")
    fi
    # Save Cydia blobs for 32-bit only
    if (( device_proc < 7 )); then
        tmp_items+=("Save Cydia Blobs")
    fi
    if [[ $device_proc != 8 ]]; then
        tmp_items+=("Create Custom IPSW")
    fi
    menu_items+=("${tmp_items[@]}")
    menu_items+=("(Re-)Install Dependencies" "(Any other key to exit)")

    print "*** Main Menu ***"
    input "Select an option:"
    select opt in "${menu_items[@]}"; do
        case $opt in
            "Downgrade Device" ) mode="downgrade"; break;;
            "Save OTA Blobs" ) mode="save-ota-blobs"; break;;
            "Create Custom IPSW" ) mode="custom-ipsw"; break;;
            "Put Device in kDFU Mode" ) mode="kdfu"; break;;
            "Disable/Enable Exploit" ) mode="remove4"; break;;
            "Restore to Latest iOS" ) mode="restore-latest"; break;;
            "SSH Ramdisk" ) mode="ramdisk4"; break;;
            "Send Pwned iBSS" ) mode="pwned-ibss"; break;;
            "Save Onboard Blobs" ) mode="save-onboard-blobs"; break;;
            "Save Cydia Blobs" ) mode="save-cydia-blobs"; break;;
            "(Re-)Install Dependencies" ) install_depends;;
            * ) break;;
        esac
    done
}

device_target_menu() {
    # provides menu to set variables device_target_vers, device_target_build, device_target_other
    local menu_items=()

    case $device_type in
        iPad4,[12345] | iPhone6,[12] )
            menu_items+=("10.3.3")
            ;;

        iPhone3,[123] )
            if [[ $mode == "custom-ipsw" ]]; then
                menu_items+=("7.1.2")
            fi
            ;;&

        iPad2,[1234567] | iPad3,[123456] | iPhone4,1 | iPhone5,[12] | iPod5,1 )
            menu_items+=("8.4.1")
            ;;&

        iPad2,[123] | iPhone4,1 | iPhone3,1 )
            menu_items+=("6.1.3")
            ;;&

        iPhone3,1 )
            menu_items+=("5.1.1 (9B208)" "5.1.1 (9B206)" "4.3.5" "More versions")
            ;;
    esac
    menu_items+=("Other (use SHSH blobs)" "(Any other key to exit)")

    if [[ -z $device_target_vers ]]; then
        echo
        input "Select iOS version:"
        select opt in "${menu_items[@]}"; do
            device_target_vers="$opt"
            break
        done
    fi

    if [[ $device_target_vers == "More versions" ]]; then
        menu_items=("6.1.2" "6.1" "6.0.1" "6.0" "5.1" "5.0.1" "5.0" "4.3.3" "4.3")
        select opt in "${menu_items[@]}"; do
            device_target_vers="$opt"
            break
        done
    fi

    case $device_target_vers in
        "10.3.3" ) device_target_build="14G60";;
        "8.4.1" ) device_target_build="12H321";;
        "7.1.2" ) device_target_build="11D257";;
        "6.1.3" ) device_target_build="10B329";;
        "6.1.2" ) device_target_build="10B146";;
        "6.1" ) device_target_build="10B144";;
        "6.0.1" ) device_target_build="10A523";;
        "6.0" ) device_target_build="10A403";;
        "5.1.1 (9B208)" ) device_target_build="9B208";;
        "5.1.1 (9B206)" ) device_target_build="9B206";;
        "5.1" ) device_target_build="9B176";;
        "5.0.1" ) device_target_build="9A405";;
        "5.0" ) device_target_build="9A334";;
        "4.3.5" ) device_target_build="8L1";;
        "4.3.3" ) device_target_build="8J2";;
        "4.3" ) device_target_build="8F190";;
        "Other (use SHSH blobs)" ) device_target_other=1;;
        * ) log "No valid version selected."; exit;;
    esac

    if [[ $device_target_build == "9B20"* ]]; then
        device_target_vers="5.1.1"
    fi
}

download_file() {
    # usage: download_file {link} {target location} {sha1}
    local filename="$(basename $2)"
    log "Downloading $filename..."
    curl -L $1 -o $2
    local sha1=$($sha1sum $2 | awk '{print $1}')
    if [[ $sha1 != "$3" ]]; then
        error "Verifying $filename failed. The downloaded file may be corrupted or incomplete. Please run the script again" \
        "* SHA1sum mismatch. Expected $3, got $sha1"
    fi
}

device_fw_key_check() {
    # check and download keys for device_target_build, then set the variable device_fw_key
    local keys_path="$device_fw_dir/$device_target_build"
    log "Checking firmware keys in $keys_path"
    if [[ -e "$keys_path/index.html" ]]; then
        if [[ $(cat "$keys_path/index.html" | grep -c "$device_target_build") != 1 ]]; then
            log "Existing firmware keys are not valid. Deleting"
            rm "$keys_path/index.html"
        fi
    fi

    if [[ ! -e "$keys_path/index.html" ]]; then
        log "Getting firmware keys for $device_type-$device_target_build"
        mkdir -p "$keys_path" 2>/dev/null
        curl -L https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/raw/master/$device_type/$device_target_build/index.html -o index.html
        if [[ $(cat index.html | grep -c "$device_target_build") != 1 ]]; then
            curl -L https://api.m1sta.xyz/wikiproxy/$device_type/$device_target_build -o index.html
            if [[ $(cat index.html | grep -c "$device_target_build") != 1 ]]; then
                error "Failed to download firmware keys."
            fi
        fi
        mv index.html "$keys_path/"
    fi
    device_fw_key="$(cat $keys_path/index.html)"
}

download_comp() {
    # usage: download_comp [build_id] [comp]
    local build_id="$1"
    local comp="$2"
    download_targetfile="$comp.$device_model"
    if [[ $build_id != "12"* ]]; then
        download_targetfile+="ap"
    fi
    download_targetfile+=".RELEASE"

    if [[ -e "../saved/$device_type/${comp}_$build_id.dfu" ]]; then
        cp "../saved/$device_type/${comp}_$build_id.dfu" ${comp}
    else
        log "Downloading ${comp}..."
        "$dir/partialzip" $(cat "$device_fw_dir/$build_id/url") "Firmware/dfu/$download_targetfile.dfu" ${comp}
        cp ${comp} "../saved/$device_type/${comp}_$build_id.dfu"
    fi
}

patch_ibss() {
    # creates file pwnediBSS to be sent to device
    local build_id
    case $device_type in
        iPad3,1 | iPhone3,[123] )
            build_id="11D257"
            ;;

        iPod5,1 )
            build_id="10B329"
            ;;

        * )
            build_id="12H321"
            ;;
    esac
    download_comp $build_id iBSS
    log "Patching iBSS..."
    $bspatch iBSS pwnediBSS "../resources/patch/$download_targetfile.patch"
    cp pwnediBSS ../saved/$device_type/
    log "Pwned iBSS saved at: saved/$device_type/pwnediBSS"
}

patch_ibec() {
    # creates file pwnediBEC to be sent to device for blob dumping
    local build_id
    case $device_type in
        iPad2,[145] | iPad3,[346] | iPhone4,1 | iPhone5,[12] | iPod5,1 )
            build_id="10B329"
            ;;

        iPad2,2 | iPhone3,[123] )
            build_id="11D257"
            ;;

        iPad2,[367] | iPad3,[25] )
            build_id="12H321"
            ;;

        iPad3,1 )
            build_id="10B146"
            ;;

        iPhone5,3 )
            build_id="11B511"
            ;;

        iPhone5,4 )
            build_id="11B651"
            ;;
    esac
    download_comp $build_id iBEC
    device_target_build=$build_id
    device_fw_key_check
    local name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .filename')
    local iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .iv')
    local key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .key')
    log "Decrypting iBEC"
    mv iBEC $name.orig
    "$dir/xpwntool" $name.orig $name.dec -iv $iv -k $key -decrypt
    "$dir/xpwntool" $name.dec $name.raw
    log "Patching iBEC"
    $bspatch $name.raw $name.patched "../resources/patch/$download_targetfile.patch"
    "$dir/xpwntool" $name.patched pwnediBEC -t $name.dec
    rm $name.dec $name.orig $name.raw $name.patched
    cp pwnediBEC ../saved/$device_type/
    log "Pwned iBEC saved at: saved/$device_type/pwnediBEC"
}

ipsw_path_set() {
    : '
    set variable ipsw_path, ipsw_custom, also ipsw_path_712 for iphone 4
    also set shsh_path, device_target_vers, device_target_build for "Other" downgrades
    '

    if [[ $device_target_vers == "$device_latest_vers" ]]; then
        case $device_type in
            iPad3,[456] )
                ipsw_path="../iPad_32bit"
                ;;

            iPad4,[123456] )
                ipsw_path="../iPad_64bit"
                ;;

            iPad4,[789] )
                ipsw_path="../iPad_64bit_TouchID"
                ;;

            iPhone5,[1234] )
                ipsw_path="../iPhone_4.0_32bit"
                ;;

            iPhone6,[12] )
                ipsw_path="../iPhone_4.0_64bit"
                ;;

            iPhone7,1 )
                ipsw_path="../iPhone_5.5"
                ;;

            iPhone7,2 )
                ipsw_path="../iPhone_4.7"
                ;;

            iPod7,1 )
                ipsw_path="../iPodtouch"
                ;;

            * )
                ipsw_path="../${device_type}"
                ;;
        esac
        ipsw_path+="_${device_target_vers}_${device_target_build}_Restore"
        if [[ $device_target_vers != "7.1.2" ]]; then
            return
        fi
    fi

    case $device_type in
        iPad4,[12345] )
            ipsw_path="../iPad_64bit"
            ;;

        iPhone6,[12] )
            ipsw_path="../iPhone_4.0_64bit"
            ;;

        * )
            ipsw_path="../${device_type}"
            ;;
    esac
    ipsw_path+="_${device_target_vers}_${device_target_build}"
    ipsw_custom="${ipsw_path}_Custom"
    ipsw_path+="_Restore"
    ipsw_path_712="../${device_type}_7.1.2_11D257_Restore"
    if [[ $ipsw_jailbreak == 1 ]]; then
        ipsw_custom+="JB"
    fi
    if [[ $device_type == "$device_disable_bbupdate" ]]; then
        device_use_bb=0
        ipsw_custom+="B"
    fi
    if [[ $ipsw_jailbreak_tool == "daibutsu" ]]; then
        ipsw_custom+="D"
    elif [[ $ipsw_jailbreak_tool == "etasonjb" ]]; then
        ipsw_custom+="E"
    fi
    if [[ $ipsw_verbose == 1 ]]; then
        ipsw_custom+="V"
    fi

    if [[ $device_target_other != 1 ]]; then
        return
    fi
    if [[ $mode == "downgrade" ]]; then
        print "* Make sure to download and select the IPSW and SHSH of your target iOS version."
        print "* Blobs are device specific: You NEED to have SHSH BLOBS for YOUR device!"
        pause
    fi
    input "Select your IPSW file in the file selection window."
    ipsw_path="$($zenity --file-selection --file-filter='IPSW | *.ipsw' --title="Select IPSW file")"
    [[ ! -s "$ipsw_path" ]] && read -p "$(input 'Enter path to IPSW file (or press Ctrl+C to cancel): ')" ipsw_path
    [[ ! -s "$ipsw_path" ]] && error "No IPSW selected, or IPSW file not found."
    ipsw_path="${ipsw_path%?????}"
    log "Selected IPSW file: $ipsw_path.ipsw"

    log "Getting version from IPSW"
    unzip -o -j "$ipsw_path.ipsw" Restore.plist -d .
    if [[ $platform == "macos" ]]; then
        plutil -extract 'ProductVersion' xml1 Restore.plist -o device_target_vers
        device_target_vers=$(cat device_target_vers | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
        plutil -extract 'ProductBuildVersion' xml1 Restore.plist -o BuildVer
        device_target_build=$(cat BuildVer | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
    else
        device_target_vers=$(cat Restore.plist | grep -i ProductVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
        device_target_build=$(cat Restore.plist | grep -i ProductBuildVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
    fi
    ipsw_custom="../${device_type}_${device_target_vers}_${device_target_build}_Custom"
    if [[ $device_type == "$device_disable_bbupdate" ]]; then
        ipsw_custom+="B"
    fi

    if [[ $mode != "downgrade" ]]; then
        return
    fi
    input "Select your SHSH file in the file selection window."
    shsh_path="$($zenity --file-selection --file-filter='SHSH | *.shsh *.shsh2' --title="Select SHSH file")"
    [[ ! -s "$shsh_path" ]] && read -p "$(input 'Enter path to SHSH file: ')" shsh_path
    [[ ! -s "$shsh_path" ]] && error "No SHSH selected, or SHSH file not found."
    log "Selected SHSH file: $shsh_path"
}

ipsw_preference_set() {
    # sets ipsw variables: ipsw_jailbreak, ipsw_jailbreak_tool, ipsw_memory, ipsw_verbose
    if [[ $device_target_vers == "$device_latest_vers" && $device_proc != 4 ]]; then
        return
    fi

    if (( device_proc < 7 )) && [[ $device_target_other != 1 && -z $ipsw_jailbreak ]]; then
        input "Jailbreak Option"
        print "* When this option is enabled, your device will be jailbroken on restore."
        if [[ $device_target_vers == "6.1.3" ]]; then
            print "* I recommend to enable this for iOS 6.1.3, since it is hard to get p0sixspwn to work."
        elif [[ $device_target_vers == "8.4.1" ]]; then
            print "* Based on some reported issues, Jailbreak Option might not work properly for iOS 8.4.1."
            print "* I recommend to disable the option for these devices and sideload EtasonJB, HomeDepot, or daibutsu manually."
        elif [[ $device_target_vers == "5.1" ]]; then
            print "* Based on some reported issues, Jailbreak Option might not work properly for iOS 5.1."
            print "* I recommend to use other versions instead, such as 5.1.1."
        fi
        print "* This option is enabled by default (Y)."
        read -p "$(input 'Enable this option? (Y/n): ')" ipsw_jailbreak
        if [[ $ipsw_jailbreak == 'N' || $ipsw_jailbreak == 'n' ]]; then
            ipsw_jailbreak=
            log "Jailbreak option disabled by user."
        else
            ipsw_jailbreak=1
            log "Jailbreak option enabled."
        fi
        echo
    fi

    if [[ $ipsw_jailbreak == 1 && $device_target_vers == "8.4.1" && -z $ipsw_jailbreak_tool ]]; then
        case $device_type in
            iPhone4,1 | iPhone5,2 )
                input "Jailbreak Tool Option"
                print "* This option is set to daibutsu by default (1)."
                Selection=("daibutsu" "EtasonJB")
                input "Select your option:"
                select opt in "${Selection[@]}"; do
                    case $opt in
                        "EtasonJB" ) ipsw_jailbreak_tool="etasonjb"; break;;
                        * ) ipsw_jailbreak_tool="daibutsu"; break;;
                    esac
                done
                log "Jailbreak tool option set to: $ipsw_jailbreak_tool"
                echo
                ;;

            iPad2,[4567] | iPad3,[123] | iPod5,1 )
                ipsw_jailbreak_tool="daibutsu"
                ;;

            * )
                ipsw_jailbreak_tool="etasonjb"
                ;;
        esac
    fi

    if [[ $platform == "windows" ]]; then
        ipsw_memory=
    elif [[ -n $ipsw_memory ]]; then
        :
    elif [[ $ipsw_jailbreak == 1 || $device_type == "$device_disable_bbupdate" ]] ||
         [[ $device_type == "iPhone3,1" && $device_target_vers != "7.1.2" ]] ||
         [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* ]]; then
        input "Memory Option for creating custom IPSW"
        print "* This option makes creating the custom IPSW faster, but it requires at least 8GB of RAM."
        print "* If you do not have enough RAM, disable this option and make sure that you have enough storage space."
        print "* This option is enabled by default (Y)."
        read -p "$(input 'Enable this option? (Y/n): ')" ipsw_memory
        if [[ $ipsw_memory == 'N' || $ipsw_memory == 'n' ]]; then
            log "Memory option disabled by user."
            ipsw_memory=
        else
            log "Memory option enabled."
            ipsw_memory=1
        fi
        echo
    fi

    if [[ $device_type == "iPhone3,1" && $device_target_vers != "7.1.2" &&
          $device_target_other != 1 && -z $ipsw_verbose ]]; then
        input "Verbose Boot Option"
        print "* When enabled, the device will have verbose boot on restore."
        print "* This option is enabled by default (Y)."
        read -p "$(input 'Enable this option? (Y/n): ')" ipsw_verbose
        if [[ $ipsw_verbose == 'N' || $ipsw_verbose == 'n' ]]; then
            ipsw_verbose=
            log "Verbose boot option disabled by user."
        else
            ipsw_verbose=1
            log "Verbose boot option enabled."
        fi
        echo
    fi
}

shsh_save() {
    # usage: shsh_save {apnonce (optional)}
    # sets variable shsh_path
    local version=$device_target_vers
    local build_id=$device_target_build
    local apnonce
    local shsh_check
    local buildmanifest="../resources/manifest/BuildManifest_${device_type}_${version}.plist"
    local ExtraArgs=

    if [[ $1 == "apnonce" ]]; then
        apnonce=$2
    elif [[ $1 == "version" ]]; then
        version=$2
    fi

    if [[ $version == "$device_latest_vers" ]]; then
        build_id="$device_latest_build"
        buildmanifest="../saved/$device_type/$build_id.plist"
        if [[ ! -e $buildmanifest ]]; then
            if [[ $version == "7.1.2" && -e "$ipsw_path_712.ipsw" ]]; then
                log "Extracting BuildManifest from $version IPSW..."
                unzip -o -j "$ipsw_path_712.ipsw" BuildManifest.plist -d .
            else
                log "Downloading BuildManifest for $version..."
                "$dir/partialzip" "$(cat "$device_fw_dir/$build_id/url")" BuildManifest.plist BuildManifest.plist
            fi
            mv BuildManifest.plist $buildmanifest
        fi
    fi
    shsh_check=${device_ecid}_${device_type}_${device_model}ap_${version}-${build_id}_${apnonce}*.shsh*

    if [[ $(ls ../saved/shsh/$shsh_check 2>/dev/null) && -z $apnonce ]]; then
        shsh_path="$(ls ../saved/shsh/$shsh_check)"
        log "Found existing saved $version blobs: $shsh_path"
        return
    fi
    rm *.shsh* 2>/dev/null

    ExtraArgs="-d $device_type -i $version -e $device_ecid -m $buildmanifest -o -s -B ${device_model}ap -b "
    if [[ -n $apnonce ]]; then
        ExtraArgs+="--apnonce $apnonce"
    else
        ExtraArgs+="-g 0x1111111111111111"
    fi
    log "Running tsschecker with command: $dir/tsschecker $ExtraArgs"
    "$dir/tsschecker" $ExtraArgs
    shsh_path="$(ls $shsh_check)"
    if [[ -z "$shsh_path" ]]; then
        error "Saving $version blobs failed. Please run the script again" \
        "* It is also possible that $version for $device_type is no longer signed"
    fi
    if [[ -z $apnonce ]]; then
        cp "$shsh_path" ../saved/shsh/
    fi
    log "Successfully saved $version blobs: $shsh_path"
}

ipsw_download() {
    if [[ $device_target_vers == "4.3"* && $device_type == "iPhone3,1" ]]; then
        ipsw_custom+="_$device_ecid"
    fi
    if [[ $device_target_other == 1 ]]; then
        return
    elif [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping $device_target_vers IPSW verification."
        return
    fi

    local version="$device_target_vers"
    local build_id="$device_target_build"
    local ipsw_dl="$ipsw_path"
    if [[ $1 == "7.1.2" ]]; then
        version="7.1.2"
        build_id="11D257"
        ipsw_dl="$ipsw_path_712"
    elif [[ $device_type == "iPhone3,1" && ! -e "$ipsw_path_712.ipsw" ]]; then
        ipsw_download 7.1.2
    fi

    if [[ ! -e "$ipsw_dl.ipsw" ]]; then
        log "iOS $version IPSW for $device_type cannot be found."
        print "* If you already downloaded the IPSW, move/copy it to the directory where the script is located."
        print "* Do NOT rename the IPSW as the script will fail to detect it."
        print "* The script will now proceed to download it for you. If you want to download it yourself, here is the link: $(cat $device_fw_dir/$build_id/url)"
        log "Downloading IPSW... (Press Ctrl+C to cancel)"
        curl -L "$(cat $device_fw_dir/$build_id/url)" -o temp.ipsw
        mv temp.ipsw "$ipsw_dl.ipsw"
    fi

    log "Verifying $ipsw_dl.ipsw..."
    local IPSWSHA1=$(cat "$device_fw_dir/$build_id/sha1sum")
    local IPSWSHA1L=$($sha1sum "$ipsw_dl.ipsw" | awk '{print $1}')
    if [[ $IPSWSHA1L != "$IPSWSHA1" ]]; then
        error "Verifying IPSW failed. Your IPSW may be corrupted or incomplete. Delete/replace the IPSW and run the script again" \
        "* SHA1sum mismatch. Expected $IPSWSHA1, got $IPSWSHA1L"
    fi
    log "IPSW SHA1sum matches"
}

ipsw_prepare_1033() {
    # patch iBSS, iBEC, iBSSb, iBECb and set variables
    iBSS="ipad4"
    if [[ $device_type == "iPhone6"* ]]; then
        iBSS="iphone6"
    fi
    iBEC="iBEC.${iBSS}.RELEASE"
    iBSSb="iBSS.${iBSS}b.RELEASE"
    iBECb="iBEC.${iBSS}b.RELEASE"
    iBSS="iBSS.$iBSS.RELEASE"

    log "Patching iBSS and iBEC..."
    unzip -o -j "$ipsw_path.ipsw" Firmware/dfu/$iBSS.im4p
    unzip -o -j "$ipsw_path.ipsw" Firmware/dfu/$iBEC.im4p
    mv $iBSS.im4p $iBSS.orig
    mv $iBEC.im4p $iBEC.orig
    $bspatch $iBSS.orig $iBSS.im4p ../resources/patch/$iBSS.patch
    $bspatch $iBEC.orig $iBEC.im4p ../resources/patch/$iBEC.patch
    if [[ $device_type == "iPad4"* ]]; then
        unzip -o -j "$ipsw_path.ipsw" Firmware/dfu/$iBSSb.im4p
        unzip -o -j "$ipsw_path.ipsw" Firmware/dfu/$iBECb.im4p
        mv $iBSSb.im4p $iBSSb.orig
        mv $iBECb.im4p $iBECb.orig
        $bspatch $iBSSb.orig $iBSSb.im4p ../resources/patch/$iBSSb.patch
        $bspatch $iBECb.orig $iBECb.im4p ../resources/patch/$iBECb.patch
    fi
    if [[ $device_type == "iPad4,4" || $device_type == "iPad4,5" ]]; then
        cp $iBSSb.im4p $iBECb.im4p ../saved/$device_type
    else
        cp $iBSS.im4p $iBEC.im4p ../saved/$device_type
    fi
    log "Pwned iBSS and iBEC saved at: saved/$device_type"

    # this will not be needed if i get to compile futurerestore on mac
    if [[ $platform == "macos" && ! -e "$ipsw_custom.ipsw" ]]; then
        log "Preparing custom IPSW..."
        mkdir -p Firmware/dfu
        cp "$ipsw_path.ipsw" temp.ipsw
        zip -d temp.ipsw Firmware/dfu/$iBEC.im4p
        cp $iBEC.im4p Firmware/dfu
        zip -r0 temp.ipsw Firmware/dfu/$iBEC.im4p
        if [[ $device_type == "iPad4"* ]]; then
            zip -d temp.ipsw Firmware/dfu/$iBECb.im4p
            cp $iBECb.im4p Firmware/dfu
            zip -r0 temp.ipsw Firmware/dfu/$iBECb.im4p
        fi
        mv temp.ipsw "$ipsw_custom.ipsw"
    fi
}

ipsw_prepare_jailbreak() {
    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi
    local ExtraArgs=
    local ipsw="$dir/ipsw"
    local JBFiles=()
    local JBFiles2=()
    local JBSHA1

    if [[ $ipsw_jailbreak_tool == "daibutsu" ]]; then
        if [[ $platform == "windows" ]]; then
            ipsw+="2"
        fi
        echo '#!/bin/bash' > reboot.sh
        echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" >> reboot.sh
        echo "nvram -d boot-partition; nvram -d boot-ramdisk" >> reboot.sh
        echo "/usr/bin/haxx_overwrite -$device_model" >> reboot.sh
        if [[ $ipsw_openssh == 1 ]]; then
            JBFiles=("../resources/jailbreak/sshdeb.tar")
        fi
        JBFiles2=("bin.tar" "untether.tar" "Cydia8.tar")
        JBSHA1="6459dbcbfe871056e6244d23b33c9b99aaeca970"
        if [[ ! -e ../resources/jailbreak/${JBFiles2[2]} ]]; then
            download_file https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/${JBFiles2[2]} ${JBFiles2[2]} $JBSHA1
            cp ${JBFiles2[2]} ../resources/jailbreak/${JBFiles2[2]}
        fi
        for i in {0..2}; do
            cp ../resources/jailbreak/${JBFiles2[$i]} .
        done
        cp -R ../resources/firmware/JailbreakBundles FirmwareBundles
        ExtraArgs+="-daibutsu" # use daibutsuCFW

    elif [[ $ipsw_jailbreak == 1 ]]; then
        if [[ $device_target_vers == "8.4.1" ]]; then
            JBFiles+=("fstab8.tar" "etasonJB-untether.tar" "Cydia8.tar")
            JBSHA1="6459dbcbfe871056e6244d23b33c9b99aaeca970"
        elif [[ $device_target_vers == "7.1.2" ]]; then
            JBFiles+=("fstab7.tar" "panguaxe.tar" "Cydia7.tar")
            JBSHA1="bba5022d6749097f47da48b7bdeaa3dc67cbf2c4"
        elif [[ $device_target_vers == "6.1.3" ]]; then
            JBFiles+=("fstab_rw.tar" "p0sixspwn.tar" "Cydia6.tar")
            JBSHA1="1d5a351016d2546aa9558bc86ce39186054dc281"
        fi
        if [[ ! -e ../resources/jailbreak/${JBFiles[2]} ]]; then
            download_file https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/${JBFiles[2]} ${JBFiles[2]} $JBSHA1
            cp ${JBFiles[2]} ../resources/jailbreak/${JBFiles[2]}
        fi
        for i in {0..2}; do
            JBFiles[i]=../resources/jailbreak/${JBFiles[$i]}
        done
        if [[ $ipsw_openssh == 1 && $device_target_vers == "6.1.3" ]]; then
            JBFiles+=("../resources/jailbreak/sshdeb.tar")
        fi
        cp -R ../resources/firmware/FirmwareBundles .
        ExtraArgs+="-S 50" # system partition add
    else
        cp -R ../resources/firmware/FirmwareBundles .
    fi

    if [[ $device_type != "$device_disable_bbupdate" && $device_proc != 4 ]]; then
        ExtraArgs+=" -bbupdate"
    fi
    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    log "Preparing custom IPSW: $ipsw $ipsw_path.ipsw temp.ipsw $ExtraArgs ${JBFiles[*]}"
    "$ipsw" "$ipsw_path.ipsw" temp.ipsw $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_32bit_keys() {
    local comp="$1"
    local getcomp="$1"
    case $comp in
        "RestoreLogo" ) getcomp="AppleLogo";;
        "RestoreKernelCache" ) getcomp="Kernelcache";;
        "RestoreDeviceTree" ) getcomp="DeviceTree";;
    esac
    local name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
    local iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
    local key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')

    case $comp in
        "iBSS" | "iBEC" )
            echo -e "<key>$comp</key><dict><key>File</key><string>Firmware/dfu/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>Patch</key><true/>" >> $NewPlist
            ;;

        "RestoreRamdisk" )
            echo -e "<key>Restore Ramdisk</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
            ;;

        "RestoreDeviceTree" | "RestoreLogo" )
            echo -e "<key>$comp</key><dict><key>File</key><string>Firmware/all_flash/all_flash.${device_model}ap.production/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string>" >> $NewPlist
            ;;

        "RestoreKernelCache" )
            echo -e "<key>$comp</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string><key>Patch</key><false/>" >> $NewPlist
            ;;
    esac
    echo -e "<key>Decrypt</key><true/></dict>" >> $NewPlist
}

ipsw_prepare_32bit() {
    if [[ $device_target_vers == "4"* ]]; then
        if [[ $device_type == "iPad2"* ]]; then
            ipsw_prepare_jailbreak
            return
        else
            error "Restoring with iOS 4 blobs is not supported on $device_type. Use iFaith/PwnageTool/sn0wbreeze instead."
        fi
    fi
    device_fw_key_check
    if [[ $platform != "windows" && $device_type != "$device_disable_bbupdate" ]]; then
        log "No need to create custom IPSW for non-jailbroken restores on $platform"
        return
    elif [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    local xmlstarlet="$dir/xmlstarlet"
    if [[ ! -e $xmlstarlet ]]; then
        xmlstarlet="$(which xmlstarlet)"
        if [[ -z $xmlstarlet ]]; then
            error "xmlstarlet is not installed. Install xmlstarlet to continue creating custom IPSW"
        fi
    fi

    local ExtraArgs
    log "Generating firmware bundle..."
    local IPSWSHA256=$($sha256sum "${ipsw_path//\\//}.ipsw" | awk '{print $1}')
    log "IPSWSHA256: $IPSWSHA256"
    local FirmwareBundle=FirmwareBundles/${device_type}_${device_target_vers}_${device_target_build}.bundle
    local NewPlist=$FirmwareBundle/Info.plist
    mkdir -p $FirmwareBundle
    cp ../resources/firmware/powdersn0wBundles/config2.plist FirmwareBundles/config.plist
    unzip -o -j "$ipsw_path.ipsw" Firmware/all_flash/all_flash.${device_model}ap.production/manifest
    mv manifest $FirmwareBundle/

    local RamdiskName=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .filename')
    local RamdiskIV=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .iv')
    local RamdiskKey=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .key')
    unzip -o -j "$ipsw_path.ipsw" $RamdiskName
    "$dir/xpwntool" $RamdiskName Ramdisk.raw -iv $RamdiskIV -k $RamdiskKey
    "$dir/hfsplus" Ramdisk.raw extract usr/local/share/restore/options.$device_model.plist
    local RootSize=$($xmlstarlet sel -t -m "plist/dict/key[.='SystemPartitionSize']" -v "following-sibling::integer[1]" options.$device_model.plist)
    echo -e $'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>' > $NewPlist
    echo -e "<key>Filename</key><string>$ipsw_path.ipsw</string>" >> $NewPlist
    echo -e "<key>RootFilesystem</key><string>$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("RootFS")) | .filename')</string>" >> $NewPlist
    echo -e "<key>RootFilesystemKey</key><string>$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("RootFS")) | .key')'</string>" >> $NewPlist
    echo -e "<key>RootFilesystemSize</key><integer>$RootSize</integer>" >> $NewPlist
    echo -e "<key>RamdiskOptionsPath</key><string>/usr/local/share/restore/options.$device_model.plist</string>" >> $NewPlist
    echo -e "<key>SHA256</key><string>$IPSWSHA256</string>" >> $NewPlist
    echo -e "<key>FilesystemPackage</key><dict/><key>RamdiskPackage</key><dict/><key>Firmware</key><dict>" >> $NewPlist
    ipsw_prepare_32bit_keys iBSS
    ipsw_prepare_32bit_keys iBEC
    ipsw_prepare_32bit_keys RestoreRamdisk
    ipsw_prepare_32bit_keys RestoreDeviceTree
    ipsw_prepare_32bit_keys RestoreLogo
    ipsw_prepare_32bit_keys RestoreKernelCache
    echo -e "</dict></dict></plist>" >> $NewPlist
    cat $NewPlist

    if [[ $device_type != "$device_disable_bbupdate" && $device_proc != 4 ]]; then
        ExtraArgs+=" -bbupdate"
    fi
    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw $ExtraArgs"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw $ExtraArgs

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_powder() {
    local config="config"
    local ExtraArgs
    local ExtraArgs2="--logo4 "
    local IV
    local JBFiles=()
    local JBSHA1
    local Key

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $ipsw_jailbreak == 1 ]]; then
        if [[ $device_target_vers == "6"* ]]; then
            # use powdersn0w jailbreak for ios 6
            JBFiles=("Cydia6.tar")
            JBSHA1="1d5a351016d2546aa9558bc86ce39186054dc281"
        else
            # use unthredeh4il for ios 4/5
            JBFiles=("Cydia5.tar" "unthredeh4il.tar" "fstab_rw.tar")
            JBSHA1="f5b5565640f7e31289919c303efe44741e28543a"
        fi
        if [[ ! -e ../resources/jailbreak/${JBFiles[0]} ]]; then
            download_file https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/${JBFiles[0]} ${JBFiles[0]} $JBSHA1
            cp ${JBFiles[0]} ../resources/jailbreak/${JBFiles[0]}
        fi
        for i in {0..2}; do
            JBFiles[i]=../resources/jailbreak/${JBFiles[$i]}
        done
    fi

    cp -R ../resources/firmware/powdersn0wBundles ./FirmwareBundles
    if [[ $device_target_vers == "4.3"* ]]; then
        ExtraArgs+="-apticket $shsh_path"
    fi
    if [[ $ipsw_verbose == 1 ]]; then
        config+="v"
    fi
    cp -R ../resources/firmware/src .
    if [[ $ipsw_jailbreak == 1 && $device_target_vers == "6"* ]]; then
        JBFiles=()
        rm FirmwareBundles/${config}.plist
        mv FirmwareBundles/${config}JB.plist FirmwareBundles/${config}.plist
        cp ../resources/jailbreak/Cydia6.tar src/cydia6.tar
    fi
    mv FirmwareBundles/${config}.plist FirmwareBundles/config.plist
    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw -base $ipsw_path_712.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw -base "$ipsw_path_712.ipsw" $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    if [[ $device_target_vers == "4.3"* ]]; then
        device_fw_key_check
        log "Applying iOS 4 patches"
        log "Patch iBoot"
        IV=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("iBoot")) | .iv')
        Key=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("iBoot")) | .key')
        if [[ $device_target_vers != "4.3.5" ]]; then
            ExtraArgs2+="--433 "
        fi
        if [[ $ipsw_verbose == 1 ]]; then
            ExtraArgs2+="-b -v"
        fi
        unzip -o -j "$ipsw_path.ipsw" Firmware/all_flash/all_flash.n90ap.production/iBoot*
        mv iBoot.n90ap.RELEASE.img3 tmp
        "$dir/xpwntool" tmp ibot.dec -iv $IV -k $Key
        "$dir/iBoot32Patcher" ibot.dec ibot.pwned --rsa --boot-partition --boot-ramdisk $ExtraArgs2
        "$dir/xpwntool" ibot.pwned iBoot -t tmp
        rm tmp
        echo "0000010: 6365" | xxd -r - iBoot
        echo "0000020: 6365" | xxd -r - iBoot
        mkdir -p Firmware/all_flash/all_flash.n90ap.production Firmware/dfu
        cp iBoot Firmware/all_flash/all_flash.n90ap.production/iBoot4.n90ap.RELEASE.img3
        log "Patch iBSS"
        unzip -o -j "$ipsw_path.ipsw" Firmware/dfu/iBSS.n90ap.RELEASE.dfu
        $bspatch iBSS.n90ap.RELEASE.dfu Firmware/dfu/iBSS.n90ap.RELEASE.dfu FirmwareBundles/${device_type}_${device_target_vers}_${device_target_build}.bundle/iBSS.n90ap.RELEASE.patch
        log "Patch Ramdisk"
        local RamdiskName=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .filename')
        unzip -o -j "$ipsw_path.ipsw" $RamdiskName
        if [[ $device_target_vers == "4.3" ]]; then
            "$dir/xpwntool" $RamdiskName ramdisk.orig -iv d11772b6a3bdd4f0b4cd8795b9f10ad9 -k 9873392c91743857cf5b35c9017c6683d5659c9358f35c742be27bfb03dee77c -decrypt
        else
            mv $RamdiskName ramdisk.orig
        fi
        $bspatch ramdisk.orig ramdisk.patched FirmwareBundles/${device_type}_${device_target_vers}_${device_target_build}.bundle/${RamdiskName%????}.patch
        "$dir/xpwntool" ramdisk.patched ramdisk.raw
        "$dir/hfsplus" ramdisk.raw rm iBoot
        "$dir/hfsplus" ramdisk.raw add iBoot iBoot
        "$dir/xpwntool" ramdisk.raw $RamdiskName -t ramdisk.patched
        log "Patch AppleLogo"
        unzip -o -j temp.ipsw Firmware/all_flash/all_flash.n90ap.production/applelogo-640x960.s5l8930x.img3
        echo "0000010: 3467" | xxd -r - applelogo-640x960.s5l8930x.img3
        echo "0000020: 3467" | xxd -r - applelogo-640x960.s5l8930x.img3
        mv applelogo-640x960.s5l8930x.img3 Firmware/all_flash/all_flash.n90ap.production/applelogo-640x960.s5l8930x.img3
        log "Add all to custom IPSW"
        zip -r0 temp.ipsw Firmware/all_flash/all_flash.n90ap.production/* Firmware/dfu/iBSS.n90ap.RELEASE.dfu $RamdiskName
    fi

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_extract() {
    local ExtraArgs
    local ipsw="$ipsw_path"
    if [[ $1 == "custom" ]]; then
        ipsw="$ipsw_custom"
    elif [[ $1 == "no_rootfs" ]]; then
        ExtraArgs="-x $2"
    fi
    if [[ ! -d "$ipsw" ]]; then
        mkdir "$ipsw"
        log "Extracting IPSW: $ipsw.ipsw"
        unzip -o "$ipsw.ipsw" -d "$ipsw/" $ExtraArgs
    fi
}

restore_download_bbsep() {
    # download and check manifest, baseband, and sep to be used for restoring
    # sets variables: restore_manifest, restore_baseband, restore_sep
    local build_id
    local baseband_sha1
    if [[ $device_latest_vers == "$device_use_vers" || $device_target_vers == "10"* ]]; then
        build_id="$device_use_build"
        restore_baseband="$device_use_bb"
        baseband_sha1="$device_use_bb_sha1"
    else
        build_id="$device_latest_build"
        restore_baseband="$device_latest_bb"
        baseband_sha1="$device_latest_bb_sha1"
    fi

    mkdir tmp
    # BuildManifest
    if [[ ! -e ../saved/$device_type/$build_id.plist ]]; then
        if [[ $device_proc == 7 && $device_target_vers == "10"* ]]; then
            cp ../resources/manifest/BuildManifest_${device_type}_10.3.3.plist $build_id.plist
        else
            log "Downloading $build_id BuildManifest"
            "$dir/partialzip" "$(cat $device_fw_dir/$build_id/url)" BuildManifest.plist $build_id.plist
        fi
        mv $build_id.plist ../saved/$device_type
    fi
    cp ../saved/$device_type/$build_id.plist tmp/BuildManifest.plist
    if [[ $? != 0 ]]; then
        rm ../saved/$device_type/$build_id.plist
        error "An error occurred copying manifest. Please run the script again"
    fi
    log "Manifest: ../saved/$device_type/$build_id.plist"
    restore_manifest="tmp/BuildManifest.plist"

    # Baseband
    if [[ $restore_baseband != 0 ]]; then
        if [[ -e ../saved/baseband/$restore_baseband ]]; then
            if [[ $baseband_sha1 != "$($sha1sum ../saved/baseband/$restore_baseband | awk '{print $1}')" ]]; then
                rm ../saved/baseband/$restore_baseband
            fi
        fi
        if [[ ! -e ../saved/baseband/$restore_baseband ]]; then
            log "Downloading $build_id Baseband"
            "$dir/partialzip" "$(cat $device_fw_dir/$build_id/url)" Firmware/$restore_baseband $restore_baseband
            if [[ $baseband_sha1 != "$($sha1sum $restore_baseband | awk '{print $1}')" ]]; then
                error "Downloading/verifying baseband failed. Please run the script again"
            fi
            mv $restore_baseband ../saved/baseband/
        fi
        cp ../saved/baseband/$restore_baseband tmp/bbfw.tmp
        if [[ $? != 0 ]]; then
            rm ../saved/baseband/$restore_baseband
            error "An error occurred copying baseband. Please run the script again"
        fi
        log "Baseband: ../saved/baseband/$restore_baseband"
        restore_baseband="tmp/bbfw.tmp"
    fi

    # SEP
    if (( device_proc >= 7 )); then
        restore_sep="sep-firmware.$device_model.RELEASE"
        if [[ ! -e ../saved/$device_type/$restore_sep-$build_id.im4p ]]; then
            log "Downloading $build_id SEP"
            "$dir/partialzip" "$(cat $device_fw_dir/$build_id/url)" Firmware/all_flash/$restore_sep.im4p $restore_sep.im4p
            mv $restore_sep.im4p ../saved/$device_type/$restore_sep-$build_id.im4p
        fi
        restore_sep="$restore_sep-$build_id.im4p"
        cp ../saved/$device_type/$restore_sep .
        if [[ $? != 0 ]]; then
            rm ../saved/$device_type/$restore_sep
            error "An error occurred copying SEP. Please run the script again"
        fi
        log "SEP: ../saved/$device_type/$restore_sep"
    fi
}

restore_idevicerestore() {
    local ExtraArgs="-e -w"
    local re

    mkdir shsh
    cp "$shsh_path" shsh/$device_ecid-$device_type-$device_target_vers.shsh
    restore_download_bbsep
    if [[ $device_use_bb == 0 ]]; then
        log "Device $device_type has no baseband/disabled baseband update"
    elif [[ $device_type != "iPhone3"* ]]; then
        ExtraArgs="-r"
        idevicerestore="$idevicererestore"
        re="re"
        cp shsh/$device_ecid-$device_type-$device_target_vers.shsh shsh/$device_ecid-$device_type-$device_target_vers-$device_target_build.shsh
    fi
    ipsw_extract custom
    if [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* ]]; then
        ExtraArgs="-e"
        log "Sending iBEC..."
        $irecovery -f $ipsw_custom/Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu
        device_find_mode Recovery
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArgs+=" -d"
    fi

    log "Running idevicere${re}store with command: $idevicerestore $ExtraArgs \"$ipsw_custom.ipsw\""
    $idevicerestore $ExtraArgs "$ipsw_custom.ipsw"
    echo
    log "Restoring done! Read the message below if any error has occurred:"
    if [[ $platform == "windows" ]]; then
        print "* Windows users may encounter errors like \"Unable to send APTicket\" or \"Unable to send iBEC\" in the restore process."
        print "* Follow the troubleshoting link for steps to attempt fixing this issue."
        print "* Troubleshooting link: https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting#windows"
    fi
    print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
    print "* Your problem may have already been addressed within the wiki page."
    print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
}

restore_futurerestore() {
    local ExtraArgs=()
    local mac_ver=0
    local port=8888

    if (( device_proc < 7 )); then
        if [[ $platform == "macos" ]]; then
            mac_ver=$(echo "$platform_ver" | cut -c -2)
        fi
        # local server for firmware keys
        pushd ../resources >/dev/null
        if [[ $platform == "macos" ]] && (( mac_ver < 12 )); then
            # python2 SimpleHTTPServer for macos 11 and older
            /usr/bin/python -m SimpleHTTPServer $port &
            httpserver_pid=$!
        else
            # python3 http.server for the rest
            if [[ -z $(which python3) ]]; then
                error "Python 3 is not installed, cannot continue. Make sure to have python3 installed."
            fi
            $(which python3) -m http.server $port &
            httpserver_pid=$!
        fi
        popd >/dev/null
    fi

    restore_download_bbsep
    # baseband args
    if [[ $restore_baseband == 0 ]]; then
        ExtraArgs+=("--no-baseband")
    else
        ExtraArgs+=("-b" "$restore_baseband" "-p" "$restore_manifest")
    fi
    if [[ -n $restore_sep ]]; then
        # sep args for 64bit
        ExtraArgs+=("-s" "$restore_sep" "-m" "$restore_manifest")
    fi
    if [[ -n "$1" ]]; then
        # custom arg, either --use-pwndfu or --skip-blob
        ExtraArgs+=("$1")
        if [[ $platform == "macos" ]] && (( device_proc < 7 )); then
            # no ibss arg for 32bit using newer fr on macos
            ExtraArgs+=("--no-ibss")
        fi
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArgs+=("-d")
    fi
    if [[ $platform != "macos" ]]; then
        if (( device_proc < 7 )); then
            futurerestore+="_old"
        else
            futurerestore+="_new"
        fi
    elif [[ $device_target_other != 1 && $device_target_vers == "10.3.3" && $device_proc == 7 ]]; then
        futurerestore="$dir/futurerestore_194"
        ipsw_path="$ipsw_custom"
    fi
    ExtraArgs+=("-t" "$shsh_path" "$ipsw_path.ipsw")
    ipsw_extract

    log "Running futurerestore with command: $futurerestore ${ExtraArgs[*]}"
    $futurerestore "${ExtraArgs[@]}"
    log "Restoring done! Read the message below if any error has occurred:"
    print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
    print "* Your problem may have already been addressed within the wiki page."
    print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    kill $httpserver_pid
}

restore_latest() {
    ipsw_download
    ipsw_extract
    log "Running idevicerestore with command: $idevicerestore -e \"$ipsw_path.ipsw\""
    $idevicerestore -e "$ipsw_path.ipsw"
    log "Restoring done!"
}

restore_prepare_1033() {
    device_enter_mode pwnDFU
    local attempt=1

    shsh_save
    if [[ $device_type == "iPad4,4" || $device_type == "iPad4,5" ]]; then
        iBSS=$iBSSb
        iBEC=$iBECb
    fi
    $irecovery -f $iBSS.im4p
    sleep 2
    while (( attempt < 5 )); do
        log "Entering pwnREC mode... (Attempt $attempt)"
        log "Sending iBSS..."
        $irecovery -f $iBSS.im4p
        sleep 2
        log "Sending iBEC..."
        $irecovery -f $iBEC.im4p
        sleep 5
        device_find_mode Recovery 1
        if [[ $? == 0 ]]; then
            break
        fi
        print "* You may also try to unplug and replug your device"
        ((attempt++))
    done

    if (( attempt >= 5 )); then
        error "Failed to enter pwnREC mode. You may have to force restart your device and start over entering pwnDFU mode again"
    fi
    shsh_save apnonce $($irecovery -q | grep "NONC" | cut -c 7-)
}

restore_prepare() {
    case $device_proc in
        4 )
            if [[ $device_target_other == 1 ]]; then
                device_enter_mode kDFU
                if [[ -e "$ipsw_custom.ipsw" ]]; then
                    restore_idevicerestore
                else
                    restore_futurerestore --use-pwndfu
                fi
            elif [[ $device_target_vers == "7.1.2" ]]; then
                if [[ $ipsw_jailbreak == 1 ]]; then
                    shsh_save version 7.1.2
                    device_enter_mode kDFU
                    restore_idevicerestore
                else
                    restore_latest
                fi
            else
                # powdersn0w 4.3.x-6.1.3
                shsh_save version 7.1.2
                device_enter_mode pwnDFU
                restore_idevicerestore
            fi
            ;;

        [56] )
            # 32-bit devices A5/A6
            if [[ $device_target_other != 1 ]]; then
                shsh_save
            fi
            if [[ $device_target_vers == "$device_latest_vers" ]]; then
                restore_latest
            elif [[ $ipsw_jailbreak == 1 || -e "$ipsw_custom.ipsw" ]]; then
                device_enter_mode kDFU
                restore_idevicerestore
            else
                device_enter_mode kDFU
                restore_futurerestore --use-pwndfu
            fi
            ;;

        [78] )
            if [[ $device_target_other != 1 && $device_target_vers == "10.3.3" ]]; then
                # A7 devices 10.3.3
                local opt="--skip-blob"
                restore_prepare_1033
                if [[ $platform == "macos" ]]; then
                    opt=
                fi
                restore_futurerestore $opt
            elif [[ $device_target_vers == "$device_latest_vers" ]]; then
                restore_latest
            else
                # 64-bit devices A7/A8
                print "* Make sure to set the nonce generator of your device!"
                print "* For iOS 10 and older: https://github.com/tihmstar/futurerestore#how-to-use"
                print "* For iOS 11 and newer: https://github.com/futurerestore/futurerestore/#method"
                print "* Also check the SEP/BB Compatibility Chart (Legacy iOS 12 sheet): https://docs.google.com/spreadsheets/d/1Mb1UNm6g3yvdQD67M413GYSaJ4uoNhLgpkc7YKi3LBs"
                pause
                restore_futurerestore
            fi
            ;;
    esac
}

ipsw_prepare() {
    ipsw_download

    case $device_proc in
        4 )
            if [[ $device_target_other == 1 ]]; then
                ipsw_prepare_32bit
            elif [[ $device_target_vers == "7.1.2" ]]; then
                if [[ $ipsw_jailbreak == 1 ]]; then
                    # jailbroken 7.1.2
                    ipsw_prepare_jailbreak
                else
                    log "No need to create custom IPSW for non-jailbroken 7.1.2 restores"
                fi
            else
                # powdersn0w 4.3.x-6.1.3
                if [[ $device_target_vers == "4.3"* ]]; then
                    shsh_save version 7.1.2
                fi
                ipsw_prepare_powder
            fi
            ;;

        [56] )
            # 32-bit devices A5/A6
            if [[ $ipsw_jailbreak == 1 ]]; then
                ipsw_prepare_jailbreak
            else
                ipsw_prepare_32bit
            fi
            ;;

        7 )
            if [[ $device_target_other != 1 && $device_target_vers == "10.3.3" ]]; then
                # A7 devices 10.3.3
                ipsw_prepare_1033
            fi
            ;;
    esac
}

device_remove4() {
    local rec
    input "Select option:"
    select opt in "Disable exploit" "Enable exploit" "(Any other key to exit)"; do
    case $opt in
        "Disable exploit" ) rec=0; break;;
        "Enable exploit" ) rec=2; break;;
        * ) exit;;
    esac
    done

    if [[ ! -e ../saved/$device_type/iBSS_8L1.dfu ]]; then
        log "Downloading 8L1 iBSS..."
        "$dir/partialzip" $(cat $device_fw_dir/8L1/url) Firmware/dfu/iBSS.n90ap.RELEASE.dfu iBSS_8L1.dfu
        cp iBSS_8L1.dfu ../saved/$device_type
    else
        cp ../saved/$device_type/iBSS_8L1.dfu .
    fi

    device_enter_mode pwnDFU
    log "Patching iBSS..."
    $bspatch iBSS_8L1.dfu pwnediBSS ../resources/patch/iBSS.n90ap.8L1.patch
    log "Sending iBSS..."
    $irecovery -f pwnediBSS
    sleep 5
    log "Running commands..."
    $irecovery -c "setenv boot-partition $rec"
    $irecovery -c "saveenv"
    $irecovery -c "setenv auto-boot true"
    $irecovery -c "saveenv"
    $irecovery -c "reset"
    log "Done!"
    print "* If disabling the exploit did not work and the device is still in recovery mode screen after restore:"
    print "* You may try another method for clearing NVRAM. See the \"Troubleshooting\" wiki page for more details"
    print "* Troubleshooting link: https://github.com/LukeZGD/iOS-OTA-Downgrader/wiki/Troubleshooting#clearing-nvram"
}

device_ramdisk4() {
    local Ramdisk=(
    058-1056-002.dmg
    DeviceTree.n90ap.img3
    iBEC.n90ap.RELEASE.dfu
    iBSS.n90ap.RELEASE.dfu
    kernelcache.release.n90
    )
    print "* This uses files and script from 4tify by Zurac-Apps"

    if [[ ! $(ls ../resources/ramdisk) ]]; then
        local JailbreakLink=https://github.com/Zurac-Apps/4tify/raw/ad319e2774f54dc3a355812cc287f39f7c38cc66
        mkdir ramdisk
        pushd ramdisk
        log "Downloading ramdisk files from 4tify repo..."
        for file in "${Ramdisk[@]}"; do
            curl -L $JailbreakLink/support_files/7.1.2/Ramdisk/$file -o $file
        done
        popd
        cp -R ramdisk ../resources
    fi

    device_enter_mode pwnDFU
    log "Sending iBSS..."
    $irecovery -f ../resources/ramdisk/iBSS.n90ap.RELEASE.dfu
    sleep 2
    log "Sending iBEC..."
    $irecovery -f ../resources/ramdisk/iBEC.n90ap.RELEASE.dfu
    device_find_mode Recovery

    log "Booting..."
    $irecovery -f ../resources/ramdisk/DeviceTree.n90ap.img3
    $irecovery -c devicetree
    $irecovery -f ../resources/ramdisk/058-1056-002.dmg
    $irecovery -c ramdisk
    $irecovery -f ../resources/ramdisk/kernelcache.release.n90
    $irecovery -c bootx
    device_find_mode Restore 30

    log "Device should now be in SSH ramdisk mode."
    echo
    print "* To access SSH ramdisk, run iproxy first:"
    print "    iproxy 2022 22"
    print "* Then SSH to 127.0.0.1:2022"
    print "    ssh -p 2022 -oHostKeyAlgorithms=+ssh-rsa root@127.0.0.1"
    print "* Enter root password: alpine"
    print "* Mount filesystems with these commands (iOS 5+):"
    print "    mount_hfs /dev/disk0s1s1 /mnt1"
    print "    mount_hfs /dev/disk0s1s2 /mnt1/private/var"
    print "* If your device is on iOS 4, use these commands instead:"
    print "    fsck_hfs /dev/disk0s1"
    print "    mount_hfs /dev/disk0s1 /mnt1"
    print "    mount_hfs /dev/disk0s2s1 /mnt/private/var"
    print "* To reboot, use this command:"
    print "    reboot_bak"
}

shsh_save_onboard() {
    if [[ $platform == "windows" ]]; then
        print "* Saving onboard SHSH is not tested on Windows"
        print "* It is recommended to do this on Linux/macOS instead"
        print "* You may also need iTunes 12.4.3 or older for shshdump to work"
        pause
    fi
    device_target_other=1
    print "* Download and select the IPSW of your current iOS version."
    ipsw_path_set
    device_enter_mode kDFU
    patch_ibec
    log "Sending iBEC..."
    $irecovery -f pwnediBEC
    device_find_mode Recovery
    log "Dumping blobs now"
    if [[ $platform == "windows" ]]; then
        "$dir/shshdump"
    else
        (echo -e "/send ../resources/payload\ngo blobs\n/exit") | $irecovery2 -s
        $irecovery2 -g dump.shsh
        $irecovery -n
    fi
    "$dir/ticket" dump.shsh dump.plist "$ipsw_path.ipsw" -z
    "$dir/validate" dump.plist "$ipsw_path.ipsw" -z
    if [[ $? != 0 ]]; then
        warn "Saved SHSH blobs might be invalid. Did you select the correct IPSW?"
    fi
    if [[ ! -s dump.plist ]]; then
        warn "Saving onboard SHSH blobs failed."
        return
    fi
    mv dump.plist ../saved/shsh/$device_ecid-$device_type-$device_target_vers.shsh
    log "Successfully saved $device_target_vers blobs: saved/shsh/$device_ecid-$device_type-$device_target_vers.shsh"
}

shsh_save_cydia() {
    local json=$(curl "https://firmware-keys.ipsw.me/device/$device_type")
    local len=$(echo "$json" | $jq length)
    local builds=()
    local i=0
    while (( i < len )); do
        builds+=($(echo "$json" | $jq -r ".[$i].buildid"))
        ((i++))
    done
    for build in ${builds[@]}; do
        printf "\n$build "
        "$dir/tsschecker" -d $device_type -e $device_ecid --server-url "http://cydia.saurik.com/TSS/controller?action=2/" -s -g 0x1111111111111111 --buildid $build >/dev/null
        if [[ $(ls *$build* 2>/dev/null) ]]; then
            printf "saved"
            mv $(ls *$build*) ../saved/shsh/$device_ecid-$device_type-$build.shsh
        else
            printf "failed"
        fi
    done
    echo
}

main() {
    clear
    print "******* iOS-OTA-Downgrader *******"
    print " - Downgrader script by LukeZGD - "
    echo

    if [[ $EUID == 0 ]]; then
        error "Running the script as root is not allowed."
    fi

    if [[ ! -d "../resources" ]]; then
        error "The resources folder cannot be found. Replace resources folder and try again." \
        "* If resources folder is present try removing spaces from path/folder name"
    fi

    set_tool_paths

    log "Checking Internet connection..."
    $ping google.com >/dev/null
    if [[ $? != 0 ]]; then
        $ping 208.67.222.222 >/dev/null
        if [[ $? != 0 ]]; then
            error "Please check your Internet connection before proceeding."
        fi
    fi

    version_check

    if [[ ! -e "../resources/firstrun" || -z $jq || -z $zenity ]] ||
       [[ $(cat "../resources/firstrun") != "$(uname)" &&
          $(cat "../resources/firstrun") != "$distro" ]]; then
        install_depends
    fi

    device_get_info
    mkdir -p ../saved/baseband ../saved/$device_type ../saved/shsh

    if [[ -z $mode ]]; then
        main_menu
    fi

    case $mode in
        "downgrade" | "custom-ipsw" )
            device_target_menu
            ipsw_preference_set
            ipsw_path_set
            if [[ $device_target_other == 1 ]]; then
                ipsw_preference_set # intentional repeat
            fi
            ipsw_prepare
            ;;&

        "downgrade" )
            restore_prepare
            ;;

        "custom-ipsw" )
            log "Done creating custom IPSW"
            ;;

        "restore-latest" )
            device_target_vers="$device_latest_vers"
            device_target_build="$device_latest_build"
            ipsw_preference_set
            ipsw_path_set
            ipsw_prepare
            restore_prepare
            ;;

        "save-ota-blobs" )
            device_target_menu
            shsh_save
            ;;

        "kdfu" )
            device_enter_mode kDFU
            ;;

        "remove4" )
            device_remove4
            ;;

        "ramdisk4" )
            device_ramdisk4
            ;;

        "pwned-ibss" )
            device_enter_mode pwnDFU
            ;;

        "save-onboard-blobs" )
            shsh_save_onboard
            ;;

        "save-cydia-blobs" )
            shsh_save_cydia
            ;;

        * )
            log "No valid option selected."
            ;;
    esac
}

for i in "$@"; do
    case $i in
        "--no-color" ) no_color=1;;
        "--no-device" ) device_argmode="none";;
        "--entry-device" ) device_argmode="entry";;
        "--no-version-check" ) no_version_check=1;;
        "--debug" ) set -x; debug_mode=1;;
        "--help" ) display_help; exit;;
        "--ipsw-verbose" ) ipsw_verbose=1;;
        "--jailbreak" ) ipsw_jailbreak=1;;
        "--memory" ) ipsw_memory=1;;
        "--sudoloop" ) device_sudoloop=1;;
    esac
done

trap "clean_and_exit" EXIT
trap "exit 1" INT TERM

clean
mkdir "$(dirname "$0")/tmp"
pushd "$(dirname "$0")/tmp" >/dev/null

if [[ $no_color != 1 ]]; then
    TERM=xterm-256color # fix colors for msys2 terminal
    color_R=$(tput setaf 9)
    color_G=$(tput setaf 10)
    color_B=$(tput setaf 12)
    color_Y=$(tput setaf 11)
    color_N=$(tput sgr0)
fi

main

popd >/dev/null
