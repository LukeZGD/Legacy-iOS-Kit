#!/usr/bin/env bash

ipsw_openssh=1 # OpenSSH will be added to jailbreak/custom IPSW if set to 1.
device_ramdisk_build="" # You can change the version of SSH Ramdisk and Pwned iBSS/iBEC here. (default is 10B329 for most devices)
jelbrek="../resources/jailbreak"

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
    kill $httpserver_pid $iproxy_pid 2>/dev/null
    popd &>/dev/null
    rm -rf "$(dirname "$0")/tmp/"* "$(dirname "$0")/iP"*/ "$(dirname "$0")/tmp/" 2>/dev/null
    if [[ $platform == "macos" ]]; then
        killall -CONT AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater
    fi
}

clean_sudo() {
    clean
    sudo rm -rf /tmp/futurerestore /tmp/*.json "$(dirname "$0")/tmp/"* "$(dirname "$0")/iP"*/ "$(dirname "$0")/tmp/"
    sudo kill $sudoloop_pid
}

clean_usbmuxd() {
    clean_sudo
    sudo systemctl restart usbmuxd
    sudo systemctl restart usbmuxd
}

bash_version=$(/usr/bin/env bash -c 'echo ${BASH_VERSINFO[0]}')
if (( bash_version > 3 )); then
    shopt -s compat32
fi

display_help() {
    echo ' *** Legacy iOS Kit ***
  - Script by LukeZGD -

Usage: ./restore.sh [Options]

List of options:
    --activation-records      Enable dumping/stitching activation records
    --debug                   For script debugging (set -x and debug mode)
    --disable-bbupdate        Disable bbupdate and enable dumping/stitching baseband
    --disable-sudoloop        Disable running tools as root for Linux
    --disable-usbmuxd         Disable running usbmuxd as root for Linux
    --entry-device            Enable manual device and ECID entry
    --help                    Display this help message
    --ipsw-hacktivate         Enable hacktivation for creating IPSW (iPhone 3GS only)
    --no-color                Disable colors for script output
    --no-device               Enable no device mode
    --no-version-check        Disable script version checking

For 32-bit devices compatible with restores/downgrades (see README):
    --ipsw-verbose            Enable verbose boot option (powdersn0w only)
    --jailbreak               Enable jailbreak option
    --memory                  Enable memory option for creating IPSW

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
            platform_arch="arm64"
        elif [[ $(uname -m) == "a"* ]]; then
            platform_arch="armhf"
        elif [[ $(uname -m) == "x86_64" ]]; then
            platform_arch="x86_64"
        else
            error "Your architecture ($(uname -m)) is not supported."
        fi
        dir+="$platform_arch"

        # version check
        if [[ -n $UBUNTU_CODENAME ]]; then
            case $UBUNTU_CODENAME in
                "jammy" | "kinetic" ) ubuntu_ver=22;;
                "lunar" | "mantic" ) ubuntu_ver=23;;
            esac
            if [[ -z $ubuntu_ver ]]; then
                . /etc/upstream-release/lsb-release 2>/dev/null
                ubuntu_ver="$(echo "$DISTRIB_RELEASE" | cut -c -2)"
            fi
            if [[ -z $ubuntu_ver ]]; then
                ubuntu_ver="$(echo "$VERSION_ID" | cut -c -2)"
            fi
        elif [[ -e /etc/debian_version ]]; then
            debian_ver=$(cat /etc/debian_version)
            if [[ $debian_ver == *"sid" ]]; then
                debian_ver="sid"
            else
                debian_ver="$(echo "$debian_ver" | cut -c -2)"
            fi
        elif [[ $ID == "fedora" || $ID == "nobara" ]]; then
            fedora_ver=$VERSION_ID
        fi

        # distro check
        if [[ $ID == "arch" || $ID_LIKE == "arch" || $ID == "artix" ]]; then
            distro="arch"
        elif (( ubuntu_ver >= 22 )) || (( debian_ver >= 12 )) || [[ $debian_ver == "sid" ]]; then
            distro="debian"
        elif (( fedora_ver >= 37 )); then
            distro="fedora"
        elif [[ $ID == "opensuse-tumbleweed" ]]; then
            distro="opensuse"
        elif [[ $ID == "gentoo" || $ID_LIKE == "gentoo" || $ID == "pentoo" ]]; then
            distro="gentoo"
        else
            error "Your distro ($platform_ver) is not detected/supported. See the repo README for supported OS versions/distros"
        fi

        ping="ping -c1"
        zenity="$(which zenity)"

        # live cd/usb check
        if [[ $(id -u $USER) == 999 || $USER == "liveuser" ]]; then
            live_cdusb=1
            live_cdusb_str="Live"
            log "Linux Live CD/USB detected."
            if [[ $(pwd) == "/home"* ]]; then
                df . -h
                if [[ $(lsblk -o label | grep -c "casper-rw") == 1 || $(lsblk -o label | grep -c "persistence") == 1 ]]; then
                    log "Detected Legacy iOS Kit running on persistent storage."
                    live_cdusb_str="Live - Persistent storage"
                else
                    warn "Detected Legacy iOS Kit running on temporary storage."
                    print "* You may run out of space and get errors during the downgrade process."
                    print "* Please move Legacy iOS Kit to an external drive that is NOT used for the live USB."
                    print "* This means using another external HDD/flash drive to store Legacy iOS Kit on."
                    print "* To be able to use one USB drive only, make sure to enable Persistent Storage for the live USB."
                    pause
                    live_cdusb_str="Live - Temporary storage"
                fi
            fi
        fi

        # if "/media" is detected in pwd, warn user of possible permission issues
        if [[ $(pwd) == *"/media"* ]]; then
            warn "You may get permission issues like \"Permission denied\" on getting device info."
            print "* If this is the case, try moving Legacy iOS Kit to the Desktop or Documents folder."
        fi

        if [[ -z $device_disable_sudoloop ]]; then
            device_sudoloop=1 # Run some tools as root for device detection if set to 1. (for Linux)
            #log "new trap"
            trap "clean_sudo" EXIT
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
            if [[ ! -d $dir && $(ls ../bin/linux) ]]; then
                log "Running on platform: $platform ($platform_ver)"
                error "Failed to find bin directory, detected $(ls -x ../bin/linux) instead of $platform_arch." \
                "* Download the \"linux_$platform_arch\" or \"complete\" version to continue (or do a git clone)"
            fi
            if [[ -z $device_disable_usbmuxd ]]; then
                sudo systemctl stop usbmuxd
                sudo -b $dir/usbmuxd -pf 2>/dev/null
                sleep 1
                #log "new trap"
                trap "clean_usbmuxd" EXIT
            fi
        fi

    elif [[ $OSTYPE == "darwin"* ]]; then
        platform="macos"
        platform_ver="${1:-$(sw_vers -productVersion)}"
        dir="../bin/macos"

        # macos version check
        if [[ ${platform_ver:0:2} == 10 ]]; then
            local mac_ver=${platform_ver:3}
            mac_ver=${mac_ver%.*}
            if (( mac_ver < 13 )); then
                error "Your macOS version ($platform_ver) is not supported." \
                "* You need to be on macOS 10.13 or newer to continue."
            fi
        fi

        bspatch="$(which bspatch)"
        ipwnder32="$dir/ipwnder32"
        ping="ping -c1"
        sha1sum="$(which shasum) -a 1"
        sha256sum="$(which shasum) -a 256"

        # kill macos daemons
        killall -STOP AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater

    else
        error "Your platform ($OSTYPE) is not supported." "* Supported platforms: Linux, macOS"
    fi
    log "Running on platform: $platform ($platform_ver)"
    if [[ ! -d $dir ]]; then
        error "Failed to find bin directory ($dir), cannot continue." \
        "* Re-download Legacy iOS Kit from releases (or do a git clone/reset)"
    fi
    if [[ $device_sudoloop == 1 ]]; then
        sudo chmod +x $dir/*
        if [[ $? != 0 ]]; then
            error "Failed setting up permissions, cannot continue."
        fi
    else
        chmod +x $dir/*
    fi

    ideviceenterrecovery="$dir/ideviceenterrecovery"
    ideviceinfo="$dir/ideviceinfo"
    iproxy="$dir/iproxy"
    irecovery+="$dir/irecovery"
    if [[ $platform == "macos" ]]; then
        local ideviceinfot="$(which ideviceinfo 2>/dev/null)"
        local irecoveryt="$(which irecovery 2>/dev/null)"
        if [[ -n $ideviceinfot && -n $irecoveryt ]]; then
            log "Detected libimobiledevice and libirecovery from Homebrew/MacPorts"
            ideviceenterrecovery="$(which ideviceenterrecovery)"
            ideviceinfo="$(which ideviceinfo)"
            iproxy="$(which iproxy)"
            irecovery="$(which irecovery)"
        fi
    else
        bspatch="$dir/bspatch"
        sha1sum="$(which sha1sum)"
        sha256sum="$(which sha256sum)"
    fi
    ideviceactivation="$(which ideviceactivation 2>/dev/null)"
    if [[ -z $ideviceactivation ]]; then
        ideviceactivation="$dir/ideviceactivation"
    fi
    jq="$dir/jq"
    if [[ $platform != "linux" ]]; then
        zenity="$dir/zenity"
    fi
    futurerestore+="$dir/futurerestore"
    gaster+="$dir/gaster"
    idevicerestore+="$dir/idevicerestore"
    idevicererestore+="$dir/idevicererestore"
    ipwnder+="$dir/ipwnder"
    irecovery2+="$dir/irecovery2"
    scp2="scp -F ../resources/ssh_config"
    ssh2="ssh -F ../resources/ssh_config"
}

install_depends() {
    log "Installing dependencies..."
    rm -f "../resources/firstrun"

    if [[ $platform == "linux" ]]; then
        print "* Legacy iOS Kit will be installing dependencies from your distribution's package manager"
        print "* Enter your user password when prompted"
        pause
    fi

    if [[ $distro == "arch" ]]; then
        sudo pacman -Sy --noconfirm --needed base-devel ca-certificates ca-certificates-mozilla curl libimobiledevice openssh pyenv python udev unzip usbmuxd usbutils vim zenity zip

    elif [[ $distro == "debian" ]]; then
        if [[ -n $ubuntu_ver ]]; then
            sudo add-apt-repository -y universe
        fi
        sudo apt update
        sudo apt install -y ca-certificates curl libimobiledevice6 libirecovery-common libssl3 openssh-client python3 unzip usbmuxd usbutils xxd zenity zip
        if [[ -n $ubuntu_ver ]] && (( ubuntu_ver < 23 )); then
            sudo apt install -y python2
        fi
        sudo systemctl enable --now udev systemd-udevd usbmuxd 2>/dev/null

    elif [[ $distro == "fedora" ]]; then
        sudo dnf install -y ca-certificates libimobiledevice openssl python3 systemd udev usbmuxd vim-common zenity zip
        sudo ln -sf /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-certificates.crt

    elif [[ $distro == "opensuse" ]]; then
        sudo zypper -n in ca-certificates curl libimobiledevice-1_0-6 openssl-3 pyenv python3 usbmuxd unzip vim zenity zip

    elif [[ $distro == "gentoo" ]]; then
        sudo emerge -av app-misc/ca-certificates net-misc/curl libimobiledevice openssh python udev unzip usbmuxd usbutils vim zenity zip

    elif [[ $platform == "macos" ]]; then
        print "* Legacy iOS Kit will be installing dependencies and setting up permissions of tools"
        print "* Enter your user password when prompted"
        pause
        sudo xattr -cr $dir
        chown -R $USER:staff $dir
        log "Installing Xcode Command Line Tools"
        xcode-select --install
        if [[ $(uname -m) != "x86_64" ]]; then
            log "Installing Rosetta 2"
            softwareupdate --install-rosetta
        fi
    fi

    echo "$platform_ver" > "../resources/firstrun"
    if [[ $platform == "linux" ]]; then
        # from linux_fix script by Cryptiiiic
        sudo systemctl enable --now systemd-udevd usbmuxd 2>/dev/null
        echo "QUNUSU9OPT0iYWRkIiwgU1VCU1lTVEVNPT0idXNiIiwgQVRUUntpZFZlbmRvcn09PSIwNWFjIiwgQVRUUntpZFByb2R1Y3R9PT0iMTIyWzI3XXwxMjhbMC0zXSIsIE9XTkVSPSJyb290IiwgR1JPVVA9InVzYm11eGQiLCBNT0RFPSIwNjYwIiwgVEFHKz0idWFjY2VzcyIKCkFDVElPTj09ImFkZCIsIFNVQlNZU1RFTT09InVzYiIsIEFUVFJ7aWRWZW5kb3J9PT0iMDVhYyIsIEFUVFJ7aWRQcm9kdWN0fT09IjEzMzgiLCBPV05FUj0icm9vdCIsIEdST1VQPSJ1c2JtdXhkIiwgTU9ERT0iMDY2MCIsIFRBRys9InVhY2Nlc3MiCgoK" | base64 -d | sudo tee /etc/udev/rules.d/39-libirecovery.rules >/dev/null 2>/dev/null
        sudo chown root:root /etc/udev/rules.d/39-libirecovery.rules
        sudo chmod 0644 /etc/udev/rules.d/39-libirecovery.rules
        sudo udevadm control --reload-rules
        sudo udevadm trigger
    fi

    log "Install script done! Please run the script again to proceed"
    log "If your iOS device is plugged in, unplug and replug your device"
    exit
}

version_get() {
    log "Checking for updates..."
    github_api=$(curl https://api.github.com/repos/LukeZGD/Legacy-iOS-Kit/releases/latest 2>/dev/null)
    pushd "$(dirname "$0")/tmp" >/dev/null
    version_latest=$(echo "$github_api" | $jq -r '.assets[] | select(.name|test("complete")) | .name' | cut -c 25- | cut -c -9)
    git_hash_latest=$(echo "$github_api" | $jq -r '.assets[] | select(.name|test("git-hash")) | .name' | cut -c 21- | cut -c -7)
    popd >/dev/null
}

version_update() {
    local url
    local req
    read -p "$(input 'Do you want to update now? (Y/n): ')" opt
    if [[ $opt == 'n' || $opt == 'N' ]]; then
        exit
    fi
    if [[ -d .git ]]; then
        log "Running git pull..."
        git pull
        log "Done! Please run the script again"
        exit
    elif (( $(ls bin | wc -l) > 1 )); then
        req=".assets[] | select (.name|test(\"complete\")) | .browser_download_url"
    elif [[ $platform == "linux" ]]; then
        req=".assets[] | select (.name|test(\"${platform}_$platform_arch\")) | .browser_download_url"
    else
        req=".assets[] | select (.name|test(\"${platform}\")) | .browser_download_url"
    fi
    pushd "$(dirname "$0")/tmp" >/dev/null
    url="$(echo "$github_api" | $jq -r "$req")"
    log "Downloading: $url"
    curl -L $url -o latest.zip
    if [[ ! -s latest.zip ]]; then
        error "Download failed. Please run the script again"
    fi
    popd >/dev/null
    log "Updating..."
    cp resources/firstrun tmp 2>/dev/null
    rm -r bin/ resources/ LICENSE README.md restore.sh
    unzip -q tmp/latest.zip -d .
    cp tmp/firstrun resources 2>/dev/null
    log "Done! Please run the script again"
    exit
}

version_check() {
    pushd .. >/dev/null
    if [[ -d .git ]]; then
        git_hash=$(git rev-parse HEAD | cut -c -7)
        local dm=$(git log -1 --format=%ci | cut -c 3- | cut -c -5)
        version_current=v${dm//-/.}.
        dm="20$dm"
        if [[ $platform == "macos" ]]; then
            dm="$(date -j -f "%Y-%m-%d %H:%M:%S" "${dm}-01 00:00:00" +%s)"
        else
            dm="$(date --date="${dm}-01" +%s)"
        fi
        dm=$((dm-1))
        version_current+=$(git rev-list --count HEAD --since=$dm | xargs printf "%02d")
    elif [[ -e ./resources/git_hash ]]; then
        version_current="$(cat ./resources/version)"
        git_hash="$(cat ./resources/git_hash)"
    else
        log ".git directory and git_hash file not found, cannot determine version."
        if [[ $no_version_check != 1 ]]; then
            warn "Your copy of Legacy iOS Kit is downloaded incorrectly. Do not use the \"Code\" button in GitHub."
            print "Please download Legacy iOS Kit using git clone or from GitHub releases: https://github.com/LukeZGD/Legacy-iOS-Kit/releases"
            version_get
            version_update
        fi
    fi

    if [[ -n $version_current ]]; then
        print "* Version: $version_current ($git_hash)"
    fi

    if [[ $no_version_check != 1 ]]; then
        version_get
        if [[ -z $version_latest ]]; then
            warn "Failed to check for updates. GitHub may be down or blocked by your network."
        elif [[ $git_hash_latest != "$git_hash" ]]; then
            if (( $(echo $version_current | cut -c 2- | sed -e 's/\.//g') >= $(echo $version_latest | cut -c 2- | sed -e 's/\.//g') )); then
                warn "Current version is newer/different than remote: $version_latest ($git_hash_latest)"
            else
                print "* A newer version of Legacy iOS Kit is available."
                print "* Current version: $version_current ($git_hash)"
                print "* Latest version:  $version_latest ($git_hash_latest)"
                print "* Please download/pull the latest version before proceeding."
                version_update
            fi
        fi
    fi
    popd >/dev/null
}

device_entry() {
    # enable manual entry
    log "Manual device/ECID entry is enabled."
    until [[ -n $device_type ]]; do
        read -p "$(input 'Enter device type (eg. iPad2,1): ')" device_type
    done
    until [[ -n $device_ecid ]] && [ "$device_ecid" -eq "$device_ecid" ]; do
        read -p "$(input 'Enter device ECID (must be decimal): ')" device_ecid
    done
}

device_manufacturing() {
    if [[ $device_type != "iPhone2,1" && $device_type != "iPod2,1" ]] || [[ $device_argmode == "none" ]]; then
        return
    fi
    if [[ $device_type == "iPhone2,1" && $device_mode != "DFU" ]]; then
        if (( device_serial >= 946 )) || (( device_serial < 900 )); then
            device_newbr=1
        elif (( device_serial >= 940 )); then
            device_newbr=2 # gray area
        else
            device_newbr=0
        fi
    elif [[ $device_type == "iPod2,1" && -z $device_newbr ]]; then
        device_newbr=2
        return
    fi
    if [[ $device_newbr == 1 ]]; then
        print "* This $device_type is a new bootrom model, some iOS versions might not be compatible"
    elif [[ $device_newbr == 2 ]]; then
        print "* This $device_type bootrom model cannot be determined. Enter DFU mode to get bootrom model"
    else
        print "* This $device_type is an old bootrom model"
    fi
    if [[ $device_type == "iPhone2,1" && -n $device_serial ]]; then
        local week=$(echo "$device_serial" | cut -c 2-)
        local year=$(echo "$device_serial" | cut -c 1)
        case $year in
            9 ) year="2009";;
            0 ) year="2010";;
            1 ) year="2011";;
            2 ) year="2012";;
        esac
        print "* Manufactured in Week $week $year"
    fi
}

device_get_info() {
    : '
    usage: device_get_info (no arguments)
    sets the variables: device_mode, device_type, device_ecid, device_vers, device_udid, device_model, device_fw_dir,
    device_use_vers, device_use_build, device_use_bb, device_use_bb_sha1, device_latest_vers, device_latest_build,
    device_latest_bb, device_latest_bb_sha1, device_proc
    '

    if [[ $device_argmode == "none" ]]; then
        log "No device mode is enabled."
        device_mode="none"
        device_vers="Unknown"
    else
        log "Finding device in Normal mode..."
    fi

    $ideviceinfo -s >/dev/null
    if [[ $? == 0 ]]; then
        device_mode="Normal"
    else
        $ideviceinfo >/dev/null
        if [[ $? == 0 ]]; then
            device_mode="Normal"
        fi
    fi

    if [[ -z $device_mode ]]; then
        log "Finding device in Recovery/DFU mode..."
        device_mode="$($irecovery -q | grep -w "MODE" | cut -c 7-)"
    fi

    if [[ -z $device_mode ]]; then
        local error_msg=$'* Make sure to trust this computer by selecting "Trust" at the pop-up.'
        [[ $platform == "macos" ]] && error_msg+=$'\n* Make sure to have the initial setup dependencies installed before retrying.'
        [[ $platform != "linux" ]] && error_msg+=$'\n* Double-check if the device is being detected by iTunes/Finder.'
        error_msg+=$'\n* For more details, read the "Troubleshooting" wiki page in GitHub.\n* Troubleshooting link: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting'
        error "No device found! Please connect the iOS device to proceed." "$error_msg"
    fi

    log "Getting device info..."
    case $device_mode in
        "WTF" | "DFU" | "Recovery" )
            #device_type=$($irecovery -q | grep "PRODUCT" | cut -c 10-)
            local ProdCut=7 # cut 7 for ipod/ipad
            device_type=$($irecovery -qv 2>&1 | grep "Connected to iP" | cut -c 14-)
            if [[ $(echo "$device_type" | cut -c 3) == 'h' ]]; then
                ProdCut=9 # cut 9 for iphone
            fi
            if [[ -n $device_argmode ]]; then
                device_entry
            else
                device_type=$(echo "$device_type" | cut -c -$ProdCut)
                device_ecid=$(printf "%d" $($irecovery -q | grep "ECID" | cut -c 7-)) # converts hex ecid to dec
            fi
            device_model=$($irecovery -q | grep "MODEL" | cut -c 8-)
            device_vers=$(echo "/exit" | $irecovery -s | grep "iBoot-")
            [[ -z $device_vers ]] && device_vers="Unknown"
            device_serial="$($irecovery -q | grep "SRNM" | cut -c 7- | cut -c 3- | cut -c -3)"
            device_manufacturing
            if [[ $device_mode == "Recovery" && $device_newbr == 2 ]]; then
                print "* Device: $device_type (${device_model}) in $device_mode mode"
                print "* iOS Version: $device_vers"
                print "* ECID: $device_ecid"
                echo
                warn "Your device is in recovery mode. Enter DFU mode to continue."
                device_enter_mode DFU
            fi
            if [[ $device_type == "iPod2,1" ]]; then
                device_newbr="$($irecovery -q | grep -c '240.5.1')"
            elif [[ $device_type == "iPhone2,1" ]]; then
                device_newbr="$($irecovery -q | grep -c '359.3.2')"
            fi
        ;;

        "Normal" )
            if [[ -n $device_argmode ]]; then
                device_entry
            else
                device_type=$($ideviceinfo -s -k ProductType)
                [[ -z $device_type ]] && device_type=$($ideviceinfo -k ProductType)
                device_ecid=$($ideviceinfo -s -k UniqueChipID)
            fi
            device_model=$($ideviceinfo -s -k HardwareModel)
            device_vers=$($ideviceinfo -s -k ProductVersion)
            device_udid=$($ideviceinfo -s -k UniqueDeviceID)
            [[ -z $device_udid ]] && device_udid=$($ideviceinfo -k UniqueDeviceID)
            if [[ $device_type == "iPod2,1" ]]; then
                device_newbr="$($ideviceinfo -k ModelNumber | grep -c 'C')"
            elif [[ $device_type == "iPhone2,1" ]]; then
                device_serial="$($ideviceinfo -k SerialNumber | cut -c 3- | cut -c -3)"
            fi
        ;;
    esac

    if [[ $device_argmode == "none" ]]; then
        device_entry
    fi

    device_model="$(echo $device_model | tr '[:upper:]' '[:lower:]')"
    device_model="${device_model%??}" # remove "ap" from the end
    if [[ -z $device_type && -n $device_model ]]; then
        case $device_model in
            k48  ) device_type="iPad1,1";;
            k93  ) device_type="iPad2,1";;
            k94  ) device_type="iPad2,2";;
            k95  ) device_type="iPad2,3";;
            k93a ) device_type="iPad2,4";;
            p105 ) device_type="iPad2,5";;
            p106 ) device_type="iPad2,6";;
            p107 ) device_type="iPad2,7";;
            j1   ) device_type="iPad3,1";;
            j2   ) device_type="iPad3,2";;
            j2a  ) device_type="iPad3,3";;
            p101 ) device_type="iPad3,4";;
            p102 ) device_type="iPad3,5";;
            p103 ) device_type="iPad3,6";;
            j71  ) device_type="iPad4,1";;
            j72  ) device_type="iPad4,2";;
            j73  ) device_type="iPad4,3";;
            j85  ) device_type="iPad4,4";;
            j86  ) device_type="iPad4,5";;
            j87  ) device_type="iPad4,6";;
            j85m ) device_type="iPad4,7";;
            j86m ) device_type="iPad4,8";;
            j87m ) device_type="iPad4,9";;
            j96  ) device_type="iPad5,1";;
            j97  ) device_type="iPad5,2";;
            j81  ) device_type="iPad5,3";;
            j82  ) device_type="iPad5,4";;
            m68  ) device_type="iPhone1,1";;
            n82  ) device_type="iPhone1,2";;
            n88  ) device_type="iPhone2,1";;
            n90  ) device_type="iPhone3,1";;
            n90b ) device_type="iPhone3,2";;
            n92  ) device_type="iPhone3,3";;
            n94  ) device_type="iPhone4,1";;
            n41  ) device_type="iPhone5,1";;
            n42  ) device_type="iPhone5,2";;
            n48  ) device_type="iPhone5,3";;
            n49  ) device_type="iPhone5,4";;
            n51  ) device_type="iPhone6,1";;
            n53  ) device_type="iPhone6,2";;
            n56  ) device_type="iPhone7,1";;
            n61  ) device_type="iPhone7,2";;
            n71  ) device_type="iPhone8,1";;
            n66  ) device_type="iPhone8,2";;
            n69  ) device_type="iPhone8,4";;
            n71m ) device_type="iPhone8,1";;
            n66m ) device_type="iPhone8,2";;
            n69u ) device_type="iPhone8,4";;
            d10  ) device_type="iPhone9,1";;
            d11  ) device_type="iPhone9,2";;
            d101 ) device_type="iPhone9,3";;
            d111 ) device_type="iPhone9,4";;
            n45  ) device_type="iPod1,1";;
            n72  ) device_type="iPod2,1";;
            n18  ) device_type="iPod3,1";;
            n81  ) device_type="iPod4,1";;
            n78  ) device_type="iPod5,1";;
            n102 ) device_type="iPod7,1";;
        esac
    fi

    device_fw_dir="../resources/firmware/$device_type"
    if [[ -s $device_fw_dir/hwmodel ]]; then
        device_model="$(cat $device_fw_dir/hwmodel)"
    fi
    device_use_bb=0
    device_latest_bb=0
    # set device_proc (what processor the device has)
    case $device_type in
        iPhone1,[12] | iPod1,1 )
            device_proc=1;; # S5L8900
        iPhone3,[123] | iPhone2,1 | iPod2,1 | iPod3,1 | iPad1,1 | iPod4,1 )
            device_proc=4;; # A4/S5L8920/22/8720
        iPad2,[1234567] | iPad3,[123] | iPhone4,1 | iPod5,1 )
            device_proc=5;; # A5
        iPad3,[456] | iPhone5,[1234] )
            device_proc=6;; # A6
        iPad4,[123456789] | iPhone6,[12] )
            device_proc=7;; # A7
        iPhone7,[12] | iPod7,1 )
            device_proc=8;; # A8
    esac
    if [[ -z $device_proc ]]; then
        print "* Device: $device_type (${device_model}ap) in $device_mode mode"
        print "* iOS Version: $device_vers"
        print "* ECID: $device_ecid"
        echo
        error "This device is not supported by Legacy iOS Kit."
    fi

    if [[ $device_mode == "DFU" && $device_proc == 1 ]]; then
        warn "Your device $device_type seems to be on an incorrect mode for restoring."
        print "* Force restart your device and place it in normal or recovery mode, then run the script again."
        print "* Or proceed to do the DFU mode procedure below."
        device_dfuhelper
    fi

    # set device_use_vers, device_use_build (where to get the baseband and manifest from for ota/other)
    # for a7/a8 other restores 11.3+, device_latest_vers and device_latest_build are used
    case $device_type in
        iPhone1,1 | iPod1,1 )
            device_use_vers="3.1.3"
            device_use_build="7E18"
        ;;
        iPhone1,2 | iPod2,1 )
            device_use_vers="4.2.1"
            device_use_build="8C148"
        ;;
        iPad1,1 | iPod3,1 )
            device_use_vers="5.1.1"
            device_use_build="9B206"
        ;;
        iPhone2,1 | iPod4,1 )
            device_use_vers="6.1.6"
            device_use_build="10B500"
        ;;
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
        ;;
    esac
    case $device_type in
        iPad4,[123456789] | iPhone6,[12] | iPhone7,[12] | iPod7,1 )
            device_latest_vers="12.5.7"
            device_latest_build="16H81"
        ;;
        iPad5,[1234] | iPhone8,[124] | iPhone9,[1234] | iPod9,1 )
            device_latest_vers="15.7.8"
            device_latest_build="19H364"
        ;;
    esac
    # set device_use_bb, device_use_bb_sha1 (what baseband to use for ota/other)
    # for a7/a8 other restores 11.3+, device_latest_bb and device_latest_bb_sha1 are used instead
    case $device_type in
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
        ;;
    esac
    case $device_type in
        iPad4,[235689] | iPhone6,[12] ) # MDM9615 12.5.7
            device_latest_bb="Mav7Mav8-10.80.02.Release.bbfw"
            device_latest_bb_sha1="f5db17f72a78d807a791138cd5ca87d2f5e859f0"
        ;;
        iPhone7,[12] ) # MDM9625
            device_latest_bb="Mav10-7.80.04.Release.bbfw"
            device_latest_bb_sha1="7ec8d734da78ca2bb1ba202afdbb6fe3fd093cb0"
        ;;
        iPad5,[24] | iPhone8,[124] ) # MDM9615/MDM9635 15.7.8
            device_latest_bb="Mav10-11.61.01.Release.bbfw"
            device_latest_bb_sha1="212cbb1e5bfd60912c01adda7dca66a569ddf758"
        ;;
        iPhone9,[12] ) # MDM9645
            device_latest_bb="Mav16-9.61.00.Release.bbfw"
            device_latest_bb_sha1="7c742e0fc4857e7c07df1e4c48ccafbb60ae38bb"
        ;;
        iPhone9,[34] ) # PMB9943
            device_latest_bb="ICE16-6.03.01.Release.bbfw"
            device_latest_bb_sha1="0e62ac6a7c8299f69f9410bdda27f6a3f9601a8f"
        ;;
    esac
    # disable bbupdate for ipad 2 cellular devices
    case $device_type in
        iPad2,[23] ) device_disable_bbupdate="$device_type";;
    esac
    # disable baseband update if var is set to 1 (manually disabled w/ --disable-bbupdate arg)
    if [[ $device_disable_bbupdate == 1 ]]; then
        device_disable_bbupdate="$device_type"
    fi
    # if latest vers is not set, copy use vers to latest
    if [[ -z $device_latest_vers || -z $device_latest_build ]]; then
        device_latest_vers=$device_use_vers
        device_latest_build=$device_use_build
        device_latest_bb=$device_use_bb
        device_latest_bb_sha1=$device_use_bb_sha1
    fi
}

device_find_mode() {
    # usage: device_find_mode {DFU,Recovery,Restore} {Timeout (default: 24 for linux, 4 for other)}
    # finds device in given mode, and sets the device_mode variable
    local usb
    local timeout=4
    local i=0
    local device_in
    local mode="$1"

    if [[ $mode == "Restore" ]]; then
        :
    elif [[ $mode == "Recovery" ]]; then
        usb=1281
    elif [[ $device_proc == 1 ]]; then
        usb=1222
        if [[ $mode == "DFU" ]]; then
            mode="WTF"
        fi
    else
        usb=1227
    fi

    if [[ -n $2 ]]; then
        timeout=$2
    elif [[ $platform == "linux" || $mode == "Restore" ]]; then
        timeout=24
    fi

    log "Finding device in $mode mode..."
    while (( i < timeout )); do
        if [[ $mode == "Restore" ]]; then
            $ideviceinfo -s >/dev/null
            if [[ $? == 0 ]]; then
                device_in=1
            fi
        elif [[ $platform == "linux" ]]; then
            device_in=$(lsusb | grep -c "05ac:$usb")
        elif [[ $($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-) == "$mode" ]]; then
            device_in=1
        fi

        if [[ $device_in == 1 ]]; then
            log "Found device in $mode mode."
            device_mode="$mode"
            break
        fi
        sleep 1
        ((i++))
    done

    if [[ $device_in != 1 ]]; then
        if [[ $timeout != 1 ]]; then
            error "Failed to find device in $mode mode (Timed out). Please run the script again."
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
    scp="$dir/sshpass -p $pass $scp2"
    ssh="$dir/sshpass -p $pass $ssh2"
}

device_dfuhelper() {
    print "* Get ready to enter DFU mode."
    read -p "$(input 'Select Y to continue, N to exit (Y/n) ')" opt
    if [[ $opt == 'N' || $opt == 'n' ]]; then
        exit
    fi
    print "* Get ready..."
    for i in {03..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n$(print '* Hold TOP and HOME buttons.')"
    for i in {10..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n$(print '* Release TOP button and keep holding HOME button.')"
    for i in {08..01}; do
        echo -n "$i "
        sleep 1
    done
    echo
    device_find_mode DFU
}

device_enter_mode() {
    # usage: device_enter_mode {Recovery, DFU, kDFU, pwnDFU}
    # attempt to enter given mode, and device_find_mode function will then set device_mode variable
    local opt
    case $1 in
        "Recovery" )
            if [[ $device_mode == "Normal" ]]; then
                print "* The device needs to be in recovery/DFU mode before proceeding."
                read -p "$(input 'Send device to recovery mode? (Y/n): ')" opt
                if [[ $opt == 'n' || $opt == 'N' ]]; then
                    exit
                fi
                log "Entering recovery mode..."
                $ideviceenterrecovery "$device_udid" >/dev/null
                device_find_mode Recovery 50
            elif [[ $device_mode == "DFU" ]]; then
                log "Device is in DFU mode, cannot enter recovery mode"
                return
            fi
        ;;

        "DFU" )
            if [[ $device_mode == "Normal" ]]; then
                device_enter_mode Recovery
            elif [[ $device_mode == "DFU" || $device_mode == "WTF" ]]; then
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
            print "* Get ready..."
            for i in {03..01}; do
                echo -n "$i "
                sleep 1
            done
            echo -e "\n$(print '* Hold TOP and HOME buttons.')"
            for i in {04..01}; do
                echo -n "$i "
                if (( i <= 1 )); then
                    $irecovery -n
                fi
                sleep 1
            done
            echo -e "\n$(print '* Release TOP button and keep holding HOME button.')"
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
                device_enter_mode pwnDFU
                return
            fi

            patch_ibss
            log "Running iproxy for SSH..."
            $iproxy 2222 22 >/dev/null &
            iproxy_pid=$!
            sleep 2

            log "Please read the message below:"
            print "1. Make sure to have OpenSSH installed on your iOS device."
            if [[ $device_det == 1 ]]; then
                print " - Make sure to also have Dropbear installed from my repo."
                print " - Repo: https://lukezgd.github.io/repo"
            fi
            print "  - Only proceed if you have these requirements installed using Cydia/Zebra."
            print "  - You will be prompted to enter the root password of your iOS device."
            print "  - The default root password is: alpine"
            print "  - Do not worry that your input is not visible, it is still being entered."
            print "2. Afterwards, the device will disconnect and its screen will stay black."
            print "  - Proceed to either press the TOP/HOME button, or unplug and replug the device."
            pause

            echo "chmod +x /tmp/kloader*" > kloaders
            if [[ $device_det == 1 ]]; then
                echo '[[ $(uname -a | grep -c "MarijuanARM") == 1 ]] && /tmp/kloader_hgsp /tmp/pwnediBSS || \
                /tmp/kloader /tmp/pwnediBSS' >> kloaders
                sendfiles+=("../resources/kloader/kloader_hgsp")
                sendfiles+=("../resources/kloader/kloader")
            elif [[ $device_det == 5 ]]; then
                echo "/tmp/kloader5 /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader/kloader5")
            elif (( device_det < 5 )); then
                echo "/tmp/kloader_axi0mX /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader/kloader_axi0mX")
            else
                echo "/tmp/kloader /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader/kloader")
            fi
            sendfiles+=("kloaders" "pwnediBSS")

            device_sshpass
            log "Entering kDFU mode..."
            print "* This may take a while, but should not take longer than a minute."
            if [[ $device_det == 1 ]]; then
                print "* If the script seems to be stuck here, try to re-install the requirements and restart the device."
                print "* Follow the steps in the GitHub wiki."
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
                    print "* Troubleshooting link: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting#dfu-advanced-menu-for-32-bit-devices"
                elif [[ $device_det == 5 ]]; then
                    print "* Try to re-install OpenSSH, reboot, and try again."
                else
                    print "* Try to re-install OpenSSH, reboot, re-jailbreak, and try again."
                    print "* Alternatively, you may use kDFUApp from my Cydia repo (see \"Troubleshooting\" wiki page for details)"
                    print "* Troubleshooting link: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting#dfu-advanced-menu-kdfu-mode"
                fi
                input "Press Enter/Return to try again with Wi-Fi SSH (or press Ctrl+C to cancel and try again)"
                read -s
                log "Will try again with Wi-Fi SSH..."
                print "* Make sure that your iOS device and PC/Mac are on the same network."
                print "* To get your device's IP Address, go to: Settings -> Wi-Fi/WLAN -> tap the 'i' next to your network name"
                local IPAddress
                until [[ -n $IPAddress ]]; do
                    read -p "$(input 'Enter the IP Address of your device: ')" IPAddress
                done
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

            if [[ $device_target_powder == 1 && $mode == "downgrade" ]]; then
                print "* Note that kDFU mode will likely not work for powdersn0w restores!"
            fi

            if [[ $device_mode != "Normal" ]]; then
                irec_pwned=$($irecovery -q | grep -c "PWND")
            fi
            if [[ $device_mode == "DFU" && $mode != "pwned-ibss" && $device_proc != 4 ]] && (( device_proc < 7 )); then
                print "* Select Y if your device is in pwned iBSS/kDFU mode."
                print "* Select N to place device to pwned DFU mode using ipwndfu/ipwnder."
                read -p "$(input 'Is your device already in pwned iBSS/kDFU mode? (y/N): ')" opt
                if [[ $opt == "Y" || $opt == "y" ]]; then
                    log "Pwned iBSS/kDFU mode specified by user."
                    return
                fi
            elif [[ $irec_pwned == 1 && $device_proc == 7 ]]; then
                if [[ $platform == "macos" ]]; then
                    $ipwnder
                else
                    device_ipwndfu rmsigchks
                fi
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

            if (( device_proc > 7 )); then
                # A8/A9/A10 uses gaster
                log "Placing device to pwnDFU mode using gaster"
                $gaster pwn
                tool_pwned=$?
                $gaster reset
            elif [[ $device_proc == 6 && $platform != "macos" ]] || [[ $device_type == "iPod2,1" ]]; then
                # A6 linux uses ipwndfu
                # ipod touch 2g uses ipwndfu
                device_ipwndfu pwn
            elif [[ $device_proc == 4 && $platform != "macos" ]]; then
                # A4 linux uses ipwnder
                log "Placing device to pwnDFU mode using ipwnder"
                $ipwnder -p
                tool_pwned=$?
            elif (( device_proc > 5 )) && [[ $platform == "macos" && $(uname -m) != "x86_64" ]]; then
                # A6/A7 asi mac uses ipwnder_lite
                log "Placing device to pwnDFU mode using ipwnder_lite"
                opt="${ipwnder}2 -p"
                $opt
                tool_pwned=$?
            else
                # A4/A6 mac uses ipwnder_lite/ipwnder32
                # A7 intel mac uses ipwnder_lite/ipwnder32/gaster
                # A7 linux uses ipwnder/gaster
                input "PwnDFU Tool Option"
                print "* Select tool to be used for entering pwned DFU mode."
                local selection=()
                if [[ $platform == "macos" ]]; then
                    print "* This option is set to ipwnder32 by default (1). Select this option if unsure."
                    selection+=("ipwnder32" "ipwnder_lite")
                elif [[ $device_proc == 7 ]]; then
                    print "* This option is set to gaster by default (1). Select this option if unsure."
                fi
                if [[ $device_proc == 7 ]]; then
                    selection+=("gaster")
                fi
                if [[ $platform != "macos" ]]; then
                    selection+=("ipwnder")
                fi
                input "Select your option:"
                select opt2 in "${selection[@]}"; do
                    case $opt2 in
                        "gaster" ) opt="$gaster pwn"; break;;
                        "ipwnder32" ) opt="$ipwnder32 -p"; break;;
                        * )
                            opt="$ipwnder"
                            if (( device_proc > 5 )); then
                                opt="${ipwnder}2 -p"
                            fi
                            break
                        ;;
                    esac
                done
                log "Placing device to pwnDFU mode using: $opt"
                $opt
                tool_pwned=$?
            fi
            irec_pwned=$($irecovery -q | grep -c "PWND")
            # irec_pwned is instances of "PWND" in serial, must be 1
            # tool_pwned is error code of pwning tool, must be 0
            if [[ $irec_pwned != 1 && $tool_pwned != 0 ]]; then
                device_pwnerror
            fi
            if [[ $opt == "${ipwnder}2 -p" && $device_proc == 6 ]]; then
                ${ipwnder}2 --upload-iboot
            fi

            if [[ $platform == "macos" && $opt != "$gaster pwn" ]] || (( device_proc > 7 )); then
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

device_pwnerror() {
    local error_msg=$'\n* Exit DFU mode first by holding the TOP and HOME buttons for 15 seconds.'
    error_msg+=$'\n* If you have an AMD CPU, you may have to try again on a machine with an Intel CPU.'
    if [[ $platform == "linux" && $device_proc != 4 ]]; then
        error_msg+=$'\n* Unfortunately, success rates for checkm8 are low on Linux.'
        error_msg+=$'\n* Pwning with a Mac or another iOS device using iPwnder Lite are better options.'
    fi
    error_msg+=$'\n* For more details, read the "Troubleshooting" wiki page in GitHub'
    error_msg+=$'\n* Troubleshooting links:
    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting
    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Pwning-Using-Another-iOS-Device'
    error "Failed to enter pwnDFU mode. Please run the script again." "$error_msg"
}

device_ipwndfu() {
    local tool_pwned=0
    local mac_ver=0
    local python2=$(which python2 2>/dev/null)
    local pyenv=$(which pyenv 2>/dev/null)
    local pyenv2="$HOME/.pyenv/versions/2.7.18/bin/python2"

    if [[ -z $pyenv && -e "$HOME/.pyenv/bin/pyenv" ]]; then
        pyenv="$HOME/.pyenv/bin/pyenv"
    fi
    if [[ $platform == "macos" ]]; then
        mac_ver=$(echo "$platform_ver" | cut -c -2)
    fi
    if [[ $platform == "macos" ]] && (( mac_ver < 12 )); then
        python2=/usr/bin/python
    elif [[ -z $python2 && ! -e $pyenv2 ]]; then
        warn "python2 is not installed. Attempting to install python2 before continuing"
        print "* You may install python2 from pyenv: pyenv install 2.7.18"
        if [[ -z $pyenv ]]; then
            warn "pyenv is not installed. Attempting to install pyenv before continuing"
            print "* You may install pyenv by running: curl https://pyenv.run | bash"
            log "Installing pyenv"
            curl https://pyenv.run | bash
            pyenv="$HOME/.pyenv/bin/pyenv"
            if [[ ! -e $pyenv ]]; then
                error "Cannot detect python2 from pyenv, its installation may have failed." \
                "* Also try installing pyenv and python2 manually before retrying."
            fi
        fi
        log "Installing python2 using pyenv"
        print "* This may take a while, but should not take longer than a few minutes."
        $pyenv install 2.7.18
        if [[ ! -e $pyenv2 ]]; then
            warn "Cannot detect python2 from pyenv, its installation may have failed."
            print "* Try installing pyenv and python2 manually:"
            print "    > curl https://pyenv.run | bash"
            print "    > ~/.pyenv/bin/pyenv install 2.7.18"
            error "Cannot detect python2 for ipwndfu, cannot continue."
        fi
    fi
    if [[ -e $pyenv2 ]]; then
        log "python2 from pyenv detected"
        python2=
        if [[ $device_sudoloop == 1 ]]; then
            python2="sudo "
        fi
        python2+="$pyenv2"
    fi

    if [[ $1 == "send_ibss" ]]; then
        patch_ibss
        cp pwnediBSS ../resources/ipwndfu/
    fi

    device_enter_mode DFU
    if [[ ! -d ../resources/ipwndfu ]]; then
        download_file https://github.com/LukeZGD/ipwndfu/archive/0883efd7de10e806e8d5e3d825950b04bb5a12b7.zip ipwndfu.zip 1f5dd30102b968ceb1f8ed361b265011e6daed98
        unzip -q ipwndfu.zip -d ../resources
        mv ../resources/ipwndfu*/ ../resources/ipwndfu/
    fi

    pushd ../resources/ipwndfu/ >/dev/null
    case $1 in
        "send_ibss" )
            log "Sending iBSS..."
            $python2 ipwndfu -l pwnediBSS
            tool_pwned=$?
            rm pwnediBSS
            if [[ $tool_pwned != 0 ]]; then
                popd >/dev/null
                error "Failed to send iBSS. Your device has likely failed to enter PWNED DFU mode." \
                "* Please exit DFU and (re-)enter PWNED DFU mode before retrying."
            fi
        ;;

        "pwn" )
            log "Placing device to pwnDFU Mode using ipwndfu"
            $python2 ipwndfu -p
            tool_pwned=$?
            if [[ $tool_pwned != 0 ]]; then
                device_pwnerror
            fi
        ;;

        "rmsigchks" )
            log "Running rmsigchks..."
            $python2 rmsigchks.py
        ;;

        "alloc8" )
            if [[ ! -s n88ap-iBSS-4.3.5.img3 ]]; then
                log "Downloading iOS 4.3.5 iBSS"
                "../$dir/pzb" -g "Firmware/dfu/iBSS.n88ap.RELEASE.dfu" -o n88ap-iBSS-4.3.5.img3 http://appldnld.apple.com/iPhone4/041-1965.20110721.gxUB5/iPhone2,1_4.3.5_8L1_Restore.ipsw
            fi
            log "Installing alloc8 to device"
            $python2 ipwndfu -x
        ;;
    esac
    popd >/dev/null
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
    # check and download keys for device_target_build, then set the variable device_fw_key (or device_fw_key_base)
    local key
    local build="$device_target_build"
    if [[ $1 == "base" ]]; then
        build="$device_base_build"
    elif [[ $1 == "temp" ]]; then
        build="$2"
    fi
    local keys_path="$device_fw_dir/$build"

    log "Checking firmware keys in $keys_path"
    if [[ -e "$keys_path/index.html" ]]; then
        if [[ $(cat "$keys_path/index.html" | grep -c "$build") != 1 ]]; then
            log "Existing firmware keys are not valid. Deleting"
            rm "$keys_path/index.html"
        fi
    fi

    if [[ ! -e "$keys_path/index.html" ]]; then
        log "Getting firmware keys for $device_type-$build"
        mkdir -p "$keys_path" 2>/dev/null
        local try=("https://github.com/LukeZGD/Legacy-iOS-Kit-Keys/raw/master/$device_type/$build/index.html"
                   "https://api.m1sta.xyz/wikiproxy/$device_type/$build"
                   "http://127.0.0.1:8888/firmware/$device_type/$build")
        for i in "${try[@]}"; do
            curl -L $i -o index.html
            if [[ $(cat index.html | grep -c "$build") == 1 ]]; then
                break
            fi
        done
        if [[ $(cat index.html | grep -c "$build") != 1 ]]; then
            error "Failed to download firmware keys."
        fi
        mv index.html "$keys_path/"
    fi
    if [[ $1 == "base" ]]; then
        device_fw_key_base="$(cat $keys_path/index.html)"
    elif [[ $1 == "temp" ]]; then
        device_fw_key_temp="$(cat $keys_path/index.html)"
    else
        device_fw_key="$(cat $keys_path/index.html)"
    fi
}

download_comp() {
    # usage: download_comp [build_id] [comp]
    local build_id="$1"
    local comp="$2"
    local url="$(cat "$device_fw_dir/$build_id/url")"
    if [[ -z $url ]]; then
        log "Getting URL for $device_type-$build_id"
        url=$(curl https://api.ipsw.me/v2.1/$device_type/$build_id/url)
        mkdir $device_fw_dir/$build_id 2>/dev/null
        echo "$url" > $device_fw_dir/$build_id/url
    fi
    download_targetfile="$comp.$device_model"
    if [[ $build_id != "12"* ]]; then
        download_targetfile+="ap"
    fi
    download_targetfile+=".RELEASE"

    if [[ -e "../saved/$device_type/${comp}_$build_id.dfu" ]]; then
        cp "../saved/$device_type/${comp}_$build_id.dfu" ${comp}
    else
        log "Downloading ${comp}..."
        "$dir/pzb" -g "Firmware/dfu/$download_targetfile.dfu" -o ${comp} "$url"
        cp ${comp} "../saved/$device_type/${comp}_$build_id.dfu"
    fi
}

patch_ibss() {
    # creates file pwnediBSS to be sent to device
    local build_id
    case $device_type in
        iPad1,1 | iPod3,1 ) build_id="9B206";;
        iPhone2,1 | iPod4,1 ) build_id="10B500";;
        iPad3,1 | iPhone3,[123] ) build_id="11D257";;
        iPod5,1 ) build_id="10B329";;
        * ) build_id="12H321";;
    esac
    if [[ -n $device_ramdisk_build ]]; then
        build_id="$device_ramdisk_build"
    fi
    download_comp $build_id iBSS
    log "Patching iBSS..."
    if [[ $build_id == "9B206" || $build_id == "10B500" ||
          $device_type == "iPhone3,2" || -n $device_ramdisk_build ]]; then
        device_fw_key_check temp $build_id
        local iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .iv')
        local key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .key')
        "$dir/xpwntool" iBSS iBSS.dec -iv $iv -k $key -decrypt
        "$dir/xpwntool" iBSS.dec iBSS.raw
        "$dir/iBoot32Patcher" iBSS.raw iBSS.patched --rsa
        "$dir/xpwntool" iBSS.patched pwnediBSS -t iBSS.dec
    else
        $bspatch iBSS pwnediBSS "../resources/patch/$download_targetfile.patch"
    fi
    cp pwnediBSS ../saved/$device_type/
    log "Pwned iBSS saved at: saved/$device_type/pwnediBSS"
}

patch_ibec() {
    # creates file pwnediBEC to be sent to device for blob dumping
    local build_id
    case $device_type in
        iPad1,1 | iPod3,1 )
            build_id="9B206";;
        iPhone2,1 | iPod4,1 )
            build_id="10B500";;
        iPad2,[145] | iPad3,[346] | iPhone4,1 | iPhone5,[12] | iPod5,1 )
            build_id="10B329";;
        iPad2,2 | iPhone3,[123] )
            build_id="11D257";;
        iPad2,[367] | iPad3,[25] )
            build_id="12H321";;
        iPad3,1 )
            build_id="10B146";;
        iPhone5,3 )
            build_id="11B511";;
        iPhone5,4 )
            build_id="11B651";;
    esac
    if [[ -n $device_ramdisk_build ]]; then
        build_id="$device_ramdisk_build"
    fi
    download_comp $build_id iBEC
    device_fw_key_check temp $build_id
    local name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .filename')
    local iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .iv')
    local key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .key')
    local address="0x80000000"
    if [[ $device_proc == 4 ]]; then
        address="0x40000000"
    fi
    log "Decrypting iBEC..."
    mv iBEC $name.orig
    "$dir/xpwntool" $name.orig $name.dec -iv $iv -k $key -decrypt
    "$dir/xpwntool" $name.dec $name.raw
    log "Patching iBEC..."
    if [[ $build_id == "9B206" || $build_id == "10B500" ||
          $device_type == "iPhone3,2" || -n $device_ramdisk_build ]]; then
        "$dir/iBoot32Patcher" $name.raw $name.patched --rsa --debug --ticket -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1" -c "go" $address
    else
        $bspatch $name.raw $name.patched "../resources/patch/$download_targetfile.patch"
    fi
    "$dir/xpwntool" $name.patched pwnediBEC -t $name.dec
    rm $name.dec $name.orig $name.raw $name.patched
    cp pwnediBEC ../saved/$device_type/
    log "Pwned iBEC saved at: saved/$device_type/pwnediBEC"
}

ipsw_preference_set() {
    # sets ipsw variables: ipsw_jailbreak, ipsw_memory, ipsw_verbose

    # latest version check
    case $device_latest_vers in
        7.1.2 | 6.1.6 | 5.1.1 | 4.2.1 | 3.1.3 ) ipsw_canjailbreak=1;;
    esac
    if [[ $device_target_vers == "$device_latest_vers" && $ipsw_canjailbreak != 1 ]] || (( device_proc >= 7 )); then
        return
    elif [[ $device_target_vers != "$device_latest_vers" ]]; then
        ipsw_canjailbreak=
    fi
    # target version check
    case $device_target_vers in
        8* | 7* | 6* | 5* ) ipsw_canjailbreak=1;;
    esac
    if [[ $device_target_powder == 1 ]] ||
       [[ $device_type == "iPhone3,1" && $device_target_vers == "4"* && $device_target_vers != "4.2.1" ]]; then
        ipsw_canjailbreak=1
    elif [[ $device_target_other == 1 && $ipsw_canjailbreak != 1 ]]; then
        return
    fi

    if [[ $device_target_vers == "3.1.3" && $device_proc != 1 ]]; then
        #log "Jailbreak Option is always enabled for $device_target_vers"
        ipsw_jailbreak=1
    elif [[ -z $ipsw_jailbreak ]]; then
        input "Jailbreak Option"
        print "* When this option is enabled, your device will be jailbroken on restore."
        print "* I recommend to enable this option to have the jailbreak and Cydia pre-installed."
        print "* This option is enabled by default (Y). Select this option if unsure."
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

    if [[ $ipsw_jailbreak == 1 && -z $ipsw_hacktivate ]] &&
       [[ $device_type == "iPhone1"* || $device_type == "iPhone2,1" ]]; then
        input "Hacktivate Option"
        print "* When this option is enabled, your device will be activated on restore."
        print "* Enable this option if you have no valid SIM card to activate the phone."
        print "* This option is disabled by default (N). Select this option if unsure."
        read -p "$(input 'Enable this option? (y/N): ')" ipsw_hacktivate
        if [[ $ipsw_hacktivate == 'Y' || $ipsw_hacktivate == 'y' ]]; then
            log "Hacktivate option enabled by user."
            ipsw_hacktivate=1
        else
            log "Hacktivate option disabled."
            ipsw_hacktivate=
        fi
        echo
    fi

    if [[ -n $ipsw_memory ]]; then
        :
    elif [[ $device_type == "iPhone2,1" || $device_type == "iPod2,1" || $device_proc == 1 ]] && [[ $device_target_other != 1 ]]; then
        :
    elif [[ $ipsw_jailbreak == 1 || $device_type == "$device_disable_bbupdate" || $device_target_powder == 1 ]] ||
         [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* ]] ||
         [[ $device_type == "iPhone3,1" && $device_target_vers == "4"* ]]; then
        input "Memory Option for creating custom IPSW"
        print "* When this option is enabled, system RAM will be used for the IPSW creation process."
        print "* I recommend to enable this option to speed up creating the custom IPSW."
        print "* However, if you have less than 8 GB of RAM, disable this option."
        print "* This option is enabled by default (Y). Select this option if unsure."
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

    if [[ $device_target_powder == 1 && -z $ipsw_verbose ]]; then
        input "Verbose Boot Option"
        print "* When this option is enabled, the device will have verbose boot on restore."
        print "* This option is enabled by default (Y). Select this option if unsure."
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

    ipsw_custom_set
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

    if [[ $version == "$device_latest_vers" || $version == "4.1" ]]; then
        if [[ $version != "4.1" ]]; then
            build_id="$device_latest_build"
        fi
        buildmanifest="../saved/$device_type/$build_id.plist"
        if [[ ! -e $buildmanifest ]]; then
            if [[ -e "$ipsw_base_path.ipsw" ]]; then
                log "Extracting BuildManifest from $version IPSW..."
                unzip -o -j "$ipsw_base_path.ipsw" BuildManifest.plist -d .
            else
                log "Downloading BuildManifest for $version..."
                "$dir/pzb" -g BuildManifest.plist -o BuildManifest.plist "$(cat "$device_fw_dir/$build_id/url")"
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
    rm -f *.shsh*

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
    local version="$device_target_vers"
    local build_id="$device_target_build"
    local ipsw_dl="$1"
    if [[ ! -e "$ipsw_dl.ipsw" ]]; then
        print "* The script will now proceed to download iOS $version IPSW."
        print "* If you want to download it yourself, here is the link: $(cat $device_fw_dir/$build_id/url)"
        log "Downloading IPSW... (Press Ctrl+C to cancel)"
        curl -L "$(cat $device_fw_dir/$build_id/url)" -o temp.ipsw
        mv temp.ipsw "$ipsw_dl.ipsw"
    fi
    ipsw_verify "$ipsw_dl" "$build_id"
}

ipsw_verify() {
    local ipsw_dl="$1"
    local build_id="$2"
    local IPSWSHA1=$(cat "$device_fw_dir/$build_id/sha1sum" 2>/dev/null)
    if (( device_proc > 7 )); then
        return
    fi
    if [[ -z $IPSWSHA1 ]]; then
        log "Getting SHA1 hash from ipsw.me..."
        IPSWSHA1="$(curl https://api.ipsw.me/v2.1/$device_type/$build_id/sha1sum)"
        mkdir $device_fw_dir/$build_id 2>/dev/null
        echo "$IPSWSHA1" > $device_fw_dir/$build_id/sha1sum
    fi
    log "Verifying $ipsw_dl.ipsw..."
    local IPSWSHA1L=$($sha1sum "${ipsw_dl//\\//}.ipsw" | awk '{print $1}')
    if [[ $IPSWSHA1L != "$IPSWSHA1" ]]; then
        if [[ -z $3 ]]; then
            log "SHA1sum mismatch. Expected $IPSWSHA1, got $IPSWSHA1L"
            warn "Verifying IPSW failed. Your IPSW may be corrupted or incomplete. Make sure to download and select the correct IPSW."
            pause
        fi
        return 1
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

    # this will not be needed if i get my fork(s) of futurerestore compiled on macos
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
    local JBFiles=()
    local JBFiles2=()

    if [[ $ipsw_jailbreak == 1 ]]; then
        if [[ $device_target_vers == "8.4.1" ]]; then
            log "Generating reboot.sh"
            echo '#!/bin/bash' | tee reboot.sh
            echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" | tee -a reboot.sh
            echo "nvram -d boot-partition; nvram -d boot-ramdisk" | tee -a reboot.sh
            echo "/usr/bin/haxx_overwrite --${device_type}_${device_target_build}" | tee -a reboot.sh
            if [[ $ipsw_openssh == 1 ]]; then
                JBFiles=("$jelbrek/sshdeb.tar")
            fi
            JBFiles2=("daibutsu/bin.tar" "daibutsu/untether.tar" "freeze.tar")
            for i in {0..2}; do
                cp $jelbrek/${JBFiles2[$i]} .
            done
            cp -R ../resources/firmware/JailbreakBundles FirmwareBundles
            ExtraArgs+="-daibutsu" # use daibutsuCFW
        else
            JBFiles+=("fstab_rw.tar" "freeze.tar")
            case $device_target_vers in
                "6.1.3" ) JBFiles+=("p0sixspwn.tar");;
                "4.3"* )  JBFiles+=("unthredeh4il.tar");;
                "4"* )    JBFiles=("fstab_new.tar" "freeze.tar" "greenpois0n/${device_type}_${device_target_build}.tar");;
            esac
            for i in {0..2}; do
                JBFiles[i]=$jelbrek/${JBFiles[$i]}
            done
            if [[ $ipsw_openssh == 1 ]]; then
                JBFiles+=("$jelbrek/sshdeb.tar")
            fi
            cp -R ../resources/firmware/FirmwareBundles .
            ExtraArgs+="-S 30" # system partition add
        fi
    else
        cp -R ../resources/firmware/FirmwareBundles .
    fi

    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    if [[ $device_use_bb != 0 && $device_type != "$device_disable_bbupdate" && $device_proc != 4 ]]; then
        ExtraArgs+=" -bbupdate"
    elif [[ $device_type == "$device_disable_bbupdate" && $device_type == "iPhone"* ]]; then
        device_dump baseband
        ExtraArgs+=" ../saved/$device_type/baseband.tar"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation.tar"
    fi
    log "Preparing custom IPSW: $ipsw $ipsw_path.ipsw temp.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/ipsw" "$ipsw_path.ipsw" temp.ipsw $ExtraArgs ${JBFiles[@]}

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
        *"KernelCache" ) getcomp="Kernelcache";;
        "RestoreDeviceTree" ) getcomp="DeviceTree";;
    esac
    local fw_key="$device_fw_key"
    if [[ $2 == "base" ]]; then
        fw_key="$device_fw_key_base"
    fi
    local name=$(echo $fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
    local iv=$(echo $fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
    local key=$(echo $fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')

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

        "KernelCache" )
            if [[ $vers != "5"* ]]; then
                echo -e "<key>$comp</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string><key>Patch</key><true/>" >> $NewPlist
            fi
        ;;
    esac
    if [[ $comp == "KernelCache" && $vers == "5"* ]]; then
        return
    fi
    echo -e "<key>Decrypt</key><true/></dict>" >> $NewPlist
}

ipsw_prepare_32bit_paths() {
    local comp="$1"
    local getcomp="$1"
    case $comp in
        "BatteryPlugin" ) getcomp="GlyphPlugin";;
        "NewAppleLogo" ) getcomp="AppleLogo";;
        "NewRecoveryMode" ) getcomp="RecoveryMode";;
        "NewiBoot" ) getcomp="iBoot";;
    esac
    local fw_key="$device_fw_key"
    if [[ $2 == "base" ]]; then
        fw_key="$device_fw_key_base"
    fi
    local name=$(echo $fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
    local str="<key>$comp</key><dict><key>File</key><string>Firmware/all_flash/all_flash.${device_model}ap.production/"
    local str2
    if [[ $2 == "target" ]]; then
        case $comp in
            "AppleLogo" ) str2="${name/applelogo/applelogo7}";;
            "RecoveryMode" ) str2="${name/recoverymode/recoverymode7}";;
            "NewiBoot" ) str2="${name/iBoot/iBoot$(echo $device_target_vers | cut -c 1)}";;
        esac
        case $comp in
            "AppleLogo" | "RecoveryMode" | "NewiBoot" )
                str+="$str2"
                echo "$str2" >> $FirmwareBundle/manifest
            ;;
            "manifest" ) str+="manifest";;
            * ) str+="$name";;
        esac
    else
        str+="$name"
    fi
    str+="</string>"

    if [[ $comp == "NewiBoot" ]]; then
        local iv=$(echo $fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
        local key=$(echo $fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')
        str+="<key>IV</key><string>$iv</string><key>Key</key><string>$key</string>"
    elif [[ $comp == "manifest" ]]; then
        str+="<key>manifest</key><string>manifest</string>"
    fi

    echo -e "$str</dict>" >> $NewPlist
}

ipsw_prepare_config() {
    # usage: ipsw_prepare_config [jailbreak (true/false)] [needpref (true/false)]
    # creates config file to FirmwareBundles/config.plist
    local verbose="false"
    if [[ $ipsw_verbose == 1 ]]; then
        verbose="true"
    fi
    log "Preparing config file"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
	<key>FilesystemJailbreak</key>
	<$1/>
	<key>needPref</key>
	<$2/>
	<key>iBootPatches</key>
	<dict>
		<key>debugEnabled</key>
		<false/>
		<key>bootArgsInjection</key>
		<$verbose/>
		<key>bootArgsString</key>
		<string>-v</string>
	</dict>
</dict>
</plist>" | tee FirmwareBundles/config.plist
}

ipsw_prepare_bundle() {
    device_fw_key_check $1
    local ipsw_p="$ipsw_path"
    local key="$device_fw_key"
    local vers="$device_target_vers"
    local build="$device_target_build"
    local hw="$device_model"
    local base_build="11D257"
    local RootSize
    FirmwareBundle="FirmwareBundles/"

    mkdir FirmwareBundles 2>/dev/null
    if [[ $1 == "base" ]]; then
        ipsw_p="$ipsw_base_path"
        key="$device_fw_key_base"
        vers="$device_base_vers"
        build="$device_base_build"
        FirmwareBundle+="BASE_"
    elif [[ $1 == "target" ]]; then
        if [[ $ipsw_jailbreak == 1 && $vers != "5"* ]]; then
            ipsw_prepare_config true true
        else
            ipsw_prepare_config false true
        fi
    elif [[ $ipsw_jailbreak == 1 ]]; then
        ipsw_prepare_config false true
    else
        ipsw_prepare_config false false
    fi
    FirmwareBundle+="${device_type}_${vers}_${build}.bundle"
    local NewPlist=$FirmwareBundle/Info.plist
    mkdir -p $FirmwareBundle

    log "Generating firmware bundle..."
    local IPSWSHA256=$($sha256sum "${ipsw_p//\\//}.ipsw" | awk '{print $1}')
    log "IPSWSHA256: $IPSWSHA256"
    unzip -o -j "$ipsw_p.ipsw" Firmware/all_flash/all_flash.${device_model}ap.production/manifest
    mv manifest $FirmwareBundle/
    local RamdiskName=$(echo "$key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .filename')
    local RamdiskIV=$(echo "$key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .iv')
    local RamdiskKey=$(echo "$key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .key')
    unzip -o -j "$ipsw_p.ipsw" $RamdiskName
    "$dir/xpwntool" $RamdiskName Ramdisk.raw -iv $RamdiskIV -k $RamdiskKey
    "$dir/hfsplus" Ramdisk.raw extract usr/local/share/restore/options.$device_model.plist
    if [[ $platform == "macos" ]]; then
        plutil -extract 'SystemPartitionSize' xml1 options.$device_model.plist -o size
        RootSize=$(cat size | sed -ne '/<integer>/,/<\/integer>/p' | sed -e "s/<integer>//" | sed "s/<\/integer>//" | sed '2d')
    else
        RootSize=$(cat options.$device_model.plist | grep -i SystemPartitionSize -A 1 | grep -oPm1 "(?<=<integer>)[^<]+")
    fi
    RootSize=$((RootSize+30))
    echo -e $'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>' > $NewPlist
    echo -e "<key>Filename</key><string>$ipsw_p.ipsw</string>" >> $NewPlist
    echo -e "<key>RootFilesystem</key><string>$(echo "$key" | $jq -j '.keys[] | select(.image == "RootFS") | .filename')</string>" >> $NewPlist
    echo -e "<key>RootFilesystemKey</key><string>$(echo "$key" | $jq -j '.keys[] | select(.image == "RootFS") | .key')</string>" >> $NewPlist
    echo -e "<key>RootFilesystemSize</key><integer>$RootSize</integer>" >> $NewPlist
    echo -e "<key>RamdiskOptionsPath</key><string>/usr/local/share/restore/options.$device_model.plist</string>" >> $NewPlist
    echo -e "<key>SHA256</key><string>$IPSWSHA256</string>" >> $NewPlist

    if [[ $1 == "base" ]]; then
        case $device_type in
            iPhone5,[12] ) hw="iphone5";;
            iPhone5,[34] ) hw="iphone5b";;
        esac
        case $device_base_build in
            "11A"* | "11B"* ) base_build="11B554a";;
        esac
        echo -e "<key>RamdiskExploit</key><dict>" >> $NewPlist
        echo -e "<key>exploit</key><string>src/target/$hw/$base_build/exploit</string>" >> $NewPlist
        echo -e "<key>inject</key><string>src/target/$hw/$base_build/partition</string></dict>" >> $NewPlist
    elif [[ $1 == "target" && $vers == "5"* ]]; then
        echo -e "<key>FilesystemPackage</key><dict/><key>RamdiskPackage</key><dict><key>package</key><string>src/bin.tar</string><key>ios</key><string>ios5</string></dict>" >> $NewPlist
    elif [[ $1 == "target" ]]; then
        echo -e "<key>FilesystemPackage</key><dict><key>bootstrap</key><string>freeze.tar</string>" >> $NewPlist
        case $vers in
            6* ) echo -e "</dict><key>RamdiskPackage</key><dict><key>package</key><string>src/bin.tar</string><key>ios</key><string>ios6</string></dict>" >> $NewPlist;;
            7* ) error "iOS 7 targets are not supported.";;
            8* | 9* ) printf "<key>package</key><string>src/ios9.tar</string></dict><key>RamdiskPackage</key><dict><key>package</key><string>src/bin.tar</string><key>ios</key><string>ios" >> $NewPlist;;
        esac
        case $vers in
            8* ) echo -e "8</string></dict>" >> $NewPlist;;
            9* ) echo -e "9</string></dict>" >> $NewPlist;;
        esac
    else
        echo -e "<key>FilesystemPackage</key><dict/><key>RamdiskPackage</key><dict/>" >> $NewPlist
    fi

    if [[ $1 == "base" ]]; then
        echo -e "<key>Firmware</key><dict/>" >> $NewPlist
    else
        echo -e "<key>Firmware</key><dict>" >> $NewPlist
        ipsw_prepare_32bit_keys iBSS $1
        ipsw_prepare_32bit_keys iBEC $1
        ipsw_prepare_32bit_keys RestoreRamdisk $1
        ipsw_prepare_32bit_keys RestoreDeviceTree $1
        ipsw_prepare_32bit_keys RestoreLogo $1
        if [[ $1 == "target" ]]; then
            ipsw_prepare_32bit_keys KernelCache $1
        else
            ipsw_prepare_32bit_keys RestoreKernelCache $1
        fi
        echo -e "</dict>" >> $NewPlist
    fi

    if [[ $1 == "base" ]]; then
        echo -e "<key>FirmwarePath</key><dict>" >> $NewPlist
        ipsw_prepare_32bit_paths AppleLogo $1
        ipsw_prepare_32bit_paths BatteryCharging0 $1
        ipsw_prepare_32bit_paths BatteryCharging1 $1
        ipsw_prepare_32bit_paths BatteryFull $1
        ipsw_prepare_32bit_paths BatteryLow0 $1
        ipsw_prepare_32bit_paths BatteryLow1 $1
        ipsw_prepare_32bit_paths BatteryPlugin $1
        ipsw_prepare_32bit_paths RecoveryMode $1
        ipsw_prepare_32bit_paths LLB $1
        ipsw_prepare_32bit_paths iBoot $1
        echo -e "</dict>" >> $NewPlist
    elif [[ $1 == "target" ]]; then
        echo -e "<key>FirmwareReplace</key><dict>" >> $NewPlist
        ipsw_prepare_32bit_paths AppleLogo $1
        ipsw_prepare_32bit_paths NewAppleLogo $1
        ipsw_prepare_32bit_paths BatteryCharging0 $1
        ipsw_prepare_32bit_paths BatteryCharging1 $1
        ipsw_prepare_32bit_paths BatteryFull $1
        ipsw_prepare_32bit_paths BatteryLow0 $1
        ipsw_prepare_32bit_paths BatteryLow1 $1
        ipsw_prepare_32bit_paths BatteryPlugin $1
        ipsw_prepare_32bit_paths RecoveryMode $1
        ipsw_prepare_32bit_paths NewRecoveryMode $1
        ipsw_prepare_32bit_paths LLB $1
        ipsw_prepare_32bit_paths iBoot $1
        ipsw_prepare_32bit_paths NewiBoot $1
        ipsw_prepare_32bit_paths manifest $1
        echo -e "</dict>" >> $NewPlist
    elif [[ $1 == "daibutsu" ]]; then
        echo -e "<key>RamdiskPackage2</key><string>./bin.tar</string><key>RamdiskReboot</key><string>./reboot.sh</string><key>UntetherPath</key><string>./untether.tar</string>" >> $NewPlist
        local hwmodel="$(tr '[:lower:]' '[:upper:]' <<< ${device_model:0:1})${device_model:1}"
        echo -e "<key>hwmodel</key><string>$hwmodel</string>" >> $NewPlist
    fi

    echo -e "</dict></plist>" >> $NewPlist
    cat $NewPlist
}

ipsw_prepare_32bit() {
    local ExtraArgs
    local daibutsu
    local JBFiles=()
    if [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
        if [[ $device_type == "iPad2"* || $device_type == "iPhone3,1" ]]; then
            ipsw_prepare_jailbreak
        elif [[ $ipsw_jailbreak == 1 ]]; then
            ipsw_prepare_custom
        fi
        return
    elif [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    elif [[ $device_type != "$device_disable_bbupdate" && $ipsw_jailbreak != 1 &&
            $device_proc != 4 && $device_actrec != 1 ]]; then
        log "No need to create custom IPSW for non-jailbroken restores on $device_type-$device_target_build"
        return
    elif [[ $ipsw_jailbreak == 1 && $device_target_vers == "8"* ]]; then
        daibutsu="daibutsu"
        ExtraArgs+=" -daibutsu"
        cp $jelbrek/daibutsu/bin.tar $jelbrek/daibutsu/untether.tar .
        log "Generating reboot.sh"
        echo '#!/bin/bash' | tee reboot.sh
        echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" | tee -a reboot.sh
        echo "nvram -d boot-partition; nvram -d boot-ramdisk" | tee -a reboot.sh
        echo "/usr/bin/haxx_overwrite --${device_type}_${device_target_build}" | tee -a reboot.sh
    fi

    ipsw_prepare_bundle $daibutsu

    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    if [[ $device_use_bb != 0 && $device_type != "$device_disable_bbupdate" && $device_proc != 4 ]]; then
        ExtraArgs+=" -bbupdate"
    elif [[ $device_type == "$device_disable_bbupdate" && $device_type == "iPhone"* ]]; then
        device_dump baseband
        ExtraArgs+=" ../saved/$device_type/baseband.tar"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation.tar"
    fi
    if [[ $ipsw_jailbreak == 1 ]]; then
        case $device_target_vers in
            7.1* )       JBFiles+=("panguaxe.tar");;
            7* )         JBFiles+=("evasi0n7-untether.tar");;
            6.1.[3456] ) JBFiles+=("p0sixspwn.tar");;
            6* )         JBFiles+=("evasi0n6-untether.tar");;
            5* )         JBFiles+=("pris0nbarake/tar-${device_model}_$device_target_build.tar")
            ;;
        esac
        case $device_target_vers in
            8* ) JBFiles+=("fstab8.tar");;
            7* ) JBFiles+=("fstab7.tar");;
            * )  JBFiles+=("fstab_rw.tar");;
        esac
        JBFiles+=("freeze.tar")
        for i in {0..2}; do
            JBFiles[i]=$jelbrek/${JBFiles[$i]}
        done
        case $device_target_vers in
            5.1.1 ) JBFiles+=("$jelbrek/rockyracoon.tar");;
            5.0.1 ) JBFiles+=("$jelbrek/corona.tar");;
            5.0 )
                if [[ $device_type == "iPhone4,1" ]]; then
                    JBFiles+=("$jelbrek/corona.tar")
                fi
            ;;
        esac
        if [[ $device_target_vers == "5"* ]]; then
            JBFiles+=("$jelbrek/cydiasubstrate.tar")
        fi
        if [[ $ipsw_openssh == 1 ]]; then
            JBFiles+=("$jelbrek/sshdeb.tar")
        fi
    fi
    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_powder() {
    local ExtraArgs
    local ExtraArgs2="--logo4 "
    local IV
    local JBFiles=()
    local Key

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $ipsw_jailbreak == 1 ]]; then
        if [[ $device_target_vers == "4"* || $device_target_vers == "5"* ]]; then
            if [[ $device_target_vers == "5"* ]]; then
                JBFiles=("pris0nbarake/tar-${device_model}_$device_target_build.tar")
            else
                JBFiles=("unthredeh4il.tar")
            fi
            JBFiles+=("fstab_rw.tar" "freeze.tar")
            for i in {0..2}; do
                JBFiles[i]=$jelbrek/${JBFiles[$i]}
            done
            case $device_target_vers in
                5.1.1 ) JBFiles+=("$jelbrek/rockyracoon.tar");;
                5.0.1 ) JBFiles+=("$jelbrek/corona.tar");;
            esac
            JBFiles+=("$jelbrek/cydiasubstrate.tar")
        fi
        if [[ $ipsw_openssh == 1 ]]; then
            JBFiles+=("$jelbrek/sshdeb.tar")
        fi
        cp $jelbrek/freeze.tar .
    fi

    cp -R ../resources/firmware/powdersn0wBundles ./FirmwareBundles
    cp -R ../resources/firmware/src .
    if [[ $device_target_vers == "4.3"* ]]; then
        ExtraArgs+="-apticket $shsh_path"
    fi
    if [[ $ipsw_jailbreak == 1 && $device_target_vers == "6"* ]]; then
        ipsw_prepare_config true true
    else
        ipsw_prepare_config false true
    fi
    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation.tar"
    fi
    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw -base $ipsw_base_path.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw -base "$ipsw_base_path.ipsw" $ExtraArgs ${JBFiles[@]}

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
        mv iBoot.n90ap.RELEASE.img3 ibot
        "$dir/xpwntool" ibot ibot.dec -iv $IV -k $Key
        "$dir/iBoot32Patcher" ibot.dec ibot.pwned --rsa --boot-partition --boot-ramdisk $ExtraArgs2
        "$dir/xpwntool" ibot.pwned iBoot -t ibot
        rm ibot*
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

ipsw_prepare_powder2() {
    local ExtraArgs
    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    ipsw_prepare_bundle target
    ipsw_prepare_bundle base
    cp -R ../resources/firmware/src .
    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    if [[ $device_use_bb != 0 && $device_type != "$device_disable_bbupdate" && $device_proc != 4 ]]; then
        ExtraArgs+=" -bbupdate"
    elif [[ $device_type == "$device_disable_bbupdate" && $device_type == "iPhone"* ]]; then
        device_dump baseband
        ExtraArgs+=" ../saved/$device_type/baseband.tar"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation.tar"
    fi
    if [[ $ipsw_jailbreak == 1 ]]; then
        cp $jelbrek/freeze.tar .
        if [[ $device_target_vers == "5"* ]]; then
            ExtraArgs+=" $jelbrek/cydiasubstrate.tar"
        fi
        if [[ $ipsw_openssh == 1 ]]; then
            ExtraArgs+=" $jelbrek/sshdeb.tar"
        fi
    fi
    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw -base $ipsw_base_path.ipsw $ExtraArgs"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw -base "$ipsw_base_path.ipsw" $ExtraArgs

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_custom() {
    local comps=("iBSS" "RestoreRamdisk")
    local name
    local iv
    local key
    local path
    local url
    local decrypt
    local patch="../resources/patch/old/$device_type/$device_target_vers"
    local RootSize

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    elif [[ $device_target_vers == "4.1" && $ipsw_jailbreak != 1 ]]; then
        log "No need to create custom IPSW for non-jailbroken restores on $device_type-$device_target_build"
        return
    fi

    if [[ $device_target_vers == "5"* || $device_target_vers == "6"* ]]; then
        comps+=("iBEC")
    fi
    if [[ $device_type == "iPod2,1" && $device_target_vers == "3.1.3" ]]; then
        :
    elif [[ $device_proc == 1 ]]; then
        comps+=("iBoot" "Kernelcache" "LLB")
    else
        case $device_target_vers in
            6.1.6 | 4.2.1 | 4.1 ) :;;
            * ) comps+=("iBoot" "Kernelcache" "LLB");;
        esac
    fi

    ipsw_extract
    device_fw_key_check
    url=$(cat "$device_fw_dir/$device_target_build/url" 2>/dev/null)
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "iBoot" | "LLB" ) path="Firmware/all_flash/all_flash.${device_model}ap.production/";;
            * ) path="";;
        esac
        if [[ -n $iv && -n $key ]]; then
            decrypt="-iv $iv -k $key"
        fi
        if [[ -z $name ]]; then
            case $getcomp in
                "iBSS" ) name="iBSS.${device_model}ap.RELEASE.dfu";;
                "LLB" )  name="LLB.${device_model}ap.RELEASE.img3";;
            esac
        fi

        log "Patching $getcomp: $name"
        cp "$ipsw_path/${path}$name" .
        mv $name $name.orig
        if [[ $getcomp == "iBoot" || $getcomp == "LLB" ]]; then
            $bspatch $name.orig $name $patch/$name.patch
        else
            "$dir/xpwntool" $name.orig $name.dec $decrypt
            if [[ $getcomp == "RestoreRamdisk" ]]; then
                cp $name.dec Ramdisk.raw
            fi
            $bspatch $name.dec $name.patched $patch/$name.patch
            if [[ $getcomp == "Kernelcache" ]]; then
                "$dir/xpwntool" $name.patched $name -t $name.orig $decrypt
            else
                "$dir/xpwntool" $name.patched $name -t $name.orig
            fi
        fi
        cp $name "$ipsw_path/$path"
    done
    if [[ $device_proc == 1 ]]; then
        local path="Firmware/dfu/"
        local name="WTF.s5l8900xall.RELEASE.dfu"
        log "Patching WTF: $name"
        cp "$ipsw_path/${path}$name" .
        mv $name $name.orig
        $bspatch $name.orig $name $patch/$name.patch
        cp $name "$ipsw_path/$path"
    fi

    log "Getting RootFS information"
    "$dir/hfsplus" Ramdisk.raw extract usr/local/share/restore/options.$device_model.plist >/dev/null
    if [[ ! -s options.$device_model.plist ]]; then
        rm options.$device_model.plist
        "$dir/hfsplus" Ramdisk.raw extract usr/local/share/restore/options.plist
        mv options.plist options.$device_model.plist
    fi
    if [[ $device_target_vers == "3"* ]]; then
        case $device_type in
            iPhone1,[12] ) RootSize=420;;
            iPhone2,1 )    RootSize=530;;
            iPod1,1 )      RootSize=413;;
            iPod2,1 )      RootSize=450;;
        esac
    elif [[ $platform == "macos" ]]; then
        plutil -extract 'SystemPartitionSize' xml1 options.$device_model.plist -o size
        RootSize=$(cat size | sed -ne '/<integer>/,/<\/integer>/p' | sed -e "s/<integer>//" | sed "s/<\/integer>//" | sed '2d')
    else
        RootSize=$(cat options.$device_model.plist | grep -i SystemPartitionSize -A 1 | grep -oPm1 "(?<=<integer>)[^<]+")
    fi
    RootSize=$((RootSize+30))
    RootSize=$((RootSize*1024*1024))
    local RootName=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image == "RootFS") | .filename')
    local RootKey=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image == "RootFS") | .key')
    log "RootFS Name: $RootName"
    log "RootFS Key: $RootKey"
    log "RootFS Size: $RootSize"
    log "Copying RootFS"
    cp "$ipsw_path/$RootName" .
    log "Decrypting RootFS"
    "$dir/dmg" extract $RootName out.dmg -k $RootKey
    "$dir/hfsplus" out.dmg grow $RootSize
    if [[ $ipsw_jailbreak == 1 ]]; then
        log "Extracting Cydia"
        "$dir/hfsplus" out.dmg untar $jelbrek/freeze.tar
        log "Extracting untether"
        case $device_target_vers in
            "6.1.6" ) "$dir/hfsplus" out.dmg untar $jelbrek/p0sixspwn.tar;;
            "5"* | "4.3"* ) "$dir/hfsplus" out.dmg untar $jelbrek/unthredeh4il.tar;;
            "4.2.1" )
                if [[ $device_proc != 1 ]]; then
                    "$dir/hfsplus" out.dmg mv sbin/launchd sbin/punchd
                    "$dir/hfsplus" out.dmg untar $jelbrek/greenpois0n/${device_type}_${device_target_build}.tar
                fi
            ;;
            "4.1" ) "$dir/hfsplus" out.dmg untar $jelbrek/greenpois0n/${device_type}_${device_target_build}.tar;;
        esac
        case $device_target_vers in
            "5.1.1" ) "$dir/hfsplus" out.dmg untar $jelbrek/rockyracoon.tar;;
            "5.0.1" ) "$dir/hfsplus" out.dmg untar $jelbrek/corona.tar;;
            "4"* | "3.1.3" )
                "$dir/hfsplus" out.dmg rm private/etc/fstab
                "$dir/hfsplus" out.dmg add $jelbrek/fstab_old private/etc/fstab
            ;;
        esac
        if [[ $device_type == "iPod2,1" && $device_target_vers == "3.1.3" ]]; then
            "$dir/hfsplus" out.dmg untar $jelbrek/greenpois0n/${device_type}_${device_target_build}.tar
        fi
        if [[ $device_target_vers != "6"* ]]; then
            "$dir/hfsplus" out.dmg untar $jelbrek/cydiasubstrate.tar
        fi
        if [[ $device_target_vers == "3.1.3" ]]; then
            "$dir/hfsplus" out.dmg untar $jelbrek/cydiahttpatch.tar
        fi
        if [[ $ipsw_openssh == 1 ]]; then
            "$dir/hfsplus" out.dmg untar $jelbrek/sshdeb.tar
        fi
        if [[ $ipsw_hacktivate == 1 ]]; then
            log "Patching lockdownd for hacktivation"
            "$dir/hfsplus" out.dmg extract usr/libexec/lockdownd
            "$dir/hfsplus" out.dmg mv usr/libexec/lockdownd usr/libexec/lockdownd.orig
            $bspatch lockdownd lockdownd.patched $patch/lockdownd.patch
            "$dir/hfsplus" out.dmg add lockdownd.patched usr/libexec/lockdownd
            "$dir/hfsplus" out.dmg chmod 100755 usr/libexec/lockdownd
        fi
    fi
    rm $RootName
    log "Building RootFS"
    "$dir/dmg" build out.dmg $RootName
    cp $RootName "$ipsw_path"

    log "Building IPSW"
    mv "$ipsw_path" "$ipsw_custom"
    pushd "$ipsw_custom" >/dev/null
    case $device_target_vers in
        6.1.6 | 4.2.1 | 4.1 ) :;;
        * ) rm BuildManifest.plist;;
    esac
    zip -r0 ../tmp/temp.ipsw *
    popd >/dev/null

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again"
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
    local restore_baseband_check
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
            "$dir/pzb" -g BuildManifest.plist -o $build_id.plist "$(cat $device_fw_dir/$build_id/url)"
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
        restore_baseband_check="../saved/baseband/$restore_baseband"
        if [[ $restore_baseband == "Mav5-11.80.00.Release.bbfw" ]]; then
            restore_baseband_check="../saved/baseband/Mav5-11.80.00.Release_${baseband_sha1}.bbfw"
        fi
        if [[ -e $restore_baseband_check ]]; then
            if [[ $baseband_sha1 != "$($sha1sum $restore_baseband_check | awk '{print $1}')" ]]; then
                rm $restore_baseband_check
            fi
        fi
        if [[ ! -e $restore_baseband_check ]]; then
            log "Downloading $build_id Baseband"
            "$dir/pzb" -g Firmware/$restore_baseband -o $restore_baseband "$(cat $device_fw_dir/$build_id/url)"
            if [[ $baseband_sha1 != "$($sha1sum $restore_baseband | awk '{print $1}')" ]]; then
                error "Downloading/verifying baseband failed. Please run the script again"
            fi
            mv $restore_baseband $restore_baseband_check
        fi
        cp $restore_baseband_check tmp/bbfw.tmp
        if [[ $? != 0 ]]; then
            rm $restore_baseband_check
            error "An error occurred copying baseband. Please run the script again"
        fi
        log "Baseband: $restore_baseband_check"
        restore_baseband="tmp/bbfw.tmp"
    fi

    # SEP
    if (( device_proc >= 7 )); then
        restore_sep="sep-firmware.$device_model.RELEASE"
        if [[ ! -e ../saved/$device_type/$restore_sep-$build_id.im4p ]]; then
            log "Downloading $build_id SEP"
            "$dir/pzb" -g Firmware/all_flash/$restore_sep.im4p -o $restore_sep.im4p "$(cat $device_fw_dir/$build_id/url)"
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
    local ExtraArgs="-ew"
    local idevicerestore2="$idevicerestore"
    local re

    mkdir shsh
    cp "$shsh_path" shsh/$device_ecid-$device_type-$device_target_vers.shsh
    if [[ $device_use_bb == 0 ]]; then
        log "Device $device_type has no baseband/disabled baseband update"
    elif [[ $device_proc != 4 ]]; then
        restore_download_bbsep
        ExtraArgs="-r"
        idevicerestore2="$idevicererestore"
        re="re"
    fi
    ipsw_extract custom
    if [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* ]]; then
        ExtraArgs="-e"
        log "Sending iBEC..."
        $irecovery -f $ipsw_custom/Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu
        device_find_mode Recovery
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArgs+="d"
    fi

    log "Running idevicere${re}store with command: $idevicerestore2 $ExtraArgs \"$ipsw_custom.ipsw\""
    $idevicerestore2 $ExtraArgs "$ipsw_custom.ipsw"
    opt=$?
    echo
    log "Restoring done! Read the message below if any error has occurred:"
    case $device_target_vers in
        1* | 2* | 3* | 4* ) print "* For device activation, go to: Other Utilities -> Attempt Activation";;
    esac
    if [[ $opt != 0 ]]; then
        print "* If you are getting the error \"could not retrieve device serial number\":"
        print " -> This means that your device is not compatible with $device_target_vers"
        print "* If the restore failed on updating baseband:"
        print " -> Try disabling baseband update: ./restore.sh --disable-bbupdate"
        echo
    fi
    print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
    print "* Your problem may have already been addressed within the wiki page."
    print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    if [[ $ipsw_jailbreak == 1 ]]; then
        case $device_target_vers in
            5* | 4* | 3* ) warn "Do not update Cydia Substrate and Substrate Safe Mode in Cydia!";;
        esac
    fi
}

restore_futurerestore() {
    local ExtraArr=()
    local futurerestore2="$futurerestore"
    local mac_ver=0
    local port=8888

    if [[ $1 == "--use-pwndfu" ]]; then
        if [[ $platform == "macos" ]]; then
            mac_ver=$(echo "$platform_ver" | cut -c -2)
        fi
        log "Starting local server for firmware keys"
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
            $(which python3) -m http.server -b 127.0.0.1 $port &
            httpserver_pid=$!
        fi
        popd >/dev/null
        sleep 1
    fi

    restore_download_bbsep
    # baseband args
    if [[ $restore_baseband == 0 ]]; then
        ExtraArr+=("--no-baseband")
    else
        ExtraArr+=("-b" "$restore_baseband" "-p" "$restore_manifest")
    fi
    if [[ -n $restore_sep ]]; then
        # sep args for 64bit
        ExtraArr+=("-s" "$restore_sep" "-m" "$restore_manifest")
    fi
    if [[ -n "$1" ]]; then
        # custom arg, either --use-pwndfu or --skip-blob
        ExtraArr+=("$1")
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArr+=("-d")
    fi
    if (( device_proc < 7 )); then
        futurerestore2+="_old"
    elif [[ $device_latest_vers == "15"* ]]; then
        :
    else
        futurerestore2+="_new"
    fi
    if [[ $platform == "macos" && $device_target_other != 1 &&
          $device_target_vers == "10.3.3" && $device_proc == 7 ]]; then
        ipsw_path="$ipsw_custom"
    fi
    ExtraArr+=("-t" "$shsh_path" "$ipsw_path.ipsw")
    ipsw_extract

    log "Running futurerestore with command: $futurerestore2 ${ExtraArr[*]}"
    $futurerestore2 "${ExtraArr[@]}"
    opt=$?
    log "Restoring done! Read the message below if any error has occurred:"
    if [[ $opt != 0 ]]; then
        print "* If you are getting the error: \"could not retrieve device serial number\","
        print " -> This means that your device is not compatible with $device_target_vers"
    fi
    print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
    print "* Your problem may have already been addressed within the wiki page."
    print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    kill $httpserver_pid
}

restore_latest() {
    local idevicerestore2="$idevicerestore"
    local ExtraArgs="-e"
    if [[ $1 == "custom" ]]; then
        ExtraArgs+="c"
        ipsw_path="$ipsw_custom"
        ipsw_extract custom
    else
        ipsw_extract
    fi
    log "Running idevicerestore with command: $idevicerestore2 $ExtraArgs \"$ipsw_path.ipsw\""
    $idevicerestore2 $ExtraArgs "$ipsw_path.ipsw"
    opt=$?
    if [[ $1 == "custom" ]]; then
        log "Restoring done! Read the message below if any error has occurred:"
        if [[ $opt != 0 ]]; then
            print "* If you are getting the error \"unable to find AppleNANDFTL\":"
            print " -> This means that your device is not compatible with $device_target_vers"
        fi
        print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
        print "* Your problem may have already been addressed within the wiki page."
        print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    fi
    case $device_target_vers in
        1* | 2* | 3* | 4* ) print "* For device activation, go to: Other Utilities -> Attempt Activation";;
    esac
    if [[ $ipsw_jailbreak == 1 ]]; then
        case $device_target_vers in
            5* | 4* | 3* ) warn "Do not update Cydia Substrate and Substrate Safe Mode in Cydia!";;
        esac
    fi
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
        error "Failed to enter pwnREC mode. You might have to force restart your device and start over entering pwnDFU mode again"
    fi
    shsh_save apnonce $($irecovery -q | grep "NONC" | cut -c 7-)
}

device_buttons() {
    local opt
    if [[ $device_mode != "Normal" ]]; then
        device_enter_mode pwnDFU
        return
    fi
    print "* This device needs to be in pwnDFU/kDFU mode before proceeding."
    print "* Select Y for pwnDFU mode, N for kDFU mode. Select Y if unsure."
    read -p "$(input 'Are both your home and power buttons working properly? (Y/n): ')" opt
    if [[ $opt != 'N' && $opt != 'n' ]]; then
        device_enter_mode pwnDFU
    else
        device_enter_mode kDFU
    fi
}

restore_prepare() {
    case $device_proc in
        1 )
            device_enter_mode DFU
            if [[ $ipsw_jailbreak == 1 ]]; then
                restore_latest custom
            else
                restore_latest
            fi
        ;;

        4 )
            if [[ $device_target_other == 1 ]] && [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
                if [[ $device_type == "iPhone3,1" ]]; then
                    device_enter_mode pwnDFU
                else
                    ipsw_custom="../${device_type}_${device_target_vers}_${device_target_build}_Restore"
                    device_enter_mode DFU
                fi
                restore_idevicerestore
                if [[ $device_type == "iPhone2,1" ]]; then
                    log "Ignore the baseband error and do not disconnect your device yet"
                    device_find_mode Recovery
                    log "Attempting to exit recovery mode"
                    $irecovery -n
                    log "Done, your device should boot now"
                fi
            elif [[ $device_target_other == 1 ]]; then
                device_buttons
                restore_idevicerestore
            elif [[ $device_target_vers == "4.1" && $ipsw_jailbreak != 1 ]]; then
                device_enter_mode DFU
                restore_latest
                if [[ $device_type == "iPhone2,1" ]]; then
                    log "Ignore the baseband error and do not disconnect your device yet"
                    device_find_mode Recovery
                    log "Attempting to exit recovery mode"
                    $irecovery -n
                    log "Done, your device should boot now"
                fi
            elif [[ $device_target_vers == "4.1" || $device_target_vers == "$device_latest_vers" ]]; then
                if [[ $ipsw_jailbreak == 1 ]]; then
                    shsh_save version $device_target_vers
                    device_enter_mode pwnDFU
                    restore_idevicerestore
                else
                    restore_latest
                fi
            elif [[ $device_type == "iPhone3,1" || $device_type == "iPhone3,3" ]]; then
                # powdersn0w 4.3.x-6.1.3
                shsh_save version 7.1.2
                if [[ $device_target_powder == 1 && $device_target_vers == "6"* ]]; then
                    device_buttons
                else
                    device_enter_mode pwnDFU
                fi
                restore_idevicerestore
            else
                device_enter_mode pwnDFU
                restore_latest custom
                if [[ $device_type == "iPhone2,1" ]]; then
                    print "* If the restore succeeded but the device does not boot:"
                    print " -> Go to: Other Utilities -> Install alloc8 Exploit"
                fi
            fi
        ;;

        [56] )
            # 32-bit devices A5/A6
            if [[ $device_target_other != 1 && $device_target_powder != 1 ]]; then
                shsh_save
            fi
            if [[ $device_target_vers == "$device_latest_vers" ]]; then
                restore_latest
            else
                if [[ $device_proc == 6 && $platform == "macos" ]]; then
                    device_buttons
                elif [[ $device_target_powder == 1 && $device_target_vers == "5"* ]]; then
                    device_enter_mode pwnDFU
                else
                    device_enter_mode kDFU
                fi
                if [[ $ipsw_jailbreak == 1 || -e "$ipsw_custom.ipsw" ]]; then
                    restore_idevicerestore
                else
                    restore_futurerestore --use-pwndfu
                fi
            fi
        ;;

        [78] )
            if [[ $device_latest_vers == "15"* ]]; then
                :
            elif [[ $device_target_other != 1 && $device_target_vers == "10.3.3" ]]; then
                # A7 devices 10.3.3
                local opt="--skip-blob"
                if [[ $platform == "macos" ]]; then
                    opt=
                fi
                restore_prepare_1033
                restore_futurerestore $opt
            elif [[ $device_target_vers == "$device_latest_vers" ]]; then
                restore_latest
            else
                log "The generator for your SHSH blob is: $shsh_generator"
                print "* Before continuing, make sure to set the nonce generator of your device!"
                print "* For iOS 10 and older: https://github.com/tihmstar/futurerestore#how-to-use"
                print "* For iOS 11 and 12: https://github.com/futurerestore/futurerestore/#using-dimentio"
                pause
                if [[ $device_mode == "Normal" ]]; then
                    device_enter_mode Recovery
                fi
                restore_futurerestore
            fi
        ;;
    esac
    if [[ $device_latest_vers == "15"* ]]; then
        device_enter_mode pwnDFU
        device_fw_key_check
        if [[ ! -s ../resources/firmware.json ]]; then
            log "Downloading firmwares.json from ipsw.me"
            curl -L https://api.ipsw.me/v2.1/firmwares.json/condensed -o firmware.json
            cp firmware.json ../resources/firmware.json
        fi
        restore_futurerestore --use-pwndfu
    fi
}

ipsw_prepare() {
    case $device_proc in
        1 )
            if [[ $ipsw_jailbreak == 1 ]]; then
                ipsw_prepare_custom
            fi
        ;;

        4 )
            if [[ $device_target_other == 1 ]]; then
                ipsw_prepare_32bit
            elif [[ $device_target_vers == "$device_latest_vers" ]]; then
                if [[ $ipsw_jailbreak == 1 && $device_type == "iPhone2,1" ]]; then
                    ipsw_prepare_custom
                elif [[ $ipsw_jailbreak == 1 ]]; then
                    ipsw_prepare_32bit
                fi
            elif [[ $device_type == "iPhone3,1" ]]; then
                # powdersn0w 4.3.x-6.1.3
                if [[ $device_target_vers == "4.3"* ]]; then
                    shsh_save version 7.1.2
                fi
                ipsw_prepare_powder
            elif [[ $device_type == "iPhone3,3" ]]; then
                ipsw_prepare_powder2
            else
                ipsw_prepare_custom
            fi
        ;;

        [56] )
            # 32-bit devices A5/A6
            if [[ $device_target_powder == 1 ]]; then
                ipsw_prepare_powder2
            elif [[ $ipsw_jailbreak == 1 && $device_target_other != 1 ]]; then
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
    local selected
    input "Select option:"
    select opt in "Disable exploit" "Enable exploit" "Go Back"; do
        selected="$opt"
        break
    done
    case $selected in
        "Disable exploit" ) rec=0;;
        "Enable exploit" ) rec=2;;
        * ) return;;
    esac

    if [[ ! -e ../saved/$device_type/iBSS_8L1.dfu ]]; then
        log "Downloading 8L1 iBSS..."
        "$dir/pzb" -g Firmware/dfu/iBSS.n90ap.RELEASE.dfu -o iBSS_8L1.dfu $(cat $device_fw_dir/8L1/url)
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
    print "* Troubleshooting link: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting#clearing-nvram"
}

device_ramdisktar() {
    local target="/mnt1"
    if [[ $2 == "data" ]]; then
        target+="/private/var"
    fi
    log "Sending $1"
    $scp -P 2222 $jelbrek/$1 root@127.0.0.1:$target
    log "Extracting $1"
    $ssh -p 2222 root@127.0.0.1 "tar -xvf $target/$1 -C /mnt1; rm $target/$1"
}

device_ramdisk() {
    local comps=("iBSS" "iBEC" "RestoreRamdisk" "DeviceTree" "AppleLogo" "Kernelcache")
    local name
    local iv
    local key
    local path
    local url
    local decrypt
    local ramdisk_path

    case $device_type in
        iPhone1,[12] | iPod1,1 ) device_target_build="7E18";;
        iPod2,1 ) device_target_build="8C148";;
        iPod3,1 | iPad1,1 ) device_target_build="9B206";;
        iPhone2,1 | iPod4,1 ) device_target_build="10B500";;
        iPhone5,3 ) device_target_build="11B511";;
        iPhone5,4 ) device_target_build="11B651";;
        * ) device_target_build="10B329";;
    esac
    if [[ -n $device_ramdisk_build ]]; then
        device_target_build=$device_ramdisk_build
    fi
    ramdisk_path="../saved/$device_type/ramdisk_$device_target_build"
    device_fw_key_check
    url=$(cat "$device_fw_dir/$device_target_build/url" 2>/dev/null)
    if [[ -z $url ]]; then
        log "Getting URL for $device_type-$device_target_build"
        url=$(curl https://api.ipsw.me/v2.1/$device_type/$device_target_build/url)
        mkdir $device_fw_dir/$device_target_build 2>/dev/null
        echo "$url" > $device_fw_dir/$device_target_build/url
    fi
    mkdir $ramdisk_path 2>/dev/null
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" | "AppleLogo" ) path="Firmware/all_flash/all_flash.${device_model}ap.production/";;
            * ) path="";;
        esac
        if [[ -z $name ]]; then
            case $getcomp in
                "iBSS" ) name="iBSS.${device_model}ap.RELEASE.dfu";;
            esac
        fi

        log "$getcomp"
        if [[ -e $ramdisk_path/$name ]]; then
            cp $ramdisk_path/$name .
        else
            "$dir/pzb" -g "${path}$name" -o "$name" "$url"
            cp $name $ramdisk_path/
        fi
        mv $name $getcomp.orig
        if [[ $getcomp == "Kernelcache" || $getcomp == "iBSS" ]] && [[ $device_type == "iPod2,1" || $device_proc == 1 ]]; then
            decrypt="-iv $iv -k $key"
            "$dir/xpwntool" $getcomp.orig $getcomp.dec $decrypt
        else
            "$dir/xpwntool" $getcomp.orig $getcomp.dec -iv $iv -k $key -decrypt
        fi
    done

    log "Patch RestoreRamdisk"
    "$dir/xpwntool" RestoreRamdisk.dec Ramdisk.raw
    "$dir/hfsplus" Ramdisk.raw grow 30000000

    if [[ $device_type == "iPod2,1" || $device_proc == 1 ]]; then
        "$dir/hfsplus" Ramdisk.raw untar ../resources/ssh_old.tar
        "$dir/xpwntool" Ramdisk.raw Ramdisk.dmg -t RestoreRamdisk.dec
        log "Patch iBSS"
        $bspatch iBSS.dec iBSS.patched ../resources/patch/iBSS.${device_model}ap.RELEASE.patch
        "$dir/xpwntool" iBSS.patched iBSS -t iBSS.orig
        log "Patch Kernelcache"
        mv Kernelcache.dec Kernelcache0.dec
        if [[ $device_proc == 1 ]]; then
            $bspatch Kernelcache0.dec Kernelcache.patched ../resources/patch/kernelcache.release.s5l8900x.patch
        else
            $bspatch Kernelcache0.dec Kernelcache.patched ../resources/patch/kernelcache.release.${device_model}.patch
        fi
        "$dir/xpwntool" Kernelcache.patched Kernelcache.dec -t Kernelcache.orig $decrypt
        rm DeviceTree.dec
        mv DeviceTree.orig DeviceTree.dec
    else
        "$dir/hfsplus" Ramdisk.raw untar ../resources/ssh.tar
        "$dir/xpwntool" Ramdisk.raw Ramdisk.dmg -t RestoreRamdisk.dec
        log "Patch iBSS"
        "$dir/xpwntool" iBSS.dec iBSS.raw
        "$dir/iBoot32Patcher" iBSS.raw iBSS.patched --rsa
        "$dir/xpwntool" iBSS.patched iBSS -t iBSS.dec
        log "Patch iBEC"
        "$dir/xpwntool" iBEC.dec iBEC.raw
        if [[ $device_verbose_boot == 1 ]]; then
            "$dir/iBoot32Patcher" iBEC.raw iBEC.patched --rsa -b "-v"
        else
            "$dir/iBoot32Patcher" iBEC.raw iBEC.patched --rsa --debug -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1"
        fi
        "$dir/xpwntool" iBEC.patched iBEC -t iBEC.dec
    fi

    mv iBSS iBEC AppleLogo.dec DeviceTree.dec Kernelcache.dec Ramdisk.dmg $ramdisk_path 2>/dev/null

    if [[ $1 == "jailbreak" ]]; then
        device_enter_mode pwnDFU
    elif [[ $device_proc == 4 ]] || [[ $device_proc == 6 && $platform == "macos" ]]; then
        device_buttons
    elif [[ $device_proc == 1 ]]; then
        local ipswj="../${device_type}_3.1.3_7E18_Custom"
        if [[ -e "${ipswj}J.ipsw" ]]; then
            ipswj="${ipswj}J"
        elif [[ -e "${ipswj}HJ.ipsw" ]]; then
            ipswj="${ipswj}HJ"
        else
            warn "Cannot detect 3.1.3 custom IPSW for $device_type."
            print "* To proceed, you need to create a 3.1.3 custom IPSW with the jailbreak option enabled."
            print "* Go to: Other Utilities -> Create Custom IPSW -> 3.1.3"
            return
        fi
        device_enter_mode DFU
        $idevicerestore -p "$ipswj.ipsw"
    else
        device_enter_mode kDFU
    fi
    log "Sending iBSS..."
    $irecovery -f $ramdisk_path/iBSS
    if [[ $device_type != "iPod2,1" && $device_proc != 1 ]]; then
        sleep 2
        log "Sending iBEC..."
        $irecovery -f $ramdisk_path/iBEC
    fi
    device_find_mode Recovery

    log "Booting, please wait..."
    $irecovery -f $ramdisk_path/DeviceTree.dec
    $irecovery -c devicetree
    if [[ $device_verbose_boot != 1 ]]; then
        $irecovery -f $ramdisk_path/Ramdisk.dmg
        $irecovery -c ramdisk
    fi
    $irecovery -f $ramdisk_path/Kernelcache.dec
    $irecovery -c bootx
    if [[ -n $1 ]]; then
        device_find_mode Restore
    fi

    case $1 in
        "nvram" | "jailbreak" | "activation" | "baseband" | "getversion" )
            log "Running iproxy for SSH..."
            $iproxy 2222 22 >/dev/null &
            iproxy_pid=$!
            sleep 2
            device_sshpass alpine
        ;;
    esac
    case $1 in
        "activation" | "baseband" )
            local arg="$1"
            local dump="../saved/$device_type"
            local opt
            log "Mounting root filesystem"
            $ssh -p 2222 root@127.0.0.1 "mount.sh root"
            sleep 2
            log "Let's just dump both activation and baseband tars"
            log "Creating baseband.tar"
            $ssh -p 2222 root@127.0.0.1 "cd /mnt1; tar -cvf baseband.tar usr/standalone usr/local/standalone"
            log "Mounting data partition"
            $ssh -p 2222 root@127.0.0.1 "mount.sh pv"
            log "Creating activation.tar"
            $ssh -p 2222 root@127.0.0.1 "cd /mnt1; tar -cvf activation.tar private/var/root/Library/Lockdown"
            log "Copying tars"
            $scp -P 2222 root@127.0.0.1:/mnt1/baseband.tar root@127.0.0.1:/mnt1/activation.tar .
            print "* Reminder to backup dump tars if needed"
            if [[ -s $dump/baseband.tar ]]; then
                read -p "Baseband dump exists in $dump/baseband.tar. Overwrite? (Y/n)" opt
                if [[ $opt != 'N' && $opt != 'n' ]]; then
                    cp baseband.tar $dump
                fi
            else
                cp baseband.tar $dump
            fi
            opt=
            if [[ -s $dump/activation.tar ]]; then
                read -p "Activation records dump exists in $dump/activation.tar. Overwrite? (Y/n)" opt
                if [[ $opt != 'N' && $opt != 'n' ]]; then
                    cp activation.tar $dump
                fi
            else
                cp activation.tar $dump
            fi
            $ssh -p 2222 root@127.0.0.1 "rm -f /mnt1/baseband.tar /mnt1/activation.tar; nvram auto-boot=0; reboot_bak"
            log "Done, device should boot to recovery mode now"
            return
        ;;

        "jailbreak" | "getversion" )
            local vers
            local build
            local untether
            log "Mounting root filesystem"
            $ssh -p 2222 root@127.0.0.1 "mount.sh root"
            sleep 2
            log "Getting iOS version"
            $scp -P 2222 root@127.0.0.1:/mnt1/System/Library/CoreServices/SystemVersion.plist .
            if [[ $platform == "macos" ]]; then
                rm -f BuildVer Version
                plutil -extract 'ProductVersion' xml1 SystemVersion.plist -o Version
                vers=$(cat Version | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
                plutil -extract 'ProductBuildVersion' xml1 SystemVersion.plist -o BuildVer
                build=$(cat BuildVer | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
            else
                vers=$(cat SystemVersion.plist | grep -i ProductVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
                build=$(cat SystemVersion.plist | grep -i ProductBuildVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
            fi
            if [[ $1 == "getversion" && -n $vers ]]; then
                log "The current iOS version of this device is: $vers ($build)"
                $ssh -p 2222 root@127.0.0.1 "reboot_bak"
                return
            elif [[ $device_type == "iPad2"* && $vers == "4"* ]]; then
                warn "iOS $vers on $device_type is not supported for jailbreaking with SSHRD."
                $ssh -p 2222 root@127.0.0.1 "reboot_bak"
                return
            fi
            case $vers in
                8* )         untether="daibutsu/untether.tar";;
                7.1* )       untether="panguaxe.tar";;
                7* )         untether="evasi0n7-untether.tar";;
                6.1.[3456] ) untether="p0sixspwn.tar";;
                6* )         untether="evasi0n6-untether.tar";;
                5* )         untether="pris0nbarake/tar-${device_model}_$build.tar";;
                4.2.1 | 4.1 | 4.0* | 3.2.2 | 3.1.3 ) untether="greenpois0n/${device_type}_${build}.tar";;
                4.3* | 4.2* ) untether="unthredeh4il.tar";;
                '' )
                    warn "Something wrong happened. Failed to get iOS version."
                    print "* Please reboot the device into normal operating mode, then perform a clean \"slide to power off\", then try again."
                    $ssh -p 2222 root@127.0.0.1 "reboot_bak"
                    return
                ;;
                * )
                    warn "iOS $vers is not supported for jailbreaking with SSHRD."
                    $ssh -p 2222 root@127.0.0.1 "reboot_bak"
                    return
                ;;
            esac
            log "Nice, iOS $vers is compatible."
            log "Sending $untether"
            $scp -P 2222 $jelbrek/$untether root@127.0.0.1:/mnt1
            # 3.1.3-4.1 untether needs to be extracted early (before data partition is mounted)
            case $vers in
                4.1 | 4.0* | 3* )
                    untether="${device_type}_${build}.tar"
                    log "Extracting $untether"
                    $ssh -p 2222 root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                ;;
            esac
            log "Mounting data partition"
            $ssh -p 2222 root@127.0.0.1 "mount.sh pv"
            case $vers in
                8* ) device_ramdisktar fstab8.tar;;
                7* ) device_ramdisktar fstab7.tar;;
                6* ) device_ramdisktar fstab_rw.tar;;
                5* ) untether="tar-${device_model}_$build.tar";;
                4.2.1 ) $ssh -p 2222 root@127.0.0.1 "[[ ! -e /mnt1/sbin/punchd ]] && mv /mnt1/sbin/launchd /mnt1/sbin/punchd";;
            esac
            case $vers in
                5.1.1 ) device_ramdisktar rockyracoon.tar;;
                5.0.1 ) device_ramdisktar corona.tar;;
                5.0 )
                    if [[ $device_type == "iPhone4,1" ]]; then
                        device_ramdisktar corona.tar
                    fi
                ;;
                4.2.1 | 4.1 | 4.0* | 3* )
                    untether="${device_type}_${build}.tar"
                    if [[ $device_type == "iPod2,1" ]]; then
                        $scp -P 2222 $jelbrek/fstab_old root@127.0.0.1:/mnt1/private/etc/fstab
                    else
                        $scp -P 2222 $jelbrek/fstab_new root@127.0.0.1:/mnt1/private/etc/fstab
                    fi
                    $ssh -p 2222 root@127.0.0.1 "rm /mnt1/private/var/mobile/Library/Caches/com.apple.mobile.installation.plist"
                ;;
            esac
            case $vers in
                8* | 4.1 | 4.0* | 3* ) :;;
                * )
                    log "Extracting $untether"
                    $ssh -p 2222 root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                ;;
            esac
            case $vers in
                5* | 4* | 3* ) device_ramdisktar cydiasubstrate.tar;;
            esac
            case $vers in
                3* ) device_ramdisktar cydiahttpatch.tar;;
            esac
            device_ramdisktar freeze.tar data
            if [[ $ipsw_openssh == 1 ]]; then
                device_ramdisktar sshdeb.tar
            fi
            sleep 3
            if [[ $vers == "8"* ]]; then
                log "Sending daibutsu/move.sh"
                $scp -P 2222 $jelbrek/daibutsu/move.sh root@127.0.0.1:/
                log "Moving files"
                $ssh -p 2222 root@127.0.0.1 "bash /move.sh"
                untether="untether.tar"
                log "Extracting $untether"
                $ssh -p 2222 root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                log "Sending daibutsu/bin.tar"
                $scp -P 2222 $jelbrek/daibutsu/bin.tar root@127.0.0.1:/mnt1
                log "Extracting bin.tar"
                $ssh -p 2222 root@127.0.0.1 "tar -xvf /mnt1/bin.tar -C /; rm /mnt1/bin.tar"
                log "Running haxx_overwrite"
                $ssh -p 2222 root@127.0.0.1 "/usr/bin/haxx_overwrite --${device_type}_${device_target_build}"
            else
                log "Rebooting"
                $ssh -p 2222 root@127.0.0.1 "reboot_bak"
            fi
            log "Cool, done and jailbroken (hopefully)"
            case $vers in
                5* | 4* | 3* ) warn "Do not update Cydia Substrate and Substrate Safe Mode in Cydia!";;
            esac
            return
        ;;

        "nvram" )
            log "Sending commands for clearing NVRAM..."
            $ssh -p 2222 root@127.0.0.1 "nvram -c; reboot_bak"
            log "Done! Your device should reboot now."
            print "* If the device did not connect, SSH to the device manually."
        ;;

        "justboot" )
            log "Device should now boot."
            return
        ;;

        * ) log "Device should now be in SSH ramdisk mode.";;
    esac
    echo
    print "* To access SSH ramdisk, run iproxy first:"
    print "    iproxy 2222 22"
    print "* Then SSH to 127.0.0.1 port 2222:"
    print "    ssh -p 2222 -oHostKeyAlgorithms=+ssh-rsa root@127.0.0.1"
    print "* Enter root password:"
    print "   alpine"
    print "* Mount filesystems with this command:"
    print "    mount.sh"
    print "* Clear NVRAM with this command:"
    print "    nvram -c"
    print "* Erase All Content and Settings with this command (iOS 9+ only):"
    print "    nvram oblit-inprogress=5"
    print "* To reboot, use this command:"
    print "    reboot_bak"
}

shsh_save_onboard() {
    if [[ $device_proc == 4 ]]; then
        device_enter_mode pwnDFU
        patch_ibss
        log "Sending iBSS..."
        $irecovery -f pwnediBSS
        sleep 5
    else
        device_enter_mode kDFU
    fi
    patch_ibec
    log "Sending iBEC..."
    $irecovery -f pwnediBEC
    device_find_mode Recovery
    log "Dumping blobs now"
    (echo -e "/send ../resources/payload\ngo blobs\n/exit") | $irecovery2 -s
    $irecovery2 -g dump.shsh
    $irecovery -n
    "$dir/ticket" dump.shsh dump.plist "$ipsw_path.ipsw" -z
    "$dir/validate" dump.plist "$ipsw_path.ipsw" -z
    if [[ $? != 0 ]]; then
        warn "Saved SHSH blobs might be invalid. Did you select the correct IPSW?"
    fi
    if [[ ! -s dump.plist ]]; then
        warn "Saving onboard SHSH blobs failed."
        if [[ -s dump.shsh ]]; then
            mv dump.shsh ../saved/myblob-rawdump_$device_ecid-$device_type-$device_target_vers.dump
            log "Raw dump saved at: ../saved/myblob-rawdump_$device_ecid-$device_type-$device_target_vers.dump"
        fi
        return
    fi
    mv dump.plist ../saved/shsh/$device_ecid-$device_type-$device_target_vers.shsh
    log "Successfully saved $device_target_vers blobs: saved/shsh/$device_ecid-$device_type-$device_target_vers.shsh"
}

shsh_save_cydia() {
    local json=$(curl "https://api.ipsw.me/v4/device/${device_type}?type=ipsw")
    local len=$(echo "$json" | $jq -r ".firmwares | length")
    local builds=()
    local i=0
    while (( i < len )); do
        builds+=($(echo "$json" | $jq -r ".firmwares[$i].buildid"))
        ((i++))
    done
    for build in ${builds[@]}; do
        if [[ $build == "10"* && $build != "10B329" && $build != "10B350" ]]; then
            continue
        fi
        printf "\n%s " "$build"
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

menu_print_info() {
    if [[ $debug_mode != 1 ]]; then
        clear
    fi
    print " *** Legacy iOS Kit ***"
    print " - Script by LukeZGD -"
    echo
    if [[ -n $version_current ]]; then
        print "* Version: $version_current ($git_hash)"
    fi
    if [[ $no_version_check == 1 ]]; then
        warn "No version check flag detected, update check is disabled and no support will be provided."
    fi
    if [[ $git_hash_latest != "$git_hash" ]]; then
        warn "Current version is newer/different than remote: $version_latest ($git_hash_latest)"
    fi
    print "* Platform: $platform ($platform_ver) $live_cdusb_str"
    echo
    print "* Device: $device_type (${device_model}ap) in $device_mode mode"
    device_manufacturing
    if [[ -n $device_disable_bbupdate ]]; then
        warn "Disable bbupdate flag detected, baseband update is disabled. Proceed with caution"
        print "* For iPhones, current baseband will be dumped and stitched to custom IPSW"
    fi
    if [[ $device_actrec == 1 ]]; then
        warn "Activation records flag detected. Proceed with caution"
    fi
    if [[ -n $device_disable_bbupdate || $device_actrec == 1 ]]; then
        print "* Stitching is supported in these restores/downgrades: 8.4.1/6.1.3, Other with SHSH (iOS 5+), powdersn0w"
    fi
    print "* iOS Version: $device_vers"
    if [[ $device_vers == "Unknown" && $device_proc != 1 ]]; then
        print "* To get iOS version, go to: Other Utilities -> Get iOS Version"
    fi
    print "* ECID: $device_ecid"
    echo
}

menu_main() {
    local menu_items
    local selected
    local back
    while [[ -z "$mode" ]]; do
        menu_items=()
        menu_print_info
        print " > Main Menu"
        input "Select an option:"
        if [[ $device_mode != "none" ]]; then
            menu_items+=("Restore/Downgrade")
            if [[ $device_type == "iPad2"* && $device_vers == "4"* ]]; then
                :
            elif (( device_proc < 7 )) && [[ $device_proc != 1 ]]; then
                menu_items+=("Jailbreak Device")
            fi
        fi
        if (( device_proc < 8 )) && [[ $device_proc != 1 ]]; then
            menu_items+=("Save SHSH Blobs")
        fi
        menu_items+=("Other Utilities" "Exit")
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Restore/Downgrade" ) menu_restore;;
            "Jailbreak Device" ) mode="jailbreak";;
            "Save SHSH Blobs" ) menu_shsh;;
            "Other Utilities" ) menu_other;;
            "Exit" ) mode="exit";;
        esac
    done
}

menu_shsh() {
    local menu_items
    local selected
    local back

    device_target_vers=
    device_target_build=
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=()
        case $device_type in
            iPad4,[12345] | iPhone6,[12] )
                menu_items+=("iOS 10.3.3");;
            iPad2,[1234567] | iPad3,[123456] | iPhone4,1 | iPhone5,[12] | iPod5,1 )
                menu_items+=("iOS 8.4.1");;
        esac
        case $device_type in
            iPad2,[123] | iPhone4,1 )
                menu_items+=("iOS 6.1.3");;
        esac
        if (( device_proc < 7 )); then
            if [[ $device_mode != "none" ]]; then
                menu_items+=("Onboard Blobs")
            fi
            menu_items+=("Cydia Blobs")
        fi
        menu_items+=("Go Back")
        menu_print_info
        print " > Main Menu > Save SHSH Blobs"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "iOS 10.3.3" )
                device_target_vers="10.3.3"
                device_target_build="14G60"
            ;;
            "iOS 8.4.1" )
                device_target_vers="8.4.1"
                device_target_build="12H321"
            ;;
            "iOS 6.1.3" )
                device_target_vers="6.1.3"
                device_target_build="10B329"
            ;;
        esac
        case $selected in
            "iOS"* ) mode="save-ota-blobs";;
            "Onboard Blobs" ) menu_shsh_onboard;;
            "Cydia Blobs" ) mode="save-cydia-blobs";;
            "Go Back" ) back=1;;
        esac
    done
}

menu_shsh_onboard() {
    local menu_items
    local selected
    local back

    ipsw_path=
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Select IPSW")
        menu_print_info
        if [[ -n $ipsw_path ]]; then
            print "* Selected IPSW: $ipsw_path.ipsw"
            print "* IPSW Version: $device_target_vers-$device_target_build"
            if [[ $device_mode == "Normal" && $device_target_vers != "$device_vers" ]]; then
                warn "Selected IPSW does not seem to match the current version."
            fi
            menu_items+=("Save Onboard Blobs")
        else
            print "* Select IPSW of your current iOS version to continue"
        fi
        menu_items+=("Go Back")
        echo
        print " > Main Menu > Save SHSH Blobs > Onboard Blobs"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Select IPSW" ) menu_ipsw_browse;;
            "Save Onboard Blobs" ) mode="save-onboard-blobs";;
            "Go Back" ) back=1;;
        esac
    done
}


menu_restore() {
    local menu_items
    local selected
    local back

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=()
        case $device_type in
            iPad4,[12345] | iPhone6,[12] )
                menu_items+=("iOS 10.3.3");;
            iPad2,[1234567] | iPad3,[123456] | iPhone4,1 | iPhone5,[12] | iPod5,1 )
                menu_items+=("iOS 8.4.1");;
        esac
        case $device_type in
            iPad2,[123] | iPhone4,1 )
                menu_items+=("iOS 6.1.3");;
            iPhone2,1 )
                menu_items+=("5.1.1" "5.0.1" "4.3.3" "4.1" "3.1.3");;
            iPod3,1 )
                menu_items+=("4.1");;
            iPhone1,2 | iPod2,1 )
                menu_items+=("4.1" "3.1.3");;
        esac
        if (( device_proc < 7 )); then
            menu_items+=("Latest iOS ($device_latest_vers)")
        fi
        case $device_type in
            iPhone4,1 | iPhone5,[1234] | iPad2,4 | iPod5,1 )
                menu_items+=("Other (powdersn0w 7.x blobs)");;
            iPhone3,[13] )
                menu_items+=("powdersn0w (any iOS)");;
            iPhone1,[12] | iPhone2,1 | iPhone3,2 | iPad1,1 | iPod1,1 | iPod2,1 | iPod3,1 | iPod4,1 )
                if [[ -z $1 ]]; then
                    menu_items+=("Other (Custom IPSW)")
                fi
            ;;
        esac
        if [[ $device_proc != 1 ]]; then
            menu_items+=("Other (Use SHSH Blobs)")
            if (( device_proc < 7 )); then
                menu_items+=("DFU IPSW")
            fi
        fi
        menu_items+=("Go Back")
        menu_print_info
        if [[ $1 == "ipsw" ]]; then
            print " > Main Menu > Other Utilities > Create Custom IPSW"
        else
            print " > Main Menu > Restore/Downgrade"
        fi
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "" ) :;;
            "Go Back" ) back=1;;
            "Other (Custom IPSW)" ) mode="customipsw";;
            "DFU IPSW" ) mode="dfuipsw${1}";;
            * ) menu_ipsw "$selected" "$1";;
        esac
    done
}

menu_ipsw() {
    local menu_items
    local selected
    local back
    local newpath
    local nav
    local start

    if [[ $2 == "ipsw" ]]; then
        nav=" > Main Menu > Other Utilities > Create Custom IPSW > $1"
        start="Create IPSW"
    else
        nav=" > Main Menu > Restore/Downgrade > $1"
        start="Start Restore"
    fi

    ipsw_path=
    ipsw_base_path=
    shsh_path=
    device_target_vers=
    device_target_build=
    device_base_vers=
    device_base_build=
    device_target_other=
    device_target_powder=

    while [[ -z "$mode" && -z "$back" ]]; do
        case $1 in
            "iOS 10.3.3" )
                device_target_vers="10.3.3"
                device_target_build="14G60"
            ;;
            "iOS 8.4.1" )
                device_target_vers="8.4.1"
                device_target_build="12H321"
            ;;
            "iOS 6.1.3" )
                device_target_vers="6.1.3"
                device_target_build="10B329"
            ;;
            "5.1.1" )
                device_target_vers="5.1.1"
                device_target_build="9B206"
                device_canhacktivate=1
            ;;
            "5.0.1" )
                device_target_vers="5.0.1"
                device_target_build="9A405"
                device_canhacktivate=1
            ;;
            "4.3.3" )
                device_target_vers="4.3.3"
                device_target_build="8J2"
                device_canhacktivate=1
            ;;
            "4.1" )
                device_target_vers="4.1"
                device_target_build="8B117"
                device_canhacktivate=1
            ;;
            "3.1.3" )
                device_target_vers="3.1.3"
                device_target_build="7E18"
                device_canhacktivate=1
            ;;
            "Latest iOS"* )
                device_target_vers="$device_latest_vers"
                device_target_build="$device_latest_build"
                case $device_latest_vers in
                    "6.1.6" | "4.2.1" | "3.1.3" ) device_canhacktivate=1;;
                esac
            ;;
        esac
        if [[ $device_target_vers == "$device_latest_vers" ]]; then
            case $device_type in
                iPad3,[456]    ) newpath="iPad_32bit";;
                iPad4,[123456] ) newpath="iPad_64bit";;
                iPad4,[789]    ) newpath="iPad_64bit_TouchID";;
                iPhone5,[1234] ) newpath="iPhone_4.0_32bit";;
                iPhone6,[12]   ) newpath="iPhone_4.0_64bit";;
                iPhone7,1      ) newpath="iPhone_5.5";;
                iPhone7,2      ) newpath="iPhone_4.7";;
                iPod7,1        ) newpath="iPodtouch";;
                * ) newpath="${device_type}";;
            esac
            newpath+="_${device_target_vers}_${device_target_build}_Restore"

        else
            case $device_type in
                iPad4,[12345] ) newpath="iPad_64bit";;
                iPhone6,[12]  ) newpath="iPhone_4.0_64bit";;
                * ) newpath="${device_type}";;
            esac
            newpath+="_${device_target_vers}_${device_target_build}"
            ipsw_custom_set $newpath
            newpath+="_Restore"
        fi
        if [[ $1 == "Other (Use SHSH Blobs)" ]]; then
            device_target_other=1
        elif [[ $1 == *"powdersn0w"* ]]; then
            device_target_powder=1
        elif [[ -n $device_target_vers && -e "../$newpath.ipsw" ]]; then
            ipsw_verify "../$newpath" "$device_target_build" nopause
            if [[ $? == 0 ]]; then
                ipsw_path="../$newpath"
            fi
        fi

        menu_items=("Select Target IPSW")
        menu_print_info
        if [[ $1 == *"powdersn0w"* ]]; then
            menu_items+=("Select Base IPSW")
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                print "* Target Version: $device_target_vers-$device_target_build"
            else
                print "* Select Target IPSW to continue"
                case $device_type in
                    iPhone3,1 ) print "* Any iOS version from 4.3 to 6.1.3 is supported";;
                    iPhone3,3 ) print "* Any iOS version from 5.0 to 6.1.3 is supported";;
                    iPhone4,1 | iPad2,[123] ) print "* Any iOS version from 5.0 to 9.3.5 is supported (not iOS 7)";;
                    iPad2,4 | iPad3,[123] ) print "* Any iOS version from 5.1 to 9.3.5 is supported (not iOS 7)";;
                    iPhone5,[12] | iPad3,[456] ) print "* Any iOS version from 6.0 to 9.3.5 is supported (not iOS 7)";;
                    iPhone5,[34] ) print "* Any iOS version from 8.0 to 9.3.5 is supported";;
                esac
            fi
            echo
            local text2="(iOS 7.1.x)"
            case $device_type in
                iPhone3,[13] ) text2="(iOS 7.1.2)";;
                iPhone5,[12] ) text2="(iOS 7.x)";;
            esac
            if [[ -n $ipsw_base_path ]]; then
                print "* Selected Base $text2 IPSW: $ipsw_base_path.ipsw"
                print "* Base Version: $device_base_vers-$device_base_build"
                if [[ $device_type != "iPhone3,1" && $device_type != "iPhone3,3" ]]; then
                    menu_items+=("Select Base SHSH")
                fi
            else
                print "* Select Base $text2 IPSW to continue"
            fi
            if [[ $device_type == "iPhone3,1" || $device_type == "iPhone3,3" ]]; then
                shsh_path=1
            else
                echo
                if [[ -n $shsh_path ]]; then
                    print "* Selected Base $text2 SHSH: $shsh_path"
                elif [[ $2 != "ipsw" ]]; then
                    print "* Select Base $text2 SHSH to continue"
                fi
            fi
            if [[ -n $ipsw_path && -n $ipsw_base_path ]] && [[ -n $shsh_path || $2 == "ipsw" ]]; then
                menu_items+=("$start")
            fi

        elif [[ $1 == "Other"* ]]; then
            # menu for other (shsh) restores
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                print "* Target Version: $device_target_vers-$device_target_build"
                menu_items+=("Select Target SHSH")
                if [[ $device_type == "iPhone3,1" && $device_target_vers == "4.2.1" ]]; then
                    warn "There currently seems to be an issue with 4.2.1 restores for iPhone 4."
                    print "* The device might get stuck at the Apple logo after the restore."
                fi
            else
                print "* Select Target IPSW to continue"
            fi
            if (( device_proc > 6 )); then
                print "* Check the SEP/BB compatibility chart: https://docs.google.com/spreadsheets/d/1Mb1UNm6g3yvdQD67M413GYSaJ4uoNhLgpkc7YKi3LBs"
            fi
            if [[ -n $shsh_path ]]; then
                echo
                print "* Selected Target SHSH: $shsh_path"
                if (( device_proc > 6 )); then
                    shsh_generator=$(cat "$shsh_path" | grep "<string>0x" | cut -c10-27)
                    print "* Generator: $shsh_generator"
                fi

            elif [[ $2 != "ipsw" ]]; then
                echo
                print "* Select Target SHSH to continue"
            fi
            if [[ -n $ipsw_path ]] && [[ -n $shsh_path || $2 == "ipsw" ]]; then
                menu_items+=("$start")
            fi

        else
            # menu for ota/latest versions
            menu_items+=("Download Target IPSW")
            if [[ -n $ipsw_path ]]; then
                print "* Selected IPSW: $ipsw_path.ipsw"
                menu_items+=("$start")
            else
                print "* Select $1 IPSW to continue"
            fi
            if [[ $device_canhacktivate == 1 ]] && [[ $device_type == "iPhone2,1" || $device_proc == 1 ]]; then
                print "* Hacktivation is supported for this restore"
            fi
        fi
        echo
        menu_items+=("Go Back")

        print "$nav"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Start Restore" ) mode="downgrade";;
            "Create IPSW" ) mode="custom-ipsw";;
            "Select Target IPSW" ) menu_ipsw_browse "$1";;
            "Select Base IPSW" ) menu_ipsw_browse "base";;
            "Select Target SHSH" ) menu_shsh_browse "$1";;
            "Select Base SHSH" ) menu_shsh_browse "base";;
            "Download Target IPSW" ) ipsw_download "../$newpath";;
            "Go Back" ) back=1;;
        esac
    done
}

ipsw_version_set() {
    local newpath="$1"
    local vers
    local build

    log "Getting version from IPSW"
    unzip -o -j "$newpath.ipsw" Restore.plist -d .
    if [[ $platform == "macos" ]]; then
        rm -f BuildVer Version
        plutil -extract 'ProductVersion' xml1 Restore.plist -o Version
        vers=$(cat Version | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
        plutil -extract 'ProductBuildVersion' xml1 Restore.plist -o BuildVer
        build=$(cat BuildVer | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
    else
        vers=$(cat Restore.plist | grep -i ProductVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
        build=$(cat Restore.plist | grep -i ProductBuildVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
    fi

    if [[ $2 == "base" ]]; then
        device_base_vers="$vers"
        device_base_build="$build"
    else
        device_target_vers="$vers"
        device_target_build="$build"
    fi
}

ipsw_custom_set() {
    ipsw_custom="../${device_type}_${device_target_vers}_${device_target_build}_Custom"
    if [[ -n $1 ]]; then
        ipsw_custom="../$1_Custom"
    fi
    # disable bbupdate for iphone 5 devices on other/powder
    #if [[ $device_type == "iPhone5"* ]] && [[ $device_target_other == 1 || $device_target_powder == 1 ]]; then
    #    device_disable_bbupdate="$device_type"
    #fi
    if [[ $device_type == "$device_disable_bbupdate" ]]; then
        device_use_bb=0
        ipsw_custom+="B"
    fi
    if [[ $ipsw_hacktivate == 1 ]]; then
        ipsw_custom+="H"
    fi
    if [[ $ipsw_jailbreak == 1 ]]; then
        ipsw_custom+="J"
    fi
    if [[ $device_target_powder == 1 ]]; then
        ipsw_custom+="P"
    fi
    if [[ $ipsw_verbose == 1 ]]; then
        ipsw_custom+="V"
    fi
    if [[ $device_target_vers == "4.3"* && $device_type == "iPhone3,1" && $device_target_powder == 1 ]]; then
        ipsw_custom+="_$device_ecid"
    fi
}

menu_ipsw_browse() {
    local versionc
    local newpath
    local text="target"
    [[ $1 == "base" ]] && text="base"

    input "Select your $text IPSW file in the file selection window."
    newpath="$($zenity --file-selection --file-filter='IPSW | *.ipsw' --title="Select $text IPSW file")"
    [[ ! -s "$newpath" ]] && read -p "$(input "Enter path to $text IPSW file (or press Ctrl+C to cancel): ")" newpath
    [[ ! -s "$newpath" ]] && return
    newpath="${newpath%?????}"
    log "Selected IPSW file: $newpath.ipsw"
    ipsw_version_set "$newpath" "$1"
    if [[ $(cat Restore.plist | grep -c $device_type) == 0 ]]; then
        log "Selected IPSW is not for your device $device_type."
        pause
        return
    elif [[ $device_proc == 8 && $device_latest_vers == "12"* ]] || [[ $device_type == "iPad4,6" ]]; then
        # SEP/BB check for iPhone 6/6+, iPad mini 2 China, iPod touch 6
        case $device_target_build in
            "11"* | "12"* | "13"* | "14"* | "15A"* | "15B"* | "15C"* | "15D"* )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    elif [[ $device_proc == 7 ]]; then
        # SEP/BB check for iPhone 5S, iPad Air 1/mini 2
        case $device_target_build in
            "11"* | "12"* | "13"* | "14A"* | "15A"* | "15B"* | "15C"* | "15D"* )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    elif [[ $device_latest_vers == "15"* ]]; then
        # SEP/BB check for iPhone 6S/6S+/SE 2016/7/7+, iPad Air 2/mini 4, iPod touch 7
        case $device_target_build in
            "12"* | "13"* | "14"* | "15"* | "16"* | "17"* )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    fi
    case $1 in
        "iOS 10.3.3" ) versionc="10.3.3";;
        "iOS 8.4.1" ) versionc="8.4.1";;
        "iOS 6.1.3" ) versionc="6.1.3";;
        "5.1.1" ) versionc="5.1.1";;
        "5.0.1" ) versionc="5.0.1";;
        "4.3.3" ) versionc="4.3.3";;
        "4.1" ) versionc="4.1";;
        "3.1.3" ) versionc="3.1.3";;
        "Latest iOS"* ) versionc="$device_latest_vers";;
        "base" )
            if [[ $device_type == "iPhone5,1" || $device_type == "iPhone5,2" ]]; then
                if [[ $device_base_vers != "7"* ]]; then
                    log "Selected IPSW is not for iOS 7.x."
                    print "* You need iOS 7.x IPSW and SHSH blobs for this device to use powdersn0w."
                    pause
                    return
                fi
            elif [[ $device_base_vers != "7.1"* ]]; then
                log "Selected IPSW is not for iOS 7.1.x."
                print "* You need iOS 7.1.x IPSW and SHSH blobs for this device to use powdersn0w."
                pause
                return
            fi
            ipsw_verify "$newpath" "$device_base_build"
            ipsw_base_path="$newpath"
            return
        ;;
        *"powdersn0w"* )
            case $device_target_build in
                "8A"* | "8B"* | "8C"* | "8G4" | "8H7" | "8K2" | "11"* | "14"* )
                    log "Selected IPSW ($device_target_vers) is not supported as target version."
                    if [[ $device_target_build == "8"* ]]; then
                        print "* Supported iOS 4.3.x versions: 4.3, 4.3.3, 4.3.5"
                    fi
                    pause
                    return
                ;;
            esac
        ;;
    esac
    if [[ -n $versionc && $device_target_vers != "$versionc" ]]; then
        log "Selected IPSW ($device_target_vers) does not match target version ($versionc)."
        pause
        return
    fi
    if [[ $1 != "custom" ]]; then
        ipsw_verify "$newpath" "$device_target_build"
        if [[ -n $versionc && $? != 0 ]]; then
            return
        fi
    fi
    ipsw_path="$newpath"
}

menu_shsh_browse() {
    local newpath
    local text="target"
    local val="$ipsw_path.ipsw"
    [[ $1 == "base" ]] && text="base"

    input "Select your $text SHSH file in the file selection window."
    newpath="$($zenity --file-selection --file-filter='SHSH | *.shsh *.shsh2' --title="Select $text SHSH file")"
    [[ ! -s "$newpath" ]] && read -p "$(input "Enter path to $text IPSW file (or press Ctrl+C to cancel): ")" newpath
    [[ ! -s "$newpath" ]] && return
    log "Selected SHSH file: $newpath"
    if (( device_proc < 7 )); then
        log "Validating..."
        if [[ $1 == "base" ]]; then
            val="$ipsw_base_path.ipsw"
        fi
        "$dir/validate" "$newpath" "$val" -z
        if [[ $? != 0 ]]; then
            warn "Validation failed. Did you select the correct IPSW/SHSH?"
            pause
        fi
    fi
    shsh_path="$newpath"
}

menu_other() {
    local menu_items
    local selected
    local back

    ipsw_path=
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=()
        if [[ $device_mode != "none" && $device_proc != 1 ]]; then
            if (( device_proc < 7 )); then
                if [[ $device_mode == "Normal" ]]; then
                    menu_items+=("Enter kDFU Mode" "Enter pwnDFU Mode")
                else
                    case $device_proc in
                        5 | 6 ) menu_items+=("Send Pwned iBSS");;
                        * ) menu_items+=("Enter pwnDFU Mode");;
                    esac
                    menu_items+=("Get iOS Version")
                fi
                if [[ $device_type == "iPhone"* ]]; then
                    menu_items+=("Dump Baseband")
                fi
                menu_items+=("Activation Records" "Clear NVRAM")
                if [[ $device_type != "iPod2,1" ]]; then
                    menu_items+=("Just Boot")
                fi
            else
                menu_items+=("Enter pwnDFU Mode")
            fi
            case $device_type in
                iPhone3,1 ) menu_items+=("Disable/Enable Exploit");;
                iPhone2,1 ) menu_items+=("Install alloc8 Exploit");;
            esac
        fi
        if [[ $device_mode != "none" ]]; then
            menu_items+=("SSH Ramdisk")
            case $device_mode in
                "Normal" ) menu_items+=("Attempt Activation" "Shutdown Device" "Restart Device" "Enter Recovery Mode");;
                "Recovery" ) menu_items+=("Exit Recovery Mode");;
            esac
            if [[ $device_mode != "DFU" ]]; then
                menu_items+=("Enter DFU Mode")
            fi
        fi
        if [[ $device_proc != 8 ]]; then
            menu_items+=("Create Custom IPSW")
        fi
        menu_items+=("(Re-)Install Dependencies" "Go Back")
        menu_print_info
        print " > Main Menu > Other Utilities"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Create Custom IPSW" ) menu_restore ipsw;;
            "Enter kDFU Mode" ) mode="kdfu";;
            "Disable/Enable Exploit" ) mode="remove4";;
            "SSH Ramdisk" ) mode="ramdisk4";;
            "Clear NVRAM" ) mode="ramdisknvram";;
            "Send Pwned iBSS" | "Enter pwnDFU Mode" ) mode="pwned-ibss";;
            "(Re-)Install Dependencies" ) install_depends;;
            "Attempt Activation" ) mode="activate";;
            "Install alloc8 Exploit" ) mode="alloc8";;
            "Dump Baseband" ) mode="baseband";;
            "Activation Records" ) mode="actrec";;
            "Enter Recovery Mode" ) mode="enterrecovery";;
            "Exit Recovery Mode" ) mode="exitrecovery";;
            "Enter DFU Mode" ) mode="enterdfu";;
            "Just Boot" ) mode="justboot";;
            "Get iOS Version" ) mode="getversion";;
            "Shutdown Device" ) mode="shutdown";;
            "Restart Device" ) mode="restart";;
            "Go Back" ) back=1;;
        esac
    done
}

device_alloc8() {
    device_enter_mode pwnDFU
    device_ipwndfu alloc8
    log "Done!"
    print "* This may take several tries. If it fails, unplug and replug your device, then run the script again"
    print "* For more troubleshooting, go to: https://github.com/axi0mX/ipwndfu/blob/master/JAILBREAK-GUIDE.md"
}

device_jailbreakrd() {
    if [[ $device_vers == *"iBoot"* || $device_vers == "Unknown"* ]]; then
        read -p "$(input 'Enter current iOS version (eg. 6.1.3): ')" device_vers
        if [[ $device_type == "iPad2"* && $device_vers == "4"* ]]; then
            warn "This version ($device_vers) is not supported for jailbreaking with SSHRD."
            print "* Supported versions for iPad 2 are: 5.0 to 8.4.1"
            return
        fi
        case $device_vers in
            8* | 7* | 6* | 5* | 4* | 3.2.2 | 3.1.3 ) :;;
            * )
                warn "This version ($device_vers) is not supported for jailbreaking with SSHRD."
                print "* Supported versions are: 3.1.3 to 8.4.1"
                return
            ;;
        esac
    fi
    print "* By selecting Jailbreak Device, your device will be jailbroken using SSH Ramdisk."
    print "* Before continuing, make sure that your device does not have a jailbreak yet."
    print "* No data will be lost, but please back up your data just in case."
    pause
    device_ramdisk jailbreak
}

device_dump() {
    local arg="$1"
    local dump="../saved/$device_type/$arg.tar"
    local dmps
    case $arg in
        "baseband" ) dmps="/usr/standalone /usr/local/standalone";;
        "activation" ) dmps="/private/var/root/Library/Lockdown";;
    esac
    log "Dumping files for $arg: $dmps"
    if [[ -s $dump ]]; then
        log "Found existing dumped $arg: $dump"
        print "* Select Y to overwrite, or N to use existing dump"
        print "* Make sure to keep a backup of the dump if needed"
        read -p "$(input 'Overwrite this existing dump? (Y/n) ')" opt
        if [[ $opt == 'N' || $opt == 'n' ]]; then
            return
        fi
        log "Deleting existing dumped $arg"
        rm $dump
    fi
    if [[ $device_mode == "Recovery" ]]; then
        device_enter_mode pwnDFU
    fi
    if [[ $device_mode == "Normal" ]]; then
        print "* Make sure to have OpenSSH and Core Utilities installed on your iOS device."
        if [[ $(echo "$device_vers" | cut -c 1) == 1 ]]; then
            print "* Install all updates in Cydia/Zebra."
            print "* Make sure to also have Dropbear installed from my repo."
            print "* Repo: https://lukezgd.github.io/repo"
        fi
        print "* Only proceed if you have these requirements installed using Cydia/Zebra."
        print "* You will be prompted to enter the root password of your iOS device."
        print "* The default root password is: alpine"
        log "Running iproxy for SSH..."
        $iproxy 2222 22 >/dev/null &
        iproxy_pid=$!
        sleep 2
        device_sshpass
        log "Creating $arg.tar"
        $ssh -p 2222 root@127.0.0.1 "tar -cvf /tmp/$arg.tar $dmps"
        log "Copying $arg.tar"
        $scp -P 2222 root@127.0.0.1:/tmp/$arg.tar .
        cp $arg.tar $dump
    elif [[ $device_mode == "DFU" ]]; then
        device_ramdisk $arg
        device_enter_mode pwnDFU
    fi
    kill $iproxy_pid
    if [[ ! -e $dump ]]; then
        error "Failed to dump $arg from device. Please run the script again"
    fi
    log "Dumping $arg done: $dump"
}

device_activate() {
    log "Attempting to activate device with ideviceactivation"
    if (( device_proc <= 4 )) && [[ $device_type == "iPhone"* ]]; then
        print "* For iPhone 4 and older devices, make sure to have a valid SIM card."
        if [[ $device_proc == 1 || $device_type == "iPhone2,1" ]]; then
            print "* For hacktivation, go to Restore/Downgrade instead."
        fi
    fi
    $ideviceactivation activate
    print "* If it returns an error, just try again."
}

restore_customipsw() {
    print "* You are about to restore with a custom IPSW."
    print "* Note that this might only work on old bootrom devices."
    print "* Also note that Legacy iOS Kit does not support tethered booting."
    print "* Legacy iOS Kit will not support tethered downgrades and jailbreaks."
    print "* Proceed with caution when restoring to custom IPSWs not made with Legacy iOS Kit."
    if [[ $device_newbr == 1 ]]; then
        warn "Your device is a new bootrom model and custom IPSWs might not be compatible."
        print "* For iPhone 3GS, after restoring you will need to go to Other Utilities -> Install alloc8 Exploit"
    fi
    pause
    menu_ipsw_browse custom
    if [[ -z $ipsw_path ]]; then
        error "No IPSW selected, cannot continue."
    fi
    device_enter_mode pwnDFU
    ipsw_extract
    log "Running idevicerestore with command: $idevicerestore -ce \"$ipsw_path.ipsw\""
    $idevicerestore -ce "$ipsw_path.ipsw"
    log "Restoring done!"
    case $device_target_vers in
        1* | 2* | 3* | 4* ) print "* For device activation, go to: Other Utilities -> Attempt Activation";;
    esac
}

restore_dfuipsw() {
    # the only change done to the "dfu ipsw" is just applelogo copied and renamed to llb
    print "* You are about to restore with a DFU IPSW."
    print "* This will force the device to enter DFU mode, which is useful for devices with broken buttons."
    print "* All device data will be wiped! Only proceed if you have backed up your data."
    print "* Expect the restore to fail and the device to be stuck in DFU mode."
    pause
    device_target_vers="$device_latest_vers"
    device_target_build="$device_latest_build"
    local ipsw_p="../${device_type}_${device_target_vers}_${device_target_build}"
    local ipsw_dfuipsw="${ipsw_p}_DFUIPSW"
    ipsw_path="${ipsw_p}_Restore"
    if [[ -s "$ipsw_path.ipsw" && ! -e "$ipsw_dfuipsw.ipsw" ]]; then
        ipsw_verify "$ipsw_path" "$device_target_build"
    elif [[ ! -e "$ipsw_path.ipsw" ]]; then
        ipsw_download "$ipsw_path"
    fi
    if [[ -s "$ipsw_dfuipsw.ipsw" ]]; then
        log "Found existing DFU IPSW. Skipping IPSW creation."
    else
        cp $ipsw_path.ipsw temp.ipsw
        device_fw_key_check
        local applelogo=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("AppleLogo")) | .filename')
        local llb=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("LLB")) | .filename')
        local all="Firmware/all_flash/all_flash.${device_model}ap.production"
        mkdir -p $all
        unzip -o -j temp.ipsw $all/$applelogo -d .
        mv $applelogo $all/$llb
        zip -r0 temp.ipsw $all/*
        mv temp.ipsw $ipsw_dfuipsw.ipsw
    fi
    if [[ $1 == "ipsw" ]]; then
        return
    fi
    ipsw_path="$ipsw_dfuipsw"
    ipsw_extract
    log "Running idevicerestore with command: $idevicerestore -e \"$ipsw_path.ipsw\""
    $idevicerestore -e "$ipsw_path.ipsw"
    log "Restoring done! Device should now be in DFU mode"
}

device_justboot() {
    print "* You are about to do a tethered verbose boot."
    print "* Enter the build version of the iOS version to use. This supports iOS 5 and newer only."
    read -p "$(input 'Enter build version (eg. 9B206): ')" device_ramdisk_build
    case $device_ramdisk_build in
        "7"* | "8"* ) error "Tethered verbose boot is supported for iOS 5 and newer only."
    esac
    device_verbose_boot=1
    device_ramdisk justboot
}

main() {
    clear
    print " *** Legacy iOS Kit ***"
    print " - Script by LukeZGD -"
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

    if [[ ! -e "../resources/firstrun" || -z $zenity || $(cat "../resources/firstrun") != "$platform_ver" ]]; then
        install_depends
    fi

    device_get_info
    mkdir -p ../saved/baseband ../saved/$device_type ../saved/shsh

    mode=
    if [[ -z $mode ]]; then
        menu_main
    fi

    case $mode in
        "custom-ipsw" )
            ipsw_preference_set
            ipsw_prepare
            log "Done creating custom IPSW"
        ;;
        "downgrade" )
            ipsw_preference_set
            ipsw_prepare
            restore_prepare
        ;;
        "baseband" )
            device_dump baseband
            log "Baseband dumping is done"
            print "* To stitch baseband to IPSW, run Legacy iOS Kit with --disable-bbupdate argument:"
            print "    > ./restore.sh --disable-bbupdate"
        ;;
        "actrec" )
            device_dump activation
            log "Activation records dumping is done"
            print "* To stitch records to IPSW, run Legacy iOS Kit with --activation-records argument:"
            print "    > ./restore.sh --activation-records"
        ;;
        "save-ota-blobs" ) shsh_save;;
        "kdfu" ) device_enter_mode kDFU;;
        "remove4" ) device_remove4;;
        "ramdisk4" ) device_ramdisk;;
        "ramdisknvram" ) device_ramdisk nvram;;
        "pwned-ibss" ) device_enter_mode pwnDFU;;
        "save-onboard-blobs" ) shsh_save_onboard;;
        "save-cydia-blobs" ) shsh_save_cydia;;
        "activate" ) device_activate;;
        "alloc8" ) device_alloc8;;
        "jailbreak" ) device_jailbreakrd;;
        "customipsw" ) restore_customipsw;;
        "enterrecovery" ) device_enter_mode Recovery;;
        "exitrecovery" ) $irecovery -n;;
        "enterdfu" ) device_enter_mode DFU;;
        "dfuipsw" ) restore_dfuipsw;;
        "dfuipswipsw" ) restore_dfuipsw ipsw;;
        "justboot" ) device_justboot;;
        "getversion" ) device_ramdisk getversion;;
        "shutdown" ) "$dir/idevicediagnostics" shutdown;;
        "restart" ) "$dir/idevicediagnostics" restart;;
        * ) :;;
    esac

    echo
    print "* Save the terminal output now if needed."
    echo
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
        "--disable-bbupdate" ) device_disable_bbupdate=1;;
        "--disable-sudoloop" ) device_disable_sudoloop=1;;
        "--disable-usbmuxd" ) device_disable_usbmuxd=1;;
        "--activation-records" ) device_actrec=1;;
        "--ipsw-hacktivate" ) ipsw_hacktivate=1;;
    esac
done

trap "clean" EXIT
trap "exit 1" INT TERM

clean
mkdir "$(dirname "$0")/tmp"
pushd "$(dirname "$0")/tmp" >/dev/null

if [[ $no_color != 1 ]]; then
    TERM=xterm-256color # fix colors for msys2 terminal
    color_R=$(tput setaf 9)
    color_G=$(tput setaf 10)
    color_B=$(tput setaf 12)
    color_Y=$(tput setaf 208)
    color_N=$(tput sgr0)
fi

main

popd >/dev/null
