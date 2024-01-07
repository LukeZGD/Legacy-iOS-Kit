#!/usr/bin/env bash

ipsw_openssh=1 # OpenSSH will be added to jailbreak/custom IPSW if set to 1.
device_rd_build="" # You can change the version of SSH Ramdisk and Pwned iBSS/iBEC here. (default is 10B329 for most devices)
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
    print "* Legacy iOS Kit $version_current ($git_hash)"
    exit 1
}

pause() {
    input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
    read -s
}

clean() {
    kill $httpserver_pid $iproxy_pid $anisette_pid 2>/dev/null
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
    --debug                   For script debugging (set -x and debug mode)
    --disable-sudoloop        Disable running tools as root for Linux
    --disable-usbmuxd         Disable running usbmuxd as root for Linux
    --entry-device            Enable manual device and ECID entry
    --help                    Display this help message
    --no-color                Disable colors for script output
    --no-device               Enable no device mode
    --no-version-check        Disable script version checking

For 32-bit devices compatible with restores/downgrades (see README):
    --activation-records      Enable dumping/stitching activation records
    --disable-bbupdate        Disable bbupdate and enable dumping/stitching baseband
    --ipsw-hacktivate         Enable hacktivation for creating IPSW (iPhone 2G/3G/3GS only)
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
    bspatch, jq, scp, ssh, sha1sum (for macos: shasum -a 1), zenity

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
                "noble" ) ubuntu_ver=24;;
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
                    print "* Please move Legacy iOS Kit to a drive that is NOT used for the live USB."
                    print "* This may mean using another external HDD/flash drive to store Legacy iOS Kit on."
                    print "* To use one USB drive only, create the live USB using Rufus with Persistent Storage enabled."
                    pause
                    live_cdusb_str="Live - Temporary storage"
                fi
            fi
        fi

        # if "/media" is detected in pwd, warn user of possible permission issues
        if [[ $(pwd) == *"/media"* ]]; then
            warn "You might get permission errors like \"Permission denied\" on getting device info."
            print "* If this is the case, try moving Legacy iOS Kit to the Desktop or Documents folder."
        fi

        if [[ -z $device_disable_sudoloop ]]; then
            device_sudoloop=1 # Run some tools as root for device detection if set to 1. (for Linux)
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
        sha1sum="$(which shasum) -a 1"

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
        sudo apt install -y ca-certificates curl libimobiledevice6 libirecovery-common libssl3 libssl-dev openssh-client python3 unzip usbmuxd usbutils xxd zenity zip
        if [[ -n $ubuntu_ver ]] && (( ubuntu_ver < 23 )); then
            sudo apt install -y python2
        fi
        sudo systemctl enable --now udev systemd-udevd usbmuxd 2>/dev/null

    elif [[ $distro == "fedora" ]]; then
        sudo dnf install -y ca-certificates libimobiledevice openssl openssl-devel python3 systemd udev usbmuxd vim-common zenity zip
        sudo ln -sf /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-certificates.crt

    elif [[ $distro == "opensuse" ]]; then
        sudo zypper -n in ca-certificates curl libimobiledevice-1_0-6 libopenssl-3-devel openssl-3 pyenv python3 usbmuxd unzip vim zenity zip

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

version_update_check() {
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

version_get() {
    pushd .. >/dev/null
    if [[ -d .git ]]; then
        git_hash=$(git rev-parse HEAD | cut -c -7)
        local dm=$(git log -1 --format=%ci | cut -c 3- | cut -c -5)
        version_current=v${dm//-/.}.
        dm="20$dm"
        if [[ $(uname) == "Darwin" ]]; then
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
            print "* Please download Legacy iOS Kit using git clone or from GitHub releases: https://github.com/LukeZGD/Legacy-iOS-Kit/releases"
        fi
    fi
    if [[ -n $version_current ]]; then
        print "* Version: $version_current ($git_hash)"
    fi
    popd >/dev/null
}

version_check() {
    if [[ $no_version_check == 1 ]]; then
        warn "No version check flag detected, update check is disabled and no support will be provided."
        return
    fi
    pushd .. >/dev/null
    version_update_check
    if [[ -z $version_latest ]]; then
        warn "Failed to check for updates. GitHub may be down or blocked by your network."
    elif [[ $git_hash_latest != "$git_hash" ]]; then
        if [[ -z $version_current ]]; then
            print "* Latest version:  $version_latest ($git_hash_latest)"
            print "* Please download/pull the latest version before proceeding."
            version_update
        elif (( $(echo $version_current | cut -c 2- | sed -e 's/\.//g') >= $(echo $version_latest | cut -c 2- | sed -e 's/\.//g') )); then
            warn "Current version is newer/different than remote: $version_latest ($git_hash_latest)"
        else
            print "* A newer version of Legacy iOS Kit is available."
            print "* Current version: $version_current ($git_hash)"
            print "* Latest version:  $version_latest ($git_hash_latest)"
            print "* Please download/pull the latest version before proceeding."
            version_update
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
        print "* This $device_type is a new bootrom model"
    elif [[ $device_newbr == 2 ]]; then
        print "* This $device_type bootrom model cannot be determined. Enter DFU mode to get bootrom model"
    else
        print "* This $device_type is an old bootrom model"
    fi
    if [[ $device_type == "iPhone2,1" && $device_mode == "DFU" ]]; then
        print "* Cannot check for manufacturing date in DFU mode"
    elif [[ $device_type == "iPhone2,1" && $device_mode != "DFU" ]]; then
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

device_s5l8900xall() {
    local wtf_sha="cb96954185a91712c47f20adb519db45a318c30f"
    local wtf_saved="../saved/WTF.s5l8900xall.RELEASE.dfu"
    local wtf_patched="$wtf_saved.patched"
    local wtf_patch="../resources/patch/WTF.s5l8900xall.RELEASE.patch"
    local wtf_sha_local="$($sha1sum "$wtf_saved" 2>/dev/null | awk '{print $1}')"
    if [[ $wtf_sha_local != "$wtf_sha" ]]; then
        log "Downloading WTF.s5l8900xall"
        "$dir/pzb" -g "Firmware/dfu/WTF.s5l8900xall.RELEASE.dfu" -o WTF.s5l8900xall.RELEASE.dfu "http://appldnld.apple.com/iPhone/061-7481.20100202.4orot/iPhone1,1_3.1.3_7E18_Restore.ipsw"
        mv WTF.s5l8900xall.RELEASE.dfu $wtf_saved
    fi
    wtf_sha_local="$($sha1sum "$wtf_saved" | awk '{print $1}')"
    if [[ $wtf_sha_local != "$wtf_sha" ]]; then
        error "SHA1sum mismatch. Expected $wtf_sha, got $wtf_sha_local. Please run the script again"
    fi
    rm "$wtf_patched"
    log "Patching WTF.s5l8900xall"
    $bspatch $wtf_saved $wtf_patched $wtf_patch
    log "Sending patched WTF.s5l8900xall (pwnage)"
    $irecovery -f "$wtf_patched"
    device_find_mode DFUreal
    sleep 1
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
    if [[ $device_mode == "WTF" ]]; then
        device_proc=1
        device_wtfexit=1
        device_s5l8900xall
    fi
    case $device_mode in
        "DFU" | "Recovery" )
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
            device_vers=$(echo "/exit" | $irecovery -s | grep -a "iBoot-")
            [[ -z $device_vers ]] && device_vers="Unknown"
            device_serial="$($irecovery -q | grep "SRNM" | cut -c 7- | cut -c 3- | cut -c -3)"
            device_manufacturing
            if [[ $device_mode == "Recovery" && $device_newbr == 2 ]]; then
                print "* Device: $device_type (${device_model}) in $device_mode mode"
                print "* iOS Version: $device_vers"
                print "* ECID: $device_ecid"
                echo
                log "Your device is in recovery mode. Enter DFU mode to continue."
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
            device_build=$($ideviceinfo -s -k BuildVersion)
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
            n71m ) device_type="iPhone8,1";;
            n66  ) device_type="iPhone8,2";;
            n66m ) device_type="iPhone8,2";;
            n69  ) device_type="iPhone8,4";;
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
            n112 ) device_type="iPod9,1";;
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
        iPhone3,[123] | iPhone2,1 | iPad1,1 | iPod[234],1 )
            device_proc=4;; # A4/S5L8920/8922/8720
        iPad2,[1234567] | iPad3,[123] | iPhone4,1 | iPod5,1 )
            device_proc=5;; # A5
        iPad3,[456] | iPhone5,[1234] )
            device_proc=6;; # A6
        iPad4,[123456789] | iPhone6,[12] )
            device_proc=7;; # A7
        iPhone7,[12] | iPad5,[1234] | iPod7,1 )
            device_proc=8;; # A8
        iPhone8,[124] )
            device_proc=9;; # A9
        iPhone9,[1234] | iPod9,1 )
            device_proc=10;; # A10
    esac
    if [[ -z $device_proc ]]; then
        print "* Device: $device_type (${device_model}ap) in $device_mode mode"
        print "* iOS Version: $device_vers"
        print "* ECID: $device_ecid"
        echo
        error "This device is not supported by Legacy iOS Kit."
    fi

    if [[ $device_mode == "DFU" && $device_proc == 1 && $device_wtfexit != 1 ]]; then
        log "Found an S5L8900 device in DFU mode. Please re-enter WTF mode for good measure."
        print "* Force restart your device and place it in normal or recovery mode, then run the script again."
        exit
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
            device_latest_vers="15.8"
            device_latest_build="19H370"
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
        iPad5,[24] | iPhone8,[124] ) # MDM9615/MDM9635 15.7.9
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
    local wtfreal

    if [[ $mode == "Restore" ]]; then
        :
    elif [[ $mode == "Recovery" ]]; then
        usb=1281
    elif [[ $device_proc == 1 ]]; then
        usb=1222
        if [[ $mode == "DFUreal" ]]; then
            mode="DFU"
            usb=1227
        elif [[ $mode == "WTFreal" ]]; then
            mode="WTF"
            wtfreal=1
        elif [[ $mode == "DFU" ]]; then
            mode="WTF"
        fi
    else
        usb=1227
    fi

    if [[ -n $2 ]]; then
        timeout=$2
    elif [[ $platform == "linux" ]]; then
        timeout=24
    fi

    log "Finding device in $mode mode..."
    while (( i < timeout )); do
        if [[ $mode == "Restore" ]]; then
            device_find_all
            if [[ $? == 4 ]]; then
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
        if [[ $timeout != 1 && $timeout != 25 ]]; then
            error "Failed to find device in $mode mode (Timed out). Please run the script again."
        fi
        return 1
    elif [[ $mode == "WTF" && $wtfreal != 1 ]]; then
        device_s5l8900xall
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

device_find_all() {
    # find device stuff from palera1n legacy
    local opt
    if [[ $1 == "norec" ]]; then
        return
    fi
    if [[ $platform == "macos" ]]; then
        opt="$(system_profiler SPUSBDataType 2> /dev/null | grep -B1 'Vendor ID: 0x05ac' | grep 'Product ID:' | cut -dx -f2 | cut -d' ' -f1 | tail -r)"
    elif [[ $platform == "linux" ]]; then
        opt="$(lsusb | cut -d' ' -f6 | grep '05ac:' | cut -d: -f2)"
    fi
    case $opt in
        1227 ) return 1;; # dfu
        1281 ) return 2;; # recovery
        1222 ) return 3;; # wtf
        12[9a][0123456789abc] ) return 4;; # normal
    esac
}

device_dfuhelper() {
    local opt
    local rec="recovery mode "
    if [[ $1 == "norec" ]]; then
        rec=
    fi
    print "* Get ready to enter DFU mode."
    print "* If you already know how to enter DFU mode, you may do so right now before continuing."
    read -p "$(input "Select Y to continue, N to exit $rec(Y/n) ")" opt
    if [[ $opt == 'N' || $opt == 'n' ]]; then
        if [[ -z $1 ]]; then
            log "Exiting recovery mode."
            $irecovery -n
        fi
        exit
    fi
    device_find_all $1
    opt=$?
    if [[ $opt == 1 ]]; then
        log "Found device in DFU mode."
        device_mode="DFU"
        return
    fi
    print "* Get ready..."
    for i in {02..01}; do
        echo -n "$i "
        sleep 1
    done
    local top="TOP"
    local home="HOME"
    case $device_type in
        iPhone7* | iPhone8,[12] | iPhone9* ) top="SIDE";;
    esac
    if [[ $device_type == "iPhone9"* ]]; then
        home="VOL DOWN"
    fi
    echo -e "\n$(print "* Hold $top and $home buttons.")"
    for i in {10..01}; do
        echo -n "$i "
        device_find_all $1
        opt=$?
        if [[ $opt == 1 ]]; then
            echo -e "\n$(log 'Found device in DFU mode.')"
            device_mode="DFU"
            return
        fi
        sleep 1
    done
    echo -e "\n$(print "* Release $top button and keep holding $home button.")"
    for i in {08..01}; do
        echo -n "$i "
        device_find_all $1
        opt=$?
        if [[ $opt == 1 ]]; then
            echo -e "\n$(log 'Found device in DFU mode.')"
            device_mode="DFU"
            return
        fi
        sleep 1
    done
    echo
    if [[ $2 == "WTFreal" ]]; then
        device_find_mode WTFreal
    else
        device_find_mode DFU
    fi
}

device_enter_mode() {
    # usage: device_enter_mode {Recovery, DFU, kDFU, pwnDFU}
    # attempt to enter given mode, and device_find_mode function will then set device_mode variable
    local opt
    case $1 in
        "WTFreal" )
            if [[ $device_mode == "WTF" ]]; then
                return
            elif [[ $device_mode == "Normal" ]]; then
                device_enter_mode Recovery
            fi
            if [[ $device_mode == "Recovery" ]]; then
                device_dfuhelper norec WTFreal
                return
            fi
            log "Found an S5L8900 device in $device_mode mode. Your device needs to be in WTF mode to continue."
            print "* Force restart your device and place it in normal or recovery mode, then re-enter WTF mode."
            print "* You can enter WTF mode by doing the DFU mode procedure."
            device_find_mode WTFreal 100
        ;;

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
            fi
        ;;

        "DFU" )
            if [[ $device_mode == "Normal" ]]; then
                device_enter_mode Recovery
            elif [[ $device_mode == "WTF" ]]; then
                device_s5l8900xall
                return
            elif [[ $device_mode == "DFU" ]]; then
                return
            fi
            device_dfuhelper
        ;;

        "kDFU" )
            local sendfiles=()
            local device_det=$(echo "$device_vers" | cut -c 1)
            local IPAddress="127.0.0.1"

            if [[ $device_mode != "Normal" ]]; then
                device_enter_mode pwnDFU
                return
            fi

            patch_ibss
            log "Running iproxy for SSH..."
            $iproxy 2222 22 >/dev/null &
            iproxy_pid=$!
            sleep 1

            log "Please read the message below:"
            print "* Follow these instructions to enter kDFU mode."
            print "1. Install \"OpenSSH\" and \"Core Utilities\" in Cydia or Zebra."
            if [[ $device_det == 1 ]]; then
                print "  - Jailbreak with kok3shiX, and enable \"use legacy patches\""
                print "  - Also install \"Dropbear\" from my repo: https://lukezgd.github.io/repo"
            fi
            print "  - After installing these requirements, lock your device."
            print "2. You will be prompted to enter the root password of your iOS device."
            print "  - The default root password is: alpine"
            print "  - Your input will not be visible, but it is still being entered."
            print "3. On entering kDFU mode, the device will disconnect."
            print "  - Proceed to unplug and replug the device when prompted."
            print "  - Alternatively, press the TOP or HOME button."
            pause

            echo "chmod +x /tmp/kloader*" > kloaders
            if [[ $device_det == 1 ]]; then
                echo '[[ $(uname -a | grep -c "MarijuanARM") == 1 ]] && /tmp/kloader_hgsp /tmp/pwnediBSS || \
                /tmp/kloader /tmp/pwnediBSS' >> kloaders
                sendfiles+=("../resources/kloader/kloader_hgsp" "../resources/kloader/kloader")
            elif [[ $device_det == 5 ]]; then
                if [[ $device_proc == 5 ]]; then
                    opt="kloader5"
                else
                    opt="kloader_axi0mX"
                fi
                log "Using $opt for kloader iOS 5"
                echo "/tmp/$opt /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader/$opt")
            elif (( device_det < 5 )); then
                opt="kloader_axi0mX"
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
                print "* If the script is stuck here, reboot and re-jailbreak the device, and try again."
                print "* Follow the steps in the GitHub wiki under \"A6(X) devices, jailbroken on iOS 10\""
            fi
            log "Sending files to device: ${sendfiles[*]}"
            $scp -P 2222 ${sendfiles[@]} root@127.0.0.1:/tmp
            if [[ $? == 0 ]]; then
                log "Running kloader"
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
                log "Trying again with Wi-Fi SSH..."
                print "* Make sure that your iOS device and PC/Mac are on the same network."
                print "* To get your iOS device's IP Address, go to: Settings -> Wi-Fi/WLAN -> tap the 'i' or '>' next to your network name"
                IPAddress=
                until [[ -n $IPAddress ]]; do
                    read -p "$(input 'Enter the IP Address of your device: ')" IPAddress
                done
                log "Sending files to device: ${sendfiles[*]}"
                $scp ${sendfiles[@]} root@$IPAddress:/tmp
                if [[ $? != 0 ]]; then
                    error "Failed to connect to device via SSH, cannot continue."
                fi
                log "Running kloader"
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
                if [[ $opt == "kloader_axi0mX" ]]; then
                    $ssh -p 2222 root@$IPAddress "bash /tmp/kloaders" &
                else
                    print "* Unplug and replug your device now"
                fi
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

            if [[ $device_proc == 1 ]]; then
                device_enter_mode DFU
                return
            fi
            if [[ $device_mode == "DFU" ]]; then
                irec_pwned=$($irecovery -q | grep -c "PWND")
            fi
            if [[ $device_mode == "DFU" && $mode != "pwned-ibss" && $device_proc != 4 ]] && (( device_proc < 7 )); then
                print "* Select Y if your device is in pwned iBSS/kDFU mode."
                if [[ $device_proc == 5 ]]; then
                    print "* Select N if this is not the case."
                else
                    print "* Select N to place device to pwned DFU mode using ipwndfu/ipwnder."
                fi
                read -p "$(input 'Is your device already in pwned iBSS/kDFU mode? (y/N): ')" opt
                if [[ $opt == "Y" || $opt == "y" ]]; then
                    log "Pwned iBSS/kDFU mode specified by user."
                    return
                fi
            elif [[ $irec_pwned == 1 && $device_proc == 7 ]]; then
                if [[ $platform == "macos" ]]; then
                    ${ipwnder}2 -p
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
            elif [[ $device_type == "iPod2,1" ]]; then
                # touch 2 uses ipwndfu
                device_ipwndfu pwn
                tool_pwned=$?
            elif [[ $platform == "linux" ]]; then
                if [[ $device_type == "iPhone2,1" || $device_type == "iPod3,1" ]]; then
                    # 3gs/touch 3 linux uses ipwnder
                    log "Placing device to pwnDFU mode using ipwnder"
                    $ipwnder -p
                    tool_pwned=$?
                elif [[ $device_proc == 4 || $device_proc == 6 ]]; then
                    # A4/A6 linux uses ipwndfu
                    device_ipwndfu pwn
                    tool_pwned=$?
                else
                    # A7 linux uses gaster
                    log "Placing device to pwnDFU mode using gaster"
                    print "* Unfortunately, success rates for checkm8 are very low on Linux."
                    print "* Pwning using a Mac or another iOS device using iPwnder Lite are better options."
                    print "* For more details, read the \"Troubleshooting\" wiki page in GitHub"
                    print "* Troubleshooting links:"
                    print "    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting"
                    print "    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Pwning-Using-Another-iOS-Device"
                    print "* If pwning gets stuck, you can press Ctrl+C to cancel."
                    $gaster pwn
                    tool_pwned=$?
                fi
            elif (( device_proc > 5 )) && [[ $(uname -m) != "x86_64" ]]; then
                # A6/A7 asi mac uses ipwnder_lite
                log "Placing device to pwnDFU mode using ipwnder_lite"
                opt="${ipwnder}2 -p"
                $opt
                tool_pwned=$?
            else
                # A4/A6/A7 mac uses ipwnder32/ipwnder_lite
                local selection=("ipwnder32" "ipwnder_lite")
                input "PwnDFU Tool Option"
                print "* Select tool to be used for entering pwned DFU mode."
                print "* This option is set to ipwnder32 by default (1). Select this option if unsure."
                print "* If the first option does not work, try many times and/or try the other option(s)."
                input "Select your option:"
                select opt2 in "${selection[@]}"; do
                    case $opt2 in
                        "ipwnder32" ) opt="$ipwnder32 -p"; break;;
                        * )
                            opt="$ipwnder"
                            if (( device_proc > 5 )); then
                                opt+="2 -p"
                            fi
                            break
                        ;;
                    esac
                done
                log "Placing device to pwnDFU mode using: $opt"
                if (( device_proc > 5 )); then
                    print "* If you have an older Mac with Core 2 Duo, success rates for checkm8 are low."
                    print "* Pwning using another Mac or iOS device using iPwnder Lite are available options if needed."
                    print "* For more details, read the \"Troubleshooting\" wiki page in GitHub"
                    print "* Troubleshooting links:"
                    print "    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting"
                    print "    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Pwning-Using-Another-iOS-Device"
                    print "* If pwning gets stuck, you can press Ctrl+C to cancel."
                fi
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
            if [[ $platform == "macos" ]] || (( device_proc > 7 )); then
                return
            elif [[ $device_proc == 7 ]]; then
                device_ipwndfu rmsigchks
            elif [[ $device_proc != 4 ]]; then
                device_ipwndfu send_ibss
            fi
        ;;
    esac
}

device_pwnerror() {
    local error_msg=$'\n* Exit DFU mode by holding the TOP and HOME buttons for about 15 seconds.'
    error_msg+=$'\n* If you have an AMD CPU, you may have to try again on a machine with an Intel CPU.'
    if [[ $platform == "linux" && $device_proc != 4 ]]; then
        error_msg+=$'\n* Unfortunately, success rates for checkm8 are very low on Linux.'
        error_msg+=$'\n* Pwning using a Mac or another iOS device using iPwnder Lite are better options.'
    elif [[ $platform == "macos" ]]; then
        error_msg+=$'\n* If you get the error "No backend available" in ipwndfu, install libusb in Homebrew: brew install libusb'
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
        python2="/usr/bin/python"
    elif [[ -n $python2 && $device_sudoloop == 1 ]]; then
        python2="sudo $python2"
    elif [[ -z $python2 && ! -e $pyenv2 ]]; then
        warn "python2 is not installed. Attempting to install python2 before continuing"
        print "* You may install python2 from pyenv by running: pyenv install 2.7.18"
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
            print "* Try installing pyenv and/or python2 manually:"
            print "    pyenv:   > curl https://pyenv.run | bash"
            print "    python2: > $pyenv install 2.7.18"
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
        device_rd_build=
        patch_ibss
        cp pwnediBSS ../resources/ipwndfu/
    fi

    device_enter_mode DFU
    local ipwndfu_comm="c2ba7abe6b1b8dee962ce8ae7a02fc64d3242d28"
    local ipwndfu_sha1="e385cdf51c8f4faaba43140a468ecbf00c4387ab"
    if [[ ! -d ../resources/ipwndfu || $(cat ../resources/ipwndfu/sha1) != "$ipwndfu_sha1" ]]; then
        rm -rf ../resources/ipwndfu
        download_file https://github.com/LukeZGD/ipwndfu/archive/$ipwndfu_comm.zip ipwndfu.zip $ipwndfu_sha1
        unzip -q ipwndfu.zip -d ../resources
        mv ../resources/ipwndfu*/ ../resources/ipwndfu/
        echo "$ipwndfu_sha1" > ../resources/ipwndfu/sha1
    fi
    if [[ -d /opt/local/lib ]]; then
        ln -sf /opt/local/lib ~/lib
    elif [[ -d /opt/homebrew/lib ]]; then
        ln -sf /opt/homebrew/lib ~/lib
    fi

    pushd ../resources/ipwndfu/ >/dev/null
    case $1 in
        "send_ibss" )
            log "Sending iBSS using ipwndfu..."
            $python2 ipwndfu -l pwnediBSS
            tool_pwned=$?
            rm pwnediBSS
            if [[ $tool_pwned != 0 ]]; then
                popd >/dev/null
                local error_msg
                if [[ $platform == "macos" ]]; then
                    error_msg+=$'\n* If you get the error "No backend available," install libusb in Homebrew: brew install libusb\n'
                fi
                error_msg+="* You might need to exit DFU and (re-)enter PWNED DFU mode before retrying."
                error "Failed to send iBSS. Your device has likely failed to enter PWNED DFU mode." "$error_msg"
            fi
            print "* ipwndfu should have \"done!\" as output."
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
            if [[ $platform == "macos" ]]; then
                print "* If you get the error \"No backend available,\" install libusb in Homebrew: brew install libusb"
            fi
        ;;
    esac
    popd >/dev/null
    return $tool_pwned
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
    if [[ $(echo "$url" | grep -c '<') != 0 ]]; then
        rm "$device_fw_dir/$build_id/url"
        url=
    fi
    if [[ -z $url ]]; then
        log "Getting URL for $device_type-$build_id"
        url="$(curl "https://api.ipsw.me/v4/ipsw/$device_type/$build_id" | $jq -j ".url")"
        if [[ $(echo "$url" | grep -c '<') != 0 ]]; then
            url="$(curl "https://api.ipsw.me/v4/device/$device_type?type=ipsw" | $jq -j ".firmwares[] | select(.buildid == \"$build_id\") | .url")"
        fi
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
        iPhone3,[123] ) build_id="11D257";;
        * ) build_id="12H321";;
    esac
    if [[ -n $device_rd_build ]]; then
        build_id="$device_rd_build"
    fi
    download_comp $build_id iBSS
    device_fw_key_check temp $build_id
    local iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .iv')
    local key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .key')
    log "Decrypting iBSS..."
    "$dir/xpwntool" iBSS iBSS.dec -iv $iv -k $key
    log "Patching iBSS..."
    "$dir/iBoot32Patcher" iBSS.dec pwnediBSS --rsa
    "$dir/xpwntool" pwnediBSS pwnediBSS.dfu -t iBSS
    cp pwnediBSS pwnediBSS.dfu ../saved/$device_type/
    log "Pwned iBSS saved at: saved/$device_type/pwnediBSS"
    log "Pwned iBSS img3 saved at: saved/$device_type/pwnediBSS.dfu"
}

patch_ibec() {
    # creates file pwnediBEC to be sent to device for blob dumping
    local build_id
    case $device_type in
        iPad1,1 | iPod3,1 )
            build_id="9B206";;
        iPhone2,1 | iPhone3,[123] | iPod4,1 )
            build_id="10A403";;
        iPad2,[367] | iPad3,[25] )
            build_id="12H321";;
        iPad3,1 )
            build_id="10B146";;
        iPhone5,3 )
            build_id="11B511";;
        iPhone5,4 )
            build_id="11B651";;
        * )
            build_id="10B329";;
    esac
    if [[ -n $device_rd_build ]]; then
        build_id="$device_rd_build"
    fi
    download_comp $build_id iBEC
    device_fw_key_check temp $build_id
    local name="iBEC"
    local iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .iv')
    local key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .key')
    local address="0x80000000"
    if [[ $device_proc == 4 ]]; then
        address="0x40000000"
    fi
    mv iBEC $name.orig
    log "Decrypting iBEC..."
    "$dir/xpwntool" $name.orig $name.dec -iv $iv -k $key
    log "Patching iBEC..."
    if [[ $device_proc == 4 || -n $device_rd_build ]]; then
        "$dir/iBoot32Patcher" $name.dec $name.patched --rsa --debug -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1" -c "go" $address
    else
        $bspatch $name.dec $name.patched "../resources/patch/$download_targetfile.patch"
    fi
    "$dir/xpwntool" $name.patched pwnediBEC.dfu -t $name.orig
    rm $name.dec $name.orig $name.patched
    cp pwnediBEC.dfu ../saved/$device_type/
    log "Pwned iBEC img3 saved at: saved/$device_type/pwnediBEC.dfu"
}

ipsw_preference_set() {
    # sets ipsw variables: ipsw_jailbreak, ipsw_memory, ipsw_verbose

    if (( device_proc >= 7 )); then
        return
    fi

    case $device_latest_vers in
        7.1.2 | 6.1.6 | 5.1.1 | 4.2.1 | 3.1.3 ) ipsw_canjailbreak=1;;
    esac
    if [[ $device_target_vers == "$device_latest_vers" && $ipsw_canjailbreak != 1 ]]; then
        return
    elif [[ $device_target_vers != "$device_latest_vers" ]]; then
        ipsw_canjailbreak=
    fi

    case $device_target_vers in
        9.3.[1234] | 9.3 | 9.2* | 9.1 | 8* | 7* | 6* | 5* | 4* | 3.1.3 ) ipsw_canjailbreak=1;;
    esac
    if [[ $device_proc == 5 ]]; then
        case $device_target_vers in
            8.2 | 8.1* | 8.0* ) ipsw_canjailbreak=;;
        esac
    fi

    if [[ $device_target_powder == 1 ]]; then
        ipsw_canjailbreak=
        case $device_target_vers in
            4.2.1 | 4.1 | 4.0* | 3* ) :;;
            * ) ipsw_canjailbreak=1;;
        esac
    elif [[ $device_target_other == 1 && $ipsw_canjailbreak != 1 ]]; then
        return
    fi

    if [[ $device_target_vers == "3.1"* && $device_proc != 1 && $device_target_powder != 1 ]]; then
        log "Jailbreak Option is always enabled for 3.1.x ($device_target_vers)"
        ipsw_jailbreak=1
    elif [[ -z $ipsw_jailbreak && $ipsw_canjailbreak == 1 ]]; then
        input "Jailbreak Option"
        print "* When this option is enabled, your device will be jailbroken on restore."
        print "* I recommend to enable this option to have the jailbreak and Cydia pre-installed."
        print "* This option is enabled by default (Y). Select this option if unsure."
        if [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* && $device_target_tethered != 1 ]]; then
            warn "This will be a semi-tethered jailbreak. Arduino is required to boot to a jailbroken state."
            print "* To boot jailbroken later, go to: Other Utilities -> Just Boot"
        fi
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

    if [[ $ipsw_jailbreak == 1 && -z $ipsw_hacktivate && $device_canhacktivate == 1 ]]; then
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
    elif [[ $ipsw_jailbreak != 1 ]] &&
         [[ $device_type == "iPhone1"* || $device_type == "iPhone2,1" ]]; then
        log "Hacktivate option is not available. Jailbreak option must be enabled"
        echo
    fi

    if [[ -n $ipsw_memory ]]; then
        :
    elif [[ $ipsw_jailbreak == 1 || $device_type == "$device_disable_bbupdate" ||
            $device_target_powder == 1 || $device_target_tethered == 1 ||
            $device_type == "iPhone2,1" || $device_type == "iPod2,1" ]] ||
         [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* ]] ||
         [[ $device_type == "iPad1,1" && $device_target_vers != "5"* ]] ||
         [[ $device_type == "iPod3,1" && $device_target_vers != "5"* ]] ||
         [[ $device_type == "iPod4,1" && $device_target_vers == "4"* ]] ||
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
    local cutver
    local device
    local IPSWSHA1=$(cat "$device_fw_dir/$build_id/sha1sum" 2>/dev/null)
    case $build_id in
        *[bcdefgkpquv] ) return;;
    esac
    case $build_id in
        7*  ) cutver=3;;
        8*  ) cutver=4;;
        9*  ) cutver=5;;
        10* ) cutver=6;;
        11* ) cutver=7;;
        12* ) cutver=8;;
        13* ) cutver=9;;
        14* ) cutver=10;;
        15* ) cutver=11;;
        16* ) cutver=12;;
        17* ) cutver=13;;
        18* ) cutver=14;;
        19* ) cutver=15;;
    esac
    case $device_type in
        iPad4,[123] | iPad5,[34] ) device="iPad_Air";;
        iPad2,[567] | iPad[45],* ) device="iPad_mini";;
        iPad* ) device="iPad";;
        iPho* ) device="iPhone";;
        iPod* ) device="iPod_touch";;
    esac
    if [[ $(echo "$IPSWSHA1" | grep -c '<') != 0 ]]; then
        rm "$device_fw_dir/$build_id/sha1sum"
        IPSWSHA1=
    fi
    if [[ -z $IPSWSHA1 ]]; then
        log "Getting SHA1 hash from The Apple Wiki..."
        IPSWSHA1="$(curl "https://theapplewiki.com/index.php?title=Firmware/${device}/${cutver}.x" | grep -A2 "${device_type}.*${build_id}" | sed -ne '/<code>/,/<\/code>/p' | sed -e "s/<code>//" | sed "s/<\/code>//" | cut -c 5-)"
        mkdir $device_fw_dir/$build_id 2>/dev/null
        echo "$IPSWSHA1" > $device_fw_dir/$build_id/sha1sum
    fi
    if [[ -z $IPSWSHA1 ]]; then
        log "Getting SHA1 hash from ipsw.me..."
        IPSWSHA1="$(curl "https://api.ipsw.me/v4/ipsw/$device_type/$build_id" | $jq -j ".sha1sum")"
        if [[ $(echo "$IPSWSHA1" | grep -c '<') != 0 ]]; then
            IPSWSHA1="$(curl "https://api.ipsw.me/v4/device/$device_type?type=ipsw" | $jq -j ".firmwares[] | select(.buildid == \"$build_id\") | .sha1sum")"
        fi
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
    if [[ $build_id == "$device_base_build" ]]; then
        device_base_sha1="$IPSWSHA1"
    else
        device_target_sha1="$IPSWSHA1"
    fi
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

ipsw_prepare_rebootsh() {
    log "Generating reboot.sh"
    echo '#!/bin/bash' | tee reboot.sh
    echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" | tee -a reboot.sh
    echo "nvram -d boot-partition; nvram -d boot-ramdisk" | tee -a reboot.sh
    echo "/usr/bin/haxx_overwrite --${device_type}_${device_target_build}" | tee -a reboot.sh
}

ipsw_prepare_jailbreak() {
    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi
    local ExtraArgs=
    local JBFiles=()
    local JBFiles2=()
    local daibutsu

    if [[ $1 == "old" ]]; then
        daibutsu="old"
    fi
    if [[ $ipsw_jailbreak == 1 ]]; then
        if [[ $device_target_vers == "8.4.1" ]]; then
            ipsw_prepare_rebootsh
            JBFiles+=("$jelbrek/fstab8.tar")
            JBFiles2=("daibutsu/bin.tar" "daibutsu/untether.tar" "freeze.tar")
            for i in {0..2}; do
                cp $jelbrek/${JBFiles2[$i]} .
            done
            ExtraArgs+="-daibutsu" # use daibutsuCFW
            daibutsu="daibutsu"
        else
            JBFiles+=("fstab_rw.tar" "freeze.tar")
            case $device_target_vers in
                6.1.[3456] ) JBFiles+=("p0sixspwn.tar");;
                6* ) JBFiles+=("evasi0n6-untether.tar");;
                4.2.1 | 4.1 | 4.0* | 3.1.3 )
                    JBFiles[0]="fstab_old.tar"
                    if [[ $device_proc != 1 ]]; then
                        JBFiles+=("greenpois0n/${device_type}_${device_target_build}.tar")
                    fi
                ;;
                5* | 4.3* | 4.2* ) JBFiles+=("g1lbertJB/${device_type}_${device_target_build}.tar");;
            esac
            for i in {0..1}; do
                JBFiles[i]=$jelbrek/${JBFiles[$i]}
            done
            if [[ $device_proc != 1 ]]; then
                case $device_target_vers in
                    4.3* )
                        JBFiles[2]=$jelbrek/${JBFiles[2]}
                        if [[ $device_type == "iPad2"* ]]; then
                            JBFiles[2]=
                        fi
                    ;;
                    4.2.1 )
                        ExtraArgs+="-punchd"
                        JBFiles[2]=$jelbrek/${JBFiles[2]}
                    ;;
                    3.1 | 3.1.[12] ) JBFiles[0]="$jelbrek/fstab_old.tar";;
                    * ) JBFiles[2]=$jelbrek/${JBFiles[2]};;
                esac
            fi
            if [[ $device_target_vers == "4"* || $device_target_vers == "5"* ]]; then
                JBFiles+=("$jelbrek/cydiasubstrate.tar")
            fi
            if [[ $device_target_vers == "3"* ]]; then
                JBFiles+=("$jelbrek/cydiahttpatch.tar")
            fi
            if [[ $device_target_vers == "5"* ]]; then
                JBFiles+=("$jelbrek/g1lbertJB.tar")
            fi
        fi
        ExtraArgs+=" -S 30" # system partition add
        if [[ $ipsw_openssh == 1 ]]; then
            JBFiles+=("$jelbrek/sshdeb.tar")
        fi
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
    if [[ $1 == "iboot" ]]; then
        ExtraArgs+=" iBoot.tar"
    fi

    log "Preparing custom IPSW: $dir/ipsw $ipsw_path.ipsw temp.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/ipsw" "$ipsw_path.ipsw" temp.ipsw $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_keys() {
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
            if [[ -z $name ]]; then
                name="$getcomp.${device_model}ap.RELEASE.dfu"
            fi
            echo -e "<key>$comp</key><dict><key>File</key><string>Firmware/dfu/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
            if [[ -s $FirmwareBundle/$comp.${device_model}ap.RELEASE.patch ]]; then
                echo -e "<key>Patch</key><string>$comp.${device_model}ap.RELEASE.patch</string>" >> $NewPlist
            elif [[ -s $FirmwareBundle/$comp.${device_model}.RELEASE.patch ]]; then
                echo -e "<key>Patch</key><string>$comp.${device_model}.RELEASE.patch</string>" >> $NewPlist
            else
                echo -e "<key>Patch</key><true/>" >> $NewPlist
            fi
        ;;

        "iBoot" )
            echo -e "<key>$comp</key><dict><key>File</key><string>Firmware/all_flash/all_flash.${device_model}ap.production/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
            echo -e "<key>Patch</key><string>$comp.${device_model}ap.RELEASE.patch</string>" >> $NewPlist
        ;;

        "RestoreRamdisk" )
            echo -e "<key>Restore Ramdisk</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
        ;;

        "RestoreDeviceTree" | "RestoreLogo" )
            echo -e "<key>$comp</key><dict><key>File</key><string>Firmware/all_flash/all_flash.${device_model}ap.production/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string>" >> $NewPlist
        ;;

        "RestoreKernelCache" )
            echo -e "<key>$comp</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string>" >> $NewPlist
        ;;

        "KernelCache" )
            echo -e "<key>$comp</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string>" >> $NewPlist
            if [[ -e $FirmwareBundle/kernelcache.release.patch ]]; then
                echo -e "<key>Patch</key><string>kernelcache.release.patch</string>" >> $NewPlist
            else
                echo -e "<key>Patch</key><true/>" >> $NewPlist
            fi
        ;;

        "WTF2" )
            echo -e "<key>WTF 2</key><dict><key>File</key><string>Firmware/dfu/WTF.s5l8900xall.RELEASE.dfu</string><key>Patch</key><string>WTF.s5l8900xall.RELEASE.patch</string>" >> $NewPlist
        ;;
    esac
    if [[ $2 != "old" ]]; then
        echo -e "<key>Decrypt</key><true/>" >> $NewPlist
    fi
    echo -e "</dict>" >> $NewPlist
}

ipsw_prepare_paths() {
    local comp="$1"
    local getcomp="$1"
    case $comp in
        "BatteryPlugin" ) getcomp="GlyphPlugin";;
        "NewAppleLogo" | "APTicket" ) getcomp="AppleLogo";;
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
            "APTicket" ) str2="${name/applelogo/applelogoT}";;
            "RecoveryMode" ) str2="${name/recoverymode/recoverymode7}";;
            "NewiBoot" ) str2="${name/iBoot/iBoot$(echo $device_target_vers | cut -c 1)}";;
        esac
        case $comp in
            "AppleLogo" | "APTicket" | "RecoveryMode" )
                str+="$str2"
                echo "$str2" >> $FirmwareBundle/manifest
            ;;
            "NewiBoot" )
                if [[ $device_type != "iPad1,1" ]]; then
                    str+="$str2"
                    echo "$str2" >> $FirmwareBundle/manifest
                fi
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
    local daibutsu
    FirmwareBundle="FirmwareBundles/"
    if [[ $1 == "daibutsu" ]]; then
        daibutsu=1
    fi

    mkdir FirmwareBundles 2>/dev/null
    if [[ $1 == "base" ]]; then
        ipsw_p="$ipsw_base_path"
        key="$device_fw_key_base"
        vers="$device_base_vers"
        build="$device_base_build"
        FirmwareBundle+="BASE_"
    elif [[ $1 == "target" ]]; then
        if [[ $ipsw_jailbreak == 1 ]]; then
            case $vers in
                [457]* ) ipsw_prepare_config false true;;
                * ) ipsw_prepare_config true true;;
            esac
        else
            ipsw_prepare_config false true
        fi
    elif [[ $ipsw_jailbreak == 1 ]]; then
        ipsw_prepare_config false true
    else
        ipsw_prepare_config false false
    fi
    local FirmwareBundle2="../resources/firmware/FirmwareBundles/Down_${device_type}_${vers}_${build}.bundle"
    if [[ $device_target_powder == 1 && $device_target_vers == "4.3"* ]]; then
        FirmwareBundle2=
    elif [[ $device_target_powder == 1 || $device_target_other == 1 ]] && [[ $device_proc != 4 ]]; then
        FirmwareBundle2=
    elif [[ -d $FirmwareBundle2 ]]; then
        FirmwareBundle+="Down_"
    fi
    FirmwareBundle+="${device_type}_${vers}_${build}.bundle"
    local NewPlist=$FirmwareBundle/Info.plist
    mkdir -p $FirmwareBundle

    log "Generating firmware bundle for $device_type-$vers ($build) $1..."
    unzip -o -j "$ipsw_p.ipsw" Firmware/all_flash/all_flash.${device_model}ap.production/manifest
    mv manifest $FirmwareBundle/
    local ramdisk_name=$(echo "$key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .filename')
    local RamdiskIV=$(echo "$key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .iv')
    local RamdiskKey=$(echo "$key" | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .key')
    unzip -o -j "$ipsw_p.ipsw" $ramdisk_name
    "$dir/xpwntool" $ramdisk_name Ramdisk.raw -iv $RamdiskIV -k $RamdiskKey
    "$dir/hfsplus" Ramdisk.raw extract usr/local/share/restore/options.$device_model.plist
    if [[ ! -s options.$device_model.plist ]]; then
        rm options.$device_model.plist
        "$dir/hfsplus" Ramdisk.raw extract usr/local/share/restore/options.plist
        mv options.plist options.$device_model.plist
    fi
    if [[ $device_target_vers == "3.2"* ]]; then
        RootSize=1000
    elif [[ $device_target_vers == "3"* ]]; then
        case $device_type in
            iPod1,1      ) RootSize=413;;
            iPhone1,[12] ) RootSize=420;;
            iPod2,1      ) RootSize=450;;
            *            ) RootSize=750;;
        esac
    elif [[ $platform == "macos" ]]; then
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
    printf "<key>RamdiskOptionsPath</key><string>/usr/local/share/restore/options" >> $NewPlist
    if [[ $device_target_vers != "3"* && $device_target_vers != "4"* ]] ||
       [[ $device_type == "iPad1,1" && $device_target_vers == "4"* ]]; then
        printf ".%s" "$device_model" >> $NewPlist
    fi
    echo -e ".plist</string>" >> $NewPlist
    if [[ $1 == "base" ]]; then
        echo -e "<key>SHA1</key><string>$device_base_sha1</string>" >> $NewPlist
    else
        echo -e "<key>SHA1</key><string>$device_target_sha1</string>" >> $NewPlist
    fi

    if [[ $1 == "base" ]]; then
        case $device_type in
            iPhone5,[12] ) hw="iphone5";;
            iPhone5,[34] ) hw="iphone5b";;
            iPad3,[456] )  hw="ipad3b";;
        esac
        case $device_base_build in
            "11A"* | "11B"* ) base_build="11B554a";;
            "9"* ) base_build="9B206";;
        esac
        echo -e "<key>RamdiskExploit</key><dict>" >> $NewPlist
        echo -e "<key>exploit</key><string>src/target/$hw/$base_build/exploit</string>" >> $NewPlist
        echo -e "<key>inject</key><string>src/target/$hw/$base_build/partition</string></dict>" >> $NewPlist
    elif [[ $1 == "target" ]]; then
        echo -e "<key>FilesystemPackage</key><dict><key>bootstrap</key><string>freeze.tar</string>" >> $NewPlist
        case $vers in
            8* | 9* ) echo -e "<key>package</key><string>src/ios9.tar</string>" >> $NewPlist;;
        esac
        printf "</dict><key>RamdiskPackage</key><dict><key>package</key><string>src/bin.tar</string><key>ios</key><string>ios" >> $NewPlist
        case $vers in
            3* ) printf "3" >> $NewPlist;;
            4* ) printf "4" >> $NewPlist;;
            5* ) printf "5" >> $NewPlist;;
            6* ) printf "6" >> $NewPlist;;
            7* ) printf "7" >> $NewPlist;;
            8* ) printf "8" >> $NewPlist;;
            9* ) printf "9" >> $NewPlist;;
        esac
        echo -e "</string></dict>" >> $NewPlist
    elif [[ -d $FirmwareBundle2 ]]; then
        cp $FirmwareBundle2/* $FirmwareBundle
        echo -e "<key>RamdiskPatches</key><dict>" >> $NewPlist
        echo -e "<key>asr</key><dict>" >> $NewPlist
        echo -e "<key>File</key><string>usr/sbin/asr</string><key>Patch</key><string>asr.patch</string></dict>" >> $NewPlist
        if [[ -s $FirmwareBundle/restoredexternal.patch ]]; then
            echo -e "<key>restoredexternal</key><dict>" >> $NewPlist
            echo -e "<key>File</key><string>usr/local/bin/restored_external</string><key>Patch</key><string>restoredexternal.patch</string></dict>" >> $NewPlist
        fi
        echo -e "</dict>" >> $NewPlist
        if [[ $ipsw_hacktivate == 1 ]]; then
            echo -e "<key>FilesystemPatches</key><dict>" >> $NewPlist
            echo -e "<key>Hacktivation</key><array><dict>" >> $NewPlist
            echo -e "<key>Action</key><string>Patch</string><key>File</key><string>usr/libexec/lockdownd</string>" >> $NewPlist
            echo -e "<key>Patch</key><string>lockdownd.patch</string></dict></array></dict>" >> $NewPlist
        else
            echo -e "<key>FilesystemPatches</key><dict/>" >> $NewPlist # ipsw segfaults if this is missing lol
        fi
    else
        echo -e "<key>FilesystemPackage</key><dict/><key>RamdiskPackage</key><dict/>" >> $NewPlist
    fi

    if [[ $1 == "base" ]]; then
        echo -e "<key>Firmware</key><dict/>" >> $NewPlist
    elif [[ $1 == "target" && $vers == "4"* ]]; then
        echo -e "<key>Firmware</key><dict>" >> $NewPlist
        ipsw_prepare_keys iBSS $1
        ipsw_prepare_keys RestoreRamdisk $1
        echo -e "</dict>" >> $NewPlist
    else
        if [[ -d $FirmwareBundle2 ]]; then
            echo -e "<key>FirmwarePatches</key><dict>" >> $NewPlist
        else
            echo -e "<key>Firmware</key><dict>" >> $NewPlist
        fi
        ipsw_prepare_keys iBSS $1
        # ios 4 and lower do not need ibec patches. the exception is the ipad lineup
        if [[ $vers != "3"* && $vers != "4"* ]] || [[ $device_type == "iPad1,1" || $device_type == "iPad2"* ]]; then
            ipsw_prepare_keys iBEC $1
        fi
        ipsw_prepare_keys RestoreRamdisk $1
        ipsw_prepare_keys RestoreDeviceTree $1
        ipsw_prepare_keys RestoreLogo $1
        if [[ $1 == "target" ]]; then
            case $vers in
                [457]* ) ipsw_prepare_keys RestoreKernelCache $1;;
                * ) ipsw_prepare_keys KernelCache $1;;
            esac
        else
            ipsw_prepare_keys RestoreKernelCache $1
        fi
        if [[ $1 == "old" ]]; then
            if [[ $device_type == "iPod2,1" ]]; then
                case $device_target_vers in
                    4.2.1 | 4.1 | 3.1.3 ) :;;
                    * )
                        ipsw_prepare_keys iBoot $1
                        ipsw_prepare_keys KernelCache $1
                    ;;
                esac
            elif [[ $device_proc == 1 ]]; then
                ipsw_prepare_keys iBoot $1
                ipsw_prepare_keys KernelCache $1
                ipsw_prepare_keys WTF2 $1
            else
                case $device_target_vers in
                    6.1.6 | 4.1 ) :;;
                    3.0* ) ipsw_prepare_keys iBoot $1;;
                    * )
                        ipsw_prepare_keys iBoot $1
                        ipsw_prepare_keys KernelCache $1
                    ;;
                esac
            fi
        fi
        echo -e "</dict>" >> $NewPlist
    fi

    if [[ $1 == "base" ]]; then
        echo -e "<key>FirmwarePath</key><dict>" >> $NewPlist
        ipsw_prepare_paths AppleLogo $1
        ipsw_prepare_paths BatteryCharging0 $1
        ipsw_prepare_paths BatteryCharging1 $1
        ipsw_prepare_paths BatteryFull $1
        ipsw_prepare_paths BatteryLow0 $1
        ipsw_prepare_paths BatteryLow1 $1
        ipsw_prepare_paths BatteryPlugin $1
        ipsw_prepare_paths RecoveryMode $1
        ipsw_prepare_paths LLB $1
        ipsw_prepare_paths iBoot $1
        echo -e "</dict>" >> $NewPlist
    elif [[ $1 == "target" ]]; then
        echo -e "<key>FirmwareReplace</key><dict>" >> $NewPlist
        if [[ $vers == "4"* ]]; then
            ipsw_prepare_paths APTicket $1
        fi
        ipsw_prepare_paths AppleLogo $1
        ipsw_prepare_paths NewAppleLogo $1
        ipsw_prepare_paths BatteryCharging0 $1
        ipsw_prepare_paths BatteryCharging1 $1
        ipsw_prepare_paths BatteryFull $1
        ipsw_prepare_paths BatteryLow0 $1
        ipsw_prepare_paths BatteryLow1 $1
        ipsw_prepare_paths BatteryPlugin $1
        ipsw_prepare_paths RecoveryMode $1
        ipsw_prepare_paths NewRecoveryMode $1
        ipsw_prepare_paths LLB $1
        ipsw_prepare_paths iBoot $1
        ipsw_prepare_paths NewiBoot $1
        ipsw_prepare_paths manifest $1
        echo -e "</dict>" >> $NewPlist
    fi

    if [[ $daibutsu == 1 ]]; then
        if [[ -d $FirmwareBundle2 ]]; then
            echo -e "<key>PackagePath</key><string>./freeze.tar</string>" >> $NewPlist
            echo -e "<key>RamdiskPackage</key>" >> $NewPlist
        else
            echo -e "<key>RamdiskPackage2</key>" >> $NewPlist
        fi
        echo -e "<string>./bin.tar</string><key>RamdiskReboot</key><string>./reboot.sh</string><key>UntetherPath</key><string>./untether.tar</string>" >> $NewPlist
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
        case $device_type in
            iPad* | iPhone3* | iPod[34],1 ) ipsw_prepare_jailbreak;;
            * )
                if [[ $ipsw_jailbreak == 1 ]]; then
                    ipsw_prepare_custom
                fi
            ;;
        esac
        return
    elif [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    elif [[ $device_type != "$device_disable_bbupdate" && $ipsw_jailbreak != 1 &&
            $device_target_build != "9A406" && # the 4s-exclusive 9a406 has unencrypted ramdisks, needs custom ipsw since futurerestore breaks (it expects encrypted ramdisks)
            $device_proc != 4 && $device_actrec != 1 && $device_target_tethered != 1 ]]; then
        log "No need to create custom IPSW for non-jailbroken restores on $device_type-$device_target_build"
        return
    elif [[ $ipsw_jailbreak == 1 && $device_target_vers == "8"* ]]; then
        daibutsu="daibutsu"
        ExtraArgs+=" -daibutsu"
        cp $jelbrek/daibutsu/bin.tar $jelbrek/daibutsu/untether.tar .
        ipsw_prepare_rebootsh
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
            9.3.[1234] | 9.3 ) JBFiles+=("untetherhomedepot.tar");;
            9.2* | 9.1 ) JBFiles+=("untetherhomedepot921.tar");;
            7.1* )       JBFiles+=("panguaxe.tar");;
            7* )         JBFiles+=("evasi0n7-untether.tar");;
            6.1.[3456] ) JBFiles+=("p0sixspwn.tar");;
            6* )         JBFiles+=("evasi0n6-untether.tar");;
            5* )         JBFiles+=("g1lbertJB/${device_type}_${device_target_build}.tar")
            ;;
        esac
        if [[ -n ${JBFiles[0]} ]]; then
            JBFiles[0]=$jelbrek/${JBFiles[0]}
        fi
        case $device_target_vers in
            9* | 8* ) JBFiles+=("$jelbrek/fstab8.tar");;
            7* ) JBFiles+=("$jelbrek/fstab7.tar");;
            * )  JBFiles+=("$jelbrek/fstab_rw.tar");;
        esac
        JBFiles+=("$jelbrek/freeze.tar")
        if [[ $device_target_vers == "5"* ]]; then
            JBFiles+=("$jelbrek/cydiasubstrate.tar" "$jelbrek/g1lbertJB.tar")
        fi
        if [[ $ipsw_openssh == 1 ]]; then
            JBFiles+=("$jelbrek/sshdeb.tar")
        fi
        if [[ $device_target_tethered == 1 ]]; then
            case $device_target_vers in
                4.2.1 ) :;;
                5* | 4.3* | 4.2* ) JBFiles+=("$jelbrek/g1lbertJB/install.tar");;
            esac
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

patch_iboot() {
    device_fw_key_check
    local iboot_name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBoot")) | .filename')
    local iboot_iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBoot")) | .iv')
    local iboot_key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBoot")) | .key')
    log "Patch iBoot: $*"
    unzip -o -j "$ipsw_path.ipsw" Firmware/all_flash/all_flash.${device_model}ap.production/$iboot_name
    mv $iboot_name ibot
    "$dir/xpwntool" ibot ibot.dec -iv $iboot_iv -k $iboot_key
    "$dir/iBoot32Patcher" ibot.dec ibot.pwned --rsa "$@"
    "$dir/xpwntool" ibot.pwned iBoot -t ibot
    rm ibot*
    echo "0000010: 6365" | xxd -r - iBoot
    echo "0000020: 6365" | xxd -r - iBoot
}

ipsw_patch_file() {
    # usage: ipsw_patch_file <ramdisk/fs> <location> <filename> <patchfile>
    "$dir/hfsplus" "$1" extract "$2"/"$3"
    "$dir/hfsplus" "$1" rm "$2"/"$3"
    $bspatch "$3" "$3".patched "$4"
    "$dir/hfsplus" "$1" add "$3".patched "$2"/"$3"
    "$dir/hfsplus" "$1" chmod 755 "$2"/"$3"
    "$dir/hfsplus" "$1" chown 0:0 "$2"/"$3"
}

ipsw_prepare_ios4multipart() {
    local JBFiles=()
    ipsw_custom_part2="${device_type}_${device_target_vers}_${device_target_build}_CustomNP-${device_ecid}"
    local all_flash2="Firmware/all_flash/all_flash.${device_model}ap.production"
    local all_flash="$ipsw_custom_part2/$all_flash2"
    local ExtraArgs2="--boot-partition --boot-ramdisk --logo4 --433"
    local iboot

    if [[ -e "../$ipsw_custom_part2.ipsw" && -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSWs. Skipping IPSW creation."
        return
    elif [[ -e "../$ipsw_custom_part2.ipsw" || -e "$ipsw_custom.ipsw" ]]; then
        rm "../$ipsw_custom_part2.ipsw" "$ipsw_custom.ipsw" 2>/dev/null
    fi

    log "Preparing NOR flash IPSW..."
    mkdir -p $ipsw_custom_part2/Firmware/dfu $ipsw_custom_part2/Downgrade $all_flash

    local comps=()
    local name
    local iv
    local key
    local path
    local vers="5.1.1"
    local build="9B206"
    local saved_path="../saved/$device_type/$build"
    local url="$(cat $device_fw_dir/$build/url)"
    device_fw_key_check temp $build

    mkdir -p $saved_path
    log "Getting $vers restore components"
    comps+=("iBSS" "iBEC" "DeviceTree" "Kernelcache" "RestoreRamdisk")
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
        iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
        key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" ) path="Firmware/all_flash/all_flash.${device_model}ap.production/";;
            * ) path="";;
        esac
        log "$getcomp"
        if [[ $vers == "$device_base_vers" ]]; then
            unzip -o -j "$ipsw_base_path.ipsw" ${path}$name
        elif [[ -e $saved_path/$name ]]; then
            cp $saved_path/$name .
        else
            "$dir/pzb" -g "${path}$name" -o "$name" "$url"
            cp $name $saved_path/
        fi
        case $getcomp in
            "DeviceTree" )
                "$dir/xpwntool" $name $ipsw_custom_part2/Downgrade/RestoreDeviceTree -iv $iv -k $key -decrypt
            ;;
            "Kernelcache" )
                "$dir/xpwntool" $name $ipsw_custom_part2/Downgrade/RestoreKernelCache -iv $iv -k $key -decrypt
            ;;
            * )
                mv $name $getcomp.orig
                "$dir/xpwntool" $getcomp.orig $getcomp.dec -iv $iv -k $key
            ;;
        esac
    done

    log "Patch iBSS"
    "$dir/iBoot32Patcher" iBSS.dec iBSS.patched --rsa
    "$dir/xpwntool" iBSS.patched $ipsw_custom_part2/Firmware/dfu/iBSS.${device_model}ap.RELEASE.dfu -t iBSS.orig

    log "Patch iBEC"
    "$dir/iBoot32Patcher" iBEC.dec iBEC.patched --rsa --ticket -b "rd=md0 -v nand-enable-reformat=1 amfi=0xff cs_enforcement_disable=1"
    "$dir/xpwntool" iBEC.patched $ipsw_custom_part2/Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu -t iBEC.orig

    log "Manifest plist"
    if [[ $vers == "$device_base_vers" ]]; then
        unzip -o -j "$ipsw_base_path.ipsw" BuildManifest.plist
    elif [[ -e $saved_path/BuildManifest.plist ]]; then
        cp $saved_path/BuildManifest.plist .
    else
        "$dir/pzb" -g "${path}BuildManifest.plist" -o "BuildManifest.plist" "$url"
        cp BuildManifest.plist $saved_path/
    fi
    cp ../resources/patch/old/$device_type/$vers/* .
    patch BuildManifest.plist < BuildManifest.patch
    cp BuildManifest.plist $ipsw_custom_part2/

    log "Restore Ramdisk"
    local ramdisk_name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .filename')
    mv RestoreRamdisk.dec ramdisk.dec
    "$dir/hfsplus" ramdisk.dec grow 18000000

    log "Dummy RootFS"
    local rootfs_name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "RootFS") | .filename')
    touch $ipsw_custom_part2/$rootfs_name

    log "Modify options.plist"
    local options_plist="options.$device_model.plist"
    echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CreateFilesystemPartitions</key>
    <false/>
    <key>UpdateBaseband</key>
    <false/>
    <key>SystemImage</key>
    <false/>
</dict>
</plist>' | tee $options_plist
    "$dir/hfsplus" ramdisk.dec rm usr/local/share/restore/$options_plist
    "$dir/hfsplus" ramdisk.dec add $options_plist usr/local/share/restore/$options_plist

    log "Patch ASR"
    ipsw_patch_file ramdisk.dec usr/sbin asr asr.patch

    log "Repack Restore Ramdisk"
    "$dir/xpwntool" ramdisk.dec $ipsw_custom_part2/$ramdisk_name -t RestoreRamdisk.orig

    log "Extract all_flash from $device_base_vers base"
    unzip -o -j "$ipsw_base_path.ipsw" Firmware/all_flash/\* -d $all_flash

    log "Add $device_target_vers DeviceTree to all_flash"
    rm $all_flash/DeviceTree.${device_model}ap.img3
    unzip -o -j "$ipsw_path.ipsw" $all_flash2/DeviceTree.${device_model}ap.img3 -d $all_flash

    if [[ $ipsw_verbose == 1 ]]; then
        ExtraArgs2+=" -b -v"
    fi
    patch_iboot $ExtraArgs2
    if [[ $device_type == "iPad1,1" ]]; then
        cp iBoot iBEC
        tar -cvf iBoot.tar iBEC
        iboot="iboot"
    else
        log "Add $device_target_vers iBoot to all_flash"
        echo "0000010: 626F" | xxd -r - iBoot
        echo "0000020: 626F" | xxd -r - iBoot
        mv iBoot $all_flash/iBoot4.img3
        echo "iBoot4.img3" >> $all_flash/manifest
    fi

    log "Add APTicket to all_flash"
    cat "$shsh_path" | sed '64,$d' | sed -ne '/<data>/,/<\/data>/p' | sed -e "s/<data>//" | sed "s/<\/data>//" | tr -d '[:space:]' | base64 --decode > apticket.der
    "$dir/xpwntool" apticket.der $all_flash/applelogoT.img3 -t ../resources/firmware/src/scab_template.img3
    echo "applelogoT.img3" >> $all_flash/manifest

    log "AppleLogo"
    local logo_name="$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "AppleLogo") | .filename')"
    unzip -o -j "$ipsw_path.ipsw" $all_flash2/$logo_name
    echo "0000010: 3467" | xxd -r - $logo_name
    echo "0000020: 3467" | xxd -r - $logo_name
    mv $logo_name $all_flash/applelogo4.img3
    log "Add AppleLogo to all_flash"
    echo "applelogo4.img3" >> $all_flash/manifest

    log "Creating $ipsw_custom_part2.ipsw..."
    pushd $ipsw_custom_part2 >/dev/null
    zip -r0 ../../$ipsw_custom_part2.ipsw *
    popd >/dev/null

    # ------ part 2 (nor flash) ends here. start creating part 1 ipsw ------

    ipsw_prepare_jailbreak $iboot
    mv "$ipsw_custom.ipsw" temp.ipsw
    rm asr* iBSS* iBEC* ramdisk* *.dmg 2>/dev/null
    options_plist="options"
    if [[ $device_type == "iPad1,1" && $device_target_vers == "4"* ]]; then
        options_plist+=".$device_model"
    fi
    options_plist+=".plist"

    vers="4.2.1"
    build="8C148"
    if [[ $device_type == "iPad1,1" ]]; then
        vers="4.3"
        build="8F190"
    elif [[ $device_type == "iPhone3,3" ]]; then
        vers="4.2.10"
        build="8E600"
    fi
    saved_path="../saved/$device_type/$build"
    url="$(cat $device_fw_dir/$build/url)"
    ramdisk_name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .filename')

    mkdir -p $saved_path Downgrade Firmware/dfu 2>/dev/null
    device_fw_key_check temp $build
    log "Getting $vers restore components"
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
        iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
        key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" ) path="Firmware/all_flash/all_flash.${device_model}ap.production/";;
            * ) path="";;
        esac
        log "$getcomp"
        if [[ $vers == "$device_target_vers" ]]; then
            unzip -o -j "$ipsw_path.ipsw" ${path}$name
        elif [[ -e $saved_path/$name ]]; then
            cp $saved_path/$name .
        else
            "$dir/pzb" -g "${path}$name" -o "$name" "$url"
            cp $name $saved_path/
        fi
        case $getcomp in
            "DeviceTree" )
                mv $name Downgrade/RestoreDeviceTree
                zip -r0 temp.ipsw Downgrade/RestoreDeviceTree
            ;;
            "Kernelcache" )
                mv $name Downgrade/RestoreKernelCache
                zip -r0 temp.ipsw Downgrade/RestoreKernelCache
            ;;
            * )
                mv $name $getcomp.orig
                "$dir/xpwntool" $getcomp.orig $getcomp.dec -iv $iv -k $key
            ;;
        esac
    done

    log "Grow ramdisk"
    if [[ $device_type == "iPad1,1" ]]; then
        "$dir/hfsplus" RestoreRamdisk.dec grow 25000000
    else
        "$dir/hfsplus" RestoreRamdisk.dec grow 18000000
    fi

    log "Patch iBSS"
    "$dir/iBoot32Patcher" iBSS.dec iBSS.patched --rsa --debug -b "rd=md0 -v nand-enable-reformat=1 amfi=0xff cs_enforcement_disable=1"
    "$dir/xpwntool" iBSS.patched Firmware/dfu/iBSS.${device_model}ap.RELEASE.dfu -t iBSS.orig
    zip -r0 temp.ipsw Firmware/dfu/iBSS.${device_model}ap.RELEASE.dfu

    log "Patch iBEC"
    "$dir/iBoot32Patcher" iBEC.dec iBEC.patched --rsa --debug -b "rd=md0 -v nand-enable-reformat=1 amfi=0xff cs_enforcement_disable=1"
    "$dir/xpwntool" iBEC.patched Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu -t iBEC.orig
    zip -r0 temp.ipsw Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu

    log "Patch ASR"
    cp ../resources/firmware/FirmwareBundles/Down_${device_type}_${vers}_${build}.bundle/asr.patch .
    ipsw_patch_file RestoreRamdisk.dec usr/sbin asr asr.patch

    log "Extract options.plist from $device_target_vers IPSW"
    unzip -o -j temp.ipsw $ramdisk_name
    mv $ramdisk_name ramdisk2.orig
    "$dir/xpwntool" ramdisk2.orig ramdisk2.dec
    "$dir/hfsplus" ramdisk2.dec extract usr/local/share/restore/$options_plist

    if [[ $device_type == "iPad1,1" && $device_target_vers == "3.2"* ]]; then
        options_plist="options.k48.plist"
        rm $options_plist
        mv options.plist $options_plist
    fi

    log "Modify options.plist"
    "$dir/hfsplus" RestoreRamdisk.dec rm usr/local/share/restore/$options_plist
    cat $options_plist | sed '$d' | sed '$d' > options2.plist
    echo "<key>FlashNOR</key><false/></dict></plist>" >> options2.plist
    cat options2.plist
    "$dir/hfsplus" RestoreRamdisk.dec add options2.plist usr/local/share/restore/$options_plist

    log "Adding exploit and partition stuff"
    cp -R ../resources/firmware/src .
    "$dir/hfsplus" RestoreRamdisk.dec untar src/bin4.tar
    "$dir/hfsplus" RestoreRamdisk.dec mv sbin/reboot sbin/reboot_
    "$dir/hfsplus" RestoreRamdisk.dec add src/target/$device_model/reboot4 sbin/reboot
    "$dir/hfsplus" RestoreRamdisk.dec chmod 755 sbin/reboot

    log "Repack Restore Ramdisk"
    "$dir/xpwntool" RestoreRamdisk.dec $ramdisk_name -t RestoreRamdisk.orig
    log "Add Restore Ramdisk to IPSW"
    zip -r0 temp.ipsw $ramdisk_name
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_tethered() {
    local name
    local iv
    local key
    options_plist="options"
    if [[ $device_type == "iPad1,1" && $device_target_vers == "4"* ]] ||
       [[ $device_target_vers != "3"* && $device_target_vers != "4"* ]]; then
        options_plist+=".$device_model"
    fi
    options_plist+=".plist"

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    ipsw_prepare_32bit

    log "Extract RestoreRamdisk and options.plist"
    device_fw_key_check temp $device_target_build
    name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .filename')
    iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .iv')
    key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .key')
    mv "$ipsw_custom.ipsw" temp.ipsw
    unzip -o -j temp.ipsw $name
    mv $name ramdisk.orig
    "$dir/xpwntool" ramdisk.orig ramdisk.dec -iv $iv -k $key
    "$dir/hfsplus" ramdisk.dec extract usr/local/share/restore/$options_plist

    log "Modify options.plist"
    "$dir/hfsplus" ramdisk.dec rm usr/local/share/restore/$options_plist
    cat $options_plist | sed '$d' | sed '$d' > options2.plist
    echo "<key>FlashNOR</key><false/></dict></plist>" >> options2.plist
    cat options2.plist
    "$dir/hfsplus" ramdisk.dec add options2.plist usr/local/share/restore/$options_plist

    log "Repack Restore Ramdisk"
    "$dir/xpwntool" ramdisk.dec $name -t ramdisk.orig
    log "Add Restore Ramdisk to IPSW"
    zip -r0 temp.ipsw $name
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_ios4powder() {
    local ExtraArgs="-apticket $shsh_path"
    local ExtraArgs2="--boot-partition --boot-ramdisk --logo4 "
    local JBFiles=()

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $ipsw_jailbreak == 1 ]]; then
        JBFiles=("g1lbertJB/${device_type}_${device_target_build}.tar" "fstab_rw.tar" "freeze.tar" "cydiasubstrate.tar")
        for i in {0..3}; do
            JBFiles[i]=$jelbrek/${JBFiles[$i]}
        done
        if [[ $ipsw_openssh == 1 ]]; then
            JBFiles+=("$jelbrek/sshdeb.tar")
        fi
        cp $jelbrek/freeze.tar .
    fi

    ipsw_prepare_bundle target
    ipsw_prepare_bundle base
    cp -R ../resources/firmware/src .
    rm src/target/$device_model/$device_base_build/partition
    mv src/target/$device_model/reboot4 src/target/$device_model/$device_base_build/partition
    rm src/bin.tar
    mv src/bin4.tar src/bin.tar
    ipsw_prepare_config false true
    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation.tar"
    fi
    case $device_target_vers in
        4.3.[45] ) :;;
        * ) ExtraArgs2+="--433 ";;
    esac
    if [[ $ipsw_verbose == 1 ]]; then
        ExtraArgs2+="-b -v"
    fi
    patch_iboot $ExtraArgs2
    tar -rvf src/bin.tar iBoot
    if [[ $device_type == "iPad1,1" ]]; then
        cp iBoot iBEC
        tar -cvf iBoot.tar iBEC
        ExtraArgs+=" iBoot.tar"
    else
        echo "0000010: 626F" | xxd -r - iBoot
        echo "0000020: 626F" | xxd -r - iBoot
    fi
    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw -base $ipsw_base_path.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw -base "$ipsw_base_path.ipsw" $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    log "Applying iOS 4 patches"
    mkdir -p Firmware/all_flash/all_flash.${device_model}ap.production Firmware/dfu
    log "Patch iBSS"
    unzip -o -j "$ipsw_path.ipsw" Firmware/dfu/iBSS.${device_model}ap.RELEASE.dfu
    local ibss_iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .iv')
    local ibss_key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .key')
    mv iBSS.${device_model}ap.RELEASE.dfu iBSS.orig
    "$dir/xpwntool" iBSS.orig iBSS.dec -iv $ibss_iv -k $ibss_key
    "$dir/iBoot32Patcher" iBSS.dec iBSS.patched --rsa --debug -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1"
    "$dir/xpwntool" iBSS.patched Firmware/dfu/iBSS.${device_model}ap.RELEASE.dfu -t iBSS.orig
    log "Patch iBEC"
    unzip -o -j "$ipsw_path.ipsw" Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu
    local ibec_iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .iv')
    local ibec_key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .key')
    mv iBEC.${device_model}ap.RELEASE.dfu iBEC.orig
    "$dir/xpwntool" iBEC.orig iBEC.dec -iv $ibec_iv -k $ibec_key
    "$dir/iBoot32Patcher" iBEC.dec iBEC.patched --rsa --debug -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1"
    "$dir/xpwntool" iBEC.patched Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu -t iBEC.orig
    log "Patch AppleLogo"
    local applelogo_name=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image | startswith("AppleLogo")) | .filename')
    unzip -o -j temp.ipsw Firmware/all_flash/all_flash.${device_model}ap.production/$applelogo_name
    echo "0000010: 3467" | xxd -r - $applelogo_name
    echo "0000020: 3467" | xxd -r - $applelogo_name
    mv $applelogo_name Firmware/all_flash/all_flash.${device_model}ap.production/$applelogo_name

    log "Add all to custom IPSW"
    if [[ $device_type != "iPad1,1" ]]; then
        cp iBoot Firmware/all_flash/all_flash.${device_model}ap.production/iBoot4.${device_model}ap.RELEASE.img3
    fi
    zip -r0 temp.ipsw Firmware/all_flash/all_flash.${device_model}ap.production/* Firmware/dfu/*

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_powder() {
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
        case $device_target_vers in
            "5"* ) ExtraArgs+=" freeze.tar $jelbrek/cydiasubstrate.tar $jelbrek/g1lbertJB.tar $jelbrek/g1lbertJB/${device_type}_${device_target_build}.tar";;
            "7.0"* ) ExtraArgs+=" freeze.tar $jelbrek/evasi0n7-untether.tar $jelbrek/fstab7.tar";;
            "7.1"* ) ExtraArgs+=" freeze.tar $jelbrek/panguaxe.tar $jelbrek/fstab7.tar";;
        esac
        if [[ $ipsw_openssh == 1 ]]; then
            ExtraArgs+=" $jelbrek/sshdeb.tar"
        fi
    fi
    local ExtraArr=("--boot-partition" "--boot-ramdisk")
    if [[ $device_type == "iPhone5"* ]]; then
        # do this stuff because these use ramdiskH (jump to /boot/iBEC) instead of jump ibot to ibob
        if [[ $device_target_vers == "9"* ]]; then
            ExtraArr[0]+="9"
        fi
        if [[ $ipsw_jailbreak == 1 && $ipsw_verbose == 1 && $device_target_vers != "7"* ]]; then
            ExtraArr+=("-b" "-v cs_enforcement_disable=1 amfi_get_out_of_my_way=1")
        elif [[ $ipsw_jailbreak == 1 && $device_target_vers != "7"* ]]; then
            ExtraArr+=("-b" "cs_enforcement_disable=1 amfi_get_out_of_my_way=1")
        elif [[ $ipsw_verbose == 1 ]]; then
            ExtraArr+=("-b" "-v")
        fi
        patch_iboot "${ExtraArr[@]}"
        tar -cvf iBoot.tar iBoot
        ExtraArgs+=" iBoot.tar"
    elif [[ $device_type == "iPad1,1" ]]; then
        if [[ $ipsw_verbose == 1 ]]; then
            ExtraArr+=("-b" "-v")
        fi
        patch_iboot "${ExtraArr[@]}"
        mv iBoot iBEC
        tar -cvf iBoot.tar iBEC
        ExtraArgs+=" iBoot.tar"
    fi
    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw -base $ipsw_base_path.ipsw $ExtraArgs"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw -base "$ipsw_base_path.ipsw" $ExtraArgs

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_patchcomp() {
    local path="Firmware/all_flash/all_flash.${device_model}ap.production"
    local name="LLB.${device_model}ap.RELEASE"
    local patch="../resources/firmware/FirmwareBundles/Down_${device_type}_${device_target_vers}_${device_target_build}.bundle"
    local ext="img3"
    if [[ $1 == "WTF2" ]]; then
        path="Firmware/dfu"
        name="WTF.s5l8900xall.RELEASE"
        ext="dfu"
    fi
    log "Patch $1"
    unzip -o -j "$ipsw_path.ipsw" $path/$name.$ext
    $bspatch $name.$ext $name.patched $patch/$name.patch
    mkdir -p $path
    mv $name.patched $path/$name.$ext
    zip -r0 "$ipsw_custom.ipsw" $path/$name.$ext
}

ipsw_prepare_custom() {
    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    elif [[ $device_target_vers == "4.1" && $ipsw_jailbreak != 1 ]]; then
        log "No need to create custom IPSW for non-jailbroken restores on $device_type-$device_target_build"
        return
    fi

    ipsw_prepare_jailbreak old
    if [[ $device_type == "iPod2,1" ]]; then
        case $device_target_vers in
            4.2.1 | 4.1 | 3.1.3 ) :;;
            * ) ipsw_prepare_patchcomp LLB;;
        esac
    elif [[ $device_proc == 1 ]]; then
        ipsw_prepare_patchcomp LLB
        if [[ $device_target_vers == "4"* ]]; then
            ipsw_prepare_patchcomp WTF2 # just to make sure
        fi
    else
        case $device_target_vers in
            6.1.6 | 4.1 ) :;;
            * ) ipsw_prepare_patchcomp LLB;;
        esac
    fi
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
    if [[ $device_latest_vers == "15"* ]]; then
        return
    elif [[ $device_latest_vers == "$device_use_vers" || $device_target_vers == "10"* ]]; then
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

    mkdir shsh 2>/dev/null
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
    if [[ $1 == "norflash" ]]; then
        cp "$shsh_path" shsh/$device_ecid-$device_type-5.1.1.shsh
    elif [[ $device_type == "iPad1,1" ]] && [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
        patch_ibss
        log "Sending iBSS..."
        $irecovery -f pwnediBSS.dfu
        sleep 1
        log "Sending iBEC..."
        $irecovery -f "$ipsw_custom/Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu"
        device_find_mode Recovery
    elif [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* ]]; then
        ExtraArgs="-e"
        log "Sending iBEC..."
        $irecovery -f "$ipsw_custom/Firmware/dfu/iBEC.${device_model}ap.RELEASE.dfu"
        device_find_mode Recovery
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArgs+="d"
    fi

    log "Running idevicere${re}store with command: $idevicerestore2 $ExtraArgs \"$ipsw_custom.ipsw\""
    $idevicerestore2 $ExtraArgs "$ipsw_custom.ipsw"
    opt=$?
    if [[ $1 == "first" ]]; then
        return $opt
    fi
    echo
    log "Restoring done! Read the message below if any error has occurred:"
    case $device_target_vers in
        1* | 2* | 3* | 4* ) print "* For device activation, go to: Other Utilities -> Attempt Activation";;
    esac
    if [[ $opt != 0 ]]; then
        print "* If the restore failed on updating baseband:"
        print " -> Try disabling baseband update: ./restore.sh --disable-bbupdate"
        echo
    fi
    print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
    print "* Your problem may have already been addressed within the wiki page."
    print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    if [[ $ipsw_jailbreak == 1 ]]; then
        case $device_target_vers in
            4* | 3* ) warn "Do not uninstall Cydia Substrate and Substrate Safe Mode in Cydia!";;
        esac
    fi
}

restore_futurerestore() {
    local ExtraArr=()
    local futurerestore2="$futurerestore"
    local mac_ver=0
    local port=8888
    local opt

    if [[ $1 == "--use-pwndfu" ]]; then
        device_fw_key_check
        if [[ $platform == "macos" ]]; then
            mac_ver=$(echo "$platform_ver" | cut -c -2)
        fi
        pushd ../resources >/dev/null
        if [[ $platform == "macos" ]]; then
            if (( mac_ver >= 12 )); then
                opt="/usr/bin/python3 -m http.server -b 127.0.0.1 $port"
            else
                opt="/usr/bin/python -m SimpleHTTPServer $port"
            fi
        else
            if [[ -z $(which python3) ]]; then
                error "Python 3 is not installed, cannot continue. Make sure to have python3 installed."
            fi
            opt="$(which python3) -m http.server -b 127.0.0.1 $port"
        fi
        log "Starting local server for firmware keys: $opt"
        $opt &
        httpserver_pid=$!
        popd >/dev/null
        log "Waiting for local server"
        until [[ $(curl http://127.0.0.1:$port 2>/dev/null) ]]; do
            sleep 1
        done
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
    if (( device_proc < 7 )); then
        futurerestore2+="_old"
    elif [[ $device_latest_vers == "15"* ]]; then
        futurerestore2="../saved/futurerestore_$platform"
        ExtraArr=("--latest-sep")
        if [[ $restore_baseband == 0 ]]; then
            ExtraArr+=("--no-baseband")
        else
            ExtraArr+=("--latest-baseband")
        fi
        log "New futurerestore will be used for this restore: https://github.com/futurerestore/futurerestore"
        if [[ $platform == "linux" && $platform_arch != "x86_64" ]]; then
            warn "New futurerestore is not supported on this arch, cannot continue. x86_64 only."
            return
        fi
        if [[ ! -e $futurerestore2 ]]; then
            local url="https://nightly.link/futurerestore/futurerestore/workflows/ci/main/"
            local file="futurerestore-"
            case $platform in
                "macos" ) file+="macOS-RELEASE.zip";;
                "linux" ) file+="Linux-x86_64-RELEASE.zip";;
            esac
            url+="$file"
            log "Downloading futurerestore: $url"
            curl -LO "$url"
            unzip -q "$file" -d .
            tar -xJvf futurerestore*.xz
            mv futurerestore $futurerestore2
            chmod +x $futurerestore2
        fi
    else
        futurerestore2+="_new"
    fi
    if [[ -n "$1" ]]; then
        # custom arg, either --use-pwndfu or --skip-blob
        ExtraArr+=("$1")
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArr+=("-d")
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
        print " -> Try restoring with the jailbreak option enabled"
    fi
    print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
    print "* Your problem may have already been addressed within the wiki page."
    print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    kill $httpserver_pid
}

restore_latest() {
    local idevicerestore2="$idevicerestore"
    local ExtraArgs="-e"
    if [[ $device_latest_vers == "12"* || $device_latest_vers == "15"* ]]; then
        idevicerestore2+="2"
        ExtraArgs+="y"
    fi
    if [[ $1 == "custom" ]]; then
        ExtraArgs+="c"
        ipsw_path="$ipsw_custom"
        ipsw_extract custom
    else
        device_enter_mode Recovery
        ipsw_extract
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArgs+="d"
    fi
    log "Running idevicerestore with command: $idevicerestore2 $ExtraArgs \"$ipsw_path.ipsw\""
    $idevicerestore2 $ExtraArgs "$ipsw_path.ipsw"
    opt=$?
    if [[ $1 == "custom" ]]; then
        log "Restoring done! Read the message below if any error has occurred:"
        print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
        print "* Your problem may have already been addressed within the wiki page."
        print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    fi
    case $device_target_vers in
        1* | 2* | 3* | 4* ) print "* For device activation, go to: Other Utilities -> Attempt Activation";;
    esac
    if [[ $ipsw_jailbreak == 1 ]]; then
        case $device_target_vers in
            3* | 4* ) warn "Do not uninstall Cydia Substrate and Substrate Safe Mode in Cydia!";;
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
    sleep 1
    while (( attempt < 5 )); do
        log "Entering pwnREC mode... (Attempt $attempt)"
        log "Sending iBSS..."
        $irecovery -f $iBSS.im4p
        sleep 1
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
            if [[ $device_target_vers == "3.1.3" ]]; then
                device_enter_mode DFU
            else
                device_enter_mode WTFreal
            fi
            if [[ $ipsw_jailbreak != 1 ]]; then
                ipsw_custom="$ipsw_path"
            fi
            restore_latest custom
        ;;

        4 )
            if [[ $device_target_tethered == 1 ]]; then
                shsh_save version $device_latest_vers
                device_enter_mode pwnDFU
                restore_idevicerestore
            elif [[ $device_target_powder == 1 ]]; then
                shsh_save version $device_latest_vers
                if [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
                    device_enter_mode pwnDFU
                else
                    device_buttons
                fi
                case $device_target_vers in
                    "3"* | "4.0"* | "4.1" | "4.2"* )
                        restore_idevicerestore first
                        log "Do not disconnect your device, not done yet"
                        print "* Please put the device in DFU mode after it reboots!"
                        sleep 10
                        device_mode=
                        log "Finding device in Recovery/DFU mode..."
                        until [[ -n $device_mode ]]; do
                            device_mode="$($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-)"
                        done
                        ipsw_custom="../$ipsw_custom_part2"
                        device_enter_mode pwnDFU
                        restore_idevicerestore norflash
                    ;;
                    * ) restore_idevicerestore;;
                esac
                if [[ $device_target_vers == "4.3"* ]] &&
                   [[ $device_type == "iPad1,1" || $device_type == "iPod3,1" ]]; then
                    log "Do not disconnect your device yet"
                    device_find_mode Recovery 50
                    $irecovery -n
                    log "Done, your device should boot now"
                fi
            elif [[ $device_type == "iPhone3"* || $device_type == "iPad1,1" ]]; then
                if [[ $device_target_vers == "$device_latest_vers" ]]; then
                    shsh_save version $device_latest_vers
                fi
                if [[ $device_target_vers == "$device_latest_vers" && $ipsw_jailbreak != 1 ]]; then
                    device_enter_mode Recovery
                    restore_latest
                    return
                fi
                if [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
                    device_enter_mode pwnDFU
                else
                    device_buttons
                fi
                restore_idevicerestore
            else
                if [[ $device_target_other == 1 ]] && [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
                    ipsw_custom="../${device_type}_${device_target_vers}_${device_target_build}_Restore"
                    device_enter_mode DFU
                    restore_idevicerestore
                    if [[ $device_type == "iPhone2,1" ]]; then
                        log "Ignore the baseband error and do not disconnect your device yet"
                        device_find_mode Recovery 50
                        log "Attempting to exit recovery mode"
                        $irecovery -n
                        log "Done, your device should boot now"
                    fi
                elif [[ $device_target_other == 1 ]]; then
                    device_buttons
                    restore_idevicerestore
                elif [[ $device_target_tethered == 1 ]]; then
                    device_enter_mode pwnDFU
                    restore_idevicerestore
                elif [[ $device_target_vers == "4.1" && $ipsw_jailbreak != 1 ]]; then
                    device_enter_mode DFU
                    restore_latest
                    if [[ $device_type == "iPhone2,1" ]]; then
                        log "Ignore the baseband error and do not disconnect your device yet"
                        device_find_mode Recovery 50
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
                else
                    device_enter_mode pwnDFU
                    restore_latest custom
                    if [[ $device_type == "iPhone2,1" ]]; then
                        print "* If the restore succeeded but the device does not boot:"
                        print " -> Go to: Other Utilities -> Install alloc8 Exploit"
                    fi
                fi
            fi
        ;;

        [56] )
            # 32-bit devices A5/A6
            if [[ $device_target_tethered == 1 ]]; then
                shsh_save version $device_latest_vers
                device_enter_mode pwnDFU
                restore_idevicerestore
                return
            elif [[ $device_target_other != 1 && $device_target_powder != 1 ]]; then
                shsh_save
            fi
            if [[ $device_target_vers == "$device_latest_vers" ]]; then
                restore_latest
            else
                if [[ $device_proc == 6 && $platform == "macos" ]]; then
                    device_buttons
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
        if [[ $device_target_vers == "$device_latest_vers" ]]; then
            restore_latest
            return
        fi
        device_enter_mode pwnDFU
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
            if [[ $device_target_tethered == 1 ]]; then
                ipsw_prepare_tethered
            elif [[ $device_target_other == 1 ]]; then
                ipsw_prepare_32bit
            elif [[ $device_target_powder == 1 ]] && [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
                shsh_save version $device_latest_vers
                case $device_target_vers in
                    "4.3"* ) ipsw_prepare_ios4powder;;
                    * ) ipsw_prepare_ios4multipart;;
                esac
            elif [[ $device_target_powder == 1 ]]; then
                ipsw_prepare_powder
            elif [[ $device_target_vers == "$device_latest_vers" ]]; then
                if [[ $ipsw_jailbreak == 1 && $device_type == "iPhone2,1" ]]; then
                    ipsw_prepare_custom
                elif [[ $ipsw_jailbreak == 1 ]]; then
                    ipsw_prepare_32bit
                fi
            else
                ipsw_prepare_custom
            fi
        ;;

        [56] )
            # 32-bit devices A5/A6
            if [[ $device_target_tethered == 1 ]]; then
                ipsw_prepare_tethered
            elif [[ $device_target_powder == 1 ]]; then
                ipsw_prepare_powder
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
    device_ramdisk setnvram $rec
}

device_send_rdtar() {
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
    local comps=("iBSS" "iBEC" "DeviceTree" "Kernelcache")
    local name
    local iv
    local key
    local path
    local url
    local decrypt
    local ramdisk_path
    local build_id
    local mode="$1"
    local rec=2

    if [[ $1 == "setnvram" ]]; then
        rec=$2
    fi
    if [[ $1 != "justboot" ]]; then
        comps+=("RestoreRamdisk")
    fi
    case $device_type in
        iPhone1,[12] | iPod1,1 ) device_target_build="7E18";;
        iPod2,1 ) device_target_build="8C148";;
        iPod3,1 | iPad1,1 ) device_target_build="9B206";;
        iPhone2,1 | iPod4,1 ) device_target_build="10B500";;
        iPhone5,[34] ) device_target_build="11D257";;
        * ) device_target_build="10B329";;
    esac
    if [[ -n $device_rd_build ]]; then
        device_target_build=$device_rd_build
    fi
    build_id=$device_target_build
    ramdisk_path="../saved/$device_type/ramdisk_$build_id"
    device_fw_key_check
    url=$(cat "$device_fw_dir/$build_id/url" 2>/dev/null)
    if [[ $(echo "$url" | grep -c '<') != 0 ]]; then
        rm "$device_fw_dir/$build_id/url"
        url=
    fi
    if [[ -z $url ]]; then
        log "Getting URL for $device_type-$build_id"
        url="$(curl "https://api.ipsw.me/v4/ipsw/$device_type/$build_id" | $jq -j ".url")"
        if [[ $(echo "$url" | grep -c '<') != 0 ]]; then
            url="$(curl "https://api.ipsw.me/v4/device/$device_type?type=ipsw" | $jq -j ".firmwares[] | select(.buildid == \"$build_id\") | .url")"
        fi
        mkdir $device_fw_dir/$build_id 2>/dev/null
        echo "$url" > $device_fw_dir/$build_id/url
    fi
    mkdir $ramdisk_path 2>/dev/null
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .filename')
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" )
                path="Firmware/all_flash/"
                case $build_id in
                    14[EFG]* ) :;;
                    * ) path+="all_flash.${device_model}ap.production/";;
                esac
            ;;
            * ) path="";;
        esac
        if [[ -z $name ]]; then
            local hwmodel="$device_model"
            case $build_id in
                14[EFG]* )
                    case $device_type in
                        iPhone5,[12] ) hwmodel="iphone5";;
                        iPhone5,[34] ) hwmodel="iphone5b";;
                        iPad3,[456] )  hwmodel="ipad3b";;
                    esac
                ;;
                7* | 8* | 9* | 10* | 11* ) hwmodel+="ap";;
            esac
            case $getcomp in
                "iBSS" | "iBEC" ) name="$getcomp.$hwmodel.RELEASE.dfu";;
                "DeviceTree" )    name="$getcomp.${device_model}ap.img3";;
                "Kernelcache" )   name="kernelcache.release.$hwmodel";;
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
        elif [[ $build_id == "14"* ]]; then
            cp $getcomp.orig $getcomp.dec
        else
            "$dir/xpwntool" $getcomp.orig $getcomp.dec -iv $iv -k $key -decrypt
        fi
    done

    if [[ $1 != "justboot" ]]; then
        log "Patch RestoreRamdisk"
        "$dir/xpwntool" RestoreRamdisk.dec Ramdisk.raw
        "$dir/hfsplus" Ramdisk.raw grow 30000000
    fi

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
        if [[ $1 != "justboot" ]]; then
            "$dir/hfsplus" Ramdisk.raw untar ../resources/ssh.tar
            if [[ $1 == "jailbreak" && $device_vers == "8"* ]]; then
                "$dir/hfsplus" Ramdisk.raw untar ../resources/jailbreak/daibutsu/bin.tar
            fi
            "$dir/hfsplus" Ramdisk.raw mv sbin/reboot sbin/reboot_bak
            "$dir/hfsplus" Ramdisk.raw mv sbin/halt sbin/halt_bak
            case $build_id in
                 "12"* | "13"* | "14"* )
                    echo '#!/bin/bash' > restored_external
                    echo "/sbin/sshd; exec /usr/local/bin/restored_external_o" >> restored_external
                    "$dir/hfsplus" Ramdisk.raw mv usr/local/bin/restored_external usr/local/bin/restored_external_o
                    "$dir/hfsplus" Ramdisk.raw add restored_external usr/local/bin/restored_external
                    "$dir/hfsplus" Ramdisk.raw chmod 755 usr/local/bin/restored_external
                ;;
            esac
            "$dir/xpwntool" Ramdisk.raw Ramdisk.dmg -t RestoreRamdisk.dec
        fi
        log "Patch iBSS"
        "$dir/xpwntool" iBSS.dec iBSS.raw
        "$dir/iBoot32Patcher" iBSS.raw iBSS.patched --rsa -b "-v"
        "$dir/xpwntool" iBSS.patched iBSS -t iBSS.dec
        if [[ $build_id == "7"* || $build_id == "8"* ]] && [[ $device_type != "iPad"* ]]; then
            :
        else
            log "Patch iBEC"
            "$dir/xpwntool" iBEC.dec iBEC.raw
            if [[ $1 == "justboot" && $device_type == "iPad2"* && $device_target_build == "8"* ]]; then
                "$dir/iBoot32Patcher" iBEC.raw iBEC.patched --rsa -b "-v cs_enforcement_disable=1"
            elif [[ $1 == "justboot" ]]; then
                "$dir/iBoot32Patcher" iBEC.raw iBEC.patched --rsa -b "-v"
            else
                "$dir/iBoot32Patcher" iBEC.raw iBEC.patched --rsa --debug -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1"
            fi
            "$dir/xpwntool" iBEC.patched iBEC -t iBEC.dec
        fi
    fi

    if [[ $device_type == "iPad2"* && $device_target_build == "8"* ]]; then
        log "Patch Kernelcache"
        mv Kernelcache.dec Kernelcache0.dec
        "$dir/xpwntool" Kernelcache0.dec Kernelcache.raw
        $bspatch Kernelcache.raw Kernelcache.patched ../resources/patch/kernelcache.release.${device_model}.${device_target_build}.patch
        "$dir/xpwntool" Kernelcache.patched Kernelcache.dec -t Kernelcache0.dec
    fi

    mv iBSS iBEC DeviceTree.dec Kernelcache.dec Ramdisk.dmg $ramdisk_path 2>/dev/null

    if [[ $1 == "jailbreak" || $1 == "justboot" ]]; then
        device_enter_mode pwnDFU
    elif [[ $device_proc == 4 ]] || [[ $device_proc == 6 && $platform == "macos" ]]; then
        device_buttons
    elif [[ $device_proc == 1 ]]; then
        device_enter_mode DFU
    else
        device_enter_mode kDFU
    fi
    log "Sending iBSS..."
    if [[ $build_id == "7"* || $build_id == "8"* ]] && [[ $device_type == "iPad"* ]]; then
        device_rd_build=
        patch_ibss
        $irecovery -f pwnediBSS.dfu
    else
        $irecovery -f $ramdisk_path/iBSS
    fi
    if [[ $device_type != "iPod2,1" && $device_proc != 1 ]]; then
        sleep 1
        log "Sending iBEC..."
        $irecovery -f $ramdisk_path/iBEC
    fi
    device_find_mode Recovery

    log "Booting, please wait..."
    $irecovery -f $ramdisk_path/DeviceTree.dec
    $irecovery -c devicetree
    if [[ $1 != "justboot" ]]; then
        $irecovery -f $ramdisk_path/Ramdisk.dmg
        $irecovery -c ramdisk
    fi
    $irecovery -f $ramdisk_path/Kernelcache.dec
    $irecovery -c bootx

    if [[ $1 == "justboot" ]]; then
        log "Device should now boot."
        return
    elif [[ -n $1 ]]; then
        device_find_mode Restore 25
    fi

    case $mode in
        "clearnvram" | "jailbreak" | "activation" | "baseband" | "getversion" | "setnvram" )
            log "Running iproxy for SSH..."
            $iproxy 2222 22 >/dev/null &
            iproxy_pid=$!
            sleep 1
            device_sshpass alpine
        ;;
    esac

    case $mode in
        "activation" | "baseband" )
            local arg="$1"
            local dump="../saved/$device_type"
            local opt
            log "Mounting root filesystem"
            $ssh -p 2222 root@127.0.0.1 "mount.sh root"
            sleep 1
            #log "Let's just dump both activation and baseband tars"
            log "Creating baseband.tar"
            $ssh -p 2222 root@127.0.0.1 "cd /mnt1; tar -cvf baseband.tar usr/local/standalone"
            log "Mounting data partition"
            $ssh -p 2222 root@127.0.0.1 "mount.sh pv"
            #log "Creating activation.tar"
            #$ssh -p 2222 root@127.0.0.1 "cd /mnt1; tar -cvf activation.tar private/var/root/Library/Lockdown"
            log "Copying tars"
            #$scp -P 2222 root@127.0.0.1:/mnt1/baseband.tar root@127.0.0.1:/mnt1/activation.tar .
            $scp -P 2222 root@127.0.0.1:/mnt1/baseband.tar .
            print "* Reminder to backup dump tars if needed"
            if [[ -s $dump/baseband.tar ]]; then
                read -p "Baseband dump exists in $dump/baseband.tar. Overwrite? (Y/n)" opt
                if [[ $opt != "N" && $opt != "n" ]]; then
                    cp baseband.tar $dump
                fi
            else
                cp baseband.tar $dump
            fi
            : '
            opt=
            if [[ -s $dump/activation.tar ]]; then
                read -p "Activation records dump exists in $dump/activation.tar. Overwrite? (Y/n)" opt
                if [[ $opt != "N" && $opt != "n" ]]; then
                    cp activation.tar $dump
                fi
            else
                cp activation.tar $dump
            fi
            '
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
            sleep 1
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
            fi
            case $vers in
                9.3.[1234] | 9.3 ) untether="untetherhomedepot.tar";;
                9.2* | 9.1 ) untether="untetherhomedepot921.tar";;
                8* )         untether="daibutsu/untether.tar";;
                7.1* )       untether="panguaxe.tar";;
                7* )         untether="evasi0n7-untether.tar";;
                6.1.[3456] ) untether="p0sixspwn.tar";;
                6* )         untether="evasi0n6-untether.tar";;
                4.2.1 | 4.1 | 4.0* | 3.2* | 3.1.3 ) untether="greenpois0n/${device_type}_${build}.tar";;
                5* | 4.3* | 4.2* ) untether="g1lbertJB/${device_type}_${build}.tar";;
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
                4.1 | 4.0* | 3.1* )
                    untether="${device_type}_${build}.tar"
                    log "Extracting $untether"
                    $ssh -p 2222 root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                ;;
            esac
            log "Mounting data partition"
            $ssh -p 2222 root@127.0.0.1 "mount.sh pv"
            case $vers in
                9* | 8* ) device_send_rdtar fstab8.tar;;
                7* ) device_send_rdtar fstab7.tar;;
                6* ) device_send_rdtar fstab_rw.tar;;
                4.2.1 ) $ssh -p 2222 root@127.0.0.1 "[[ ! -e /mnt1/sbin/punchd ]] && mv /mnt1/sbin/launchd /mnt1/sbin/punchd";;
                5* | 4.3* | 4.2* ) untether="${device_type}_${build}.tar";;
            esac
            case $vers in
                5* ) device_send_rdtar g1lbertJB.tar;;
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
                5* | 4* | 3* ) device_send_rdtar cydiasubstrate.tar;;
            esac
            case $vers in
                3* ) device_send_rdtar cydiahttpatch.tar;;
            esac
            if [[ $device_type == "iPhone2,1" && $vers == "4.3"* ]]; then
                # 4.3.x 3gs'es have little free space in rootfs. workaround: extract an older strap that takes less space
                device_send_rdtar freeze5.tar data
            else
                device_send_rdtar freeze.tar data
            fi
            if [[ $ipsw_openssh == 1 ]]; then
                device_send_rdtar sshdeb.tar
            fi
            if [[ $vers == "8"* ]]; then
                log "Sending daibutsu/move.sh"
                $scp -P 2222 $jelbrek/daibutsu/move.sh root@127.0.0.1:/mnt1
                log "Moving files"
                $ssh -p 2222 root@127.0.0.1 "bash /mnt1/move.sh; rm /mnt1/move.sh"
                untether="untether.tar"
                log "Extracting $untether"
                $ssh -p 2222 root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                log "Running haxx_overwrite --${device_type}_${build}"
                $ssh -p 2222 root@127.0.0.1 "/usr/bin/haxx_overwrite --${device_type}_${build}"
            else
                log "Rebooting"
                $ssh -p 2222 root@127.0.0.1 "reboot_bak"
            fi
            log "Cool, done and jailbroken (hopefully)"
            case $vers in
                4* | 3* ) warn "Do not uninstall Cydia Substrate and Substrate Safe Mode in Cydia!";;
            esac
            return
        ;;

        "clearnvram" )
            log "Sending commands for clearing NVRAM..."
            $ssh -p 2222 root@127.0.0.1 "nvram -c; reboot_bak"
            log "Done! Your device should reboot now."
            print "* If the device did not connect, SSH to the device manually."
        ;;

        "setnvram" )
            log "Sending commands for NVRAM..."
            $ssh -p 2222 root@127.0.0.1 "nvram -c; nvram boot-partition=$rec"
            if [[ $device_type == "iPhone3,3" && $rec == 2 ]]; then
                $ssh -p 2222 root@127.0.0.1 "nvram boot-ramdisk=/a/b/c/d/e/f/g/h/i/disk.dmg"
            fi
            $ssh -p 2222 root@127.0.0.1 "reboot_bak"
            log "Done, your device should boot now"
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
    if [[ $device_proc == 4 ]] || [[ $device_proc == 6 && $platform == "macos" ]]; then
        device_buttons
    else
        device_enter_mode kDFU
    fi
    if [[ $device_proc == 4 ]]; then
        patch_ibss
        log "Sending iBSS..."
        $irecovery -f pwnediBSS.dfu
    fi
    sleep 1
    patch_ibec
    log "Sending iBEC..."
    $irecovery -f pwnediBEC.dfu
    device_find_mode Recovery
    log "Dumping blobs now"
    (echo -e "/send ../resources/payload\ngo blobs\n/exit") | $irecovery2 -s
    $irecovery2 -g myblob.dump
    $irecovery -n
    "$dir/ticket" myblob.dump myblob.shsh "$ipsw_path.ipsw" -z
    "$dir/validate" myblob.shsh "$ipsw_path.ipsw" -z
    if [[ $? != 0 ]]; then
        warn "Saved SHSH blobs might be invalid. Did you select the correct IPSW?"
    fi
    if [[ ! -s myblob.shsh ]]; then
        error "Saving onboard SHSH blobs failed."
    fi
    mv myblob.shsh ../saved/shsh/$device_ecid-$device_type-$device_target_vers.shsh
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
    if [[ -n $device_disable_bbupdate && $device_type == "iPad"* ]]; then
        print "* Disable bbupdate flag detected, baseband update is disabled."
    elif [[ -n $device_disable_bbupdate && $device_type == "iPhone"* ]]; then
        warn "Disable bbupdate flag detected, baseband update is disabled. Proceed with caution"
        print "* For iPhones, current baseband will be dumped and stitched to custom IPSW"
        print "* Stitching is supported in these restores/downgrades: 8.4.1/6.1.3, Other with SHSH, powdersn0w"
    fi
    if [[ $device_actrec == 1 ]]; then
        warn "Activation records flag detected. Proceed with caution"
        print "* Stitching is supported in these restores/downgrades: 8.4.1/6.1.3, Other with SHSH, powdersn0w"
    fi
    if [[ -n $device_build ]]; then
        print "* iOS Version: $device_vers ($device_build)"
    else
        print "* iOS Version: $device_vers"
    fi
    if [[ $device_vers == "Unknown" && $device_proc != 1 ]] && (( device_proc < 7 )); then
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
        if [[ $device_mode == "Normal" ]]; then
            if [[ $platform == "linux" ]]; then
                case $device_vers in
                    9* | 1* ) menu_items+=("Sideload IPA");;
                esac
            fi
            menu_items+=("Install IPA (AppSync)")
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
            "Install IPA (AppSync)" | "Sideload IPA" ) menu_ipa "$selected";;
            "Other Utilities" ) menu_other;;
            "Exit" ) mode="exit";;
        esac
    done
}

menu_ipa() {
    local menu_items
    local selected
    local back

    ipa_path=
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Select IPA")
        menu_print_info
        if [[ $1 == "Install"* ]]; then
            print "* Make sure that AppSync Unified is installed on your device."
        else
            print "* Sideload IPA is for iOS 9 and newer."
            print "* Sideloading will require an Apple ID."
            print "* Your Apple ID and password will only be sent to Apple servers."
        fi
        echo
        if [[ -n $ipa_path ]]; then
            print "* Selected IPA: $ipa_path"
            menu_items+=("Install IPA")
        else
            print "* Select IPA to install"
        fi
        menu_items+=("Go Back")
        echo
        print " > Main Menu > $1"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Select IPA" ) menu_ipa_browse;;
            "Install IPA" )
                if [[ $1 == "Install"* ]]; then
                    mode="ideviceinstaller"
                else
                    mode="altserver_linux"
                fi
            ;;
            "Go Back" ) back=1;;
        esac
    done
}

menu_ipa_browse() {
    local newpath
    input "Select your IPA file(s) in the file selection window."
    newpath="$($zenity --file-selection --multiple --file-filter='IPA | *.ipa' --title="Select IPA file(s)")"
    [[ -z "$newpath" ]] && read -p "$(input "Enter path to IPA file (or press Ctrl+C to cancel): ")" newpath
    ipa_path="$newpath"
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
        if [[ $device_mode != "none" && $device_proc == 4 ]]; then
            print "* Dumping onboard blobs might not work for this device, proceed with caution"
            print "* Legacy iOS Kit only fully supports dumping onboard blobs for A5(X) and A6(X) devices"
            echo
        fi
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
        if [[ $device_mode != "none" && $device_proc == 4 ]]; then
            print "* Dumping onboard blobs might not work for this device, proceed with caution"
            print "* Legacy iOS Kit only fully supports dumping onboard blobs for A5(X) and A6(X) devices"
            echo
        fi
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
                menu_items+=("5.1.1" "4.3.3" "4.1" "3.1.3" "More versions");;
            iPod3,1 )
                menu_items+=("4.1");;
            iPhone1,2 )
                menu_items+=("4.1" "3.1.3");;
            iPod2,1 )
                menu_items+=("4.1" "3.1.3" "More versions");;
        esac
        case $device_type in
            iPhone3,[13] | iPad1,1 | iPod3,1 )
                menu_items+=("powdersn0w (any iOS)");;
        esac
        if (( device_proc < 7 )); then
            menu_items+=("Latest iOS ($device_latest_vers)")
        elif [[ $platform == "linux" ]]; then
            menu_items+=("Latest iOS ($device_latest_vers)")
        fi
        case $device_type in
            iPhone4,1 | iPhone5,[1234] | iPad2,4 | iPad3,[456] | iPod5,1 )
                menu_items+=("Other (powdersn0w 7.x blobs)");;
            iPhone1,[12] | iPhone2,1 | iPod[12],1 )
                if [[ -z $1 ]]; then
                    menu_items+=("Other (Custom IPSW)")
                fi
            ;;
        esac
        if [[ $device_proc != 1 ]]; then
            if [[ $device_type != "iPod2,1" ]]; then
                menu_items+=("Other (Use SHSH Blobs)")
            fi
            if [[ $device_proc == 5 || $device_proc == 6 ]]; then
                menu_items+=("Other (Tethered)")
            fi
            case $device_type in
                iPhone3,[23] | iPad1,1 | iPod[34],1 )
                    menu_items+=("Other (Tethered)");;
            esac
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
        if [[ -z $1 ]]; then
            if [[ $device_proc == 1 ]]; then
                print "* Select \"Other (Custom IPSW)\" to restore to any iOS version"
                print "* iOS 1 may require the usage of ZiPhone: https://nitter.net/tihmstar/status/1734620913071542435"
                echo
            fi
            if [[ $device_type == "iPod2,1" || $device_type == "iPhone2,1" ]] && [[ $device_newbr != 0 ]]; then
                print "* New bootrom devices might be incompatible with some older iOS versions"
                echo
            elif [[ $device_type == "iPod2,1" ]]; then
                print "* Select \"Other (Custom IPSW)\" to restore to any iOS version (2.1.1 to 3.0)"
                echo
            fi
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
            "More versions" ) menu_restore_more "$1";;
            * ) menu_ipsw "$selected" "$1";;
        esac
    done
}

menu_restore_more() {
    local menu_items
    local selected
    local back

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=()
        case $device_type in
            iPhone2,1 )
                menu_items+=("6.1.3" "6.1.2" "6.1" "6.0.1" "6.0" "5.1" "5.0.1" "5.0")
                #menu_items+=("4.3.5" "4.3.4" "4.3.2" "4.3.1" "4.3")
                menu_items+=("4.2.1" "4.0.2" "4.0.1" "4.0" "3.1.2" "3.1" "3.0")
            ;;
            iPod2,1 ) menu_items+=("4.0.2" "4.0");;
        esac
        menu_items+=("Go Back")
        menu_print_info
        if [[ $1 == "ipsw" ]]; then
            print " > Main Menu > Other Utilities > Create Custom IPSW"
        else
            print " > Main Menu > Restore/Downgrade"
        fi
        if [[ -z $1 && $device_type == "iPod2,1" && $device_newbr != 0 ]]; then
            warn "These versions are for old bootrom devices only. They will not work on your device"
            echo
        fi
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "" ) :;;
            "Go Back" ) back=1;;
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
    device_target_tethered=

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
            "Latest iOS"* )
                device_target_vers="$device_latest_vers"
                device_target_build="$device_latest_build"
                case $device_latest_vers in
                    "6.1.6" | "4.2.1" | "3.1.3" ) device_canhacktivate=1;;
                esac
            ;;
            6* | 5* | 4* | 3* )
                device_target_vers="$1"
                device_canhacktivate=1
            ;;
        esac
        if [[ $device_type != "iPhone"* ]]; then
            device_canhacktivate=
        fi
        case $1 in
            "6.1.3" ) device_target_build="10B329";;
            "6.1.2" ) device_target_build="10B146";;
            "6.1"   ) device_target_build="10B141";;
            "6.0.1" ) device_target_build="10A523";;
            "6.0"   ) device_target_build="10A403";;
            "5.1.1" ) device_target_build="9B206";;
            "5.1"   ) device_target_build="9B176";;
            "5.0.1" ) device_target_build="9A405";;
            "5.0"   ) device_target_build="9A334";;
            "4.3.5" ) device_target_build="8L1";;
            "4.3.4" ) device_target_build="8K2";;
            "4.3.3" ) device_target_build="8J2";;
            "4.3.2" ) device_target_build="8H7";;
            "4.3.1" ) device_target_build="8G4";;
            "4.3"   ) device_target_build="8F190";;
            "4.2.1" )
                device_target_build="8C148"
                if [[ $device_type == "iPhone2,1" ]]; then
                    device_target_build+="a"
                fi
            ;;
            "4.1"   ) device_target_build="8B117";;
            "4.0.2" ) device_target_build="8A400";;
            "4.0.1" ) device_target_build="8A306";;
            "4.0"   ) device_target_build="8A293";;
            "3.1.3" ) device_target_build="7E18";;
            "3.1.2" ) device_target_build="7D11";;
            "3.1.1" ) device_target_build="7C145";;
            "3.1"   ) device_target_build="7C144";;
            "3.0.1" ) device_target_build="7A400";;
            "3.0"   ) device_target_build="7A341";;
        esac
        if [[ $device_target_vers == "$device_latest_vers" ]]; then
            case $device_type in
                iPad3,[456]    ) newpath="iPad_32bit";;
                iPad4,[123456] ) newpath="iPad_64bit";;
                iPhone5,[1234] ) newpath="iPhone_4.0_32bit";;
                iPod[79],1     ) newpath="iPodtouch";;
                iPhone9,[13]   ) newpath="iPhone_4.7_P3";;
                iPhone9,[24]   ) newpath="iPhone_5.5_P3";;
                iPad4,[789] | iPad5*     ) newpath="iPad_64bit_TouchID";;
                iPhone6,[12] | iPhone8,4 ) newpath="iPhone_4.0_64bit";;
                iPhone7,1 | iPhone8,2    ) newpath="iPhone_5.5";;
                iPhone7,2 | iPhone8,1    ) newpath="iPhone_4.7";;
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
            if [[ $device_type == "iPhone2,1" ]]; then
                device_canhacktivate=1
            fi
        elif [[ $1 == *"powdersn0w"* ]]; then
            device_target_powder=1
        elif [[ $1 == *"Tethered"* ]]; then
            device_target_tethered=1
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
                case $device_target_build in
                    7* | 8[CE]* ) warn "Selected target version will restore but is most likely not functional.";;
                esac
            else
                print "* Select Target IPSW to continue"
                local lo
                local hi
                case $device_type in
                    iPhone3,1 ) lo=4.0; hi=7.1.1;;
                    iPhone3,3 ) lo=5.0; hi=7.1.1;;
                    iPhone4,1 | iPad2,[123]    ) lo=5.0; hi=9.3.5;;
                    iPad2,4 | iPad3,[123]      ) lo=5.1; hi=9.3.5;;
                    iPhone5,[12] | iPad3,[456] ) lo=6.0; hi=9.3.5;;
                    iPhone5,[34] ) lo=7.0; hi=9.3.5;;
                    iPad1,1 ) lo=4.3; hi=5.1;;
                    iPod3,1 ) lo=4.0; hi=5.1;;
                esac
                print "* Any iOS version from $lo to $hi is supported"
            fi
            if [[ $device_type == "iPad1,1" || $device_type == "iPod3,1" ]]; then
                print "* For downgrading to 4.3.x or lower, make sure to downgrade to 5.0 first."
            fi
            echo
            local text2="(iOS 7.1.x)"
            case $device_type in
                iPhone3,[13] ) text2="(iOS 7.1.2)";;
                iPhone5,[1234] ) text2="(iOS 7.x)";;
                iPad3,[456] ) text2="(iOS 7.0.x)";;
                iPad1,1 | iPod3,1 ) text2="(iOS 5.1.1)";;
            esac
            if [[ -n $ipsw_base_path ]]; then
                print "* Selected Base $text2 IPSW: $ipsw_base_path.ipsw"
                print "* Base Version: $device_base_vers-$device_base_build"
                if [[ $device_base_build == "11A"* ]]; then
                    warn "There might be an issue when selecting iOS 7.0-7.0.2 base."
                    print "* The device might get stuck at recovery mode after the restore."
                fi
                if [[ $device_proc != 4 ]]; then
                    menu_items+=("Select Base SHSH")
                fi
            else
                print "* Select Base $text2 IPSW to continue"
            fi
            if [[ $device_proc == 4 ]]; then
                shsh_path=1
            else
                if [[ -n $shsh_path ]]; then
                    echo
                    print "* Selected Base $text2 SHSH: $shsh_path"
                    if [[ $shsh_validate == 0 ]]; then
                        print "* Selected SHSH file is validated"
                    else
                        warn "Selected SHSH file failed validation"
                    fi
                elif [[ $2 != "ipsw" ]]; then
                    echo
                    print "* Select Base $text2 SHSH to continue"
                fi
            fi
            if [[ -n $ipsw_path && -n $ipsw_base_path ]] && [[ -n $shsh_path || $2 == "ipsw" ]]; then
                menu_items+=("$start")
            fi

        elif [[ $1 == *"Tethered"* ]]; then
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                print "* Target Version: $device_target_vers-$device_target_build"
            else
                print "* Select Target IPSW to continue"
            fi
            warn "This is a tethered downgrade. Not recommended unless you know what you are doing."
            print "* Tethered downgrade: you need to use Legacy iOS Kit every time to boot the device."
            print "* Booting can be done by going to: Other Utilities -> Just Boot"
            if [[ -n $ipsw_path ]]; then
                menu_items+=("$start")
            fi

        elif [[ $1 == "Other"* ]]; then
            # menu for other (shsh) restores
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                print "* Target Version: $device_target_vers-$device_target_build"
                menu_items+=("Select Target SHSH")
                if [[ $device_type == "iPhone3,1" && $device_target_vers == "4.2.1" ]]; then
                    warn "There might be an issue with 4.2.1 restores for iPhone 4."
                    print "* The device might get stuck at boot after the restore."
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
                elif [[ $shsh_validate == 0 ]]; then
                    print "* Selected SHSH file is validated"
                else
                    warn "Selected SHSH file failed validation"
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
        if [[ $device_base_vers == "7.0"* ]]; then
            ipsw_custom+="0"
        fi
    fi
    if [[ $device_target_tethered == 1 ]]; then
        ipsw_custom+="T"
    fi
    if [[ $ipsw_verbose == 1 ]]; then
        ipsw_custom+="V"
    fi
    if [[ $device_target_powder == 1 ]] && [[ $device_target_vers == "4.3"* ]]; then
        ipsw_custom+="-$device_ecid"
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
            local check_vers="7.1"
            local base_vers="7.1.x"
            case $device_type in
                iPhone5* )
                    check_vers="7"
                    base_vers="7.x"
                ;;
                iPad3* )
                    check_vers="7.0"
                    base_vers="7.0.x"
                ;;
                iPhone3* )
                    check_vers="7.1.2"
                    base_vers="$check_vers"
                ;;
                iPad1,1 | iPod3,1 )
                    check_vers="5.1.1"
                    base_vers="$check_vers"
                ;;
            esac
            if [[ $device_base_vers != "$check_vers"* ]]; then
                log "Selected IPSW is not for iOS $base_vers."
                print "* You need iOS $base_vers IPSW and SHSH blobs for this device to use powdersn0w."
                pause
                return
            elif [[ $device_target_build == "$device_base_build" ]]; then
                log "The base version and the target version must not be the same."
                pause
                return
            fi
            ipsw_verify "$newpath" "$device_base_build"
            ipsw_base_path="$newpath"
            return
        ;;
        *"powdersn0w"* )
            if [[ $device_target_build == "14"* ]]; then
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                pause
                return
            elif [[ $device_target_build == "$device_base_build" ]]; then
                log "The base version and the target version must not be the same."
                pause
                return
            fi
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
        shsh_validate=$?
        if [[ $shsh_validate != 0 ]]; then
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
                menu_items+=("Clear NVRAM")
                if [[ $device_type != "iPod2,1" ]]; then
                    menu_items+=("Just Boot")
                fi
            else
                menu_items+=("Enter pwnDFU Mode")
            fi
            menu_items+=("Activation Records")
            case $device_type in
                iPhone3,[13] | iPad1,1 | iPod3,1 ) menu_items+=("Disable/Enable Exploit");;
                iPhone2,1 ) menu_items+=("Install alloc8 Exploit");;
            esac
        fi
        if [[ $device_mode != "none" ]]; then
            if (( device_proc < 7 )); then
                menu_items+=("SSH Ramdisk")
            fi
            case $device_mode in
                "Normal" ) menu_items+=("Attempt Activation" "Shutdown Device" "Restart Device" "Enter Recovery Mode");;
                "Recovery" ) menu_items+=("Exit Recovery Mode");;
            esac
            if [[ $device_mode != "DFU" ]]; then
                menu_items+=("Enter DFU Mode")
            fi
        fi
        if (( device_proc < 8 )); then
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
    else
        case $device_vers in
            5* | 6.0* | 6.1 | 6.1.[12] )
                print "* Your device on iOS $device_vers will be jailbroken using g1lbertJB."
                print "* No data will be lost, but please back up your data just in case."
                print "* Ignore the \"Error Code 1\" and \"Error Code 102\" errors, this is normal and part of the jailbreaking process."
                pause
                pushd ../resources/jailbreak/g1lbertJB >/dev/null
                cp ../freeze.tar payload/common/Cydia.tar
                ../../$dir/gilbertjb
                rm payload/common/Cydia.tar
                popd >/dev/null
                return
            ;;
        esac
    fi
    if [[ $device_type == "iPad2"* && $device_vers == "4"* ]]; then
        warn "This will be a semi-tethered jailbreak. Arduino is required to boot to a jailbroken state."
        print "* To boot jailbroken later, go to: Other Utilities -> Just Boot"
        pause
    fi
    case $device_vers in
        9.3.[1234] | 9.3 | 9.2* | 9.1 | 8* | 7* | 6* | 5* | 4* | 3.2* | 3.1.3 ) :;;
        * )
            warn "This version ($device_vers) is not supported for jailbreaking with SSHRD."
            print "* Supported versions are: 3.1.3 to 9.3.4 (excluding 9.0.x)"
        ;;
    esac
    case $device_vers in
        8.2 | 8.1* | 8.0* )
            if [[ $device_proc == 5 ]]; then
                warn "This version ($device_vers) is broken for daibutsu A5(X)."
                print "* Supported iOS 8 versions for A5(X) are 8.3 to 8.4.1 only for now."
                print "* For this version, use Home Depot patched with ohd."
                print "* https://ios.cfw.guide/installing-homedepot/"
                return
            fi
        ;;
        9.0* )
            print "* For this version, use Pangu9, or download openpwnage and sideload it to your device."
            print "* https://ios.cfw.guide/installing-pangu9/"
            print "* https://github.com/0xilis/openpwnage"
            return
        ;;
        9.3.[56] )
            print "* For this version, download kok3shi9 and sideload it to your device."
            print "* https://kok3shidoll.web.app/kok3shi9.html"
            return
        ;;
        10* )
            print "* For this version, download kok3shiX or socket and sideload it to your device."
            print "* https://kok3shidoll.github.io/download/kokeshi/kokeshiX_v1.0_alpha_2.ipa"
            print "* https://github.com/staturnzz/socket"
            return
        ;;
    esac
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
    local dmp2
    case $arg in
        "baseband" ) dmps="/usr/local/standalone";;
        "activation" )
            dmp2="private/var/root/Library/Lockdown"
            case $device_vers in
                [34567]* ) dmps="/$dmp2";;
                8* ) dmps="/private/var/mobile/Library/mad";;
                * )
                    dmps="/private/var/containers/Data/System/*/Library/activation_records"
                    dmp2+="/activation_records"
                ;;
            esac
        ;;
    esac

    log "Dumping files for $arg: $dmps"
    if [[ -s $dump ]]; then
        log "Found existing dumped $arg: $dump"
        print "* Select Y to overwrite, or N to use existing dump"
        print "* Make sure to keep a backup of the dump if needed"
        read -p "$(input 'Overwrite this existing dump? (y/N) ')" opt
        if [[ $opt != 'Y' && $opt != 'y' ]]; then
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
        sleep 1
        device_sshpass
        log "Creating $arg.tar"
        if [[ $arg == "activation" ]]; then
            $ssh -p 2222 root@127.0.0.1 "mkdir -p /tmp/$dmp2; cp -R $dmps/* /tmp/$dmp2"
            $ssh -p 2222 root@127.0.0.1 "cd /tmp; tar -cvf $arg.tar $dmp2"
        else
            $ssh -p 2222 root@127.0.0.1 "tar -cvf /tmp/$arg.tar $dmps"
        fi
        log "Copying $arg.tar"
        $scp -P 2222 root@127.0.0.1:/tmp/$arg.tar .
        cp $arg.tar $dump
    elif [[ $device_mode == "DFU" ]]; then
        device_ramdisk $arg
        if [[ $mode != "baseband" ]]; then
            device_find_mode Recovery
            device_enter_mode DFU
            device_enter_mode pwnDFU
        fi
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
        if [[ $device_type == "iPhone1"* || $device_type == "iPhone2,1" ]]; then
            print "* For hacktivation, go to Restore/Downgrade instead."
        fi
    fi
    $ideviceactivation activate
    print "* If it returns an error, just try again."
}

restore_customipsw() {
    print "* You are about to restore with a custom IPSW."
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
    if [[ $device_proc == 1 ]]; then
        device_enter_mode WTFreal
    else
        device_enter_mode pwnDFU
    fi
    ipsw_custom="$ipsw_path"
    restore_latest custom
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
    local ipsw_p="../"
    case $device_type in
        iPhone5,[1234] ) ipsw_p+="iPhone_4.0_32bit";;
        iPad3,[456] ) ipsw_p+="iPad_32bit";;
        * ) ipsw_p+="${device_type}";;
    esac
    ipsw_p+="_${device_target_vers}_${device_target_build}"
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
        local llb="LLB.${device_model}ap.RELEASE.img3"
        local all="Firmware/all_flash"
        if [[ $device_latest_vers == "10"* ]]; then
            case $device_type in
                iPhone5,[1234] ) applelogo="applelogo@2x~iphone.s5l8950x.img3";;
                iPad3,[456] ) applelogo="applelogo@2x~ipad.s5l8955x.img3";;
            esac
            case $device_type in
                iPhone5,[12] ) llb="LLB.iphone5.RELEASE.img3";;
                iPhone5,[34] ) llb="LLB.iphone5b.RELEASE.img3";;
                iPad3,[456] ) llb="LLB.ipad3b.RELEASE.img3";;
            esac
        else
            all+="/all_flash.${device_model}ap.production"
        fi
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
    device_enter_mode Recovery
    ipsw_extract
    log "Running idevicerestore with command: $idevicerestore -e \"$ipsw_path.ipsw\""
    $idevicerestore -e "$ipsw_path.ipsw"
    log "Restoring done! Device should now be in DFU mode"
}

device_justboot() {
    print "* You are about to do a tethered boot."
    read -p "$(input 'Enter build version (eg. 10B329): ')" device_rd_build
    device_ramdisk justboot
}

device_enter_ramdisk() {
    if (( device_proc >= 5 )); then
        print "* To mount /var (/mnt2) for iOS 9-10, I recommend using 9.0.2 (13A452)."
        print "* If not sure, just press Enter/Return. This will select the default build version."
        read -p "$(input 'Enter build version (eg. 10B329): ')" device_rd_build
    fi
    device_ramdisk
}

device_ideviceinstaller() {
    log "Installing selected IPA(s) to device using ideviceinstaller..."
    IFS='|' read -r -a ipa_files <<< "$ipa_path"
    for i in "${ipa_files[@]}"; do
        log "Installing: $i"
        "$dir/ideviceinstaller" install "$i"
    done
}

device_altserver_linux() {
    local altserver="../saved/anisette-server-$platform"
    local anisette="../saved/AltServer-$platform"
    local arch="$platform_arch"
    case $arch in
        "armhf" ) arch="armv7";;
        "arm64" ) arch="aarch64";;
    esac
    if [[ $platform == "linux" ]]; then
        altserver+="_$arch"
        anisette+="_$arch"
    fi
    if [[ ! -e $altserver ]]; then
        log "Downloading AltServer-Linux..."
        curl -LO https://github.com/NyaMisty/AltServer-Linux/releases/download/v0.0.5/AltServer-$arch
        mv AltServer-$arch $altserver
    fi
    if [[ ! -e $anisette ]]; then
        log "Downloading Anisette server..."
        curl -LO https://github.com/Dadoum/Provision/releases/download/2.2.0/anisette-server-$arch
        mv anisette-server-$arch $anisette
    fi
    chmod +x $altserver $anisette
    log "Running Anisette"
    $anisette &
    anisette_pid=$!
    local ready=0
    log "Waiting for Anisette"
    while [[ $ready != 1 ]]; do
        [[ $(curl 127.0.0.1:6969 2>/dev/null) ]] && ready=1
        sleep 1
    done
    export ALTSERVER_ANISETTE_SERVER=http://127.0.0.1:6969
    altserver_linux="env ALTSERVER_ANISETTE_SERVER=$ALTSERVER_ANISETTE_SERVER $altserver"
    log "Attempting idevicepair"
    "$dir/idevicepair" pair
    log "Enter Apple ID details to continue."
    print "* Your Apple ID and password will only be sent to Apple servers."
    local apple_id
    local apple_pass
    while [[ -z $apple_id ]]; do
        read -p "$(input 'Apple ID: ')" apple_id
    done
    while [[ -z $apple_pass ]]; do
        read -s -p "$(input 'Password: ')" apple_pass
    done
    echo
    log "Attempting idevicepair"
    "$dir/idevicepair" pair
    log "Running AltServer-Linux with given Apple ID details..."
    pushd ../saved >/dev/null
    $altserver_linux -u $device_udid -a "$apple_id" -p "$apple_pass" "$ipa_path"
    popd >/dev/null
}

main() {
    clear
    print " *** Legacy iOS Kit ***"
    print " - Script by LukeZGD -"
    echo
    version_get

    if [[ $EUID == 0 ]]; then
        error "Running the script as root is not allowed."
    fi

    if [[ ! -d "../resources" ]]; then
        error "The resources folder cannot be found. Replace resources folder and try again." \
        "* If resources folder is present try removing spaces from path/folder name"
    fi

    set_tool_paths

    log "Checking Internet connection..."
    local try=("google.com"
               "www.apple.com"
               "208.67.222.222")
    local check
    for i in "${try[@]}"; do
        ping -c1 $i >/dev/null
        check=$?
        if [[ $check == 0 ]]; then
            break
        fi
    done
    if [[ $check != 0 ]]; then
        error "Please check your Internet connection before proceeding."
    fi

    version_check

    if [[ ! -e "../resources/firstrun" || $(cat "../resources/firstrun") != "$platform_ver" ||
          -z $zenity || ! $(which curl) ]]; then
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
        "ramdisk4" ) device_enter_ramdisk;;
        "ramdisknvram" ) device_ramdisk clearnvram;;
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
        "ideviceinstaller" ) device_ideviceinstaller;;
        "altserver_linux" ) device_altserver_linux;;
        * ) :;;
    esac

    echo
    print "* Save the terminal output now if needed."
    print "* Legacy iOS Kit $version_current ($git_hash)"
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
