#!/usr/bin/env bash

ipsw_openssh=1 # OpenSSH will be added to jailbreak/custom IPSW if set to 1.
device_rd_build="" # You can change the version of SSH Ramdisk and Pwned iBSS/iBEC here. (default is 10B329 for most devices)
jelbrek="../resources/jailbreak"
ssh_port=6414

bash_test=$(echo -n 0)
(( bash_test += 1 ))
if [ "$bash_test" != "1" ] || [ -z $BASH_VERSION ]; then
    echo "[Error] Detected that script is not running with bash on runtime. Please run the script properly using bash."
    exit 1
fi
bash_ver=$(/usr/bin/env bash -c 'echo ${BASH_VERSINFO[0]}')
if (( bash_ver > 3 )); then
    shopt -s compat32
fi

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
    echo
    print "* Save the terminal output now if needed. (macOS: Cmd+S, Linux: Ctrl+Shift+S)"
    print "* Legacy iOS Kit $version_current ($git_hash)"
    print "* Platform: $platform ($platform_ver - $platform_arch) $live_cdusb_str"
    exit 1
}

pause() {
    input "Press Enter/Return to continue (or press Ctrl+C to cancel)"
    read -s
}

clean() {
    kill $httpserver_pid $iproxy_pid $anisette_pid 2>/dev/null
    popd &>/dev/null
    rm -rf "$(dirname "$0")/tmp$$/"* "$(dirname "$0")/iP"*/ "$(dirname "$0")/tmp$$/" 2>/dev/null
    if [[ $platform == "macos" && $(ls "$(dirname "$0")" | grep -v tmp$$ | grep -c tmp) == 0 ]]; then
        killall -CONT AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater
    fi
}

clean_sudo() {
    clean
    sudo rm -rf /tmp/futurerestore /tmp/*.json "$(dirname "$0")/tmp$$/"* "$(dirname "$0")/iP"*/ "$(dirname "$0")/tmp$$/"
    sudo kill $sudoloop_pid
}

clean_usbmuxd() {
    clean_sudo
    if [[ $(ls "$(dirname "$0")" | grep -v tmp$$ | grep -c tmp) != 0 ]]; then
        return
    fi
    sudo killall usbmuxd usbmuxd2 2>/dev/null
    if [[ $(command -v systemctl) ]]; then
        sleep 1
        sudo systemctl restart usbmuxd
    fi
}

display_help() {
    echo ' *** Legacy iOS Kit ***
  - Script by LukeZGD -

Usage: ./restore.sh [Options]

List of options:
    --debug                   For script debugging (set -x and debug mode)
    --dfuhelper               Launch to DFU Mode Helper only
    --disable-sudoloop        Disable running tools as root for Linux
    --entry-device            Enable manual device and ECID entry
    --exit-recovery           Attempt to exit recovery mode
    --help                    Display this help message
    --no-color                Disable colors for script output
    --no-device               Enable no device mode
    --no-version-check        Disable script version checking

For 32-bit devices compatible with restores/downgrades (see README):
    --activation-records      Enable dumping/stitching activation records
    --dead-bb                 Disable bbupdate completely without dumping/stitching baseband
    --disable-bbupdate        Disable bbupdate and enable dumping/stitching baseband
    --gasgauge-patch          Enable multipatch to get past "gas gauge" error (aka error 29 in iTunes)
    --ipsw-hacktivate         Enable hacktivation for creating IPSW (iPhone 2G/3G/3GS only)
    --ipsw-verbose            Enable verbose boot option (3GS and powdersn0w only)
    --jailbreak               Enable jailbreak option
    --memory                  Enable memory option for creating IPSW
    --pwned-recovery          Assume that device is in pwned recovery mode (experimental)
    --skip-first              Skip first restore and flash NOR IPSW only for powdersn0w 4.2.x and lower
    --skip-ibss               Assume that pwned iBSS has already been sent to the device

For 64-bit checkm8 devices compatible with pwned restores:
    --skip-blob               Enable futurerestore skip blob option for OTA/onboard/factory blobs
    --use-pwndfu              Enable futurerestore pwned restore option

    * Default IPSW path: <script location>/<name of IPSW file>.ipsw
    * Default SHSH path: <script location>/saved/shsh/<name of SHSH file>.shsh(2)
    '
}

unzip2="$(command -v unzip)"
zip2="$(command -v zip)"

unzip() {
    $unzip2 "$@" || error "An error occurred with the unzip operation: $*"
}

zip() {
    $zip2 "$@" || error "An error occurred with the zip operation: $*"
}

set_tool_paths() {
    : '
    sets variables: platform, platform_ver, dir
    also checks architecture (linux) and macos version
    also set distro, debian_ver, ubuntu_ver, fedora_ver variables for linux

    list of tools set here:
    bspatch, jq, scp, ssh, sha1sum (for macos: shasum -a 1), zenity

    these ones "need" sudo for linux arm, not for others:
    futurerestore, gaster, idevicerestore, ipwnder, irecovery

    tools set here will be executed using:
    $name_of_tool

    the rest of the tools not listed here will be executed using:
    "$dir/$name_of_tool"
    '

    if [[ $OSTYPE == "linux"* ]]; then
        source /etc/os-release
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
                "jammy" | "kinetic"  ) ubuntu_ver=22;;
                "lunar" | "mantic"   ) ubuntu_ver=23;;
                "noble" | "oracular" ) ubuntu_ver=24;;
                "plucky"             ) ubuntu_ver=25;;
            esac
            if [[ -z $ubuntu_ver ]]; then
                source /etc/upstream-release/lsb-release 2>/dev/null
                ubuntu_ver="$(echo "$DISTRIB_RELEASE" | cut -c -2)"
            fi
            if [[ -z $ubuntu_ver ]]; then
                ubuntu_ver="$(echo "$VERSION_ID" | cut -c -2)"
            fi
        elif [[ -e /etc/debian_version ]]; then
            debian_ver=$(cat /etc/debian_version)
            case $debian_ver in
                *"sid" | "kali"* ) debian_ver="sid";;
                * ) debian_ver="$(echo "$debian_ver" | cut -c -2)";;
            esac
        elif [[ $ID == "fedora" || $ID_LIKE == "fedora" || $ID == "nobara" ]]; then
            fedora_ver=$VERSION_ID
        fi

        # distro check
        if [[ $ID == "arch" || $ID_LIKE == "arch" || $ID == "artix" ]]; then
            distro="arch"
        elif (( ubuntu_ver >= 22 )) || (( debian_ver >= 12 )) || [[ $debian_ver == "sid" ]]; then
            distro="debian"
        elif (( fedora_ver >= 37 )); then
            distro="fedora"
            if [[ $(command -v rpm-ostree) ]]; then
                distro="fedora-atomic"
            fi
        elif [[ $ID == "opensuse-tumbleweed" ]]; then
            distro="opensuse"
        elif [[ $ID == "gentoo" || $ID_LIKE == "gentoo" || $ID == "pentoo" ]]; then
            distro="gentoo"
        elif [[ $ID == "void" ]]; then
            distro="void"
        elif [[ -n $ubuntu_ver || -n $debian_ver || -n $fedora_ver ]]; then
            error "Your distro version ($platform_ver - $platform_arch) is not supported. See the repo README for supported OS versions/distros"
        else
            warn "Your distro ($platform_ver - $platform_arch) is not detected/supported. See the repo README for supported OS versions/distros"
            print "* You may still continue, but you need to install required packages and libraries manually as needed."
            sleep 5
            pause
        fi
        bspatch="$dir/bspatch"
        if [[ $platform_arch != "armhf" ]]; then
            dir_env="env LD_LIBRARY_PATH=$dir/lib "
            ideviceactivation="$dir_env"
            idevicediagnostics="$dir_env"
            ideviceinstaller="$dir_env"
        fi
        PlistBuddy="$dir/PlistBuddy"
        sha1sum="$(command -v sha1sum)"
        tsschecker="$dir/tsschecker"
        zenity="$(command -v zenity)"
        scp2="$dir/scp"
        ssh2="$dir/ssh"
        cp $ssh2 .
        chmod +x ssh

        # live cd/usb check
        if [[ $(id -u $USER) == 999 || $USER == "liveuser" ]]; then
            live_cdusb=1
            live_cdusb_str="Live session"
            log "Linux Live session detected."
            if [[ $(pwd) == "/home"* ]]; then
                df . -h
                if [[ $(lsblk -o label | grep -c "casper-rw") == 1 || $(lsblk -o label | grep -c "persistence") == 1 ]]; then
                    log "Detected Legacy iOS Kit running on persistent storage."
                    live_cdusb_str+=" - Persistent storage"
                else
                    warn "Detected Legacy iOS Kit running on temporary storage."
                    print "* You may run out of space and get errors during the restore process."
                    print "* Please move Legacy iOS Kit to a drive that is NOT used for the live USB."
                    print "* This may mean using another external HDD/flash drive to store Legacy iOS Kit on."
                    print "* To use one USB drive only, create the live USB using Rufus with Persistent Storage enabled."
                    sleep 5
                    pause
                    live_cdusb_str+=" - Temporary storage"
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
            ipwnder="sudo "
            irecovery="sudo "
            irecovery2="sudo "
            irecovery3="sudo "
            if [[ ! -d $dir && $(ls ../bin/linux) ]]; then
                log "Running on platform: $platform ($platform_ver - $platform_arch)"
                error "Failed to find bin directory for $platform_arch, found $(ls -x ../bin/linux) instead." \
                "* Download the \"linux_$platform_arch\" or \"complete\" version to continue (or do a git clone)"
            fi
            trap "clean_usbmuxd" EXIT
            if [[ $othertmp == 0 ]]; then
                if [[ $(command -v systemctl) ]]; then
                    sudo systemctl stop usbmuxd
                fi
                #sudo killall usbmuxd 2>/dev/null
                #sleep 1
                if [[ $platform_arch == "armhf" ]]; then
                    log "Running usbmuxd"
                    sudo -b $dir/usbmuxd -pf &>../saved/usbmuxd.log
                else
                    log "Running usbmuxd2"
                    sudo -b $dir/usbmuxd2 &>../saved/usbmuxd2.log
                fi
            elif [[ $othertmp != 0 ]]; then
                log "Detected existing tmp folder(s), there might be other Legacy iOS Kit instance(s) running"
                log "Not running usbmuxd"
            fi
        fi
        gaster+="$dir/gaster"

    elif [[ $(uname -m) == "iP"* ]]; then
        error "Running Legacy iOS Kit on iOS is not supported (yet)" "* Supported platforms: Linux, macOS"

    elif [[ $OSTYPE == "darwin"* ]]; then
        platform="macos"
        platform_ver="${1:-$(sw_vers -productVersion)}"
        dir="../bin/macos"

        platform_arch="$(uname -m)"
        if [[ $platform_arch == "arm64" ]]; then
            dir+="/arm64"
        fi

        # macos version check
        mac_majver="${platform_ver:0:2}"
        if [[ $mac_majver == 10 ]]; then
            mac_minver=${platform_ver:3}
            mac_minver=${mac_minver%.*}
            if (( mac_minver < 11 )); then
                warn "Your macOS version ($platform_ver - $platform_arch) is not supported. Expect features to not work properly."
                print "* Supported versions are macOS 10.11 and newer. (10.13/10.15 and newer recommended)"
                pause
            fi
            if (( mac_minver <= 11 )); then
                mac_cocoa=1
                if [[ -z $(command -v cocoadialog) ]]; then
                    local error_msg="* You need to install cocoadialog from MacPorts."
                    error_msg+=$'\n* Please read the wiki and install the requirements needed in MacPorts: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/How-to-Use'
                    error_msg+=$'\n* Also make sure that /opt/local/bin (or /usr/local/bin) is in your $PATH.'
                    error_msg+=$'\n* You may try running this command: export PATH="/opt/local/bin:$PATH"'
                    error "Cannot find cocoadialog, cannot continue." "$error_msg"
                fi
            fi
            if [[ $(command -v curl) == "/usr/bin/curl" ]] && (( mac_minver < 15 )); then
                local error_msg="* You need to install curl from MacPorts."
                error_msg+=$'\n* Please read the wiki and install the requirements needed in MacPorts: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/How-to-Use'
                error_msg+=$'\n* Also make sure that /opt/local/bin (or /usr/local/bin) is in your $PATH.'
                error_msg+=$'\n* You may try running this command: export PATH="/opt/local/bin:$PATH"'
                error "Outdated curl detected, cannot continue." "$error_msg"
            fi
        fi

        bspatch="$(command -v bspatch)"
        cocoadialog="$(command -v cocoadialog)"
        gaster+="../bin/macos/gaster"
        ipwnder32="$dir/ipwnder32"
        PlistBuddy="/usr/libexec/PlistBuddy"
        sha1sum="$(command -v shasum) -a 1"
        tsschecker="../bin/macos/tsschecker"
        zenity="../bin/macos/zenity"
        scp2="/usr/bin/scp"
        ssh2="/usr/bin/ssh"

        # kill macos daemons
        killall -STOP AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater

    else
        error "Your platform ($OSTYPE) is not supported." "* Supported platforms: Linux, macOS"
    fi
    log "Running on platform: $platform ($platform_ver - $platform_arch)"
    if [[ ! -d $dir ]]; then
        error "Failed to find bin directory ($dir), cannot continue." \
        "* Re-download Legacy iOS Kit from releases (or do a git clone/reset)"
    fi
    if [[ $device_sudoloop == 1 ]]; then
        sudo chmod +x $dir/*
        if [[ $? != 0 ]]; then
            error "Failed to set up execute permissions of binaries, cannot continue. Try to move Legacy iOS Kit somewhere else."
        fi
    else
        chmod +x $dir/*
    fi

    futurerestore+="$dir/futurerestore"
    ideviceactivation+="$dir/ideviceactivation"
    idevicediagnostics+="$dir/idevicediagnostics"
    ideviceinfo="$dir/ideviceinfo"
    ideviceinstaller+="$dir/ideviceinstaller"
    idevicerestore+="$dir/idevicerestore"
    ifuse="$(command -v ifuse)"
    ipwnder+="$dir/ipwnder"
    irecovery+="$dir/irecovery"
    irecovery2+="$dir/irecovery2"
    irecovery3+="../$dir/irecovery"
    jq="$dir/jq"

    cp ../resources/ssh_config .
    if [[ $(ssh -V 2>&1 | grep -c SSH_8.8) == 1 || $(ssh -V 2>&1 | grep -c SSH_8.9) == 1 ||
          $(ssh -V 2>&1 | grep -c SSH_9.) == 1 || $(ssh -V 2>&1 | grep -c SSH_1) == 1 ]]; then
        echo "    PubkeyAcceptedAlgorithms +ssh-rsa" >> ssh_config
    elif [[ $(ssh -V 2>&1 | grep -c SSH_6) == 1 ]]; then
        cat ../resources/ssh_config | sed "s,Add,#Add,g" | sed "s,HostKeyA,#HostKeyA,g" > ssh_config
    fi
    scp2+=" -F ./ssh_config"
    ssh2+=" -F ./ssh_config"
}

prepare_udev_rules() {
    local owner="$1"
    local group="$2"
    echo "ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}==\"05ac\", ATTR{idProduct}==\"122[27]|128[0-3]|1338\", OWNER=\"$owner\", GROUP=\"$group\", MODE=\"0660\" TAG+=\"uaccess\"" > 39-libirecovery.rules
}

install_depends() {
    log "Installing dependencies..."
    rm -f "../resources/firstrun"

    if [[ $platform == "linux" ]]; then
        print "* Legacy iOS Kit will be installing dependencies from your distribution's package manager"
        print "* Enter your user password when prompted"
        if [[ $distro != "debian" && $distro != "fedora-atomic" ]]; then
            echo
            warn "Before continuing, make sure that your system is fully updated first!"
            echo "${color_Y}* This operation can result in a partial upgrade and may cause breakage if your system is not updated${color_N}"
            echo
        fi
        pause
        prepare_udev_rules usbmux plugdev
    fi

    if [[ $distro == "arch" ]]; then
        sudo pacman -Sy --noconfirm --needed base-devel ca-certificates ca-certificates-mozilla curl git ifuse libimobiledevice libxml2 openssh pyenv python udev unzip usbmuxd usbutils vim zenity zip zstd
        prepare_udev_rules root storage

    elif [[ $distro == "debian" ]]; then
        if [[ -n $ubuntu_ver ]]; then
            sudo add-apt-repository -y universe
        fi
        sudo apt update
        sudo apt install -m -y build-essential ca-certificates curl git ifuse libimobiledevice6 libssl3 libssl-dev libxml2 libzstd1 openssh-client patch python3 unzip usbmuxd usbutils xxd zenity zip zlib1g-dev
        if [[ $(command -v systemctl 2>/dev/null) ]]; then
            sudo systemctl enable --now udev systemd-udevd usbmuxd 2>/dev/null
        fi

    elif [[ $distro == "fedora" ]]; then
        sudo dnf install -y ca-certificates git ifuse libimobiledevice libxml2 libzstd openssl openssl-devel patch python3 systemd udev usbmuxd vim-common zenity zip zlib-devel
        sudo dnf group install -y c-development
        sudo ln -sf /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-certificates.crt
        prepare_udev_rules root usbmuxd

    elif [[ $distro == "fedora-atomic" ]]; then
        rpm-ostree install patch vim-common zenity
        print "* You may need to reboot to apply changes with rpm-ostree. Perform a reboot after this before running the script again."

    elif [[ $distro == "opensuse" ]]; then
        sudo zypper -n install ca-certificates curl git ifuse libimobiledevice-1_0-6 libopenssl-3-devel libxml2 libzstd1 openssl-3 patch pyenv python3 usbmuxd unzip vim zenity zip zlib-devel
        sudo zypper -n install -t pattern devel_basis
        prepare_udev_rules usbmux usbmux # idk if this is right

    elif [[ $distro == "gentoo" ]]; then
        sudo emerge -av --noreplace app-arch/zstd app-misc/ca-certificates app-pda/ifuse dev-libs/libxml2 libimobiledevice net-misc/curl openssh python udev unzip usbmuxd usbutils vim zenity zip

    elif [[ $distro == "void" ]]; then
        sudo xbps-install curl git patch openssh python3 unzip xxd zenity zip base-devel libffi-devel bzip2-devel openssl openssl-devel readline readline-devel sqlite-devel xz liblzma-devel zlib zlib-devel

    elif [[ $platform == "macos" ]]; then
        print "* Legacy iOS Kit will be installing dependencies and setting up permissions of tools"
        xattr -cr ../bin/macos
        log "Installing Xcode Command Line Tools"
        xcode-select --install
        print "* Make sure to install requirements from Homebrew/MacPorts: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/How-to-Use"
        pause
    fi

    echo "$platform_ver" > "../resources/firstrun"
    if [[ $platform == "linux" && $distro != "fedora-atomic" ]]; then
        # from linux_fix and libirecovery-rules by Cryptiiiic
        if [[ $(command -v systemctl) ]]; then
            sudo systemctl enable --now systemd-udevd usbmuxd 2>/dev/null
        fi
        sudo cp 39-libirecovery.rules /etc/udev/rules.d/39-libirecovery.rules
        sudo chown root:root /etc/udev/rules.d/39-libirecovery.rules
        sudo chmod 0644 /etc/udev/rules.d/39-libirecovery.rules
        sudo udevadm control --reload-rules
        sudo udevadm trigger -s usb
    fi

    log "Install script done! Please run the script again to proceed"
    log "If your iOS device is plugged in, unplug and replug your device"
    exit
}

version_update_check() {
    pushd "$(dirname "$0")/tmp$$" >/dev/null
    if [[ $platform == "macos" && ! -e ../resources/firstrun ]]; then
        xattr -cr ../bin/macos
    fi
    log "Checking for updates..."
    github_api=$(curl https://api.github.com/repos/LukeZGD/Legacy-iOS-Kit/releases/latest 2>/dev/null)
    version_latest=$(echo "$github_api" | $jq -r '.assets[] | select(.name|test("complete")) | .name' | cut -c 25- | cut -c -9)
    git_hash_latest=$(echo "$github_api" | $jq -r '.assets[] | select(.name|test("git-hash")) | .name' | cut -c 21- | cut -c -7)
    popd >/dev/null
}

version_update() {
    local url
    local req
    read -p "$(input 'Do you want to update now? (Y/n): ')" opt
    if [[ $opt == 'n' || $opt == 'N' ]]; then
        log "User selected N, cannot continue. Exiting."
        exit
    fi
    if [[ -d .git ]]; then
        log "Running git pull..."
        print "* If this fails for some reason, run: git reset --hard"
        print "* To clean more files if needed, run: git clean -df"
        git pull
        pushd "$(dirname "$0")/tmp$$" >/dev/null
        log "Done! Please run the script again"
        exit
    elif (( $(ls bin | wc -l) > 1 )); then
        req=".assets[] | select (.name|test(\"complete\")) | .browser_download_url"
    elif [[ $platform == "linux" ]]; then
        req=".assets[] | select (.name|test(\"${platform}_$platform_arch\")) | .browser_download_url"
    else
        req=".assets[] | select (.name|test(\"${platform}\")) | .browser_download_url"
    fi
    pushd "$(dirname "$0")/tmp$$" >/dev/null
    url="$(echo "$github_api" | $jq -r "$req")"
    log "Downloading: $url"
    curl -L $url -o latest.zip
    if [[ ! -s latest.zip ]]; then
        error "Download failed. Please run the script again"
    fi
    popd >/dev/null
    log "Updating..."
    cp resources/firstrun tmp$$ 2>/dev/null
    rm -r bin/ LICENSE README.md restore.sh
    if [[ $device_sudoloop == 1 ]]; then
        sudo rm -rf resources/
    fi
    rm -r resources/ saved/ipwndfu/ 2>/dev/null
    unzip -q tmp$$/latest.zip -d .
    cp tmp$$/firstrun resources 2>/dev/null
    pushd "$(dirname "$0")/tmp$$" >/dev/null
    log "Done! Please run the script again"
    exit
}

version_get() {
    pushd .. >/dev/null
    if [[ -d .git ]]; then
        if [[ -e .git/shallow ]]; then
            log "Shallow git repository detected. Unshallowing..."
            git fetch --unshallow
        fi
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
    if [[ $device_type != "iPhone1"* && $device_type != "iPod1,1" ]]; then
        until [[ -n $device_ecid ]] && [ "$device_ecid" -eq "$device_ecid" ]; do
            read -p "$(input 'Enter device ECID (must be decimal): ')" device_ecid
        done
    fi
}

device_get_name() {
    # all devices that run iOS/iPhoneOS/iPadOS
    device_name=$device_type
    case $device_type in
        "iPhone1,1") device_name="iPhone 2G";;
        "iPhone1,2") device_name="iPhone 3G";;
        "iPhone2,1") device_name="iPhone 3GS";;
        "iPhone3,1") device_name="iPhone 4 (GSM)";;
        "iPhone3,2") device_name="iPhone 4 (GSM, Rev A)";;
        "iPhone3,3") device_name="iPhone 4 (CDMA)";;
        "iPhone4,1") device_name="iPhone 4S";;
        "iPhone5,1") device_name="iPhone 5 (GSM)";;
        "iPhone5,2") device_name="iPhone 5 (Global)";;
        "iPhone5,3") device_name="iPhone 5C (GSM)";;
        "iPhone5,4") device_name="iPhone 5C (Global)";;
        "iPhone6,1") device_name="iPhone 5S (GSM)";;
        "iPhone6,2") device_name="iPhone 5S (Global)";;
        "iPhone7,1") device_name="iPhone 6 Plus";;
        "iPhone7,2") device_name="iPhone 6";;
        "iPhone8,1") device_name="iPhone 6S";;
        "iPhone8,2") device_name="iPhone 6S Plus";;
        "iPhone8,4") device_name="iPhone SE 2016";;
        "iPhone9,1") device_name="iPhone 7 (Global)";;
        "iPhone9,2") device_name="iPhone 7 Plus (Global)";;
        "iPhone9,3") device_name="iPhone 7 (GSM)";;
        "iPhone9,4") device_name="iPhone 7 Plus (GSM)";;
        "iPhone10,1") device_name="iPhone 8 (Global)";;
        "iPhone10,2") device_name="iPhone 8 Plus (Global)";;
        "iPhone10,3") device_name="iPhone X (Global)";;
        "iPhone10,4") device_name="iPhone 8 (GSM)";;
        "iPhone10,5") device_name="iPhone 8 Plus (GSM)";;
        "iPhone10,6") device_name="iPhone X (GSM)";;
        "iPhone11,2") device_name="iPhone XS";;
        "iPhone11,4") device_name="iPhone XS Max (China)";;
        "iPhone11,6") device_name="iPhone XS Max";;
        "iPhone11,8") device_name="iPhone XR";;
        "iPhone12,1") device_name="iPhone 11";;
        "iPhone12,3") device_name="iPhone 11 Pro";;
        "iPhone12,5") device_name="iPhone 11 Pro Max";;
        "iPhone12,8") device_name="iPhone SE 2020";;
        "iPhone13,1") device_name="iPhone 12 mini";;
        "iPhone13,2") device_name="iPhone 12";;
        "iPhone13,3") device_name="iPhone 12 Pro";;
        "iPhone13,4") device_name="iPhone 12 Pro Max";;
        "iPhone14,2") device_name="iPhone 13 Pro";;
        "iPhone14,3") device_name="iPhone 13 Pro Max";;
        "iPhone14,4") device_name="iPhone 13 mini";;
        "iPhone14,5") device_name="iPhone 13";;
        "iPhone14,6") device_name="iPhone SE 2022";;
        "iPhone14,7") device_name="iPhone 14";;
        "iPhone14,8") device_name="iPhone 14 Plus";;
        "iPhone15,2") device_name="iPhone 14 Pro";;
        "iPhone15,3") device_name="iPhone 14 Pro Max";;
        "iPhone15,4") device_name="iPhone 15";;
        "iPhone15,5") device_name="iPhone 15 Plus";;
        "iPhone16,1") device_name="iPhone 15 Pro";;
        "iPhone16,2") device_name="iPhone 15 Pro Max";;
        "iPhone17,1") device_name="iPhone 16 Pro";;
        "iPhone17,2") device_name="iPhone 16 Pro Max";;
        "iPhone17,3") device_name="iPhone 16";;
        "iPhone17,4") device_name="iPhone 16 Plus";;
        "iPad1,1") device_name="iPad 1";;
        "iPad2,1") device_name="iPad 2 (Wi-Fi)";;
        "iPad2,2") device_name="iPad 2 (GSM)";;
        "iPad2,3") device_name="iPad 2 (CDMA)";;
        "iPad2,4") device_name="iPad 2 (Wi-Fi, Rev A)";;
        "iPad2,5") device_name="iPad mini 1 (Wi-Fi)";;
        "iPad2,6") device_name="iPad mini 1 (GSM)";;
        "iPad2,7") device_name="iPad mini 1 (Global)";;
        "iPad3,1") device_name="iPad 3 (Wi-Fi)";;
        "iPad3,2") device_name="iPad 3 (CDMA)";;
        "iPad3,3") device_name="iPad 3 (GSM)";;
        "iPad3,4") device_name="iPad 4 (Wi-Fi)";;
        "iPad3,5") device_name="iPad 4 (GSM)";;
        "iPad3,6") device_name="iPad 4 (Global)";;
        "iPad4,1") device_name="iPad Air 1 (Wi-Fi)";;
        "iPad4,2") device_name="iPad Air 1 (Cellular)";;
        "iPad4,3") device_name="iPad Air 1 (China)";;
        "iPad4,4") device_name="iPad mini 2 (Wi-Fi)";;
        "iPad4,5") device_name="iPad mini 2 (Cellular)";;
        "iPad4,6") device_name="iPad mini 2 (China)";;
        "iPad4,7") device_name="iPad mini 3 (Wi-Fi)";;
        "iPad4,8") device_name="iPad mini 3 (Cellular)";;
        "iPad4,9") device_name="iPad mini 3 (China)";;
        "iPad5,1") device_name="iPad mini 4 (Wi-Fi)";;
        "iPad5,2") device_name="iPad mini 4 (Cellular)";;
        "iPad5,3") device_name="iPad Air 2 (Wi-Fi)";;
        "iPad5,4") device_name="iPad Air 2 (Cellular)";;
        "iPad6,3") device_name="iPad Pro 9.7\" (Wi-Fi)";;
        "iPad6,4") device_name="iPad Pro 9.7\" (Cellular)";;
        "iPad6,7") device_name="iPad Pro 12.9\" (Wi-Fi)";;
        "iPad6,8") device_name="iPad Pro 12.9\" (Cellular)";;
        "iPad6,11") device_name="iPad 5 (Wi-Fi)";;
        "iPad6,12") device_name="iPad 5 (Cellular)";;
        "iPad7,1") device_name="iPad Pro 12.9\" (2nd gen, Wi-Fi)";;
        "iPad7,2") device_name="iPad Pro 12.9\" (2nd gen, Cellular)";;
        "iPad7,3") device_name="iPad Pro 10.5\" (Wi-Fi)";;
        "iPad7,4") device_name="iPad Pro 10.5\" (Cellular)";;
        "iPad7,5") device_name="iPad 6 (Wi-Fi)";;
        "iPad7,6") device_name="iPad 6 (Cellular)";;
        "iPad7,11") device_name="iPad 7 (Wi-Fi)";;
        "iPad7,12") device_name="iPad 7 (Cellular)";;
        "iPad8,1") device_name="iPad Pro 11\" (Wi-Fi)";;
        "iPad8,2") device_name="iPad Pro 11\" (Wi-Fi, 6GB RAM)";;
        "iPad8,3") device_name="iPad Pro 11\" (Cellular)";;
        "iPad8,4") device_name="iPad Pro 11\" (Cellular, 6GB RAM)";;
        "iPad8,5") device_name="iPad Pro 12.9\" (3rd gen, Wi-Fi)";;
        "iPad8,6") device_name="iPad Pro 12.9\" (3rd gen, Wi-Fi, 6GB RAM)";;
        "iPad8,7") device_name="iPad Pro 12.9\" (3rd gen, Cellular)";;
        "iPad8,8") device_name="iPad Pro 12.9\" (3rd gen, Cellular, 6GB RAM)";;
        "iPad8,9") device_name="iPad Pro 11\" (2nd gen, Wi-Fi)";;
        "iPad8,10") device_name="iPad Pro 11\" (2nd gen, Cellular)";;
        "iPad8,11") device_name="iPad Pro 12.9\" (4th gen, Wi-Fi)";;
        "iPad8,12") device_name="iPad Pro 12.9\" (4th gen, Cellular)";;
        "iPad11,1") device_name="iPad mini 5 (Wi-Fi)";;
        "iPad11,2") device_name="iPad mini 5 (Cellular)";;
        "iPad11,3") device_name="iPad Air 3 (Wi-Fi)";;
        "iPad11,4") device_name="iPad Air 3 (Cellular)";;
        "iPad11,6") device_name="iPad 8 (Wi-Fi)";;
        "iPad11,7") device_name="iPad 8 (Cellular)";;
        "iPad12,1") device_name="iPad 9 (Wi-Fi)";;
        "iPad12,2") device_name="iPad 9 (Cellular)";;
        "iPad13,1") device_name="iPad Air 4 (Wi-Fi)";;
        "iPad13,2") device_name="iPad Air 4 (Cellular)";;
        "iPad13,4") device_name="iPad Pro 11\" (3rd gen, Wi-Fi)";;
        "iPad13,5") device_name="iPad Pro 11\" (3rd gen, Wi-Fi, 16GB RAM)";;
        "iPad13,6") device_name="iPad Pro 11\" (3rd gen, Cellular)";;
        "iPad13,7") device_name="iPad Pro 11\" (3rd gen, Cellular, 16GB RAM)";;
        "iPad13,8") device_name="iPad Pro 12.9\" (5th gen, Wi-Fi)";;
        "iPad13,9") device_name="iPad Pro 12.9\" (5th gen, Wi-Fi, 16GB RAM)";;
        "iPad13,10") device_name="iPad Pro 12.9\" (5th gen, Cellular)";;
        "iPad13,11") device_name="iPad Pro 12.9\" (5th gen, Cellular, 16GB RAM)";;
        "iPad13,16") device_name="iPad Air 5 (Wi-Fi)";;
        "iPad13,17") device_name="iPad Air 5 (Cellular)";;
        "iPad13,18") device_name="iPad 10 (Wi-Fi)";;
        "iPad13,19") device_name="iPad 10 (Cellular)";;
        "iPad14,1") device_name="iPad mini 6 (Wi-Fi)";;
        "iPad14,2") device_name="iPad mini 6 (Cellular)";;
        "iPad14,3") device_name="iPad Pro 11\" (4th gen, Wi-Fi)";;
        "iPad14,4") device_name="iPad Pro 11\" (4th gen, Cellular)";;
        "iPad14,5") device_name="iPad Pro 12.9\" (6th gen, Wi-Fi)";;
        "iPad14,6") device_name="iPad Pro 12.9\" (6th gen, Cellular)";;
        "iPad14,8") device_name="iPad Air 11\" (M2, Wi-Fi)";;
        "iPad14,9") device_name="iPad Air 11\" (M2, Cellular)";;
        "iPad14,10") device_name="iPad Air 13\" (M2, Wi-Fi)";;
        "iPad14,11") device_name="iPad Air 13\" (M2, Cellular)";;
        "iPad16,1") device_name="iPad mini (A17 Pro, Wi-Fi)";;
        "iPad16,2") device_name="iPad mini (A17 Pro, Cellular)";;
        "iPad16,3") device_name="iPad Pro 11\" (M4, Wi-Fi)";;
        "iPad16,4") device_name="iPad Pro 11\" (M4, Cellular)";;
        "iPad16,5") device_name="iPad Pro 12.9\" (M4, Wi-Fi)";;
        "iPad16,6") device_name="iPad Pro 12.9\" (M4, Cellular)";;
        "iPod1,1") device_name="iPod touch 1";;
        "iPod2,1") device_name="iPod touch 2";;
        "iPod3,1") device_name="iPod touch 3";;
        "iPod4,1") device_name="iPod touch 4";;
        "iPod5,1") device_name="iPod touch 5";;
        "iPod7,1") device_name="iPod touch 6";;
        "iPod9,1") device_name="iPod touch 7";;
    esac
}

device_manufacturing() {
    if [[ $device_type != "iPhone2,1" && $device_type != "iPod2,1" ]] || [[ $device_argmode == "none" ]]; then
        return
    fi
    if [[ $device_type == "iPhone2,1" && $device_mode != "DFU" ]]; then
        local week=$(echo "$device_serial" | cut -c 2-)
        local year=$(echo "$device_serial" | cut -c 1)
        case $year in
            9 ) year="2009";;
            0 ) year="2010";;
            1 ) year="2011";;
            2 ) year="2012";;
        esac
        if [[ $year != "2009" ]] || (( week >= 46 )); then
            device_newbr=1
        elif [[ $year == "2009" ]] && (( week >= 40 )); then
            device_newbr=2 # gray area
        else
            device_newbr=0
        fi
    elif [[ $device_type == "iPod2,1" && $device_mode == "Recovery" ]]; then
        device_newbr=2
        return
    fi
    case $device_newbr in
        0 ) print "* This $device_name is an old bootrom model";;
        1 ) print "* This $device_name is a new bootrom model";;
        2 ) print "* This $device_name bootrom model cannot be determined. Enter DFU mode to get bootrom model";;
    esac
    if [[ $device_type == "iPhone2,1" && $device_mode == "DFU" ]]; then
        print "* Cannot check for manufacturing date in DFU mode"
    elif [[ $device_type == "iPhone2,1" ]]; then
        print "* Manufactured in Week $week $year"
    fi
}

device_s5l8900xall() {
    local wtf_sha="cb96954185a91712c47f20adb519db45a318c30f"
    local wtf_saved="../saved/WTF.s5l8900xall.RELEASE.dfu"
    local wtf_patched="$wtf_saved.patched"
    local wtf_patch="../resources/patch/WTF.s5l8900xall.RELEASE.patch"
    local wtf_sha_local="$($sha1sum "$wtf_saved" 2>/dev/null | awk '{print $1}')"
    mkdir ../saved 2>/dev/null
    if [[ $wtf_sha_local != "$wtf_sha" ]]; then
        log "Downloading WTF.s5l8900xall"
        "$dir/pzb" -g "Firmware/dfu/WTF.s5l8900xall.RELEASE.dfu" -o WTF.s5l8900xall.RELEASE.dfu "http://appldnld.apple.com/iPhone/061-7481.20100202.4orot/iPhone1,1_3.1.3_7E18_Restore.ipsw"
        rm -f "$wtf_saved"
        mv WTF.s5l8900xall.RELEASE.dfu $wtf_saved
    fi
    wtf_sha_local="$($sha1sum "$wtf_saved" | awk '{print $1}')"
    if [[ $wtf_sha_local != "$wtf_sha" ]]; then
        error "SHA1sum mismatch. Expected $wtf_sha, got $wtf_sha_local. Please run the script again"
    fi
    rm -f "$wtf_patched"
    log "Patching WTF.s5l8900xall"
    $bspatch $wtf_saved $wtf_patched $wtf_patch
    log "Sending patched WTF.s5l8900xall (Pwnage)"
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
        if [[ $platform == "linux" ]]; then
            print "* If it gets stuck here, try to restart your PC"
            if [[ $othertmp != 0 ]]; then
                print "* If it fails to detect devices, try to delete all \"tmp\" folders in your Legacy iOS Kit folder"
            fi
        fi
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

    if [[ $device_mode == "Recovery" && $device_pwnrec == 1 ]]; then
        device_mode="DFU"
    fi

    if [[ -z $device_mode ]]; then
        local error_msg=$'* Make sure to trust this computer by selecting "Trust" at the pop-up.'
        if [[ $platform == "macos" ]]; then
            error_msg+=$'\n* Make sure to have the initial setup dependencies installed before retrying.'
            error_msg+=$'\n* Double-check if the device is being detected by iTunes/Finder.'
        else
            error_msg+=$'\n* If your device in normal mode is not being detected, this is likely a usbmuxd issue.'
            error_msg+=$'\n* You may also try again in a live USB.'
        fi
        error_msg+=$'\n* Try restarting your PC/Mac as well as using different USB ports/cables.'
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
            if [[ -n $device_argmode ]]; then
                device_entry
            else
                device_type=$($irecovery -q | grep "PRODUCT" | cut -c 10-)
                device_ecid=$(printf "%d" $($irecovery -q | grep "ECID" | cut -c 7-)) # converts hex ecid to dec
            fi
            if [[ $device_type == "iPhone1,1" && -z $device_argmode ]]; then
                print "* Device Type Option"
                print "* Select Y if the device is an iPhone 2G, or N if it is an iPod touch 1"
                read -p "$(input 'Is this device an iPhone 2G? (Y/n): ')" opt
                if [[ $opt == 'n' || $opt == 'N' ]]; then
                    device_type="iPod1,1"
                fi
            fi
            device_model=$($irecovery -q | grep "MODEL" | cut -c 8-)
            device_vers=$(echo "/exit" | $irecovery -s | grep -a "iBoot-")
            if [[ -z $device_vers ]]; then
                device_vers="Unknown"
                if [[ $device_mode == "Recovery" ]]; then
                    device_vers+=". Re-enter recovery mode to get iBoot version"
                fi
            fi
            device_serial="$($irecovery -q | grep "SRNM" | cut -c 7- | cut -c 3- | cut -c -3)"
            device_get_name
            print "* Device: $device_name (${device_type} - ${device_model}) in $device_mode mode"
            print "* iOS Version: $device_vers"
            print "* ECID: $device_ecid"
            device_manufacturing
            if [[ $device_type == "iPod2,1" && $device_newbr != 2 ]]; then
                device_newbr="$($irecovery -q | grep -c '240.5.1')"
            elif [[ $device_type == "iPhone2,1" ]]; then
                device_newbr="$($irecovery -q | grep -c '359.3.2')"
            fi
            device_pwnd="$($irecovery -q | grep "PWND" | cut -c 7-)"
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
            device_det=$(echo "$device_vers" | cut -c 1)
            device_det2=$(echo "$device_vers" | cut -c -2)
            device_build=$($ideviceinfo -s -k BuildVersion)
            device_udid=$($ideviceinfo -s -k UniqueDeviceID)
            [[ -z $device_udid ]] && device_udid=$($ideviceinfo -k UniqueDeviceID)
            if [[ $device_type == "iPod2,1" ]]; then
                device_newbr="$($ideviceinfo -k ModelNumber | grep -c 'C')"
            elif [[ $device_type == "iPhone2,1" ]]; then
                device_serial="$($ideviceinfo -k SerialNumber | cut -c 3- | cut -c -3)"
            fi
            device_unactivated=$($ideviceactivation state | grep -c "Unactivated")
        ;;
    esac

    if [[ $device_argmode == "none" ]]; then
        device_entry
    fi

    device_model="$(echo $device_model | tr '[:upper:]' '[:lower:]')"
    device_model="${device_model%??}" # remove "ap" from the end
    if [[ -z $device_type && -n $device_model ]]; then
        # device_model fallback (this will be up to checkm8 devices only)
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
            j127 ) device_type="iPad6,3";;
            j128 ) device_type="iPad6,4";;
            j98a ) device_type="iPad6,7";;
            j99a ) device_type="iPad6,8";;
            j71s ) device_type="iPad6,11";;
            j71t ) device_type="iPad6,11";;
            j72s ) device_type="iPad6,12";;
            j72t ) device_type="iPad6,12";;
            j120 ) device_type="iPad7,1";;
            j121 ) device_type="iPad7,2";;
            j207 ) device_type="iPad7,3";;
            j208 ) device_type="iPad7,4";;
            j71b ) device_type="iPad7,5";;
            j72b ) device_type="iPad7,6";;
            j171 ) device_type="iPad7,11";;
            j172 ) device_type="iPad7,12";;
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
            d20  ) device_type="iPhone10,1";;
            d21  ) device_type="iPhone10,2";;
            d22  ) device_type="iPhone10,3";;
            d201 ) device_type="iPhone10,4";;
            d211 ) device_type="iPhone10,5";;
            d221 ) device_type="iPhone10,6";;
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
    all_flash="Firmware/all_flash/all_flash.${device_model}ap.production"
    device_use_bb=0
    device_latest_bb=0
    # set device_proc (what processor the device has)
    case $device_type in
        iPhone1,[12] | iPod1,1 )
            device_proc=1;; # S5L8900
        iPhone3,[123] | iPhone2,1 | iPad1,1 | iPod[234],1 )
            device_proc=4;; # A4/S5L8720/8920/8922
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
        iPhone9,[1234] | iPhone10* | iPad[67]* | iPod9,1 )
            device_proc=10;; # A10 (or A9/A10 iPad/A11 device)
        iPhone* | iPad* )
            device_proc=11;; # Newer devices
    esac
    case $device_type in
        iPad7* ) device_checkm8ipad=1;;
    esac
    device_get_name
    if (( device_proc > 10 )); then
        print "* Device: $device_name (${device_type} - ${device_model}ap) in $device_mode mode"
        print "* iOS Version: $device_vers"
        print "* ECID: $device_ecid"
        echo
        warn "This device is not supported by Legacy iOS Kit."
        print "* You may still continue but features will be very limited."
        pause
    elif [[ -z $device_proc ]]; then
        error "Unrecognized device $device_type. Enter the device type properly."
    fi

    if [[ $device_mode == "DFU" && $device_proc == 1 && $device_wtfexit != 1 ]]; then
        log "Found an S5L8900 device in DFU mode. Please re-enter WTF mode for good measure."
        print "* Force restart your device and place it in normal or recovery mode, then run the script again."
        print "* You may also use DFU Mode Helper (--dfuhelper) for entering WTF mode."
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
        iPad5* | iPhone[89]* | iPod9,1 )
            device_latest_vers="15.8.3"
            device_latest_build="19H386"
        ;;
        iPad6* | iPhone10* )
            device_latest_vers="16.7.10"
            device_latest_build="20H350"
        ;;
        iPad7* )
            log "Getting latest iOS version for $device_type"
            local latestver="$(curl "https://api.ipsw.me/v4/device/$device_type?type=ipsw" | $jq -j ".firmwares[0]")"
            device_latest_vers="$(echo "$latestver" | $jq -j ".version")"
            device_latest_build="$(echo "$latestver" | $jq -j ".buildid")"
        ;;
    esac
    # set device_use_bb, device_use_bb_sha1 (what baseband to use for ota/other)
    # for a7/a8 other restores 11.3+, device_latest_bb and device_latest_bb_sha1 are used instead
    case $device_type in
        iPhone4,1 ) # MDM6610
            device_use_bb="Trek-6.7.00.Release.bbfw"
            device_use_bb_sha1="22a35425a3cdf8fa1458b5116cfb199448eecf49"
        ;;
        iPad2,[67] ) # MDM9615 9.3.6 (32bit)
            device_use_bb="Mav5-11.80.00.Release.bbfw"
            device_use_bb_sha1="aa52cf75b82fc686f94772e216008345b6a2a750"
        ;;
        iPhone5,[12] | iPad3,[56] ) # MDM9615 10.3.4 (32bit)
            device_use_bb="Mav5-11.80.00.Release.bbfw"
            device_use_bb_sha1="8951cf09f16029c5c0533e951eb4c06609d0ba7f"
        ;;
        iPad4,[235] | iPhone5,[34] | iPhone6,[12] ) # MDM9615 10.3.3 (5C, 5S, air, mini2)
            device_use_bb="Mav7Mav8-7.60.00.Release.bbfw"
            device_use_bb_sha1="f397724367f6bed459cf8f3d523553c13e8ae12c"
        ;;
        iPad1,1 | iPhone[123],* ) device_use_bb2=1;;
        iPad[23],[23] ) device_use_bb2=2;;
    esac
    case $device_type in
        iPad4,[235689] | iPhone6,[12] ) # MDM9615 12.4-latest
            device_latest_bb="Mav7Mav8-10.80.02.Release.bbfw"
            device_latest_bb_sha1="f5db17f72a78d807a791138cd5ca87d2f5e859f0"
        ;;
    esac
    # disable baseband update if var is set to 1 (manually disabled w/ --disable-bbupdate arg)
    if [[ $device_disable_bbupdate == 1 && $device_use_bb != 0 ]] && (( device_proc < 7 )); then
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
            if [[ $platform == "macos" ]]; then
                opt="$(system_profiler SPUSBDataType 2> /dev/null | grep -B1 'Vendor ID: 0x05ac' | grep 'Product ID:' | cut -dx -f2 | cut -d' ' -f1 | tail -r)"
            elif [[ $platform == "linux" ]]; then
                opt="$(lsusb | cut -d' ' -f6 | grep '05ac:' | cut -d: -f2)"
            fi
            case $opt in
                12[9a][0123456789abcdef] ) device_in=1;; # normal
            esac
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
        if [[ $timeout != 1 && $timeout != 20 ]]; then
            error "Failed to find device in $mode mode (Timed out). Please run the script again."
        fi
        return 1
    elif [[ $mode == "WTF" && $wtfreal != 1 ]]; then
        device_s5l8900xall
    fi
}

device_sshpass() {
    # ask for device password and use sshpass for scp and ssh
    ssh_user="root"
    if [[ $device_det == 1 ]]; then
        if (( device_det2 >= 15 )); then
            log "iOS 15+ device detected. Connecting to device SSH as mobile..."
            ssh_user="mobile"
        fi
    fi
    local pass=$1
    if [[ -z $pass ]]; then
        read -s -p "$(input "Enter the SSH $ssh_user password of your iOS device: ")" pass
        echo
    fi
    if [[ -z $pass ]]; then
        pass="alpine"
    fi
    scp="$dir/sshpass -p $pass $scp2"
    ssh="$dir/sshpass -p $pass $ssh2"
}

device_iproxy() {
    local port=22
    log "Running iproxy for SSH..."
    if [[ -n $2 ]]; then
        port=$2
    fi
    if [[ $1 == "no-logging" && $debug_mode != 1 ]]; then
        "$dir/iproxy" $ssh_port $port >/dev/null &
        iproxy_pid=$!
    else
        "$dir/iproxy" $ssh_port $port &
        iproxy_pid=$!
    fi
    log "iproxy PID: $iproxy_pid"
    sleep 1
}

device_find_all() {
    # find device stuff from palera1n legacy
    local opt
    if [[ $1 == "norec" || $platform == "macos" ]]; then
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
        12[9a][0123456789abcdef] ) return 4;; # normal
    esac
}

device_dfuhelper2() {
    local top="SIDE"
    if [[ $device_type == "iPad"* ]]; then
        top="TOP"
    fi
    echo
    print "* Press the VOL UP button now."
    sleep 1
    print "* Press the VOL DOWN button now."
    sleep 1
    print "* Press and hold the $top button."
    for i in {10..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n$(print "* Press and hold VOL DOWN and $top buttons.")"
    for i in {05..01}; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n$(print "* Release $top button and keep holding VOL DOWN button.")"
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
    device_find_mode DFU
}

device_dfuhelper() {
    local opt
    local rec="recovery mode "
    if [[ $1 == "norec" ]]; then
        rec=
    fi
    if [[ $device_mode == "DFU" ]]; then
        log "Device is already in DFU mode"
        return
    fi
    print "* DFU Mode Helper - Get ready to enter DFU mode."
    print "* If you already know how to enter DFU mode, you may do so right now before continuing."
    read -p "$(input "Select Y to continue, N to exit $rec(Y/n) ")" opt
    if [[ $opt == 'N' || $opt == 'n' ]]; then
        if [[ -z $1 ]]; then
            log "Attempting to exit Recovery mode."
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
    for i in {03..01}; do
        echo -n "$i "
        sleep 1
    done
    case $device_type in
        iPhone1,* | iPad1,1 | iPad1[12]* ) :;;
        iPhone1* | iPad[81]* ) device_dfuhelper2; return;;
    esac
    local top="TOP"
    local home="HOME"
    case $device_type in
        iPhone7* | iPhone8,[12] | iPhone9* ) top="SIDE";;
    esac
    if [[ $device_type == "iPhone9"* || $device_type == "iPod9,1" ]]; then
        home="VOL DOWN"
    fi
    echo -e "\n$(print "* Hold $top and $home buttons.")"
    if [[ $device_proc == 1 ]]; then
        for i in {10..01}; do
            echo -n "$i "
            sleep 1
        done
    else
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
    fi
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
            device_dfuhelper norec WTFreal
            device_find_mode WTFreal 100
        ;;

        "Recovery" )
            if [[ $device_mode == "Normal" ]]; then
                if [[ $mode != "enterrecovery" ]]; then
                    print "* The device needs to be in recovery/DFU mode before proceeding."
                    read -p "$(input 'Send device to recovery mode? (Y/n): ')" opt
                    if [[ $opt == 'n' || $opt == 'N' ]]; then
                        log "User selected N, cannot continue. Exiting."
                        exit
                    fi
                fi
                log "Entering recovery mode..."
                print "* If the device does not enter recovery mode automatically, press Ctrl+C to cancel and try putting the device in DFU/Recovery mode manually"
                "$dir/ideviceenterrecovery" "$device_udid" >/dev/null
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
            local ip="127.0.0.1"

            if [[ $device_mode != "Normal" ]]; then
                device_enter_mode pwnDFU
                return
            fi

            patch_ibss
            device_iproxy

            log "Please read the message below:"
            print "* Follow these instructions to enter kDFU mode."
            print "1. Install \"OpenSSH\" in Cydia or Zebra."
            if [[ $device_det == 1 ]]; then
                print "  - Jailbreak with socket: https://github.com/staturnzz/socket"
                print "  - Also install \"Dropbear\" from my repo: https://lukezgd.github.io/repo"
            fi
            print "  - After installing these requirements, lock your device."
            print "2. You will be prompted to enter the root password of your iOS device."
            print "  - The default root password is: alpine"
            print "  - Your password input will not be visible, but it is still being entered."
            print "3. On entering kDFU mode, the device will disconnect."
            print "  - Proceed to unplug and replug the device when prompted."
            print "  - Alternatively, press the TOP or HOME button."
            pause

            echo "chmod +x /tmp/kloader*" > kloaders
            if [[ $device_det == 1 ]]; then
                echo '[[ $(uname -a | grep -c "MarijuanARM") == 1 ]] && /tmp/kloader_hgsp /tmp/pwnediBSS || \
                /tmp/kloader /tmp/pwnediBSS' >> kloaders
                sendfiles+=("../resources/kloader/kloader_hgsp" "../resources/kloader/kloader")
            elif (( device_det <= 5 )); then
                opt="kloader_axi0mX"
                case $device_type in
                    iPad2,4 | iPad3* ) opt="kloader5";; # needed for ipad 3 ios 5, unsure for ipad2,4
                esac
                log "Using $opt for $device_type iOS $device_det"
                echo "/tmp/$opt /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader/$opt")
            else
                echo "/tmp/kloader /tmp/pwnediBSS" >> kloaders
                sendfiles+=("../resources/kloader/kloader")
            fi
            sendfiles+=("kloaders" "pwnediBSS")

            device_sshpass
            log "Entering kDFU mode..."
            print "* This may take a while, but should not take longer than a minute."
            log "Sending files to device: ${sendfiles[*]}"
            if [[ $device_det == 1 ]]; then
                for file in "${sendfiles[@]}"; do
                    cat $file | $ssh -p $ssh_port root@127.0.0.1 "cat > /tmp/$(basename $file)" &>scp.log &
                done
                sleep 3
                cat scp.log
                check="$(cat scp.log | grep -c "Connection reset")"
            else
                $scp -P $ssh_port ${sendfiles[@]} root@127.0.0.1:/tmp
                check=$?
            fi
            if [[ $check == 0 ]]; then
                log "Running kloader"
                $ssh -p $ssh_port root@127.0.0.1 "bash /tmp/kloaders" &
            else
                warn "Failed to connect to device via USB SSH."
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
                ip=
                until [[ -n $ip ]]; do
                    read -p "$(input 'Enter the IP Address of your device: ')" ip
                done
                log "Sending files to device: ${sendfiles[*]}"
                $scp ${sendfiles[@]} root@$ip:/tmp
                if [[ $? != 0 ]]; then
                    error "Failed to connect to device via SSH, cannot continue."
                fi
                log "Running kloader"
                $ssh root@$ip "bash /tmp/kloaders" &
            fi

            local attempt=1
            local device_in
            local port
            if [[ $ip == "127.0.0.1" ]]; then
                port="-p $ssh_port"
            fi
            while (( attempt <= 5 )); do
                log "Finding device in kDFU mode... (Attempt $attempt of 5)"
                if [[ $($irecovery -q 2>/dev/null | grep -w "MODE" | cut -c 7-) == "DFU" ]]; then
                    device_in=1
                fi
                if [[ $device_in == 1 ]]; then
                    log "Found device in kDFU mode."
                    device_mode="DFU"
                    break
                fi
                if [[ $opt == "kloader_axi0mX" ]]; then
                    print "* Keep the device plugged in"
                    $ssh $port root@$ip "bash /tmp/kloaders" &
                else
                    print "* Unplug and replug your device now"
                fi
                ((attempt++))
            done
            if (( attempt > 5 )); then
                error "Failed to find device in kDFU mode. Please run the script again"
            fi
            kill $iproxy_pid
        ;;

        "pwnDFU" )
            local irec_pwned
            local tool_pwned

            if [[ $device_skip_ibss == 1 ]]; then
                warn "Skip iBSS flag detected, skipping pwned DFU check. Proceed with caution"
                return
            elif [[ $device_pwnrec == 1 ]]; then
                warn "Pwned recovery flag detected, skipping pwned DFU check. Proceed with caution"
                return
            elif [[ $device_proc == 1 ]]; then
                device_enter_mode DFU
                return
            fi
            if [[ $device_mode == "DFU" ]]; then
                device_pwnd="$($irecovery -q | grep "PWND" | cut -c 7-)"
            fi
            if [[ $device_mode == "DFU" && $mode != "pwned-ibss" &&
                  $device_boot4 != 1 && $device_proc == 5 ]]; then
                print "* Select Y if your device is in pwned iBSS/kDFU mode."
                print "* Select N if this is not the case. (pwned using checkm8-a5)"
                print "* Failing to answer correctly will cause \"Sending iBEC\" to fail."
                read -p "$(input 'Is your device already in pwned iBSS/kDFU mode? (y/N): ')" opt
                if [[ $opt == "Y" || $opt == "y" ]]; then
                    log "Pwned iBSS/kDFU mode specified by user."
                    return
                fi
            elif [[ -n $device_pwnd ]]; then
                log "Device seems to be already in pwned DFU mode"
                print "* Pwned: $device_pwnd"
                case $device_proc in
                    4 ) return;;
                    7 )
                        if [[ $platform != "macos" ]]; then
                            device_ipwndfu rmsigchks
                        fi
                        return
                    ;;
                    [89] | 10 )
                        log "gaster reset"
                        $gaster reset
                        return
                    ;;
                esac
            fi

            if [[ $device_proc == 5 ]]; then
                print "* DFU mode for A5 device - Make sure that your device is in PWNED DFU mode."
                print "* You need to have an Arduino and USB Host Shield for checkm8-a5."
                print "* Use my fork of checkm8-a5: https://github.com/LukeZGD/checkm8-a5"
                print "* You may also use checkm8-a5 for the Pi Pico: https://www.reddit.com/r/LegacyJailbreak/comments/1djuprf/working_checkm8a5_on_the_raspberry_pi_pico/"
                print "* Also make sure that you have NOT sent a pwned iBSS yet."
                print "* If you do not know what you are doing, restart your device in normal mode."
                echo
                log "Checking for device"
                device_pwnd="$($irecovery -q | grep "PWND" | cut -c 7-)"
                if [[ -n $device_pwnd ]]; then
                    log "Found device in pwned DFU mode."
                    print "* Pwned: $device_pwnd"
                else
                    local error_msg=$'\n* If you have just used checkm8-a5, it may have just failed. Just re-enter DFU, and retry.'
                    if [[ $mode != "device_justboot" && $device_target_tethered != 1 ]]; then
                        echo
                        error_msg+=$'\n* As much as possible, use the jailbroken method instead: restart the device in normal mode and jailbreak it.'
                        error_msg+=$'\n* You just need to have OpenSSH installed from Cydia.'
                        error_msg+=$'\n    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Restore-32-bit-Device'
                        echo
                    fi
                    error_msg+=$'\n* Exit DFU mode first by holding the TOP and HOME buttons for about 10 seconds.'
                    error_msg+=$'\n* For more info about kDFU/pwnDFU, read the "Troubleshooting" wiki page in GitHub'
                    error_msg+=$'\n* Troubleshooting link: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting#dfu-advanced-menu-a5x-pwndfu-mode-with-arduino-and-usb-host-shield'
                    error "32-bit A5 device is NOT in PWNED DFU mode. Already pwned iBSS mode?" "$error_msg"
                fi
                device_ipwndfu send_ibss
                return
            fi

            device_enter_mode DFU

            if [[ $device_proc == 4 ]] || [[ $device_proc == 6 && $platform == "macos" && $platform_arch == "x86_64" ]]; then
                tool_ipwndfu=1
            fi

            if (( device_proc > 7 )); then
                # A8/A9/A10 uses gaster
                log "Placing device to pwnDFU mode using gaster"
                print "* If pwning fails and gets stuck, you can press Ctrl+C to cancel."
                $gaster pwn
                tool_pwned=$?
                log "gaster reset"
                $gaster reset
            elif [[ $device_type == "iPod2,1" || $mode == "device_alloc8" ]]; then
                # touch 2 uses ipwndfu
                # also installing alloc8 requires pwning with ipwndfu
                device_ipwndfu pwn
                tool_pwned=$?
            elif [[ $tool_ipwndfu == 1 ]]; then
                # A6 intel mac/A4/3gs/touch 3 uses ipwndfu/ipwnder
                local selection=("ipwnder" "ipwndfu")
                if [[ $platform == "linux" ]]; then
                    selection=("ipwndfu" "ipwnder (limera1n)")
                    if [[ $device_type != "iPhone2,1" && $device_type != "iPod3,1" ]]; then
                        selection+=("ipwnder (SHAtter)")
                    fi
                fi
                input "PwnDFU Tool Option"
                print "* Select tool to be used for entering pwned DFU mode."
                print "* This option is set to ${selection[0]} by default (1). Select this option if unsure."
                print "* If the first option does not work, try the other option and do multiple attempts."
                print "* Note: Some Intel Macs may have better success rates with ipwndfu than ipwnder."
                input "Select your option:"
                select opt2 in "${selection[@]}"; do
                    log "Placing device to pwnDFU mode using $opt2"
                    case $opt2 in
                        "ipwndfu" ) device_ipwndfu pwn; tool_pwned=$?; break;;
                        "ipwnder (SHAtter)"  ) $ipwnder -s; tool_pwned=$?; break;;
                        "ipwnder (limera1n)" ) $ipwnder -p; tool_pwned=$?; break;;
                        "ipwnder"            ) tool_ipwndfu=2; $ipwnder -d; tool_pwned=$?; break;;
                    esac
                done
            elif [[ $platform == "linux" ]]; then
                # A6/A7 linux uses ipwndfu
                device_ipwndfu pwn
                tool_pwned=$?
            elif [[ $device_proc == 6 ]]; then
                # A6 asi mac uses ipwnder_lite
                log "Placing device to pwnDFU mode using ipwnder_lite"
                $ipwnder -d
                tool_pwned=$?
            elif [[ $platform_arch == "arm64" ]]; then
                # A7 asi mac uses ipwnder_lite
                log "Placing device to pwnDFU mode using ipwnder_lite"
                ${ipwnder}2 -p
                tool_pwned=$?
            else
                # A7 intel mac uses ipwnder32/ipwnder_lite
                local selection=("ipwnder32" "ipwnder_lite" "ipwndfu")
                input "PwnDFU Tool Option"
                print "* Select tool to be used for entering pwned DFU mode."
                print "* This option is set to ${selection[0]} by default (1). Select this option if unsure."
                print "* If the first option does not work, try many times and/or try the other option(s)."
                print "* Note: Some Intel Macs have very low success rates for A7 checkm8."
                input "Select your option:"
                select opt2 in "${selection[@]}"; do
                    log "Placing device to pwnDFU mode using $opt"
                    case $opt2 in
                        "ipwnder32" ) $ipwnder32 -p; tool_pwned=$?; break;;
                        "ipwndfu" ) tool_ipwndfu=1; device_ipwndfu pwn; tool_pwned=$?; break;;
                        * ) ${ipwnder}2 -p; tool_pwned=$?; break;;
                    esac
                done
            fi
            if [[ $tool_pwned == 2 ]]; then
                return
            fi
            log "Checking for device"
            irec_pwned=$($irecovery -q | grep -c "PWND")
            # irec_pwned is instances of "PWND" in serial, must be 1
            # tool_pwned is error code of pwning tool, must be 0
            if [[ $irec_pwned != 1 && $tool_pwned != 0 ]]; then
                device_pwnerror
            fi
            if [[ $device_proc == 6 && $tool_ipwndfu == 2 ]]; then
                device_ipwndfu send_ibss
                return
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
    local error_msg=$'\n* Exit DFU mode first by holding the TOP and HOME buttons for about 10 seconds.'
    if [[ $platform == "linux" ]]; then
        error_msg+=$'\n* Unfortunately, pwning may have low success rates for PCs with an AMD desktop CPU if you have one.'
        error_msg+=$'\n* Also, success rates for A6 and A7 checkm8 are lower on Linux.'
        error_msg+=$'\n* Pwning using an Intel PC or another Mac or iOS device may be better options.'
        if [[ $device_proc == 6 && $mode != "device_justboot" && $device_target_tethered != 1 ]]; then
            echo
            error_msg+=$'\n* As much as possible, use the jailbroken method instead: restart the device in normal mode and jailbreak it.'
            error_msg+=$'\n* You just need to have OpenSSH (and Dropbear if on iOS 10) installed from Cydia/Zebra.'
            error_msg+=$'\n    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Restore-32-bit-Device'
            echo
        fi
    elif [[ $platform == "macos" && -n $tool_ipwndfu ]]; then
        error_msg+=$'\n* If you get the error "No backend available" in ipwndfu, install libusb in Homebrew/MacPorts'
    elif [[ $platform == "macos" && $platform_arch == "x86_64" ]]; then
        if [[ $device_proc == 4 || $device_proc == 6 ]]; then
            error_msg+=$'\n* Try to do attempts with ipwndfu selected if ipwnder does not work.'
        elif [[ $device_proc == 7 ]]; then
            error_msg+=$'\n* Some Intel Macs have very low success rates for A7 checkm8.'
            error_msg+=$'\n* Particularly Core 2 Duo Macs, but may include some newer Intel Macs as well.'
            error_msg+=$'\n* Pwning using another Mac or iOS device using iPwnder Lite are better options if needed.'
        fi
    fi
    error_msg+=$'\n* For more details, read the "Troubleshooting" wiki page in GitHub'
    error_msg+=$'\n* Troubleshooting links:
    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting
    - https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Pwning-Using-Another-iOS-Device'
    error "Failed to enter pwnDFU mode. Please run the script again." "$error_msg"
}

device_ipwndfu() {
    local tool_pwned=0
    local python2="$(command -v python2)"
    local pyenv="$(command -v pyenv)"
    local pyenv2="$HOME/.pyenv/versions/2.7.18/bin/python2"

    if [[ -z "$pyenv" && -e "$HOME/.pyenv/bin/pyenv" ]]; then
        pyenv="$HOME/.pyenv/bin/pyenv"
    fi
    if [[ $platform == "macos" ]] && (( mac_majver < 12 )); then
        python2="/usr/bin/python"
        log "Using macOS system python2"
        print "* You may also install python2 from pyenv if something is wrong with system python2"
        print "* Install pyenv by running: curl https://pyenv.run | bash"
        print "* Install python2 from pyenv by running: pyenv install 2.7.18"
    elif [[ -n "$python2" && $device_sudoloop == 1 ]]; then
        p2_sudo="sudo"
    elif [[ -z "$python2" && ! -e "$pyenv2" ]]; then
        warn "python2 is not installed. Attempting to install python2 before continuing"
        print "* Install python2 from pyenv by running: pyenv install 2.7.18"
        if [[ -z "$pyenv" ]]; then
            warn "pyenv is not installed. Attempting to install pyenv before continuing"
            print "* Install pyenv by running: curl https://pyenv.run | bash"
            log "Installing pyenv"
            curl https://pyenv.run | bash
            pyenv="$HOME/.pyenv/bin/pyenv"
            if [[ ! -e "$pyenv" ]]; then
                error "Cannot detect pyenv, its installation may have failed." \
                "* Try installing pyenv manually before retrying."
            fi
        fi
        log "Installing python2 using pyenv"
        print "* This may take a while, but should not take longer than a few minutes."
        "$pyenv" install 2.7.18
        if [[ ! -e "$pyenv2" ]]; then
            warn "Cannot detect python2 from pyenv, its installation may have failed."
            print "* Try installing pyenv and/or python2 manually:"
            print "    pyenv:   > curl https://pyenv.run | bash"
            print "    python2: > \"$pyenv\" install 2.7.18"
            if [[ $distro == "fedora-atomic" ]]; then
                print "* For Fedora Atomic, you will also need to set up toolbox and build environment."
                print "* Follow the commands here under Fedora Silverblue: https://github.com/pyenv/pyenv/wiki#suggested-build-environment"
                print "* Run the pyenv install commands while in the toolbox container."
            fi
            error "Cannot detect python2 for ipwndfu, cannot continue."
        fi
    fi
    if [[ -e "$pyenv2" ]]; then
        log "python2 from pyenv detected, this will be used"
        if [[ $device_sudoloop == 1 ]]; then
            p2_sudo="sudo"
        fi
        python2="$pyenv2"
    fi

    mkdir ../saved/ipwndfu 2>/dev/null
    rm -f ../saved/ipwndfu/pwnediBSS
    if [[ $1 == "send_ibss" && $device_boot4 == 1 ]]; then
        cp iBSS.patched ../saved/ipwndfu/pwnediBSS
    elif [[ $1 == "send_ibss" ]]; then
        device_rd_build=
        patch_ibss
        cp pwnediBSS ../saved/ipwndfu/
    fi

    device_enter_mode DFU
    local ipwndfu_comm="1d22fd01b0daf52bbcf1ce730022d4212d87f967"
    local ipwndfu_sha1="30f0802078ab6ff83d6b918e13f09a652a96d6dc"
    if [[ ! -s ../saved/ipwndfu/ipwndfu || $(cat ../saved/ipwndfu/sha1check) != "$ipwndfu_sha1" ]]; then
        rm -rf ../saved/ipwndfu-*
        download_file https://github.com/LukeZGD/ipwndfu/archive/$ipwndfu_comm.zip ipwndfu.zip $ipwndfu_sha1
        unzip -q ipwndfu.zip -d ../saved
        rm -rf ../saved/ipwndfu
        mv ../saved/ipwndfu-* ../saved/ipwndfu
        echo "$ipwndfu_sha1" > ../saved/ipwndfu/sha1check
        rm -rf ../saved/ipwndfu-*
    fi
    if [[ $platform == "macos" && ! -e "$HOME/lib/libusb-1.0.dylib" ]]; then
        if [[ -e "$HOME/lib" && -e "$HOME/lib.bak" ]]; then
            rm -rf "$HOME/lib"
        elif [[ -e "$HOME/lib" ]]; then
            mv "$HOME/lib" "$HOME/lib.bak"
        fi
        if [[ -e /opt/local/lib/libusb-1.0.dylib ]]; then
            ln -sf /opt/local/lib "$HOME/lib"
        elif [[ -e /opt/homebrew/lib/libusb-1.0.dylib ]]; then
            ln -sf /opt/homebrew/lib "$HOME/lib"
        fi
    fi

    pushd ../saved/ipwndfu/ >/dev/null
    case $1 in
        "send_ibss" )
            log "Sending iBSS using ipwndfu..."
            $p2_sudo "$python2" ipwndfu -l pwnediBSS
            tool_pwned=$?
            rm pwnediBSS
            if [[ $tool_pwned != 0 ]]; then
                popd >/dev/null
                local error_msg
                if [[ $platform == "macos" ]]; then
                    error_msg+=$'\n* If you get the error "No backend available," install libusb in Homebrew/MacPorts\n'
                fi
                error_msg+="* You might need to exit DFU and (re-)enter PWNED DFU mode before retrying."
                error "Failed to send iBSS. Your device has likely failed to enter PWNED DFU mode." "$error_msg"
            fi
            print "* ipwndfu should have \"done!\" as output. If not, sending iBEC will fail."
        ;;

        "pwn" )
            log "Placing device to pwnDFU Mode using ipwndfu"
            $p2_sudo "$python2" ipwndfu -p
            tool_pwned=$?
            if [[ $tool_pwned != 0 && $tool_pwned != 2 ]]; then
                if (( device_proc >= 6 )) && [[ $tool_pwned != 2 && $platform == "linux" ]]; then
                    log "You may see the langid error above. This is normal, let's try to make it work"
                    print "* If it is any other error, it may have failed. Just continue, re-enter DFU, and retry"
                    log "Please read the message below:"
                    print "* Unplug and replug the device 2 times"
                    print "* After doing this, continue by pressing Enter/Return"
                    pause
                    log "Checking for device"
                    device_pwnd="$($irecovery3 -q | grep "PWND" | cut -c 7-)"
                    if [[ -n $device_pwnd ]]; then
                        log "Success!"
                        print "* Pwned: $device_pwnd"
                    else
                        popd >/dev/null
                        device_pwnerror
                    fi
                else
                    popd >/dev/null
                    device_pwnerror
                fi
            fi
        ;;

        "rmsigchks" )
            log "Running rmsigchks..."
            $p2_sudo "$python2" rmsigchks.py
        ;;

        "alloc8" )
            if [[ ! -s n88ap-iBSS-4.3.5.img3 ]]; then
                log "Downloading iOS 4.3.5 iBSS"
                "../$dir/pzb" -g "Firmware/dfu/iBSS.n88ap.RELEASE.dfu" -o n88ap-iBSS-4.3.5.img3 http://appldnld.apple.com/iPhone4/041-1965.20110721.gxUB5/iPhone2,1_4.3.5_8L1_Restore.ipsw
            fi
            log "Installing alloc8 to device"
            $p2_sudo "$python2" ipwndfu -x
            if [[ $platform == "macos" ]]; then
                print "* If you get the error \"No backend available,\" install libusb in Homebrew/MacPorts"
            fi
        ;;
    esac
    if [[ $device_sudoloop == 1 ]]; then
        sudo rm *.pyc libusbfinder/*.pyc usb/*.pyc usb/backend/*.pyc
    fi
    popd >/dev/null
    return $tool_pwned
}

download_file() {
    # usage: download_file {link} {target location} {sha1}
    local filename="$(basename $2)"
    log "Downloading $filename..."
    curl -L $1 -o $2
    if [[ ! -s $2 ]]; then
        error "Downloading $2 failed. Please run the script again"
    fi
    if [[ -z $3 ]]; then
        return
    fi
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
        case $build in
            1[23]* )
                if [[ $(cat "$keys_path/index.html" | sed "s|DeviceTree.${device_model}ap||g" | grep -c "${device_model}ap") != 0 ]]; then
                    log "Existing firmware keys seem to have incorrect filenames. Deleting"
                    rm "$keys_path/index.html"
                fi
            ;;
        esac
    fi

    if [[ ! -e "$keys_path/index.html" ]]; then
        log "Getting firmware keys for $device_type-$build"
        mkdir -p "$keys_path" 2>/dev/null
        local try=("https://github.com/LukeZGD/Legacy-iOS-Kit-Keys/raw/master/$device_type/$build/index.html"
                   "http://127.0.0.1:8888/firmware/$device_type/$build"
                   "https://api.m1sta.xyz/wikiproxy/$device_type/$build")
        for i in "${try[@]}"; do
            curl -L $i -o index.html
            if [[ $(cat index.html | grep -c "$build") == 1 ]]; then
                break
            fi
        done
        if [[ $(cat index.html | grep -c "$build") != 1 ]]; then
            local error_msg="* You may need to run wikiproxy to get firmware keys."
            error_msg+=$'\n* For more details, go to the "Troubleshooting" wiki page in GitHub.'
            error_msg+=$'\n* Troubleshooting link: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting#running-wikiproxy'
            error "Failed to download firmware keys." "$error_msg"
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

ipsw_get_url() {
    local build_id="$1"
    local url="$(cat "$device_fw_dir/$build_id/url" 2>/dev/null)"
    ipsw_url=
    log "Checking URL in $device_fw_dir/$build_id/url"
    if [[ $(echo "$url" | grep -c '<') != 0 || $url != *"$build_id"* ]]; then
        rm -f "$device_fw_dir/$build_id/url"
        url=
    fi
    if [[ -z $url ]]; then
        log "Getting URL for $device_type-$build_id"
        url="$(curl "https://api.ipsw.me/v4/ipsw/$device_type/$build_id" | $jq -j ".url")"
        if [[ $(echo "$url" | grep -c '<') != 0 ]]; then
            url="$(curl "https://api.ipsw.me/v4/device/$device_type?type=ipsw" | $jq -j ".firmwares[] | select(.buildid == \"$build_id\") | .url")"
        fi
        mkdir -p $device_fw_dir/$build_id 2>/dev/null
        echo "$url" > $device_fw_dir/$build_id/url
    fi
    ipsw_url="$url"
}

download_comp() {
    # usage: download_comp [build_id] [comp]
    local build_id="$1"
    local comp="$2"
    ipsw_get_url $build_id
    download_targetfile="$comp.$device_model"
    if [[ $build_id != "12"* ]]; then
        download_targetfile+="ap"
    fi
    download_targetfile+=".RELEASE"

    if [[ -e "../saved/$device_type/${comp}_$build_id.dfu" ]]; then
        cp "../saved/$device_type/${comp}_$build_id.dfu" ${comp}
    else
        log "Downloading ${comp}..."
        "$dir/pzb" -g "Firmware/dfu/$download_targetfile.dfu" -o ${comp} "$ipsw_url"
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
    local iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "iBSS") | .iv')
    local key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "iBSS") | .key')
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
    local iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "iBEC") | .iv')
    local key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "iBEC") | .key')
    local address="0x80000000"
    if [[ $device_proc == 4 ]]; then
        address="0x40000000"
    fi
    mv iBEC $name.orig
    log "Decrypting iBEC..."
    "$dir/xpwntool" $name.orig $name.dec -iv $iv -k $key
    log "Patching iBEC..."
    if [[ $device_proc == 4 || -n $device_rd_build ]]; then
        "$dir/iBoot32Patcher" $name.dec $name.patched --rsa --ticket -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1" -c "go" $address
    else
        $bspatch $name.dec $name.patched "../resources/patch/$download_targetfile.patch"
    fi
    "$dir/xpwntool" $name.patched pwnediBEC.dfu -t $name.orig
    rm $name.dec $name.orig $name.patched
    cp pwnediBEC.dfu ../saved/$device_type/
    log "Pwned iBEC img3 saved at: saved/$device_type/pwnediBEC.dfu"
}

ipsw_nojailbreak_message() {
    local hac
    local tohac
    case $device_type in
        iPhone[23],1 ) hac=" (and hacktivate)"; tohac=1;;
    esac
    log "Jailbreak option is not available for this version. You may jailbreak$hac later after the restore"
    print "* To jailbreak, select \"Jailbreak Device\" in the main menu"
    if [[ $tohac == 1 ]]; then
        print "* To hacktivate, go to \"Other Utilities -> Hacktivate Device\" after jailbreaking"
    fi
}

ipsw_preference_set() {
    # sets ipsw variables: ipsw_jailbreak, ipsw_memory, ipsw_verbose

    if (( device_proc >= 7 )); then
        return
    fi

    case $device_latest_vers in
        [76543]* ) ipsw_canjailbreak=1;;
    esac
    if [[ $device_target_vers == "$device_latest_vers" && $ipsw_canjailbreak != 1 && $ipsw_gasgauge_patch != 1 ]]; then
        return
    elif [[ $device_target_vers != "$device_latest_vers" ]]; then
        ipsw_canjailbreak=
    fi

    case $device_target_vers in
        9.3.[4321] | 9.3 | 9.[21]* | [8765]* | 4.[32]* ) ipsw_canjailbreak=1;;
        3.1.3 )
            case $device_proc in
                1 ) ipsw_canjailbreak=1;;
                * ) ipsw_nojailbreak_message;;
            esac
        ;;
    esac

    if [[ $device_proc == 5 ]]; then
        case $device_target_vers in
            8.[210]* ) ipsw_canjailbreak=;;
        esac
    elif [[ $device_type == "iPhone1,2" || $device_type == "iPhone2,1" || $device_type == "iPod2,1" ]]; then
        case $device_target_vers in
            4* ) ipsw_canjailbreak=1;;
            3.1.3 ) :;;
            3.[10]* ) ipsw_nojailbreak_message;;
        esac
    else
        case $device_target_vers in
            4.[10]* ) ipsw_nojailbreak_message;;
        esac
    fi

    if [[ $device_target_powder == 1 ]]; then
        case $device_target_vers in
            [98]* ) ipsw_canjailbreak=1;;
        esac
    elif [[ $device_target_other == 1 && $ipsw_canjailbreak != 1 ]]; then
        return
    fi

    if [[ $ipsw_isbeta == 1 ]]; then
        case $device_target_vers in
            8* )
                if [[ $device_target_build == "12A4265u" || $device_target_build == "12A4297e" ]]; then
                    warn "iOS beta detected. Disabling jailbreak option"
                    ipsw_canjailbreak=
                fi
            ;;
            [76]* ) :;;
            * )
                warn "iOS beta detected. Disabling jailbreak option"
                ipsw_canjailbreak=
            ;;
        esac
        if [[ $ipsw_canjailbreak == 1 ]]; then
            warn "iOS beta detected. Jailbreak option might not work properly"
        fi
    fi

    if [[ $ipsw_fourthree == 1 ]]; then
        ipsw_jailbreak=1
    elif [[ $ipsw_jailbreak == 1 ]]; then
        warn "Jailbreak flag detected, jailbreak option enabled by user."
    elif [[ $ipsw_canjailbreak == 1 && -z $ipsw_jailbreak ]]; then
        input "Jailbreak Option"
        print "* When this option is enabled, your device will be jailbroken on restore."
        print "* I recommend to enable this option to have the jailbreak and Cydia pre-installed."
        print "* This option is enabled by default (Y). Select this option if unsure."
        if [[ $device_type == "iPad2"* && $device_target_vers == "4.3"* && $device_target_tethered != 1 ]]; then
            warn "This will be a semi-tethered jailbreak. checkm8-a5 is required to boot to a jailbroken state."
            print "* To boot jailbroken later, go to: Main Menu -> Just Boot"
        elif [[ $device_type == "iPhone3,3" ]]; then
            case $device_target_vers in
                4.2.9 | 4.2.10 )
                    warn "This will be a semi-tethered jailbreak."
                    print "* To boot jailbroken later, go to: Main Menu -> Just Boot"
                ;;
            esac
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

    if [[ $ipsw_jailbreak == 1 && -z $ipsw_hacktivate && $ipsw_canhacktivate == 1 ]]; then
        input "Hacktivate Option"
        print "* When this option is enabled, your device will be activated on restore."
        print "* Enable this option if you have no valid SIM card to activate the phone."
        print "* Disable this option if you have a working SIM card and want cellular data."
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

    case $device_type in
        iPad[23],[23] | "$device_disable_bbupdate" ) ipsw_nskip=1;;
    esac
    if [[ $device_target_vers == "4.2"* || $device_target_vers == "4.3"* || $ipsw_gasgauge_patch == 1 ]] ||
       [[ $platform == "macos" && $platform_arch == "arm64" ]]; then
        ipsw_nskip=1
    fi

    case $device_type in
        iPhone2,1 | iPod2,1 ) ipsw_canmemory=1;;
        iPad[23],[23] ) ipsw_canmemory=1;;
        iPhone3,1 | iPad1,1 | iPad2* | iPod[34],1 )
            case $device_target_vers in
                [34]* ) ipsw_canmemory=1;;
            esac
        ;;
    esac

    if [[ $device_proc == 1 && $device_type != "iPhone1,2" ]]; then
        ipsw_canmemory=
    elif [[ $device_target_powder == 1 || $device_target_tethered == 1 ||
          $ipsw_jailbreak == 1 || $ipsw_gasgauge_patch == 1 || $ipsw_nskip == 1 ||
          $device_type == "$device_disable_bbupdate" ]]; then
        ipsw_canmemory=1
    fi

    if [[ $ipsw_canmemory == 1 && -z $ipsw_memory ]]; then
        input "Memory Option for creating custom IPSW"
        print "* When this option is enabled, system RAM will be used for the IPSW creation process."
        print "* I recommend to enable this option to speed up creating the custom IPSW."
        print "* However, if your PC/Mac has less than 8 GB of RAM, disable this option."
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

    if [[ $device_target_powder == 1 ]]; then
        ipsw_canverbose=1
    elif [[ $device_type == "iPhone2,1" && $device_target_other != 1 ]]; then
        case $device_target_vers in
            6.1.6 | 4.1 ) log "3GS verbose boot is not supported on 6.1.6 and 4.1";;
            [65]* ) log "3GS verbose boot is currently supported on iOS 4 and lower only";;
            3.0* ) :;;
            * ) ipsw_canverbose=1;;
        esac
    fi

    if [[ $ipsw_canverbose == 1 && -z $ipsw_verbose ]]; then
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
    log "Running tsschecker with command: $tsschecker $ExtraArgs"
    $tsschecker $ExtraArgs
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
    ipsw_get_url $build_id
    if [[ -z $ipsw_dl ]]; then
        ipsw_dl="../${ipsw_url##*/}"
        ipsw_dl="${ipsw_dl%?????}"
    fi
    if [[ ! -e "$ipsw_dl.ipsw" ]]; then
        if [[ -n $version ]]; then
            print "* The script will now proceed to download iOS $version IPSW."
        fi
        print "* If you want to download it yourself, here is the link: $ipsw_url"
        log "Downloading IPSW... (Press Ctrl+C to cancel)"
        curl -L "$ipsw_url" -o temp.ipsw
        mv temp.ipsw "$ipsw_dl.ipsw"
    fi
    ipsw_verify "$ipsw_dl" "$build_id"
}

ipsw_verify() {
    local ipsw_dl="$1"
    local build_id="$2"
    local cutver
    local device
    local type
    local IPSWSHA1
    local IPSWSHA1E=$(cat "$device_fw_dir/$build_id/sha1sum" 2>/dev/null)
    log "Getting SHA1 hash for $ipsw_dl.ipsw..."
    local IPSWSHA1L=$($sha1sum "${ipsw_dl//\\//}.ipsw" | awk '{print $1}')
    case $build_id in
        *[bcdefgkmpquv] )
            log "Beta IPSW detected, skip verification"
            if [[ $build_id == "$device_base_build" ]]; then
                device_base_sha1="$IPSWSHA1L"
            else
                ipsw_isbeta=1
                device_target_sha1="$IPSWSHA1L"
            fi
            return
        ;;
    esac
    case $build_id in
        7*  ) cutver=3;;
        8*  ) cutver=4;;
        9*  ) cutver=5;;
        10* ) cutver=6;;
        11* ) cutver=7;;
        12* ) cutver=8;;
        13* ) cutver=9;;
    esac
    if [[ -n $cutver ]]; then
        type="$device_type"
    else
        ipsw_latest_set
        type="$device_type2"
    fi
    case $build_id in
        14* ) cutver=10;;
        15* ) cutver=11;;
        16* ) cutver=12;;
        17* ) cutver=13;;
        18* ) cutver=14;;
        19* ) cutver=15;;
        20* ) cutver=16;;
    esac
    case $device_type in
        iPad4,[123] | iPad5,[34] ) device="iPad_Air";;
        iPad2,[567] | iPad[45],* ) device="iPad_mini";;
        iPad6,[3478] ) device="iPad_Pro";;
        iPad* ) device="iPad";;
        iPho* ) device="iPhone";;
        iPod* ) device="iPod_touch";;
    esac

    if [[ $(echo "$IPSWSHA1E" | grep -c '<') != 0 ]]; then
        rm "$device_fw_dir/$build_id/sha1sum"
    fi

    log "Getting SHA1 hash from The Apple Wiki..."
    IPSWSHA1="$(curl "https://theapplewiki.com/index.php?title=Firmware/${device}/${cutver}.x" | grep -A10 "${type}.*${build_id}" | sed -ne '/<code>/,/<\/code>/p' | sed '1!d' | sed -e "s/<code>//" | sed "s/<\/code>//" | cut -c 5-)"
    mkdir -p $device_fw_dir/$build_id 2>/dev/null

    if [[ -n $IPSWSHA1 && -n $IPSWSHA1E && $IPSWSHA1 == "$IPSWSHA1E" ]]; then
        log "Using saved SHA1 hash for this IPSW: $IPSWSHA1"
    elif [[ -z $IPSWSHA1 && -n $IPSWSHA1E ]]; then
        warn "No SHA1 hash from The Apple Wiki, using local hash"
        IPSWSHA1="$IPSWSHA1E"
    elif [[ -z $IPSWSHA1 && -z $IPSWSHA1E ]]; then
        warn "No SHA1 hash from either The Apple Wiki or local hash, cannot verify IPSW."
        pause
        return
    elif [[ -n $IPSWSHA1E ]]; then
        warn "Local SHA1 hash mismatch. Overwriting local hash."
        echo "$IPSWSHA1" > $device_fw_dir/$build_id/sha1sum
    elif [[ -z $IPSWSHA1E ]]; then
        warn "Local SHA1 hash does not exist. Creating local hash."
        echo "$IPSWSHA1" > $device_fw_dir/$build_id/sha1sum
    fi

    if [[ $IPSWSHA1L != "$IPSWSHA1" ]]; then
        rm "$device_fw_dir/$build_id/sha1sum"
        if [[ -z $3 ]]; then
            log "SHA1sum mismatch. Expected $IPSWSHA1, got $IPSWSHA1L"
            warn "Verifying IPSW failed. Your IPSW may be corrupted or incomplete. Make sure to download and select the correct IPSW."
            pause
        fi
        if [[ $build_id == "$device_base_build" ]]; then
            ipsw_base_validate=1
        else
            ipsw_validate=1
        fi
        return 1
    fi
    log "IPSW SHA1sum matches"
    if [[ $build_id == "$device_base_build" ]]; then
        device_base_sha1="$IPSWSHA1"
        ipsw_base_validate=0
    else
        ipsw_isbeta=
        device_target_sha1="$IPSWSHA1"
        ipsw_validate=0
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
    case $device_type in
        iPad4,[45] ) cp $iBSSb.im4p $iBECb.im4p ../saved/$device_type;;
        * ) cp $iBSS.im4p $iBEC.im4p ../saved/$device_type;;
    esac
    log "Pwned iBSS and iBEC saved at: saved/$device_type"
}

ipsw_prepare_rebootsh() {
    log "Generating reboot.sh"
    echo '#!/bin/bash' | tee reboot.sh
    echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" | tee -a reboot.sh
    echo "nvram -d boot-partition; nvram -d boot-ramdisk" | tee -a reboot.sh
    echo "/usr/bin/haxx_overwrite --${device_type}_${device_target_build}" | tee -a reboot.sh
}

ipsw_prepare_logos_convert() {
    local iv
    local key
    local name
    if [[ -n $ipsw_customlogo ]]; then
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "AppleLogo") | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "AppleLogo") | .key')
        name=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image == "AppleLogo") | .filename')
        logoname="$name"
        log "Converting custom logo"
        unzip -o -j "$ipsw_path.ipsw" $all_flash/$name
        "$dir/xpwntool" $name logo-orig.img3 -iv $iv -k $key -decrypt
        "$dir/imagetool" inject "$ipsw_customlogo" logo.img3 logo-orig.img3
        if [[ ! -s logo.img3 ]]; then
            error "Converting custom logo failed. Check your image"
        fi
        if [[ $device_target_powder == 1 ]]; then
            if [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
                log "log4"
                echo "0000010: 3467" | xxd -r - logo.img3
                echo "0000020: 3467" | xxd -r - logo.img3
            else
                log "logb"
                echo "0000010: 6267" | xxd -r - logo.img3
                echo "0000020: 6267" | xxd -r - logo.img3
            fi
        fi
        mkdir -p $all_flash 2>/dev/null
        mv logo.img3 $all_flash/$name
    fi
    if [[ -n $ipsw_customrecovery ]]; then
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "RecoveryMode") | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "RecoveryMode") | .key')
        name=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image == "RecoveryMode") | .filename')
        recmname="$name"
        log "Converting custom recovery"
        unzip -o -j "$ipsw_path.ipsw" $all_flash/$name
        "$dir/xpwntool" $name recovery-orig.img3 -iv $iv -k $key -decrypt
        "$dir/imagetool" inject "$ipsw_customrecovery" recovery.img3 recovery-orig.img3
        if [[ ! -s recovery.img3 ]]; then
            error "Converting custom recovery failed. Check your image"
        fi
        mkdir -p $all_flash 2>/dev/null
        mv recovery.img3 $all_flash/$name
    fi
}

ipsw_prepare_logos_add() {
    if [[ -n $ipsw_customlogo ]]; then
        log "Adding custom logo to IPSW"
        zip -r0 temp.ipsw $all_flash/$logoname
    fi
    if [[ -n $ipsw_customrecovery ]]; then
        log "Adding custom recovery to IPSW"
        zip -r0 temp.ipsw $all_flash/$recmname
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
    local daibutsu=$1

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
                4.1 | 4.0* | 3.1.3 ) JBFiles+=("greenpois0n/${device_type}_${device_target_build}.tar");;
                5* | 4.[32]* ) JBFiles+=("g1lbertJB/${device_type}_${device_target_build}.tar");;
            esac
            case $device_target_vers in
                [43]* ) JBFiles[0]="fstab_old.tar"
            esac
            for i in {0..1}; do
                JBFiles[i]=$jelbrek/${JBFiles[$i]}
            done
            case $device_target_vers in
                4.3* )
                    JBFiles[2]=$jelbrek/${JBFiles[2]}
                    if [[ $device_type == "iPad2"* ]]; then
                        JBFiles[2]=
                    fi
                ;;
                4.2.[8761] )
                    if [[ $device_type == "iPhone1,2" ]]; then
                        JBFiles[2]=
                    else
                        ExtraArgs+=" -punchd"
                        JBFiles[2]=$jelbrek/greenpois0n/${device_type}_${device_target_build}.tar
                    fi
                ;;
                3.0* | 3.1 | 3.1.[12] | 4.2* ) :;;
                * ) JBFiles[2]=$jelbrek/${JBFiles[2]};;
            esac
            case $device_target_vers in
                [543]* ) JBFiles+=("$jelbrek/cydiasubstrate.tar");;
            esac
            if [[ $device_target_vers == "3"* ]]; then
                JBFiles+=("$jelbrek/cydiahttpatch.tar")
            fi
            if [[ $device_target_vers == "5"* ]]; then
                JBFiles+=("$jelbrek/g1lbertJB.tar")
            fi
            if [[ $device_target_tethered == 1 && $device_type != "iPad2"* ]]; then
                case $device_target_vers in
                    5* | 4.3* ) JBFiles+=("$jelbrek/g1lbertJB/install.tar");;
                esac
            fi
        fi
        ExtraArgs+=" -S 30" # system partition add
        if [[ $ipsw_openssh == 1 ]]; then
            JBFiles+=("$jelbrek/sshdeb.tar")
        fi
    fi

    ipsw_prepare_bundle $daibutsu
    ipsw_prepare_logos_convert

    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    ExtraArgs+=" -ramdiskgrow 10"
    if [[ $device_use_bb != 0 && $device_type != "$device_disable_bbupdate" ]]; then
        ExtraArgs+=" -bbupdate"
    elif [[ $device_type == "$device_disable_bbupdate" && $device_deadbb != 1 ]]; then
        device_dump baseband
        ExtraArgs+=" ../saved/$device_type/baseband-$device_ecid.tar"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation-$device_ecid.tar"
    fi
    if [[ $1 == "iboot" ]]; then
        ExtraArgs+=" iBoot.tar"
    fi
    if [[ $ipsw_isbeta == 1 ]]; then
        ipsw_prepare_systemversion
        ExtraArgs+=" systemversion.tar"
    fi

    log "Preparing custom IPSW: $dir/ipsw $ipsw_path.ipsw temp.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/ipsw" "$ipsw_path.ipsw" temp.ipsw $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    ipsw_prepare_logos_add
    ipsw_prepare_fourthree
    ipsw_bbreplace

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_fourthree() {
    local comps=("AppleLogo" "DeviceTree" "iBoot" "RecoveryMode")
    local saved_path="../saved/$device_type/8L1"
    local bpatch="../resources/patch/fourthree/$device_type/6.1.3"
    local name
    local iv
    local key
    if [[ $ipsw_fourthree != 1 ]]; then
        return
    fi
    ipsw_get_url 8L1
    url="$ipsw_url"
    device_fw_key_check
    device_fw_key_check temp 8L1
    mkdir -p $all_flash Downgrade $saved_path 2>/dev/null
    log "Extracting files"
    unzip -o -j "$ipsw_path.ipsw" $all_flash/manifest -d $all_flash
    unzip -o -j temp.ipsw Downgrade/RestoreDeviceTree
    log "RestoreDeviceTree"
    iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "DeviceTree") | .iv')
    key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "DeviceTree") | .key')
    "$dir/xpwntool" RestoreDeviceTree RestoreDeviceTree.dec -iv $iv -k $key -decrypt
    $bspatch RestoreDeviceTree.dec Downgrade/RestoreDeviceTree $bpatch/RestoreDeviceTree.patch
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        path="$all_flash/"
        log "$getcomp"
        if [[ $vers == "$device_base_vers" ]]; then
            unzip -o -j "$ipsw_base_path.ipsw" ${path}$name
        elif [[ -e $saved_path/$name ]]; then
            cp $saved_path/$name .
        else
            "$dir/pzb" -g "${path}$name" -o "$name" "$url"
            cp $name $saved_path/
        fi
        "$dir/xpwntool" $name $getcomp.dec -iv $iv -k $key -decrypt
        case $getcomp in
            "AppleLogo" )
                getcomp="applelogo"
                mv AppleLogo.dec applelogo.dec
                echo "0000010: 6267" | xxd -r - applelogo.dec
                echo "0000020: 6267" | xxd -r - applelogo.dec
            ;;
            "DeviceTree" )
                echo "0000010: 6272" | xxd -r - DeviceTree.dec
                echo "0000020: 6272" | xxd -r - DeviceTree.dec
            ;;
            "RecoveryMode" )
                getcomp="recoverymode"
                mv RecoveryMode.dec recoverymode.dec
                echo "0000010: 6263" | xxd -r - recoverymode.dec
                echo "0000020: 6263" | xxd -r - recoverymode.dec
            ;;
            "iBoot" )
                mv iBoot.dec iBoot.dec0
                $bspatch iBoot.dec0 iBoot.dec $bpatch/iBoot.${device_model}ap.RELEASE.patch
                #"$dir/xpwntool" iBoot.dec0 iBoot.dec2
                #"$dir/iBoot32Patcher" iBoot.dec2 iBoot.patched --rsa -b "rd=disk0s3 -v amfi=0xff cs_enforcement_disable=1 pio-error=0"
                #"$dir/xpwntool" iBoot.patched iBoot.dec -t iBoot.dec0
                #echo "0000010: 626F" | xxd -r - iBoot.dec
                #echo "0000020: 626F" | xxd -r - iBoot.dec
            ;;
        esac
        mv $getcomp.dec $path/${getcomp}B.img3
        echo "${getcomp}B.img3" >> $path/manifest
    done
    log "Add files to IPSW"
    zip -r0 temp.ipsw $all_flash/* Downgrade/*
}

ipsw_prepare_fourthree_part2() {
    device_fw_key_check base
    local saved_path="../saved/$device_type/$device_base_build"
    local bpatch="../resources/patch/fourthree/$device_type/$device_base_vers"
    local iv
    local key
    mkdir -p $saved_path 2>/dev/null
    if [[ ! -s $saved_path/Kernelcache ]]; then
        log "Kernelcache"
        iv=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "Kernelcache") | .iv')
        key=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "Kernelcache") | .key')
        unzip -o -j "$ipsw_base_path.ipsw" kernelcache.release.$device_model
        "$dir/xpwntool" kernelcache.release.$device_model kernelcache.dec -iv $iv -k $key
        $bspatch kernelcache.dec kernelcache.patched $bpatch/kernelcache.release.patch
        #$bspatch kernelcache.dec kernelcache.patched ../resources/patch/kernelcache.release.$device_model.$device_base_build.patch
        "$dir/xpwntool" kernelcache.patched kernelcachb -t kernelcache.release.$device_model -iv $iv -k $key
        "$dir/xpwntool" kernelcachb $saved_path/Kernelcache -iv $iv -k $key -decrypt
    fi
    if [[ ! -s $saved_path/LLB ]]; then
        log "LLB"
        iv=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "LLB") | .iv')
        key=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "LLB") | .key')
        unzip -o -j "$ipsw_base_path.ipsw" $all_flash/LLB.${device_model}ap.RELEASE.img3
        "$dir/xpwntool" LLB.${device_model}ap.RELEASE.img3 llb.dec -iv $iv -k $key
        $bspatch llb.dec $saved_path/LLB $bpatch/LLB.${device_model}ap.RELEASE.patch
    fi
    if [[ ! -s $saved_path/RootFS.dmg ]]; then
        log "RootFS"
        name=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "RootFS") | .filename')
        key=$(echo $device_fw_key_base | $jq -j '.keys[] | select(.image == "RootFS") | .key')
        unzip -o -j "$ipsw_base_path.ipsw" $name
        "$dir/dmg" extract $name rootfs.dec -k $key
        rm $name
        "$dir/dmg" build rootfs.dec $saved_path/RootFS.dmg
    fi
    echo "device_base_vers=$device_base_vers" > ../saved/$device_type/fourthree_$device_ecid
    echo "device_base_build=$device_base_build" >> ../saved/$device_type/fourthree_$device_ecid
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
    local name=$(echo $fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
    local iv=$(echo $fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
    local key=$(echo $fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
    if [[ $device_target_build == "14"* && $getcomp == "iBSS" ]]; then
        name="$(curl "https://www.theiphonewiki.com/wiki/${ipsw_codename}_${device_target_build}_(${device_type})" | grep "iBSS" -A1 | sed "s/^.*keypage-ibss\">//" | sed "s/^.*h2>//" | sed "s/<\/span>//" | sed "s/<\/p>//" | tr -d '\n')"
    elif [[ $device_target_build == "14"* && $getcomp == "iBEC" ]]; then
        name="$(curl "https://www.theiphonewiki.com/wiki/${ipsw_codename}_${device_target_build}_(${device_type})" | grep "iBEC" -A1 | sed "s/^.*keypage-ibec\">//" | sed "s/^.*h2>//" | sed "s/<\/span>//" | sed "s/<\/p>//" | tr -d '\n')"
    fi
    if [[ -z $name && $device_proc != 1 ]]; then
        error "Issue with firmware keys: Failed getting $getcomp. Check The Apple Wiki or your wikiproxy"
    fi

    case $comp in
        "iBSS" | "iBEC" )
            if [[ -z $name ]]; then
                name="$getcomp.${device_model}ap.RELEASE.dfu"
            fi
            echo "<key>$comp</key><dict><key>File</key><string>Firmware/dfu/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
            if [[ $ipsw_prepare_usepowder == 1 ]]; then
                echo "<key>Patch</key><true/>" >> $NewPlist
            elif [[ -s $FirmwareBundle/$comp.${device_model}ap.RELEASE.patch ]]; then
                echo "<key>Patch</key><string>$comp.${device_model}ap.RELEASE.patch</string>" >> $NewPlist
            elif [[ -s $FirmwareBundle/$comp.${device_model}.RELEASE.patch ]]; then
                echo "<key>Patch</key><string>$comp.${device_model}.RELEASE.patch</string>" >> $NewPlist
            fi
        ;;

        "iBoot" )
            echo "<key>$comp</key><dict><key>File</key><string>$all_flash/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
            echo "<key>Patch</key><string>$comp.${device_model}ap.RELEASE.patch</string>" >> $NewPlist
        ;;

        "RestoreRamdisk" )
            echo "<key>Restore Ramdisk</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
        ;;

        "RestoreDeviceTree" | "RestoreLogo" )
            echo "<key>$comp</key><dict><key>File</key><string>$all_flash/$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string>" >> $NewPlist
        ;;

        "RestoreKernelCache" )
            echo "<key>$comp</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string><key>DecryptPath</key><string>Downgrade/$comp</string>" >> $NewPlist
        ;;

        "KernelCache" )
            echo "<key>$comp</key><dict><key>File</key><string>$name</string><key>IV</key><string>$iv</string><key>Key</key><string>$key</string>" >> $NewPlist
            if [[ $ipsw_prepare_usepowder == 1 ]]; then
                echo "<key>Patch</key><true/>" >> $NewPlist
            elif [[ -e $FirmwareBundle/kernelcache.release.patch ]]; then
                echo "<key>Patch</key><string>kernelcache.release.patch</string>" >> $NewPlist
            fi
        ;;

        "WTF2" )
            echo "<key>WTF 2</key><dict><key>File</key><string>Firmware/dfu/WTF.s5l8900xall.RELEASE.dfu</string><key>Patch</key><string>WTF.s5l8900xall.RELEASE.patch</string>" >> $NewPlist
        ;;
    esac
    if [[ $2 != "old" ]]; then
        echo "<key>Decrypt</key><true/>" >> $NewPlist
    fi
    echo "</dict>" >> $NewPlist
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
    local name=$(echo $fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
    if [[ -z $name && $getcomp != "manifest" ]]; then
        error "Issue with firmware keys: Failed getting $getcomp. Check The Apple Wiki or your wikiproxy"
    fi
    local str="<key>$comp</key><dict><key>File</key><string>$all_flash/"
    local str2
    local logostuff
    if [[ $2 == "target" ]]; then
        case $comp in
            *"AppleLogo" )
                if [[ $device_latest_vers == "5"* ]]; then
                    logostuff=1
                else
                    case $device_target_vers in
                        [789]* ) logostuff=1;;
                    esac
                fi
            ;;
        esac
        case $comp in
            "AppleLogo" ) str2="${name/applelogo/applelogo7}";;
            "APTicket" ) str2="${name/applelogo/applelogoT}";;
            "RecoveryMode" ) str2="${name/recoverymode/recoverymode7}";;
            "NewiBoot" ) str2="${name/iBoot/iBoot2}";;
        esac
        case $comp in
            "AppleLogo" )
                str+="$str2"
                if [[ $logostuff == 1 ]]; then
                    echo "$str2" >> $FirmwareBundle/manifest
                fi
            ;;
            "APTicket" | "RecoveryMode" )
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
        local iv=$(echo $fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        local key=$(echo $fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        str+="<key>IV</key><string>$iv</string><key>Key</key><string>$key</string>"
    elif [[ $comp == "manifest" ]]; then
        str+="<key>manifest</key><string>manifest</string>"
    fi

    echo "$str</dict>" >> $NewPlist
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

ipsw_prepare_systemversion() {
    local sysplist="SystemVersion.plist"
    log "Beta iOS detected, preparing modified $sysplist"
    echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>' > $sysplist
    echo "<key>ProductBuildVersion</key><string>$device_target_build</string>" >> $sysplist
    local copyright="<key>ProductCopyright</key><string>1983-201"
    case $device_target_vers in
        3* ) copyright+="0";;
        4* ) copyright+="1";;
        5* ) copyright+="2";;
        6* ) copyright+="3";;
        7* ) copyright+="4";;
        8* ) copyright+="5";;
        9* ) copyright+="6";;
    esac
    copyright+=" Apple Inc.</string>"
    echo "$copyright" >> $sysplist # idk if the copyright key is actually needed but whatever
    echo "<key>ProductName</key><string>iPhone OS</string>" >> $sysplist
    echo "<key>ProductVersion</key><string>$device_target_vers</string>" >> $sysplist
    echo "</dict></plist>" >> $sysplist
    cat $sysplist
    mkdir -p System/Library/CoreServices
    mv SystemVersion.plist System/Library/CoreServices
    tar -cvf systemversion.tar System
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
                [689]* ) ipsw_prepare_config true true;;
                * ) ipsw_prepare_config false true;;
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
    if [[ $ipsw_prepare_usepowder == 1 ]]; then
        FirmwareBundle2=
    elif [[ -d $FirmwareBundle2 ]]; then
        FirmwareBundle+="Down_"
    fi
    FirmwareBundle+="${device_type}_${vers}_${build}.bundle"
    local NewPlist=$FirmwareBundle/Info.plist
    mkdir -p $FirmwareBundle

    log "Generating firmware bundle for $device_type-$vers ($build) $1..."
    unzip -o -j "$ipsw_p.ipsw" $all_flash/manifest
    mv manifest $FirmwareBundle/
    local ramdisk_name=$(echo "$key" | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .filename')
    local RamdiskIV=$(echo "$key" | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .iv')
    local RamdiskKey=$(echo "$key" | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .key')
    if [[ $device_target_build == "14"* ]]; then
        case $device_target_build in
            14A* ) ipsw_codename="Whitetail";;
            14B* ) ipsw_codename="Butler";;
            14C* ) ipsw_codename="Corry";;
            14D* ) ipsw_codename="Dubois";;
            14E* ) ipsw_codename="Erie";;
            14F* ) ipsw_codename="Franklin";;
            14G* ) ipsw_codename="Greensburg";;
        esac
        if [[ $ipsw_isbeta == 1 ]]; then
            ipsw_codename+="Seed"
        fi
        ramdisk_name="$(curl "https://www.theiphonewiki.com/wiki/${ipsw_codename}_${device_target_build}_(${device_type})" | grep "Restore Ramdisk" -A1 | sed "s/^.*keypage-restoreramdisk\">//" | sed "s/^.*h2>//" | sed "s/<\/span>//" | tr -d '\n')"
    fi
    if [[ -z $ramdisk_name ]]; then
        error "Issue with firmware keys: Failed getting RestoreRamdisk. Check The Apple Wiki or your wikiproxy"
    fi
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
            iPhone1* | iPod1,1 ) RootSize=420;;
            iPod2,1 ) RootSize=450;;
            *       ) RootSize=750;;
        esac
    elif [[ $platform == "macos" ]]; then
        plutil -extract 'SystemPartitionSize' xml1 options.$device_model.plist -o size
        RootSize=$(cat size | sed -ne '/<integer>/,/<\/integer>/p' | sed -e "s/<integer>//" | sed "s/<\/integer>//" | sed '2d')
    else
        RootSize=$(cat options.$device_model.plist | grep -i SystemPartitionSize -A 1 | grep -oPm1 "(?<=<integer>)[^<]+")
    fi
    RootSize=$((RootSize+30))
    local rootfs_name="$(echo "$key" | $jq -j '.keys[] | select(.image == "RootFS") | .filename')"
    local rootfs_key="$(echo "$key" | $jq -j '.keys[] | select(.image == "RootFS") | .key')"
    if [[ $device_target_build == "14"* ]]; then
        rootfs_name="$(curl "https://www.theiphonewiki.com/wiki/${ipsw_codename}_${device_target_build}_(${device_type})" | grep "Root" -A1 | sed "s/^.*keypage-rootfs\">//" | sed "s/^.*h2>//" | sed "s/<\/span>//" | tr -d '\n')"
    fi
    if [[ -z $rootfs_name ]]; then
        error "Issue with firmware keys: Failed getting RootFS. Check The Apple Wiki or your wikiproxy"
    fi
    echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>' > $NewPlist
    echo "<key>Filename</key><string>$ipsw_p.ipsw</string>" >> $NewPlist
    echo "<key>RootFilesystem</key><string>$rootfs_name</string>" >> $NewPlist
    echo "<key>RootFilesystemKey</key><string>$rootfs_key</string>" >> $NewPlist
    echo "<key>RootFilesystemSize</key><integer>$RootSize</integer>" >> $NewPlist
    printf "<key>RamdiskOptionsPath</key><string>/usr/local/share/restore/options" >> $NewPlist
    if [[ $device_target_vers != "3"* && $device_target_vers != "4"* ]] ||
       [[ $device_type == "iPad1,1" && $device_target_vers == "4"* ]]; then
        printf ".%s" "$device_model" >> $NewPlist
    fi
    echo ".plist</string>" >> $NewPlist
    if [[ $1 == "base" ]]; then
        echo "<key>SHA1</key><string>$device_base_sha1</string>" >> $NewPlist
    else
        echo "<key>SHA1</key><string>$device_target_sha1</string>" >> $NewPlist
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
        echo "<key>RamdiskExploit</key><dict>" >> $NewPlist
        echo "<key>exploit</key><string>src/target/$hw/$base_build/exploit</string>" >> $NewPlist
        echo "<key>inject</key><string>src/target/$hw/$base_build/partition</string></dict>" >> $NewPlist
    elif [[ $1 == "target" ]]; then
        echo "<key>FilesystemPackage</key><dict><key>bootstrap</key><string>freeze.tar</string>" >> $NewPlist
        case $vers in
            8* | 9* ) echo "<key>package</key><string>src/ios9.tar</string>" >> $NewPlist;;
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
        echo "</string></dict>" >> $NewPlist
    elif [[ $ipsw_prepare_usepowder == 1 ]]; then
        echo "<key>FilesystemPackage</key><dict/><key>RamdiskPackage</key><dict/>" >> $NewPlist
    elif [[ $ipsw_isbeta == 1 && $ipsw_prepare_usepowder != 1 ]]; then
        warn "iOS 4.1 beta or older detected. Attempting workarounds"
        cp $FirmwareBundle2/* $FirmwareBundle
        echo "<key>RamdiskPatches</key><dict/>" >> $NewPlist
        echo "<key>FilesystemPatches</key><dict/>" >> $NewPlist
        ipsw_isbeta_needspatch=1
    elif [[ -d $FirmwareBundle2 ]]; then
        cp $FirmwareBundle2/* $FirmwareBundle
        echo "<key>RamdiskPatches</key><dict>" >> $NewPlist
        echo "<key>asr</key><dict>" >> $NewPlist
        echo "<key>File</key><string>usr/sbin/asr</string><key>Patch</key><string>asr.patch</string></dict>" >> $NewPlist
        if [[ -s $FirmwareBundle/restoredexternal.patch ]]; then
            echo "<key>restoredexternal</key><dict>" >> $NewPlist
            echo "<key>File</key><string>usr/local/bin/restored_external</string><key>Patch</key><string>restoredexternal.patch</string></dict>" >> $NewPlist
        fi
        echo "</dict>" >> $NewPlist
        if [[ $ipsw_hacktivate == 1 ]]; then
            echo "<key>FilesystemPatches</key><dict>" >> $NewPlist
            echo "<key>Hacktivation</key><array><dict>" >> $NewPlist
            echo "<key>Action</key><string>Patch</string><key>File</key><string>usr/libexec/lockdownd</string>" >> $NewPlist
            echo "<key>Patch</key><string>lockdownd.patch</string></dict></array></dict>" >> $NewPlist
        else
            echo "<key>FilesystemPatches</key><dict/>" >> $NewPlist # ipsw segfaults if this is missing lol
        fi
    fi

    if [[ $1 == "base" ]]; then
        echo "<key>Firmware</key><dict/>" >> $NewPlist
    elif [[ $1 == "target" && $vers == "4"* ]]; then
        echo "<key>Firmware</key><dict>" >> $NewPlist
        ipsw_prepare_keys iBSS $1
        ipsw_prepare_keys RestoreRamdisk $1
        echo "</dict>" >> $NewPlist
    elif [[ $ipsw_isbeta_needspatch == 1 ]]; then
        echo "<key>FirmwarePatches</key><dict>" >> $NewPlist
        ipsw_prepare_keys RestoreDeviceTree $1
        ipsw_prepare_keys RestoreLogo $1
        ipsw_prepare_keys RestoreKernelCache $1
        ipsw_prepare_keys RestoreRamdisk $1
        echo "</dict>" >> $NewPlist
    elif [[ $device_target_build == "14"* ]]; then
        echo "<key>Firmware</key><dict>" >> $NewPlist
        ipsw_prepare_keys iBSS
        ipsw_prepare_keys iBEC
        ipsw_prepare_keys RestoreRamdisk
    else
        if [[ $ipsw_prepare_usepowder == 1 ]]; then
            echo "<key>Firmware</key><dict>" >> $NewPlist
        else
            echo "<key>FirmwarePatches</key><dict>" >> $NewPlist
        fi
        ipsw_prepare_keys iBSS $1
        # ios 4 and lower do not need ibec patches. the exception is the ipad lineup
        if [[ $vers != "3"* && $vers != "4"* ]] || [[ $device_type == "iPad1,1" || $device_type == "iPad2"* ]]; then
            ipsw_prepare_keys iBEC $1
        fi
        if [[ $device_proc == 1 && $device_target_vers != "4.2.1" ]]; then
            :
        else
            ipsw_prepare_keys RestoreDeviceTree $1
            ipsw_prepare_keys RestoreLogo $1
        fi
        if [[ $1 == "target" ]]; then
            case $vers in
                [457]* ) ipsw_prepare_keys RestoreKernelCache $1;;
                * ) ipsw_prepare_keys KernelCache $1;;
            esac
        elif [[ $device_proc == 1 && $device_target_vers == "4.2.1" ]]; then
            ipsw_prepare_keys RestoreKernelCache $1
        elif [[ $device_proc != 1 && $device_target_vers != "3.0"* ]]; then
            ipsw_prepare_keys RestoreKernelCache $1
        fi
        ipsw_prepare_keys RestoreRamdisk $1
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
        echo "</dict>" >> $NewPlist
    fi

    if [[ $1 == "base" ]]; then
        echo "<key>FirmwarePath</key><dict>" >> $NewPlist
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
        echo "</dict>" >> $NewPlist
    elif [[ $1 == "target" ]]; then
        echo "<key>FirmwareReplace</key><dict>" >> $NewPlist
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
        echo "</dict>" >> $NewPlist
    fi

    if [[ $daibutsu == 1 ]]; then
        if [[ $ipsw_prepare_usepowder == 1 ]]; then
            echo "<key>RamdiskPackage2</key>" >> $NewPlist
        else
            echo "<key>PackagePath</key><string>./freeze.tar</string>" >> $NewPlist
            echo "<key>RamdiskPackage</key>" >> $NewPlist
        fi
        echo "<string>./bin.tar</string><key>RamdiskReboot</key><string>./reboot.sh</string><key>UntetherPath</key><string>./untether.tar</string>" >> $NewPlist
        local hwmodel="$(tr '[:lower:]' '[:upper:]' <<< ${device_model:0:1})${device_model:1}"
        echo "<key>hwmodel</key><string>$hwmodel</string>" >> $NewPlist
    fi

    echo "</dict></plist>" >> $NewPlist
    cat $NewPlist
}

ipsw_prepare_32bit() {
    local ExtraArgs
    local daibutsu
    local JBFiles=()
    if [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]] && [[ $ipsw_nskip != 1 ]]; then
        ipsw_prepare_jailbreak
        return
    elif [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    elif [[ $ipsw_jailbreak == 1 && $device_target_vers == "8"* ]]; then
        daibutsu="daibutsu"
        ExtraArgs+=" -daibutsu"
        cp $jelbrek/daibutsu/bin.tar $jelbrek/daibutsu/untether.tar .
        ipsw_prepare_rebootsh
    elif [[ $ipsw_nskip == 1 ]]; then
        :
    elif [[ $ipsw_jailbreak != 1 && $device_target_build != "9A406" && # 9a406 needs custom ipsw
            $device_proc != 4 && $device_actrec != 1 && $device_target_tethered != 1 ]]; then
        log "No need to create custom IPSW for non-jailbroken restores on $device_type-$device_target_build"
        return
    fi
    ipsw_prepare_usepowder=1

    ipsw_prepare_bundle $daibutsu

    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    ExtraArgs+=" -ramdiskgrow 10"
    if [[ $device_use_bb != 0 && $device_type != "$device_disable_bbupdate" ]]; then
        ExtraArgs+=" -bbupdate"
    elif [[ $device_type == "$device_disable_bbupdate" && $device_deadbb != 1 ]]; then
        device_dump baseband
        ExtraArgs+=" ../saved/$device_type/baseband-$device_ecid.tar"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation-$device_ecid.tar"
    fi

    if [[ $ipsw_jailbreak == 1 ]]; then
        case $device_target_vers in
            9.3.[1234] | 9.3 ) JBFiles+=("untetherhomedepot.tar");;
            9.2* | 9.1 ) JBFiles+=("untetherhomedepot921.tar");;
            7.1* )       JBFiles+=("panguaxe.tar");;
            7* )         JBFiles+=("evasi0n7-untether.tar");;
            6.1.[3456] ) JBFiles+=("p0sixspwn.tar");;
            6* )         JBFiles+=("evasi0n6-untether.tar");;
            5* | 4.[32]* ) JBFiles+=("g1lbertJB/${device_type}_${device_target_build}.tar");;
        esac
        if [[ -n ${JBFiles[0]} ]]; then
            JBFiles[0]=$jelbrek/${JBFiles[0]}
        fi
        case $device_target_vers in
            9* | 8* ) JBFiles+=("$jelbrek/fstab8.tar");;
            7* ) JBFiles+=("$jelbrek/fstab7.tar");;
            4* ) JBFiles+=("$jelbrek/fstab_old.tar");;
            * )  JBFiles+=("$jelbrek/fstab_rw.tar");;
        esac
        case $device_target_vers in
            4.3* )
                if [[ $device_type == "iPad2"* ]]; then
                    JBFiles[0]=
                fi
            ;;
            4.2.9 | 4.2.10 ) JBFiles[0]=;;
            4.2.1 )
                if [[ $device_type != "iPhone1,2" ]]; then
                    ExtraArgs+=" -punchd"
                    JBFiles[0]=$jelbrek/greenpois0n/${device_type}_${device_target_build}.tar
                fi
            ;;
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
                5* | 4.3* ) JBFiles+=("$jelbrek/g1lbertJB/install.tar");;
            esac
        fi
    fi
    if [[ $ipsw_isbeta == 1 ]]; then
        ipsw_prepare_systemversion
        ExtraArgs+=" systemversion.tar"
    fi
    if [[ $1 == "iboot" ]]; then
        ExtraArgs+=" iBoot.tar"
    fi

    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    ipsw_bbreplace
    if [[ $device_target_vers == "4"* ]]; then
        ipsw_prepare_ios4patches
        log "Add all to custom IPSW"
        zip -r0 temp.ipsw Firmware/dfu/*
    fi

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_bbdigest() {
    local loc="BuildIdentities:0:"
    if [[ $2 != "UniqueBuildID" ]]; then
        loc+="Manifest:BasebandFirmware:"
    fi
    loc+="$2"
    local out="$1"
    if [[ $platform == "macos" ]]; then
        echo $out | base64 --decode > t
        log "Replacing $2"
        $PlistBuddy -c "Import $loc t" BuildManifest.plist
        rm t
        return
    fi
    in=$($PlistBuddy -c "Print $loc" BuildManifest.plist | tr -d "<>" | xxd -r -p | base64)
    echo "${in}<" > replace
    #sed -i'' "s,AAAAAAAAAAAAAAAAAAAAAAA<,==," replace
    #sed -i'' "s,AAAAAAAAAAAAA<,=," replace
    #sed -i'' "s,AAAAAAAAA<,=," replace
    cat replace | sed "s,AAAAAAAAAAAAAAAAAAAAAAA<,==," > t
    cat t  | sed "s,AAAAAAAAAAAAA<,=," > tt
    cat tt | sed "s,AAAAAAAAA<,=," > replace
    in="$(cat replace)"
    rm replace t tt
    case $2 in
        *"PartialDigest" )
            in="${in%????????????}"
            in=$(cat BuildManifest.plist | grep "$in" -m1)
            log "Replacing $2"
            #sed -i'' "s,$in,replace," BuildManifest.plist
            #sed -i'' "/replace/{n;d}" BuildManifest.plist
            cat BuildManifest.plist | sed "s,$in,replace," > t
            awk 'f{$0="";f=0}/replace/{f=1}1' t > tt
            awk '/replace$/{printf("%s",$0);next}1' tt > tmp.plist
            rm t tt
            in="replace"
        ;;
        * ) log "Replacing $2"; mv BuildManifest.plist tmp.plist;;
    esac
    #sed -i'' "s,$in,$out," BuildManifest.plist
    cat tmp.plist | sed "s,$in,$out," > BuildManifest.plist
    rm tmp.plist
}

ipsw_bbreplace() {
    local rsb1
    local sbl1
    local path
    local rsb_latest
    local sbl_latest
    local bbfw="Print BuildIdentities:0:Manifest:BasebandFirmware"
    local ubid
    if [[ $device_use_bb == 0 || $device_target_vers == "$device_latest_vers" ]] || (( device_proc < 5 )); then
        return
    fi

    log "Extracting BuildManifest from IPSW"
    unzip -o -j temp.ipsw BuildManifest.plist
    mkdir Firmware 2>/dev/null
    restore_download_bbsep
    cp $restore_baseband Firmware/$device_use_bb

    case $device_type in
        iPhone4,1 ) ubid="d9Xbp0xyiFOxDvUcKMsoNjIvhwQ=";;
        iPhone5,1 ) ubid="IcrFKRzWDvccKDfkfMNPOPYHEV0=";;
        iPhone5,2 ) ubid="lnU0rtBUK6gCyXhEtHuwbEz/IKY=";;
        iPhone5,3 ) ubid="dwrol4czV3ijtNHh3w1lWIdsNdA=";;
        iPhone5,4 ) ubid="Z4ST0TczwAhpfluQFQNBg7Y3BVE=";;
        iPad2,6 ) ubid="L73HfN42pH7qAzlWmsEuIZZg2oE=";;
        iPad2,7 ) ubid="z/vJsvnUovZ+RGyXKSFB6DOjt1k=";;
        iPad3,5 ) ubid="849RPGQ9kNXGMztIQBhVoU/l5lM=";;
        iPad3,6 ) ubid="cO+N+Eo8ynFf+0rnsIWIQHTo6rg=";;
    esac
    ipsw_bbdigest $ubid UniqueBuildID

    case $device_type in
        iPhone4,1 )
            rsb1=$($PlistBuddy -c "$bbfw:eDBL-Version" BuildManifest.plist)
            sbl1=$($PlistBuddy -c "$bbfw:RestoreDBL-Version" BuildManifest.plist)
            path=$($PlistBuddy -c "$bbfw:Info:Path" BuildManifest.plist | tr -d '"')
            rsb_latest="-1577031936"
            sbl_latest="-1575983360"
            ipsw_bbdigest XAAAAADHAQCqerR8d+PvcfusucizfQ4ECBI0TA== RestoreDBL-PartialDigest
            ipsw_bbdigest Q1TLjk+/PjayCzSJJo68FTtdhyE= AMSS-HashTableDigest
            ipsw_bbdigest KkJI7ufv5tfNoqHcrU7gqoycmXA= OSBL-DownloadDigest
            ipsw_bbdigest eAAAAADIAQDxcjzF1q5t+nvLBbvewn/arYVkLw== eDBL-PartialDigest
            ipsw_bbdigest 3CHVk7EmtGjL14ApDND81cqFqhM= AMSS-DownloadDigest
        ;;
        iPhone5,[12] | iPad2,[67] | iPad3,[56] )
            rsb1=$($PlistBuddy -c "$bbfw:RestoreSBL1-Version" BuildManifest.plist)
            sbl1=$($PlistBuddy -c "$bbfw:SBL1-Version" BuildManifest.plist)
            path=$($PlistBuddy -c "$bbfw:Info:Path" BuildManifest.plist | tr -d '"')
            rsb_latest="-1559114512"
            sbl_latest="-1560163088"
            ipsw_bbdigest 2bmJ7Vd+WAmogV+hjq1a86UlBvA= APPS-DownloadDigest
            ipsw_bbdigest oNmIZf39zd94CPiiKOpKvhGJbyg= APPS-HashTableDigest
            ipsw_bbdigest dFi5J+pSSqOfz31fIvmah2GJO+E= DSP1-DownloadDigest
            ipsw_bbdigest HXUnmGmwIHbVLxkT1rHLm5V6iDM= DSP1-HashTableDigest
            ipsw_bbdigest oA5eQ8OurrWrFpkUOhD/3sGR3y8= DSP2-DownloadDigest
            ipsw_bbdigest L7v8ulq1z1Pr7STR47RsNbxmjf0= DSP2-HashTableDigest
            ipsw_bbdigest MZ1ERfoeFcbe79pFAl/hbWUSYKc= DSP3-DownloadDigest
            ipsw_bbdigest sKmLhQcjfaOliydm+iwxucr9DGw= DSP3-HashTableDigest
            ipsw_bbdigest oiW/8qZhN0r9OaLdUHCT+MMGknY= RPM-DownloadDigest
            ipsw_bbdigest fAAAAEAQAgAH58t5X9KETIPrycULi8dg7b2rSw== RestoreSBL1-PartialDigest
            ipsw_bbdigest ZAAAAIC9AQAfgUcPMN/lMt+U8s6bxipdy6td6w== SBL1-PartialDigest
            ipsw_bbdigest kHLoJsT9APu4Xwu/aRjNK10Hx84= SBL2-DownloadDigest
        ;;
        iPhone5,[34] )
            rsb1=$($PlistBuddy -c "$bbfw:RestoreSBL1-Version" BuildManifest.plist)
            sbl1=$($PlistBuddy -c "$bbfw:SBL1-Version" BuildManifest.plist)
            path=$($PlistBuddy -c "$bbfw:Info:Path" BuildManifest.plist | tr -d '"')
            rsb_latest="-1542379296"
            sbl_latest="-1543427872"
            ipsw_bbdigest TSVi7eYY4FiAzXynDVik6TY2S1c= APPS-DownloadDigest
            ipsw_bbdigest xd/JBOTxYJWmLkTWqLWl8GeINgU= APPS-HashTableDigest
            ipsw_bbdigest RigCEz69gUymh2UdyJdwZVx74Ic= DSP1-DownloadDigest
            ipsw_bbdigest a3XhREtzynTWtyQGqi/RXorXSVE= DSP1-HashTableDigest
            ipsw_bbdigest 3JTgHWvC+XZYWa5U5MPvle+imj4= DSP2-DownloadDigest
            ipsw_bbdigest Hvppb92/1o/cWQbl8ftoiW5jOLg= DSP2-HashTableDigest
            ipsw_bbdigest R60ZfsOqZX+Pd/UnEaEhWfNvVlY= DSP3-DownloadDigest
            ipsw_bbdigest DFQWkktFWNh90G2hOfwO14oEbrI= DSP3-HashTableDigest
            ipsw_bbdigest Rsn+u2mOpYEmdrw98yA8EDT5LiE= RPM-DownloadDigest
            ipsw_bbdigest cAAAAIC9AQBLeCHzsjHo8Q7+IzELZTV/ri/Vow== RestoreSBL1-PartialDigest
            ipsw_bbdigest eAAAAEBsAQB9b44LqXjR3izAYl5gB4j3Iqegkg== SBL1-PartialDigest
            ipsw_bbdigest iog3IVe+8VqgQzP2QspgFRUNwn8= SBL2-DownloadDigest
        ;;
    esac

    log "Replacing $rsb1 with $rsb_latest"
    #sed -i'' "s,$rsb1,$rsb_latest," BuildManifest.plist
    cat BuildManifest.plist | sed "s,$rsb1,$rsb_latest," > t
    log "Replacing $sbl1 with $sbl_latest"
    #sed -i'' "s,$sbl1,$sbl_latest," BuildManifest.plist
    cat t | sed "s,$sbl1,$sbl_latest," > tt
    log "Replacing $path with Firmware/$device_use_bb"
    #sed -i'' "s,$path,Firmware/$device_use_bb," BuildManifest.plist
    cat tt | sed "s,$path,Firmware/$device_use_bb," > BuildManifest.plist
    rm t tt

    zip -r0 temp.ipsw Firmware/$device_use_bb BuildManifest.plist
}

patch_iboot() {
    device_fw_key_check
    local iboot_name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "iBoot") | .filename')
    local iboot_iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "iBoot") | .iv')
    local iboot_key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "iBoot") | .key')
    if [[ -z $iboot_name ]]; then
        error "Issue with firmware keys: Failed getting iBoot. Check The Apple Wiki or your wikiproxy"
    fi
    local rsa="--rsa"
    log "Patch iBoot: $*"
    if [[ $1 == "--logo" ]]; then
        iboot_name="${iboot_name/iBoot/iBoot2}"
        rsa=
        unzip -o -j temp.ipsw $all_flash/$iboot_name
    else
        unzip -o -j "$ipsw_path.ipsw" $all_flash/$iboot_name
    fi
    mv $iboot_name iBoot.orig
    "$dir/xpwntool" iBoot.orig iBoot.dec -iv $iboot_iv -k $iboot_key
    "$dir/iBoot32Patcher" iBoot.dec iBoot.pwned $rsa "$@"
    "$dir/xpwntool" iBoot.pwned iBoot -t iBoot.orig
    if [[ $device_type == "iPad1,1" || $device_type == "iPhone5"* ]]; then
        echo "0000010: 6365" | xxd -r - iBoot
        echo "0000020: 6365" | xxd -r - iBoot
        return
    elif [[ $device_type != "iPhone2,1" ]]; then
        echo "0000010: 626F" | xxd -r - iBoot
        echo "0000020: 626F" | xxd -r - iBoot
    fi
    "$dir/xpwntool" iBoot.pwned $iboot_name -t iBoot -iv $iboot_iv -k $iboot_key
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
    local all_flash2="$ipsw_custom_part2/$all_flash"
    local ExtraArgs2="--boot-partition --boot-ramdisk --logo4"
    local iboot
    case $device_target_vers in
        4.2.9 | 4.2.10 ) :;;
        * ) ExtraArgs2+=" --433";;
    esac
    ExtraArgs2+=" -b"

    if [[ -e "../$ipsw_custom_part2.ipsw" && -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSWs. Skipping IPSW creation."
        return
    elif [[ -e "../$ipsw_custom_part2.ipsw" || -e "$ipsw_custom.ipsw" ]]; then
        rm "../$ipsw_custom_part2.ipsw" "$ipsw_custom.ipsw" 2>/dev/null
    fi

    log "Preparing NOR flash IPSW..."
    mkdir -p $ipsw_custom_part2/Firmware/dfu $ipsw_custom_part2/Downgrade $all_flash2

    local comps=("iBSS" "iBEC" "DeviceTree" "Kernelcache" "RestoreRamdisk")
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
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" ) path="$all_flash/";;
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
    $PlistBuddy -c "Set BuildIdentities:0:Manifest:RestoreDeviceTree:Info:Path Downgrade/RestoreDeviceTree" BuildManifest.plist
    $PlistBuddy -c "Set BuildIdentities:0:Manifest:RestoreKernelCache:Info:Path Downgrade/RestoreKernelCache" BuildManifest.plist
    $PlistBuddy -c "Set BuildIdentities:0:Manifest:RestoreLogo:Info:Path Downgrade/RestoreLogo" BuildManifest.plist
    cp BuildManifest.plist $ipsw_custom_part2/

    log "Restore Ramdisk"
    local ramdisk_name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .filename')
    mv RestoreRamdisk.dec ramdisk.dec
    "$dir/hfsplus" ramdisk.dec grow 18000000

    local rootfs_name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "RootFS") | .filename')
    touch $ipsw_custom_part2/$rootfs_name
    log "Dummy RootFS: $rootfs_name"

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
    unzip -o -j "$ipsw_base_path.ipsw" Firmware/all_flash/\* -d $all_flash2

    log "Add $device_target_vers DeviceTree to all_flash"
    rm $all_flash2/DeviceTree.${device_model}ap.img3
    unzip -o -j "$ipsw_path.ipsw" $all_flash/DeviceTree.${device_model}ap.img3 -d $all_flash2

    local ExtraArgs3="pio-error=0"
    if [[ $ipsw_verbose == 1 ]]; then
        ExtraArgs3+=" -v"
    fi
    patch_iboot $ExtraArgs2 "$ExtraArgs3"
    if [[ $device_type == "iPad1,1" && $device_target_vers == "3"* ]]; then
        cp iBoot ../saved/iPad1,1/iBoot3_$device_ecid
    elif [[ $device_type == "iPad1,1" ]]; then
        cp iBoot iBEC
        tar -cvf iBoot.tar iBEC
        iboot="iboot"
    else
        log "Add $device_target_vers iBoot to all_flash"
        cp iBoot $all_flash2/iBoot2.img3
        echo "iBoot2.img3" >> $all_flash2/manifest
    fi

    log "Add APTicket to all_flash"
    cat "$shsh_path" | sed '64,$d' | sed -ne '/<data>/,/<\/data>/p' | sed -e "s/<data>//" | sed "s/<\/data>//" | tr -d '[:space:]' | base64 --decode > apticket.der
    "$dir/xpwntool" apticket.der $all_flash2/applelogoT.img3 -t ../resources/firmware/src/scab_template.img3
    echo "applelogoT.img3" >> $all_flash2/manifest

    log "AppleLogo"
    local logo_name="$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "AppleLogo") | .filename')"
    if [[ -n $ipsw_customlogo ]]; then
        ipsw_prepare_logos_convert
        mv $all_flash/$logoname $logo_name
    else
        unzip -o -j "$ipsw_path.ipsw" $all_flash/$logo_name
        echo "0000010: 3467" | xxd -r - $logo_name
        echo "0000020: 3467" | xxd -r - $logo_name
    fi
    log "Add AppleLogo to all_flash"
    if [[ $device_latest_vers == "5"* ]]; then
        mv $logo_name $all_flash2/applelogo4.img3
        echo "applelogo4.img3" >> $all_flash2/manifest
    else
        sed '/applelogo/d' $all_flash2/manifest > manifest
        rm $all_flash2/manifest
        echo "$logo_name" >> manifest
        mv $logo_name manifest $all_flash2/
    fi

    log "Creating $ipsw_custom_part2.ipsw..."
    pushd $ipsw_custom_part2 >/dev/null
    zip -r0 ../../$ipsw_custom_part2.ipsw *
    popd >/dev/null

    if [[ $ipsw_skip_first == 1 ]]; then
        return
    fi

    # ------ part 2 (nor flash) ends here. start creating part 1 ipsw ------
    case $device_target_vers in
        4.2* ) ipsw_prepare_32bit $iboot;;
        *    ) ipsw_prepare_jailbreak $iboot;;
    esac

    ipsw_prepare_ios4multipart_patch=1
    ipsw_prepare_multipatch
}

ipsw_prepare_multipatch() {
    local vers
    local build
    local options_plist
    local saved_path
    local url
    local ramdisk_name
    local name
    local iv
    local key
    local comps=("iBSS" "iBEC" "DeviceTree" "Kernelcache" "RestoreRamdisk")
    local use_ticket=1

    log "Starting multipatch"
    mv "$ipsw_custom.ipsw" temp.ipsw
    rm asr* iBSS* iBEC* ramdisk* *.dmg 2>/dev/null
    options_plist="options.$device_model.plist"
    if [[ $device_type == "iPad1,1" && $device_target_vers == "4"* ]]; then
        use_ticket=
    elif [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
        options_plist="options.plist"
        use_ticket=
    fi

    vers="4.2.1"
    build="8C148"
    if [[ $ipsw_isbeta == 1 ]]; then
        :
    elif [[ $device_type == "iPad1,1" || $device_type == "iPhone3,3" ]] ||
         [[ $device_type == "iPod3,1" && $device_target_vers == "3"* ]]; then
        vers="$device_target_vers"
        build="$device_target_build"
    fi
    case $device_target_vers in
        4.3* ) vers="4.3.5"; build="8L1";;
        5.0* ) vers="5.0.1"; build="9A405";;
        5.1* ) vers="5.1.1"; build="9B206";;
        6* ) vers="6.1.3"; build="10B329";;
    esac
    if [[ $ipsw_gasgauge_patch == 1 ]]; then
        local ver2="${device_target_vers:0:1}"
        if (( ver2 >= 7 )); then
            vers="6.1.3"
            build="10B329"
        fi
    else
        case $device_target_vers in
            7* ) vers="7.1.2"; build="11D257";;
            8* ) vers="8.4.1"; build="12H321";;
            9* ) vers="9.3.5"; build="13G36";;
        esac
    fi
    saved_path="../saved/$device_type/$build"
    ipsw_get_url $build
    url="$ipsw_url"
    device_fw_key_check
    ramdisk_name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .filename')
    rootfs_name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "RootFS") | .filename')
    if [[ -z $ramdisk_name ]]; then
        error "Issue with firmware keys: Failed getting RestoreRamdisk. Check The Apple Wiki or your wikiproxy"
    fi

    mkdir -p $saved_path Downgrade Firmware/dfu 2>/dev/null
    device_fw_key_check temp $build
    log "Getting $vers restore components"
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" ) path="$all_flash/";;
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
                "$dir/xpwntool" $name Downgrade/RestoreDeviceTree -iv $iv -k $key -decrypt
                zip -r0 temp.ipsw Downgrade/RestoreDeviceTree
            ;;
            "Kernelcache" )
                "$dir/xpwntool" $name Downgrade/RestoreKernelCache -iv $iv -k $key -decrypt
                zip -r0 temp.ipsw Downgrade/RestoreKernelCache
            ;;
            * )
                mv $name $getcomp.orig
                "$dir/xpwntool" $getcomp.orig $getcomp.dec -iv $iv -k $key
            ;;
        esac
        if [[ $getcomp == "iB"* ]]; then
            local ticket=
            if [[ $getcomp == "iBEC" && $use_ticket == 1 ]]; then
                ticket="--ticket"
            fi
            log "Patch $getcomp"
            "$dir/iBoot32Patcher" $getcomp.dec $getcomp.patched --rsa --debug $ticket -b "rd=md0 -v nand-enable-reformat=1 amfi=0xff amfi_get_out_of_my_way=1 cs_enforcement_disable=1 pio-error=0"
            "$dir/xpwntool" $getcomp.patched ${path}$name -t $getcomp.orig
            cp ${path}$name ${path}$getcomp.$device_model.RELEASE.dfu 2>/dev/null
            zip -r0 temp.ipsw ${path}$name ${path}$getcomp.$device_model.RELEASE.dfu
        fi
    done

    log "Extracting ramdisk from IPSW"
    unzip -o -j temp.ipsw $ramdisk_name
    mv $ramdisk_name ramdisk2.orig
    "$dir/xpwntool" ramdisk2.orig ramdisk2.dec

    log "Checking"
    "$dir/hfsplus" ramdisk2.dec extract multipatched
    if [[ -s multipatched ]]; then
        log "Already multipatched"
        mv temp.ipsw "$ipsw_custom.ipsw"
        return
    fi

    log "Grow ramdisk"
    "$dir/hfsplus" RestoreRamdisk.dec grow 30000000

    log "Patch ASR"
    if [[ $ipsw_prepare_usepowder == 1 ]]; then
        rm -f asr
        "$dir/hfsplus" ramdisk2.dec extract usr/sbin/asr
        "$dir/hfsplus" RestoreRamdisk.dec rm usr/sbin/asr
        "$dir/hfsplus" RestoreRamdisk.dec add asr usr/sbin/asr
        "$dir/hfsplus" RestoreRamdisk.dec chmod 755 usr/sbin/asr
        "$dir/hfsplus" RestoreRamdisk.dec chown 0:0 usr/sbin/asr
    else
        cp ../resources/firmware/FirmwareBundles/Down_${device_type}_${vers}_${build}.bundle/asr.patch .
        ipsw_patch_file RestoreRamdisk.dec usr/sbin asr asr.patch
    fi

    if [[ $device_target_vers == "3.2"* ]]; then
        log "3.2 options.plist"
        cp ../resources/firmware/src/target/k48/options.plist $options_plist
    else
        log "Extract options.plist from $device_target_vers IPSW"
        "$dir/hfsplus" ramdisk2.dec extract usr/local/share/restore/$options_plist
    fi

    log "Modify options.plist"
    "$dir/hfsplus" RestoreRamdisk.dec rm usr/local/share/restore/$options_plist
    if [[ $ipsw_prepare_ios4multipart_patch == 1 || $device_target_tethered == 1 ]]; then
        cat $options_plist | sed '$d' | sed '$d' > options2.plist
        printf "<key>FlashNOR</key><false/></dict>\n</plist>\n" >> options2.plist
        cat options2.plist
        "$dir/hfsplus" RestoreRamdisk.dec add options2.plist usr/local/share/restore/$options_plist
    else
        "$dir/hfsplus" RestoreRamdisk.dec add $options_plist usr/local/share/restore/$options_plist
    fi
    if [[ $device_target_vers == "3"* ]]; then
        :
    elif [[ $device_target_powder == 1 && $device_target_vers == "4"* ]]; then
        log "Adding exploit and partition stuff"
        cp -R ../resources/firmware/src .
        "$dir/hfsplus" RestoreRamdisk.dec untar src/bin4.tar
        "$dir/hfsplus" RestoreRamdisk.dec mv sbin/reboot sbin/reboot_
        "$dir/hfsplus" RestoreRamdisk.dec add src/target/$device_model/reboot4 sbin/reboot
        "$dir/hfsplus" RestoreRamdisk.dec chmod 755 sbin/reboot
        "$dir/hfsplus" RestoreRamdisk.dec chown 0:0 sbin/reboot
    elif [[ $device_target_powder == 1 ]]; then
        local hw="$device_model"
        local base_build="11D257"
        case $device_type in
            iPhone5,[12] ) hw="iphone5";;
            iPhone5,[34] ) hw="iphone5b";;
            iPad3,[456] )  hw="ipad3b";;
        esac
        case $device_base_build in
            "11A"* | "11B"* ) base_build="11B554a";;
            "9"* ) base_build="9B206";;
        esac
        local exploit="src/target/$hw/$base_build/exploit"
        local partition="src/target/$hw/$base_build/partition"
        log "Adding exploit and partition stuff"
        "$dir/hfsplus" RestoreRamdisk.dec untar src/bin.tar
        "$dir/hfsplus" RestoreRamdisk.dec mv sbin/reboot sbin/reboot_
        "$dir/hfsplus" RestoreRamdisk.dec add $partition sbin/reboot
        "$dir/hfsplus" RestoreRamdisk.dec chmod 755 sbin/reboot
        "$dir/hfsplus" RestoreRamdisk.dec chown 0:0 sbin/reboot
        "$dir/hfsplus" RestoreRamdisk.dec add $exploit exploit
    elif [[ $ipsw_jailbreak == 1 && $device_target_vers == "8"* ]]; then
        "$dir/hfsplus" RestoreRamdisk.dec untar bin.tar
        "$dir/hfsplus" RestoreRamdisk.dec mv sbin/reboot sbin/reboot_
        "$dir/hfsplus" RestoreRamdisk.dec add reboot.sh sbin/reboot
        "$dir/hfsplus" RestoreRamdisk.dec chmod 755 sbin/reboot
        "$dir/hfsplus" RestoreRamdisk.dec chown 0:0 sbin/reboot
    fi

    echo "multipatched" > multipatched
    "$dir/hfsplus" RestoreRamdisk.dec add multipatched multipatched

    log "Repack Restore Ramdisk"
    "$dir/xpwntool" RestoreRamdisk.dec $ramdisk_name -t RestoreRamdisk.orig
    log "Add Restore Ramdisk to IPSW"
    zip -r0 temp.ipsw $ramdisk_name

    # 3.2 fs workaround
    if [[ $device_target_vers == "3.2"* ]]; then
        local ipsw_name="${device_type}_${device_target_vers}_${device_target_build}_FS"
        ipsw_url="https://github.com/LukeZGD/Legacy-iOS-Kit-Keys/releases/download/jailbreak/iPad1.1_${device_target_vers}_${device_target_build}_FS.ipsw"
        local sha1E="123d8717b1accbf43c03d2fbd6e82aa5ca3533c9"
        if [[ $device_target_vers == "3.2.1" ]]; then
            sha1E="e1b2652aee400115b0b83c97628f90c3953e7eaf"
        elif [[ $device_target_vers == "3.2" ]]; then
            sha1E="5763a6f9d5ead3675535c6f7037192e8611206bc"
        fi
        if [[ ! -s ../$ipsw_name.ipsw ]]; then
            log "Downloading FS IPSW..."
            curl -L "$ipsw_url" -o temp2.ipsw
            log "Getting SHA1 hash for FS IPSW..."
            local sha1L=$($sha1sum temp2.ipsw | awk '{print $1}')
            if [[ $sha1L != "$sha1E" ]]; then
                error "Verifying IPSW failed. The IPSW may be corrupted or incomplete. Please run the script again" \
                "* SHA1sum mismatch. Expected $sha1E, got $sha1L"
            fi
            mv temp2.ipsw ../$ipsw_name.ipsw
        fi
        log "Extract RootFS from FS IPSW"
        unzip -o -j ../$ipsw_name.ipsw $rootfs_name
        log "Add RootFS to IPSW"
        zip -r0 temp.ipsw $rootfs_name
    fi

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_tethered() {
    local name
    local iv
    local key
    local options_plist="options.$device_model.plist"
    if [[ $device_type == "iPad1,1" && $device_target_vers == "4"* ]]; then
        :
    elif [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
        options_plist="options.plist"
    fi

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    ipsw_prepare_32bit

    log "Extract RestoreRamdisk and options.plist"
    device_fw_key_check temp $device_target_build
    name=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .filename')
    iv=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .iv')
    key=$(echo $device_fw_key_temp | $jq -j '.keys[] | select(.image == "RestoreRamdisk") | .key')
    mv "$ipsw_custom.ipsw" temp.ipsw
    unzip -o -j temp.ipsw $name
    mv $name ramdisk.orig
    "$dir/xpwntool" ramdisk.orig ramdisk.dec -iv $iv -k $key
    "$dir/hfsplus" ramdisk.dec extract usr/local/share/restore/$options_plist

    log "Modify options.plist"
    "$dir/hfsplus" ramdisk.dec rm usr/local/share/restore/$options_plist
    cat $options_plist | sed '$d' | sed '$d' > options2.plist
    printf "<key>FlashNOR</key><false/></dict>\n</plist>\n" >> options2.plist
    cat options2.plist
    "$dir/hfsplus" ramdisk.dec add options2.plist usr/local/share/restore/$options_plist

    log "Repack Restore Ramdisk"
    "$dir/xpwntool" ramdisk.dec $name -t ramdisk.orig
    log "Add Restore Ramdisk to IPSW"
    zip -r0 temp.ipsw $name
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_ios4patches() {
    local comps=("iBSS" "iBEC")
    local iv
    local key
    local name
    local path="Firmware/dfu/"
    log "Applying iOS 4 patches"
    mkdir -p $all_flash $path
    for getcomp in "${comps[@]}"; do
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        name="$getcomp.${device_model}ap.RELEASE.dfu"
        log "Patch $getcomp"
        unzip -o -j "$ipsw_path.ipsw" ${path}$name
        mv $name $getcomp.orig
        "$dir/xpwntool" $getcomp.orig $getcomp.dec -iv $iv -k $key
        "$dir/iBoot32Patcher" $getcomp.dec $getcomp.patched --rsa --debug -b "rd=md0 -v amfi=0xff cs_enforcement_disable=1 pio-error=0"
        "$dir/xpwntool" $getcomp.patched ${path}$name -t $getcomp.orig
    done
}

ipsw_prepare_ios4powder() {
    local ExtraArgs="-apticket $shsh_path"
    local ExtraArgs2="--boot-partition --boot-ramdisk --logo4 "
    local JBFiles=()
    ipsw_prepare_usepowder=1

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $ipsw_jailbreak == 1 ]]; then
        JBFiles=("g1lbertJB/${device_type}_${device_target_build}.tar" "fstab_old.tar" "freeze.tar" "cydiasubstrate.tar")
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
    ipsw_prepare_logos_convert
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
        ExtraArgs+=" ../saved/$device_type/activation-$device_ecid.tar"
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
    fi
    if [[ $ipsw_isbeta == 1 ]]; then
        ipsw_prepare_systemversion
        ExtraArgs+=" systemversion.tar"
    fi

    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw -base $ipsw_base_path.ipsw $ExtraArgs ${JBFiles[*]}"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw -base "$ipsw_base_path.ipsw" $ExtraArgs ${JBFiles[@]}

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    ipsw_prepare_ios4patches
    if [[ -n $ipsw_customlogo ]]; then
        ipsw_prepare_logos_add
    else
        log "Patch AppleLogo"
        local applelogo_name=$(echo "$device_fw_key" | $jq -j '.keys[] | select(.image == "AppleLogo") | .filename')
        unzip -o -j temp.ipsw $all_flash/$applelogo_name
        echo "0000010: 3467" | xxd -r - $applelogo_name
        echo "0000020: 3467" | xxd -r - $applelogo_name
        mv $applelogo_name $all_flash/$applelogo_name
    fi

    log "Add all to custom IPSW"
    if [[ $device_type != "iPad1,1" ]]; then
        cp iBoot $all_flash/iBoot2.${device_model}ap.RELEASE.img3
    fi
    zip -r0 temp.ipsw $all_flash/* Firmware/dfu/* $ramdisk_name

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_powder() {
    local ExtraArgs
    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi
    ipsw_prepare_usepowder=1

    ipsw_prepare_bundle target
    ipsw_prepare_bundle base
    ipsw_prepare_logos_convert
    cp -R ../resources/firmware/src .
    if [[ $ipsw_memory == 1 ]]; then
        ExtraArgs+=" -memory"
    fi
    if [[ $device_use_bb != 0 && $device_type != "$device_disable_bbupdate" ]]; then
        ExtraArgs+=" -bbupdate"
    elif [[ $device_type == "$device_disable_bbupdate" && $device_deadbb != 1 ]]; then
        device_dump baseband
        ExtraArgs+=" ../saved/$device_type/baseband-$device_ecid.tar"
    fi
    if [[ $device_actrec == 1 ]]; then
        device_dump activation
        ExtraArgs+=" ../saved/$device_type/activation-$device_ecid.tar"
    fi

    if [[ $ipsw_jailbreak == 1 ]]; then
        cp $jelbrek/freeze.tar .
        case $device_target_vers in
            5*   ) ExtraArgs+=" $jelbrek/cydiasubstrate.tar $jelbrek/g1lbertJB.tar $jelbrek/g1lbertJB/${device_type}_${device_target_build}.tar";;
            7.0* ) ExtraArgs+=" $jelbrek/evasi0n7-untether.tar $jelbrek/fstab7.tar";;
            7.1* ) ExtraArgs+=" $jelbrek/panguaxe.tar $jelbrek/fstab7.tar";;
        esac
        case $device_target_vers in
            [689]* ) :;;
            * ) ExtraArgs+=" freeze.tar";;
        esac
        if [[ $ipsw_openssh == 1 ]]; then
            ExtraArgs+=" $jelbrek/sshdeb.tar"
        fi
    fi

    local ExtraArr=("--boot-partition" "--boot-ramdisk")
    case $device_target_vers in
        [789]* ) :;;
        * ) ExtraArr+=("--logo");;
    esac
    if [[ $device_type == "iPhone5,3" || $device_type == "iPhone5,4" ]] && [[ $device_base_vers == "7.0"* ]]; then
        ipsw_powder_5c70=1
    fi
    if [[ $device_type == "iPhone5"* && $ipsw_powder_5c70 != 1 ]]; then
        # do this stuff because these use ramdiskH (jump to /boot/iBEC) instead of jump ibot to ibob
        if [[ $device_target_vers == "9"* ]]; then
            ExtraArr[0]+="9"
        fi
        local bootargs
        if [[ $ipsw_jailbreak == 1 && $device_target_vers != "7"* ]]; then
            bootargs+="cs_enforcement_disable=1 amfi_get_out_of_my_way=1 amfi=0xff"
        fi
        if [[ $ipsw_verbose == 1 ]]; then
            bootargs+=" -v"
        fi
        ExtraArr+=("-b" "$bootargs")
        patch_iboot "${ExtraArr[@]}"
        tar -cvf iBoot.tar iBoot
        ExtraArgs+=" iBoot.tar"
    elif [[ $device_type == "iPad1,1" ]]; then
        # ipad 1 ramdiskH jumps to /iBEC instead
        if [[ $ipsw_verbose == 1 ]]; then
            ExtraArr+=("-b" "-v")
        fi
        patch_iboot "${ExtraArr[@]}"
        mv iBoot iBEC
        tar -cvf iBoot.tar iBEC
        ExtraArgs+=" iBoot.tar"
    fi
    if [[ $ipsw_isbeta == 1 ]]; then
        ipsw_prepare_systemversion
        ExtraArgs+=" systemversion.tar"
    fi

    log "Preparing custom IPSW: $dir/powdersn0w $ipsw_path.ipsw temp.ipsw -base $ipsw_base_path.ipsw $ExtraArgs"
    "$dir/powdersn0w" "$ipsw_path.ipsw" temp.ipsw -base "$ipsw_base_path.ipsw" $ExtraArgs

    if [[ ! -e temp.ipsw ]]; then
        error "Failed to find custom IPSW. Please run the script again" \
        "* You may try selecting N for memory option"
    fi

    if [[ $device_type != "iPhone5"* && $device_type != "iPad1,1" ]] || [[ $ipsw_powder_5c70 == 1 ]]; then
        case $device_target_vers in
            [789]* ) :;;
            * )
                patch_iboot --logo
                mkdir -p $all_flash
                mv iBoot*.img3 $all_flash
                zip -r0 temp.ipsw $all_flash/iBoot*.img3
            ;;
        esac
    fi
    ipsw_prepare_logos_add
    ipsw_bbreplace

    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_prepare_patchcomp() {
    local path="$all_flash/"
    local name="LLB.${device_model}ap.RELEASE"
    local name41
    local ext="img3"
    local patch
    local iv
    local key

    if [[ $1 == "Kernelcache" ]]; then
        path=
        name="kernelcache.release"
        ext="s5l8900x"
        patch="../resources/patch/$name.$ext.p2"
        log "Patch $1"
        unzip -o -j temp.ipsw $name.$ext
        mv $name.$ext kc.orig
        $bspatch kc.orig $name.$ext $patch.patch
        zip -r0 temp.ipsw $name.$ext
        return
    fi

    if [[ $1 == "WTF2" ]]; then
        path="Firmware/dfu/"
        name="WTF.s5l8900xall.RELEASE"
        ext="dfu"
    elif [[ $1 == "iBoot" ]]; then
        name="iBoot.${device_model}ap.RELEASE"
    elif [[ $1 == "iB"* ]]; then
        path="Firmware/dfu/"
        name="$1.${device_model}ap.RELEASE"
        ext="dfu"
    elif [[ $1 == "RestoreRamdisk" ]]; then
        path=
        name="018-6494-014"
        ext="dmg"
        iv=25e713dd5663badebe046d0ffa164fee
        key=7029389c2dadaaa1d1e51bf579493824
        if [[ $device_target_vers == "4"* ]]; then
            name="018-7079-079"
            iv=a0fc6ca4ef7ef305d975e7f881ddcc7f
            key=18eab1ba646ae018b013bc959001fbde
            if [[ $device_target_vers == "4.2.1" ]]; then
                name41="$name"
                name="038-0029-002"
            fi
        fi
    elif [[ $1 == "RestoreDeviceTree" ]]; then
        name="DeviceTree.${device_model}ap"
    elif [[ $1 == "RestoreKernelCache" ]]; then
        path=
        name="kernelcache.release"
        ext="$device_model"
    fi
    patch="../resources/firmware/FirmwareBundles/Down_${device_type}_${device_target_vers}_${device_target_build}.bundle/$name.patch"
    local saved_path="../saved/$device_type/8B117"
    if [[ $1 == "RestoreRamdisk" ]]; then
        local ivkey
        if [[ $device_target_vers == "4"* || $device_type == *"1,1" ]]; then
            ivkey="-iv $iv -k $key"
        fi
        log "Patch $1"
        if [[ $device_target_vers == "4.2.1" ]]; then
            mkdir -p $saved_path 2>/dev/null
            if [[ -s $saved_path/$name41.$ext ]]; then
                cp $saved_path/$name41.$ext $name.$ext
            else
                ipsw_get_url 8B117
                "$dir/pzb" -g $name41.$ext -o $name.$ext "$ipsw_url"
                cp $name.$ext $saved_path/$name41.$ext
            fi
        else
            unzip -o -j "$ipsw_path.ipsw" $name.$ext
        fi
        mv $name.$ext rd.orig
        "$dir/xpwntool" rd.orig rd.dec -iv $iv -k $key
        $bspatch rd.dec rd.patched "$patch"
        "$dir/xpwntool" rd.patched $name.$ext -t rd.orig $ivkey
        zip -r0 temp.ipsw $name.$ext
        return
    fi
    log "Patch $1"
    if [[ $device_target_vers == "4.2.1" ]] && [[ $1 == "RestoreDeviceTree" || $1 == "RestoreKernelCache" ]]; then
        mkdir -p $saved_path 2>/dev/null
        if [[ -s $saved_path/$name.$ext ]]; then
            cp $saved_path/$name.$ext $name.$ext
        else
            ipsw_get_url 8B117
            "$dir/pzb" -g ${path}$name.$ext -o $name.$ext "$ipsw_url"
            cp $name.$ext $saved_path/$name.$ext
        fi
        mkdir Downgrade 2>/dev/null
        if [[ $1 == "RestoreKernelCache" ]]; then
            local ivkey="-iv 7238dcea75bf213eff209825a03add51 -k 0295d4ef87b9db687b44f54c8585d2b6"
            "$dir/xpwntool" $name.$ext kernelcache $ivkey
            $bspatch kernelcache kc.patched ../resources/patch/$name.$ext.patch
            "$dir/xpwntool" kc.patched Downgrade/$1 -t $name.$ext $ivkey
        else
            mv $name.$ext Downgrade/$1
        fi
        zip -r0 temp.ipsw Downgrade/$1
        return
    else
        unzip -o -j "$ipsw_path.ipsw" ${path}$name.$ext
    fi
    $bspatch $name.$ext $name.patched $patch
    mkdir -p $path
    mv $name.patched ${path}$name.$ext
    zip -r0 temp.ipsw ${path}$name.$ext
}

ipsw_prepare_s5l8900() {
    local rname="018-6494-014.dmg"
    local sha1E="4f6539d2032a1c7e1a068c667e393e62d8912700"
    local sha1L
    ipsw_url="https://github.com/LukeZGD/Legacy-iOS-Kit-Keys/releases/download/jailbreak/"
    if [[ $device_target_vers == "4.1" ]]; then
        rname="018-7079-079.dmg"
        sha1E="9a64eea9949b720f1033d41adc85254e6dbf9525"
    elif [[ $device_target_vers == "4.2.1" ]]; then
        rname="038-0029-002.dmg"
        sha1E="9a64eea9949b720f1033d41adc85254e6dbf9525"
    elif [[ $device_type == "iPhone1,1" && $ipsw_hacktivate == 1 ]]; then
        ipsw_url+="iPhone1.1_3.1.3_7E18_Custom_Hacktivate.ipsw"
        sha1E="f642829875ce632cd071e62169a1acbdcffcf0c8"
    elif [[ $device_type == "iPhone1,1" ]]; then
        ipsw_url+="iPhone1.1_3.1.3_7E18_Custom.ipsw"
        sha1E="7b3dd17c48c139dc827696284736d3c37d8fb7ac"
    elif [[ $device_type == "iPod1,1" ]]; then
        ipsw_url+="iPod1.1_3.1.3_7E18_Custom.ipsw"
        sha1E="f76cd3d4deaf82587dc758c6fbe724c31c9b6de2"
    fi

    if [[ $device_type == "iPhone1,2" && -e "$ipsw_custom.ipsw" ]]; then
        log "Checking RestoreRamdisk hash of custom IPSW"
        unzip -o -j "$ipsw_custom.ipsw" $rname
        sha1L="$($sha1sum $rname | awk '{print $1}')"
    elif [[ -e "$ipsw_custom2.ipsw" ]]; then
        log "Getting SHA1 hash for $ipsw_custom2.ipsw..."
        sha1L=$($sha1sum "$ipsw_custom2.ipsw" | awk '{print $1}')
    fi
    if [[ $sha1L == "$sha1E" && $ipsw_customlogo2 == 1 ]]; then
        log "Verified existing Custom IPSW. Preparing custom logo images and IPSW"
        rm -f "$ipsw_custom.ipsw"
        cp "$ipsw_custom2.ipsw" temp.ipsw
        device_fw_key_check
        ipsw_prepare_logos_convert
        ipsw_prepare_logos_add
        mv temp.ipsw "$ipsw_custom.ipsw"
        return
    elif [[ $sha1L == "$sha1E" ]]; then
        log "Verified existing Custom IPSW. Skipping IPSW creation."
        return
    else
        log "Verifying IPSW failed. Expected $sha1E, got $sha1L"
    fi

    if [[ -e "$ipsw_custom.ipsw" ]]; then
        log "Deleting existing custom IPSW"
        rm "$ipsw_custom.ipsw"
    fi

    if [[ $device_type != "iPhone1,2" ]]; then
        log "Downloading IPSW: $ipsw_url"
        curl -L "$ipsw_url" -o temp.ipsw
        log "Getting SHA1 hash for IPSW..."
        sha1L=$($sha1sum temp.ipsw | awk '{print $1}')
        if [[ $sha1L != "$sha1E" ]]; then
            error "Verifying IPSW failed. The IPSW may be corrupted or incomplete. Please run the script again" \
            "* SHA1sum mismatch. Expected $sha1E, got $sha1L"
        fi
        if [[ $ipsw_customlogo2 == 1 ]]; then
            cp temp.ipsw "$ipsw_custom2.ipsw"
            device_fw_key_check
            ipsw_prepare_logos_convert
            ipsw_prepare_logos_add
        fi
        mv temp.ipsw "$ipsw_custom.ipsw"
        return
    fi

    ipsw_prepare_jailbreak old

    mv "$ipsw_custom.ipsw" temp.ipsw
    ipsw_prepare_patchcomp LLB
    ipsw_prepare_patchcomp iBoot
    ipsw_prepare_patchcomp RestoreRamdisk
    if [[ $device_target_vers == "4"* ]]; then
        ipsw_prepare_patchcomp WTF2
        ipsw_prepare_patchcomp iBEC
    fi
    if [[ $device_target_vers == "4.2.1" ]]; then
        ipsw_prepare_patchcomp iBSS
        ipsw_prepare_patchcomp RestoreDeviceTree
        ipsw_prepare_patchcomp RestoreKernelCache
    elif [[ $device_target_vers == "3.1.3" ]]; then
        ipsw_prepare_patchcomp Kernelcache
    fi
    mv temp.ipsw "$ipsw_custom.ipsw"
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

    mv "$ipsw_custom.ipsw" temp.ipsw
    if [[ $device_type == "iPod2,1" ]]; then
        case $device_target_vers in
            4.2.1 | 4.1 | 3.1.3 ) :;;
            * ) ipsw_prepare_patchcomp LLB;;
        esac
    else # 3GS
        case $device_target_vers in
            6.1.6 | 4.1 ) :;;
            3.0* )
                ipsw_prepare_patchcomp LLB
                log "Patch Kernelcache"
                unzip -o -j "$ipsw_path.ipsw" kernelcache.release.s5l8920x
                mv kernelcache.release.s5l8920x kernelcache.orig
                $bspatch kernelcache.orig kernelcache.release.s5l8920x ../resources/firmware/FirmwareBundles/Down_iPhone2,1_${device_target_vers}_${device_target_build}.bundle/kernelcache.release.patch
                zip -r0 temp.ipsw kernelcache.release.s5l8920x
            ;;
            * )
                ipsw_prepare_patchcomp LLB
                local ExtraArgs3="pio-error=0"
                if [[ $device_target_vers == "3"* ]]; then
                    ExtraArgs3+=" amfi=0xff cs_enforcement_disable=1"
                fi
                if [[ $ipsw_verbose == 1 ]]; then
                    ExtraArgs3+=" -v"
                fi
                local path="Firmware/all_flash/all_flash.${device_model}ap.production"
                local name="iBoot.${device_model}ap.RELEASE.img3"
                patch_iboot -b "$ExtraArgs3"
                mkdir -p $path
                mv $name $path/$name
                zip -r0 temp.ipsw $path/$name
            ;;
        esac
    fi
    mv temp.ipsw "$ipsw_custom.ipsw"
}

ipsw_extract() {
    local ExtraArgs
    local ipsw="$ipsw_path"
    if [[ $1 == "custom" ]]; then
        ipsw="$ipsw_custom"
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
    if [[ $device_proc == 8 || $device_latest_vers == "15"* || $device_latest_vers == "16"* || $device_checkm8ipad == 1 ]]; then
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
    if [[ $device_use_bb == 0 || $device_type == "$device_disable_bbupdate" ]]; then
        log "Device $device_type has no baseband/disabled baseband update"
    fi
    ipsw_extract custom
    if [[ $1 == "norflash" ]]; then
        cp "$shsh_path" shsh/$device_ecid-$device_type-5.1.1.shsh
    fi
    if [[ $device_type == "iPad"* && $device_pwnrec != 1 ]] &&
       [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
        if [[ $device_type == "iPad1,1" ]]; then
            patch_ibss
            log "Sending iBSS..."
            $irecovery -f pwnediBSS.dfu
            sleep 1
        fi
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
        [1234]* ) print "* For device activation, go to: Other Utilities -> Attempt Activation";;
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
            [543]* ) warn "Do not uninstall Cydia Substrate and Substrate Safe Mode in Cydia!";;
        esac
    fi
}

restore_futurerestore() {
    local ExtraArr=()
    local futurerestore2="$futurerestore"
    local port=8888
    local opt

    if [[ $1 == "--use-pwndfu" ]]; then
        device_fw_key_check
        pushd ../resources >/dev/null
        if [[ $platform == "macos" ]]; then
            if (( mac_majver >= 12 )); then
                opt="/usr/bin/python3 -m http.server -b 127.0.0.1 $port"
            else
                opt="/usr/bin/python -m SimpleHTTPServer $port"
            fi
        else
            if [[ -z $(command -v python3) ]]; then
                error "Python 3 is not installed, cannot continue. Make sure to have python3 installed."
            fi
            opt="$(command -v python3) -m http.server -b 127.0.0.1 $port"
        fi
        log "Starting local server for firmware keys: $opt"
        $opt &
        httpserver_pid=$!
        log "httpserver PID: $httpserver_pid"
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
    # sep args for 64bit
    if [[ -n $restore_sep ]]; then
        ExtraArr+=("-s" "$restore_sep" "-m" "$restore_manifest")
    fi
    if (( device_proc < 7 )); then
        futurerestore2+="_old"
    elif [[ $device_proc == 7 && $device_target_other != 1 &&
            $device_target_vers == "10.3.3" && $restore_usepwndfu64 != 1 ]]; then
        futurerestore2+="_new"
    else
        futurerestore2="../saved/futurerestore_$platform"
        if [[ $device_target_vers == "10"* ]]; then
            export FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 # required since custom-latest-ota is broken
        else
            ExtraArr=("--latest-sep")
            case $device_type in
                iPhone* | iPad5,[24] | iPad6,[48] | iPad6,12 | iPad7,[46] | iPad7,12 ) ExtraArr+=("--latest-baseband");;
                * ) ExtraArr+=("--no-baseband");;
            esac
        fi
        ExtraArr+=("--no-rsep")
        if [[ $device_target_setnonce == 1 ]]; then
            ExtraArr+=("--set-nonce")
        fi
        log "futurerestore nightly will be used for this restore: https://github.com/futurerestore/futurerestore"
        if [[ $platform == "linux" && $platform_arch != "x86_64" ]]; then
            warn "futurerestore nightly is not supported on Linux $platform_arch, cannot continue. x86_64 only."
            return
        fi
        log "Checking for futurerestore updates..."
        #local fr_latest="$(curl https://api.github.com/repos/futurerestore/futurerestore/commits | $jq -r '.[0].sha')"
        local fr_latest="1a5317ce543e6f6c583b31e379775e36b0ac0916--"
        local fr_current="$(cat ${futurerestore2}_version 2>/dev/null)"
        if [[ $fr_latest != "$fr_current" ]]; then
            log "futurerestore nightly update detected, downloading."
            rm $futurerestore2
        fi
        if [[ ! -e $futurerestore2 ]]; then
            local url="https://github.com/LukeZGD/Legacy-iOS-Kit-Keys/releases/download/jailbreak/"
            local file="futurerestore-"
            case $platform in
                "macos" ) file+="macOS-RELEASE.zip";;
                "linux" ) file+="Linux-x86_64-RELEASE.zip";;
            esac
            url+="$file"
            download_file $url $file
            unzip -q "$file" -d .
            tar -xJvf futurerestore*.xz
            mv futurerestore $futurerestore2
            perl -pi -e 's/nightly/nightlo/' $futurerestore2 # disable update check for now since it segfaults
            chmod +x $futurerestore2
            if [[ $platform == "macos" ]]; then
                ldid="../saved/ldid_${platform}_${platform_arch}"
                if [[ ! -e $ldid ]]; then
                    download_file https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_$platform_arch ldid
                    chmod +x ldid
                    mv ldid $ldid
                fi
                $ldid -S $futurerestore2
            fi
            echo "$fr_latest" > ${futurerestore2}_version
        fi
    fi
    # custom arg(s), either --use-pwndfu or --skip-blob, or both
    if [[ -n "$1" ]]; then
        ExtraArr+=("$1")
    fi
    if [[ -n "$2" ]]; then
        ExtraArr+=("$2")
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArr+=("-d")
    fi
    ExtraArr+=("-t" "$shsh_path" "$ipsw_path.ipsw")
    ipsw_extract

    log "Running futurerestore with command: $futurerestore2 ${ExtraArr[*]}"
    $futurerestore2 "${ExtraArr[@]}"
    opt=$?
    log "Restoring done! Read the message below if any error has occurred:"
    if [[ $opt != 0 ]] && (( device_proc < 7 )); then
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
    if [[ $device_latest_vers == "12"* || $device_latest_vers == "15"* || $device_latest_vers == "16"* || $device_checkm8ipad == 1 ]]; then
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
    if [[ $device_type == "iPhone1,2" && $device_target_vers == "4"* ]]; then
        if [[ $1 == "custom" ]]; then
            log "Sending s5l8900xall..."
            $irecovery -f "$ipsw_custom/Firmware/dfu/WTF.s5l8900xall.RELEASE.dfu"
            device_find_mode DFUreal
            log "Sending iBSS..."
            $irecovery -f "$ipsw_custom/Firmware/dfu/iBSS.${device_model}ap.RELEASE.dfu"
            device_find_mode Recovery
        else
            ExtraArgs="-e"
        fi
    fi
    if [[ $debug_mode == 1 ]]; then
        ExtraArgs+="d"
    fi
    log "Running idevicerestore with command: $idevicerestore2 $ExtraArgs \"$ipsw_path.ipsw\""
    $idevicerestore2 $ExtraArgs "$ipsw_path.ipsw"
    opt=$?
    if [[ $2 == "first" ]]; then
        return $opt
    fi
    if [[ $1 == "custom" ]]; then
        log "Restoring done! Read the message below if any error has occurred:"
        print "* Please read the \"Troubleshooting\" wiki page in GitHub before opening any issue!"
        print "* Your problem may have already been addressed within the wiki page."
        print "* If opening an issue in GitHub, please provide a FULL log/output. Otherwise, your issue may be dismissed."
    fi
    case $device_target_vers in
        [1234]* ) print "* For device activation, go to: Other Utilities -> Attempt Activation";;
    esac
    if [[ $ipsw_jailbreak == 1 ]]; then
        case $device_target_vers in
            [543]* ) warn "Do not uninstall Cydia Substrate and Substrate Safe Mode in Cydia!";;
        esac
    fi
}

restore_prepare_pwnrec64() {
    local attempt=1
    if [[ $device_pwnrec == 1 ]]; then
        warn "Pwned recovery flag detected, skipping pwnREC mode procedure. Proceed with caution"
        return
    fi

    device_enter_mode pwnDFU
    if [[ $device_proc == 7 ]]; then
        log "gaster reset"
        $gaster reset
    fi
    sleep 1
    while (( attempt <= 5 )); do
        log "Entering pwnREC mode... (Attempt $attempt of 5)"
        log "Sending iBSS..."
        $irecovery -f $iBSS.im4p
        sleep 1
        log "Sending iBEC..."
        $irecovery -f $iBEC.im4p
        sleep 3
        device_find_mode Recovery 1
        if [[ $? == 0 ]]; then
            break
        fi
        print "* You may also try to unplug and replug your device"
        ((attempt++))
    done
    if [[ $device_proc == 10 ]]; then
        log "irecovery -c go"
        $irecovery -c "go"
        sleep 3
    fi

    if (( attempt > 5 )); then
        error "Failed to enter pwnREC mode. You might have to force restart your device and start over entering pwnDFU mode again"
    fi
}

device_buttons() {
    local selection=("pwnDFU" "kDFU")
    if [[ $device_mode != "Normal" ]]; then
        device_enter_mode pwnDFU
        return
    fi
    input "pwnDFU/kDFU Mode Option"
    print "* This device needs to be in pwnDFU/kDFU mode before proceeding."
    print "* Selecting 1 (pwnDFU) is recommended. Both your home and power buttons must be working properly for DFU mode."
    print "* Selecting 2 (kDFU) is for those that prefer the jailbroken method instead (have OpenSSH installed)."
    input "Select your option:"
    select opt2 in "${selection[@]}"; do
        case $opt2 in
            *"DFU" ) device_enter_mode $opt2; break;;
        esac
    done
}

restore_prepare() {
    case $device_proc in
        1 )
            if [[ $device_target_vers == "4"* && $ipsw_jailbreak != 1 ]]; then
                restore_latest
                return
            elif [[ $device_target_vers == "3.1.3" ]]; then
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
            elif [[ $device_target_vers == "4.1" && $ipsw_jailbreak == 1 ]]; then
                case $device_type in
                    iPhone2,1 | iPod[23],1 ) shsh_save version 4.1;;
                esac
                device_enter_mode pwnDFU
                restore_idevicerestore
            elif [[ $device_target_powder == 1 ]]; then
                shsh_save version $device_latest_vers
                case $device_target_vers in
                    [34]* ) device_enter_mode pwnDFU;;
                    * ) device_buttons;;
                esac
                case $device_target_vers in
                    "3"* | "4.0"* | "4.1" | "4.2"* )
                        if [[ $ipsw_skip_first != 1 ]]; then
                            restore_idevicerestore first
                            log "Do not disconnect your device, not done yet"
                            print "* Please put the device in DFU mode after it reboots!"
                            sleep 10
                            device_mode=
                        fi
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
                if [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]] && [[ $device_target_powder == 1 ]]; then
                    echo
                    log "The device may enter recovery mode after the restore"
                    print "* To fix this, go to: Other Utilities -> Disable/Enable Exploit -> Enable Exploit"
                fi
            elif [[ $device_target_other == 1 ]]; then
                case $device_target_vers in
                    [34]* ) device_enter_mode pwnDFU;;
                    * ) device_buttons;;
                esac
                restore_idevicerestore
            elif [[ $device_target_vers == "4.1" ]]; then
                shsh_save version 4.1
                device_enter_mode DFU
                restore_latest
                if [[ $device_type == "iPhone2,1" ]]; then
                    log "Ignore the baseband error and do not disconnect your device yet"
                    device_find_mode Recovery 50
                    log "Attempting to exit recovery mode"
                    $irecovery -n
                    log "Done, your device should boot now"
                fi
            elif [[ $device_target_vers == "$device_latest_vers" ]]; then
                if [[ $ipsw_jailbreak == 1 ]]; then
                    shsh_save version $device_latest_vers
                    device_buttons
                    restore_idevicerestore
                else
                    restore_latest
                fi
            else
                device_enter_mode pwnDFU
                if [[ $device_type == "iPhone2,1" && $device_newbr != 0 ]]; then
                    restore_latest custom first
                    print "* Proceed to install the alloc8 exploit for the device to boot:"
                    print " -> Go to: Other Utilities -> Install alloc8 Exploit"
                    log "Do not disconnect your device, not done yet"
                    device_find_mode DFU 50
                    device_alloc8
                else
                    restore_latest custom
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
            if [[ $device_target_vers == "$device_latest_vers" && $ipsw_gasgauge_patch != 1 ]]; then
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

        7 )
            if [[ $device_target_other != 1 && $device_target_vers == "10.3.3" ]]; then
                shsh_save
            fi
            if [[ $restore_usepwndfu64 == 1 ]]; then
                restore_pwned64
            elif [[ $device_target_other != 1 && $device_target_vers == "10.3.3" ]]; then
                if [[ $device_type == "iPad4,4" || $device_type == "iPad4,5" ]]; then
                    iBSS=$iBSSb
                    iBEC=$iBECb
                fi
                restore_prepare_pwnrec64
                shsh_save apnonce $($irecovery -q | grep "NONC" | cut -c 7-)
                restore_futurerestore --skip-blob
            elif [[ $device_target_vers == "$device_latest_vers" ]]; then
                restore_latest
            else
                restore_notpwned64
            fi
        ;;

        [89] | 10 )
            if [[ $restore_usepwndfu64 == 1 ]]; then
                restore_pwned64
            elif [[ $device_target_vers == "$device_latest_vers" ]]; then
                restore_latest
            else
                restore_notpwned64
            fi
        ;;
    esac
}

restore_pwned64() {
    device_enter_mode pwnDFU
    if [[ ! -s ../saved/firmwares.json ]]; then
        download_file https://api.ipsw.me/v2.1/firmwares.json/condensed firmwares.json
        cp firmwares.json ../saved
    fi
    rm -f /tmp/firmwares.json
    cp ../saved/firmwares.json /tmp
    if [[ $device_proc == 7 ]]; then
        log "gaster reset"
        $gaster reset
    fi
    local opt
    if [[ $device_proc == 7 && $device_target_other != 1 &&
          $device_target_vers == "10.3.3" ]] || [[ $restore_useskipblob == 1 ]]; then
        opt="--skip-blob"
    fi
    restore_futurerestore --use-pwndfu $opt
}

restore_notpwned64() {
    log "The generator for your SHSH blob is: $shsh_generator"
    print "* Before continuing, make sure to set the nonce generator of your device!"
    print "* For iOS 10 and older: https://github.com/tihmstar/futurerestore#how-to-use"
    print "* For iOS 11 and newer: https://github.com/futurerestore/futurerestore/#using-dimentio"
    print "* Using \"Set Nonce Only\" in the Restore/Downgrade menu is also an option"
    pause
    if [[ $device_mode == "Normal" ]]; then
        device_enter_mode Recovery
    fi
    restore_futurerestore
}

ipsw_prepare() {
    case $device_proc in
        1 )
            if [[ $ipsw_jailbreak == 1 ]]; then
                ipsw_prepare_s5l8900
            elif [[ $device_target_vers == "$device_latest_vers" && ! -s "../$ipsw_latest_path.ipsw" ]]; then
                ipsw_path="../$ipsw_latest_path"
                ipsw_download "$ipsw_path"
            fi
        ;;

        4 )
            if [[ $device_target_tethered == 1 ]]; then
                ipsw_prepare_tethered
            elif [[ $device_target_other == 1 ]] || [[ $device_target_vers == "$device_latest_vers" && $ipsw_jailbreak == 1 ]]; then
                case $device_type in
                    iPhone2,1 ) ipsw_prepare_jailbreak;;
                    iPod2,1 ) ipsw_prepare_custom;;
                    * ) ipsw_prepare_32bit;;
                esac
            elif [[ $device_target_powder == 1 ]] && [[ $device_target_vers == "3"* || $device_target_vers == "4"* ]]; then
                shsh_save version $device_latest_vers
                case $device_target_vers in
                    "4.3"* ) ipsw_prepare_ios4powder;;
                    * ) ipsw_prepare_ios4multipart;;
                esac
            elif [[ $device_target_powder == 1 ]]; then
                ipsw_prepare_powder
            elif [[ $device_target_vers != "$device_latest_vers" ]]; then
                ipsw_prepare_custom
            fi
            if [[ $ipsw_isbeta == 1 && $ipsw_prepare_ios4multipart_patch != 1 ]] ||
               [[ $device_target_vers == "3.2"* && $ipsw_prepare_ios4multipart_patch != 1 ]] ||
               [[ $ipsw_gasgauge_patch == 1 ]]; then
                ipsw_prepare_multipatch
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
            elif [[ $device_target_vers != "$device_latest_vers" || $ipsw_gasgauge_patch == 1 ]]; then
                ipsw_prepare_32bit
            fi
            if [[ $ipsw_fourthree == 1 ]]; then
                ipsw_prepare_fourthree_part2
            elif [[ $ipsw_isbeta == 1 || $ipsw_gasgauge_patch == 1 ]]; then
                case $device_target_vers in
                    [59] ) :;;
                    * ) ipsw_prepare_multipatch;;
                esac
            fi
        ;;

        [789] | 10 )
            restore_usepwndfu64_option
            if [[ $device_target_other != 1 && $device_target_vers == "10.3.3" && $restore_usepwndfu64 != 1 ]]; then
                 ipsw_prepare_1033
            fi
        ;;
    esac
}

restore_usepwndfu64_option() {
    if [[ $device_target_vers == "$device_latest_vers" || $restore_usepwndfu64 == 1 ]]; then
        return
    elif [[ $restore_useskipblob == 1 ]]; then
        log "skip-blob flag detected, Pwned Restore Option enabled."
        restore_usepwndfu64=1
        return
    elif [[ $device_mode == "DFU" && $device_target_other == 1 ]]; then
        log "Device is in DFU mode, Pwned Restore Option enabled."
        print "* If you want to disable Pwned Restore Option, place the device in Normal/Recovery mode"
        restore_usepwndfu64=1
        return
    elif [[ $device_target_vers == "10.3.3" && $device_target_other != 1 &&
            $platform == "macos" && $platform_arch == "arm64" ]] ||
         [[ $device_target_setnonce == 1 ]]; then
        restore_usepwndfu64=1
        return
    fi
    local opt
    input "Pwned Restore Option"
    print "* When this option is enabled, use-pwndfu will be enabled for restoring."
    if [[ $device_target_other == 1 ]]; then
        print "* When disabled, user must set the device generator manually before the restore."
    fi
    if [[ $device_proc == 7 ]]; then
        print "* This option is disabled by default (N). Select this option if unsure."
        read -p "$(input 'Enable this option? (y/N): ')" opt
        if [[ $opt == 'Y' || $opt == 'y' ]]; then
            log "Pwned restore option enabled by user."
            restore_usepwndfu64=1
        else
            log "Pwned restore option disabled."
        fi
    else
        print "* This option is enabled by default (Y). Select this option if unsure."
        read -p "$(input 'Enable this option? (Y/n): ')" opt
        if [[ $opt == 'N' || $opt == 'n' ]]; then
            log "Pwned restore option disabled by user."
        else
            log "Pwned restore option enabled."
            restore_usepwndfu64=1
        fi
    fi
}

menu_remove4() {
    local menu_items
    local selected
    local back

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Disable Exploit" "Enable Exploit" "Go Back")
        menu_print_info
        print " > Main Menu > Other Utilities > Disable/Enable Exploit"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Disable Exploit" ) rec=0;;
            "Enable Exploit" ) rec=2;;
        esac
        case $selected in
            "Go Back" ) back=1;;
            * ) mode="remove4";;
        esac
    done
}

device_send_rdtar() {
    local target="/mnt1"
    if [[ $2 == "data" ]]; then
        target+="/private/var"
    fi
    log "Sending $1"
    $scp -P $ssh_port $jelbrek/$1 root@127.0.0.1:$target
    log "Extracting $1"
    $ssh -p $ssh_port root@127.0.0.1 "tar -xvf $target/$1 -C /mnt1; rm $target/$1"
}

device_ramdisk64() {
    local sshtar="../saved/ssh64.tar"
    local comps=("iBSS" "iBEC" "DeviceTree" "Kernelcache" "RestoreRamdisk")
    local name
    local iv
    local key
    local path
    local url
    local decrypt
    local ios8
    local opt
    local build_id="16A366"
    if (( device_proc >= 9 )) || [[ $device_type == "iPad5"* ]]; then
        build_id="18C66"
    fi

    if [[ $1 == "jailbreak" ]]; then
        ios8=1
    elif (( device_proc <= 8 )) && [[ $device_type != "iPad5,1" && $device_type != "iPad5,2" ]]; then
        local ver="12"
        if [[ $device_type == "iPad5"* ]]; then
            ver="14"
        fi
        device_ramdiskver="$ver"
        input "Version Select Option"
        print "* The version of the SSH Ramdisk is set to iOS $ver by default. This is the recommended option."
        print "* There is also an option to use iOS 8 ramdisk. This can be used to fix devices on iOS 7 not booting after using iOS $ver ramdisk."
        print "* If not sure, just press Enter/Return. This will select the default version."
        read -p "$(input "Select Y to use iOS $ver, select N to use iOS 8 (Y/n) ")" opt
        if [[ $opt == 'n' || $opt == 'N' ]]; then
            ios8=1
        fi
    fi

    if [[ $ios8 == 1 ]]; then
        build_id="12B410"
        if [[ $device_type == "iPhone"* ]]; then
            build_id="12B411"
        elif [[ $device_type == "iPod7,1" ]]; then
            build_id="12H321"
        fi
        sshtar="../saved/iram.tar"
        if [[ ! -e $sshtar ]]; then
            log "Downloading iram.tar from iarchive.app..."
            download_file https://github.com/LukeZGD/Legacy-iOS-Kit/files/14952123/iram.zip iram.zip
            unzip iram.zip
            mv iram.tar $sshtar
        fi
        cp $sshtar ssh.tar
    else
        comps+=("Trustcache")
        if [[ $($sha1sum $sshtar.gz 2>/dev/null | awk '{print $1}') != "61975423c096d5f21fd9f8a48042fffd3828708b" ]]; then
            rm -f $sshtar $sshtar.gz
        fi
        if [[ ! -e $sshtar.gz ]]; then
            log "Downloading ssh.tar from SSHRD_Script..."
            download_file https://github.com/LukeZGD/sshtars/raw/eed9dcb6aa7562c185eb8b3b66c6035c0b026d47/ssh.tar.gz ssh.tar.gz
            mv ssh.tar.gz $sshtar.gz
        fi
        cp $sshtar.gz ssh.tar.gz
        gzip -d ssh.tar.gz
    fi

    local ramdisk_path="../saved/$device_type/ramdisk_$build_id"
    device_target_build="$build_id"
    device_fw_key_check
    ipsw_get_url $build_id

    mkdir $ramdisk_path 2>/dev/null
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        if [[ $device_type == "iPhone8"* && $getcomp == "iB"* ]]; then
            name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | select(.filename | startswith("'$getcomp'.'$device_model'.")) | .filename')
            iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith("'$getcomp'")) | select(.filename | startswith("'$getcomp'.'$device_model'.")) | .iv')
            key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image | startswith ("'$getcomp'")) | select(.filename | startswith("'$getcomp'.'$device_model'.")) | .key')
        fi
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" ) path="Firmware/all_flash/";;
            "Trustcache" ) path="Firmware/";;
            * ) path="";;
        esac
        if [[ $ios8 == 1 && $getcomp == "DeviceTree" ]]; then
            path="$all_flash/"
        fi
        if [[ -z $name ]]; then
            local hwmodel
            ipsw_hwmodel_set
            hwmodel="$ipsw_hwmodel"
            case $getcomp in
                "iBSS" | "iBEC"  ) name="$getcomp.$hwmodel.RELEASE.im4p";;
                "DeviceTree"     ) name="$getcomp.${device_model}ap.im4p";;
                "Kernelcache"    ) name="kernelcache.release.$hwmodel";;
                "Trustcache"     ) name="048-08497-242.dmg.trustcache";;
                "RestoreRamdisk" ) name="048-08497-242.dmg";;
            esac
            if [[ $device_type == "iPhone8,1" || $device_type == "iPhone8,2" ]] && [[ $getcomp == "Kernelcache" ]]; then
                name="kernelcache.release.${device_model:0:3}"
            fi
            if [[ $build_id == "18C66" ]]; then
                case $getcomp in
                    "Trustcache"     ) name="038-83284-083.dmg.trustcache";;
                    "RestoreRamdisk" ) name="038-83284-083.dmg";;
                esac
            fi
        fi

        log "$getcomp"
        if [[ -e $ramdisk_path/$name ]]; then
            cp $ramdisk_path/$name .
        else
            "$dir/pzb" -g "${path}$name" -o "$name" "$ipsw_url"
            cp $name $ramdisk_path/
        fi
        mv $name $getcomp.orig
        local reco="-i $getcomp.orig -o $getcomp.img4 -M ../resources/sshrd/IM4M$device_proc -T "
        case $getcomp in
            "iBSS" | "iBEC" )
                reco+="$(echo $getcomp | tr '[:upper:]' '[:lower:]') -A"
                "$dir/img4" -i $getcomp.orig -o $getcomp.dec -k ${iv}${key}
                mv $getcomp.orig $getcomp.orig0
                if [[ $ios8 == 1 ]]; then
                    $bspatch $getcomp.dec $getcomp.orig ../resources/sshrd/ios8/$name.patch
                else
                    $bspatch $getcomp.dec $getcomp.orig ../resources/sshrd/$name.patch
                fi
            ;;
            "Kernelcache" )
                reco+="rkrn"
                if [[ $ios8 == 1 ]]; then
                    mv $getcomp.orig $getcomp.orig0
                    "$dir/img4" -i $getcomp.orig0 -o $getcomp.orig -k ${iv}${key} -D
                else
                    reco+=" -P ../resources/sshrd/$name.bpatch"
                    if [[ $platform == "linux" && $build_id == "18"* ]] || [[ $device_proc == 10 ]]; then
                        reco+=" -J"
                    fi
                fi
            ;;
            "DeviceTree" )
                reco+="rdtr"
                if [[ $ios8 == 1 ]]; then
                    reco+=" -A"
                    mv $getcomp.orig $getcomp.orig0
                    "$dir/img4" -i $getcomp.orig0 -o $getcomp.orig -k ${iv}${key}
                fi
            ;;
            "Trustcache" ) reco+="rtsc";;
            "RestoreRamdisk" )
                reco+="rdsk -A"
                mv $getcomp.orig $getcomp.orig0
                if [[ $ios8 == 1 ]]; then
                    "$dir/img4" -i $getcomp.orig0 -o $getcomp.orig -k ${iv}${key}
                    "$dir/hfsplus" $getcomp.orig grow 50000000
                else
                    "$dir/img4" -i $getcomp.orig0 -o $getcomp.orig
                    "$dir/hfsplus" $getcomp.orig grow 210000000
                fi
                "$dir/hfsplus" $getcomp.orig untar ssh.tar
                "$dir/hfsplus" $getcomp.orig untar ../resources/sshrd/sbplist.tar
            ;;
        esac
        "$dir/img4" $reco
        cp $getcomp.img4 $ramdisk_path
    done

    mv $ramdisk_path/iBSS.img4 $ramdisk_path/iBSS.im4p
    mv $ramdisk_path/iBEC.img4 $ramdisk_path/iBEC.im4p
    iBSS="$ramdisk_path/iBSS"
    iBEC="$ramdisk_path/iBEC"
    restore_prepare_pwnrec64

    log "Booting, please wait..."
    $irecovery -f $ramdisk_path/RestoreRamdisk.img4
    $irecovery -c ramdisk
    $irecovery -f $ramdisk_path/DeviceTree.img4
    $irecovery -c devicetree
    if [[ $ios8 != 1 ]]; then
        $irecovery -f $ramdisk_path/Trustcache.img4
        $irecovery -c firmware
    fi
    $irecovery -f $ramdisk_path/Kernelcache.img4
    $irecovery -c bootx
    device_find_mode Restore 20

    if [[ $ios8 == 1 ]]; then
        device_iproxy no-logging 44
        print "* Booted SSH ramdisk is based on: https://ios7.iarchive.app/downgrade/making-ramdisk.html"
    else
        device_iproxy no-logging
        print "* Booted SSH ramdisk is based on: https://github.com/verygenericname/SSHRD_Script"
    fi
    device_sshpass alpine

    print "* Mount filesystems with this command (for iOS 11.3 and newer):"
    print "    /usr/bin/mount_filesystems"
    print "* Mount filesystems with this command (for iOS 10.3.x):"
    print "    /sbin/mount_apfs /dev/disk0s1s1 /mnt1; /sbin/mount_apfs /dev/disk0s1s2 /mnt2"
    print "* Mount filesystems with this command (for iOS 10.2.1 and older):"
    print "    /sbin/mount_hfs /dev/disk0s1s1 /mnt1; /sbin/mount_hfs /dev/disk0s1s2 /mnt2"
    warn "Mounting and/or modifying data (/mnt2) might not work for 64-bit iOS"

    menu_ramdisk $build_id
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
        device_rd_build=
    fi
    build_id=$device_target_build
    device_fw_key_check
    ipsw_get_url $build_id
    ramdisk_path="../saved/$device_type/ramdisk_$build_id"
    mkdir $ramdisk_path 2>/dev/null
    for getcomp in "${comps[@]}"; do
        name=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .filename')
        iv=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .iv')
        key=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "'$getcomp'") | .key')
        case $getcomp in
            "iBSS" | "iBEC" ) path="Firmware/dfu/";;
            "DeviceTree" )
                path="Firmware/all_flash/"
                case $build_id in
                    14[EFG]* ) :;;
                    * ) path="$all_flash/";;
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
                [789]* | 10* | 11* ) hwmodel+="ap";;
            esac
            case $getcomp in
                "iBSS" | "iBEC" ) name="$getcomp.$hwmodel.RELEASE.dfu";;
                "DeviceTree" )    name="$getcomp.${device_model}ap.img3";;
                "Kernelcache" )   name="kernelcache.release.$hwmodel";;
            esac
        fi

        log "$getcomp"
        if [[ -n $ipsw_justboot_path ]]; then
            unzip -o -j "$ipsw_justboot_path.ipsw" "${path}$name" -d .
        elif [[ -e $ramdisk_path/$name ]]; then
            cp $ramdisk_path/$name .
        else
            "$dir/pzb" -g "${path}$name" -o "$name" "$ipsw_url"
            cp $name $ramdisk_path/
        fi
        mv $name $getcomp.orig
        if [[ $getcomp == "Kernelcache" || $getcomp == "iBSS" ]] && [[ $device_type == "iPod2,1" ]]; then
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
        "$dir/hfsplus" Ramdisk.raw untar ../resources/sshrd/sbplist.tar
    fi

    if [[ $device_type == "iPod2,1" ]]; then
        "$dir/hfsplus" Ramdisk.raw untar ../resources/sshrd/ssh_old.tar
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
            "$dir/hfsplus" Ramdisk.raw untar ../resources/sshrd/ssh.tar
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
                    "$dir/hfsplus" Ramdisk.raw chown 0:0 usr/local/bin/restored_external
                ;;
            esac
            "$dir/xpwntool" Ramdisk.raw Ramdisk.dmg -t RestoreRamdisk.dec
        fi
        log "Patch iBSS"
        "$dir/xpwntool" iBSS.dec iBSS.raw
        if [[ $device_type == "iPhone3,3" ]]; then
            case $build_id in
                8E600 | 8E501 ) device_boot4=1;;
            esac
        fi
        if [[ $build_id == "8"* && $device_type == "iPad2"* ]] || [[ $device_boot4 == 1 ]]; then
            "$dir/iBoot32Patcher" iBSS.raw iBSS.patched --rsa -b "-v amfi=0xff cs_enforcement_disable=1"
            device_boot4=1
        else
            "$dir/iBoot32Patcher" iBSS.raw iBSS.patched --rsa -b "$device_bootargs"
        fi
        "$dir/xpwntool" iBSS.patched iBSS -t iBSS.dec
        if [[ $build_id == "7"* || $build_id == "8"* ]] && [[ $device_type != "iPad"* ]]; then
            :
        else
            log "Patch iBEC"
            "$dir/xpwntool" iBEC.dec iBEC.raw
            if [[ $1 == "justboot" ]]; then
                "$dir/iBoot32Patcher" iBEC.raw iBEC.patched --rsa -b "$device_bootargs"
            else
                "$dir/iBoot32Patcher" iBEC.raw iBEC.patched --rsa --debug -b "rd=md0 -v amfi=0xff amfi_get_out_of_my_way=1 cs_enforcement_disable=1 pio-error=0"
            fi
            "$dir/xpwntool" iBEC.patched iBEC -t iBEC.dec
        fi
    fi

    if [[ $device_boot4 == 1 ]]; then
        log "Patch Kernelcache"
        mv Kernelcache.dec Kernelcache0.dec
        "$dir/xpwntool" Kernelcache0.dec Kernelcache.raw
        $bspatch Kernelcache.raw Kernelcache.patched ../resources/patch/kernelcache.release.${device_model}.${build_id}.patch
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

    if [[ $device_type == "iPad1,1" && $build_id != "9"* ]]; then
        patch_ibss
        log "Sending iBSS..."
        $irecovery -f pwnediBSS.dfu
        log "Sending iBEC..."
        $irecovery -f $ramdisk_path/iBEC
    elif (( device_proc < 5 )) && [[ $device_pwnrec != 1 ]]; then
        log "Sending iBSS..."
        $irecovery -f $ramdisk_path/iBSS
    fi
    sleep 2
    if [[ $build_id != "7"* && $build_id != "8"* ]]; then
        log "Sending iBEC..."
        $irecovery -f $ramdisk_path/iBEC
        if [[ $device_pwnrec == 1 ]]; then
            $irecovery -c "go"
        fi
    fi
    sleep 3
    device_find_mode Recovery
    if [[ $1 != "justboot" ]]; then
        log "Sending ramdisk..."
        $irecovery -f $ramdisk_path/Ramdisk.dmg
        log "Running ramdisk"
        $irecovery -c "getenv ramdisk-delay"
        $irecovery -c ramdisk
        sleep 2
    fi
    log "Sending DeviceTree..."
    $irecovery -f $ramdisk_path/DeviceTree.dec
    log "Running devicetree"
    $irecovery -c devicetree
    log "Sending KernelCache..."
    $irecovery -f $ramdisk_path/Kernelcache.dec
    $irecovery -c bootx

    if [[ $1 == "justboot" ]]; then
        log "Device should now boot."
        return
    elif [[ -n $1 ]]; then
        log "Booting, please wait..."
        device_find_mode Restore 20
        device_iproxy
    else
        log "Booting, please wait..."
        device_find_mode Restore 20
        device_iproxy no-logging
    fi
    device_sshpass alpine

    case $mode in
        "activation" | "baseband" )
            return
        ;;

        "TwistedMind2" )
            log "Sending dd command for TwistedMind2"
            $scp -P $ssh_port TwistedMind2 root@127.0.0.1:/
            $ssh -p $ssh_port root@127.0.0.1 "dd if=/TwistedMind2 of=/dev/rdisk0 bs=8192; reboot_bak"
            return
        ;;

        "jailbreak" | "getversion" )
            local vers
            local build
            local untether
            device_ramdisk_iosvers
            vers=$device_vers
            build=$device_build
            if [[ $1 == "getversion" && -n $vers ]]; then
                log "Retrieved the current iOS version, rebooting device"
                print "* iOS Version: $vers ($build)"
                $ssh -p $ssh_port root@127.0.0.1 "reboot_bak"
                return
            fi
            case $vers in
                9.3.[4231] | 9.3 ) untether="untetherhomedepot.tar";;
                9.2* | 9.1 ) untether="untetherhomedepot921.tar";;
                8* )         untether="daibutsu/untether.tar";;
                7.1* )       untether="panguaxe.tar";;
                7* )         untether="evasi0n7-untether.tar";;
                6.1.[6543] ) untether="p0sixspwn.tar";;
                6* )         untether="evasi0n6-untether.tar";;
                4.2.[8761] | 4.[10]* | 3.2* | 3.1.3 ) untether="greenpois0n/${device_type}_${build}.tar";;
                5* | 4.[32]* ) untether="g1lbertJB/${device_type}_${build}.tar";;
                '' )
                    warn "Something wrong happened. Failed to get iOS version."
                    print "* Please reboot the device into normal operating mode, then perform a clean \"slide to power off\", then try again."
                    $ssh -p $ssh_port root@127.0.0.1 "reboot_bak"
                    return
                ;;
                * )
                    warn "iOS $vers is not supported for jailbreaking with SSHRD."
                    $ssh -p $ssh_port root@127.0.0.1 "reboot_bak"
                    return
                ;;
            esac
            log "Nice, iOS $vers is compatible."
            log "Sending $untether"
            $scp -P $ssh_port $jelbrek/$untether root@127.0.0.1:/mnt1
            # 3.1.3-4.1 untether needs to be extracted early (before data partition is mounted)
            case $vers in
                4.[10]* | 3.2* )
                    untether="${device_type}_${build}.tar"
                    log "Extracting $untether"
                    $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                ;;
            esac
            # Do not extract untether for 3GS 3.1.x
            if [[ $vers == "3.1"* && $device_type != "iPhone2,1" ]]; then
                untether="${device_type}_${build}.tar"
                log "Extracting $untether"
                $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
            fi
            log "Mounting data partition"
            $ssh -p $ssh_port root@127.0.0.1 "mount.sh pv"
            case $vers in
                9* | 8* ) device_send_rdtar fstab8.tar;;
                7* ) device_send_rdtar fstab7.tar;;
                6* ) device_send_rdtar fstab_rw.tar;;
                4.2.[8761] ) $ssh -p $ssh_port root@127.0.0.1 "[[ ! -e /mnt1/sbin/punchd ]] && mv /mnt1/sbin/launchd /mnt1/sbin/punchd";;
                5* | 4.[32]* ) untether="${device_type}_${build}.tar";;
            esac
            case $vers in
                5* ) device_send_rdtar g1lbertJB.tar;;
                4.2.[8761] | 4.[10]* | 3* )
                    untether="${device_type}_${build}.tar"
                    log "fstab"
                    if [[ $device_proc == 1 || $device_type == "iPod2,1" ]]; then
                        $scp -P $ssh_port $jelbrek/fstab_old root@127.0.0.1:/mnt1/private/etc/fstab
                    else
                        $scp -P $ssh_port $jelbrek/fstab_new root@127.0.0.1:/mnt1/private/etc/fstab
                    fi
                    $ssh -p $ssh_port root@127.0.0.1 "rm /mnt1/private/var/mobile/Library/Caches/com.apple.mobile.installation.plist"
                ;;
            esac
            case $vers in
                8* | 4.[10]* | 3* ) :;;
                * )
                    log "Extracting $untether"
                    $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                ;;
            esac
            case $vers in
                [543]* ) device_send_rdtar cydiasubstrate.tar;;
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
                $scp -P $ssh_port $jelbrek/daibutsu/move.sh root@127.0.0.1:/mnt1
                log "Moving files"
                $ssh -p $ssh_port root@127.0.0.1 "bash /mnt1/move.sh; rm /mnt1/move.sh"
                untether="untether.tar"
                log "Extracting $untether"
                $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
                log "Running haxx_overwrite --${device_type}_${build}"
                $ssh -p $ssh_port root@127.0.0.1 "/usr/bin/haxx_overwrite --${device_type}_${build}"
            else
                log "Rebooting"
                $ssh -p $ssh_port root@127.0.0.1 "reboot_bak"
            fi
            log "Cool, done and jailbroken (hopefully)"
            case $vers in
                [543]* ) warn "Do not uninstall Cydia Substrate and Substrate Safe Mode in Cydia!";;
            esac
            return
        ;;

        "clearnvram" )
            log "Sending command for clearing NVRAM..."
            $ssh -p $ssh_port root@127.0.0.1 "nvram -c; reboot_bak"
            log "Done, your device should reboot now"
            return
        ;;

        "setnvram" )
            device_ramdisk_setnvram
            log "Rebooting device"
            $ssh -p $ssh_port root@127.0.0.1 "reboot_bak"
            return
        ;;

        * ) log "Device should now boot to SSH ramdisk mode.";;
    esac
    echo
    print "* Mount filesystems with this command:"
    print "    mount.sh"
    menu_ramdisk
}

device_ramdisk_setnvram() {
    log "Sending commands for setting NVRAM variables..."
    $ssh -p $ssh_port root@127.0.0.1 "nvram -c; nvram boot-partition=$rec"
    if [[ $rec == 2 ]]; then
        case $device_type in
            iPhone3,3 ) $ssh -p $ssh_port root@127.0.0.1 "nvram boot-ramdisk=/a/b/c/d/e/f/g/h/i/disk.dmg";;
            iPad2,4   ) $ssh -p $ssh_port root@127.0.0.1 "nvram boot-ramdisk=/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/disk.dmg";;
            iPhone4,1 ) $ssh -p $ssh_port root@127.0.0.1 "nvram boot-ramdisk=/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/disk.dmg";;
            iPod5,1   ) $ssh -p $ssh_port root@127.0.0.1 "nvram boot-ramdisk=/a/b/c/d/e/f/g/h/i/j/k/l/m/disk.dmg";;
            iPhone5*  )
                read -p "$(input "Select base version: Y for iOS 7.1.x, N for iOS 7.0.x (Y/n) ")" opt
                if [[ $opt != 'N' && $opt != 'n' ]]; then
                    $ssh -p $ssh_port root@127.0.0.1 "nvram boot-ramdisk=/a/b/c/d/e/f/g/h/i/j/k/l/m/disk.dmg"
                else
                    $ssh -p $ssh_port root@127.0.0.1 "nvram boot-ramdisk=/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/disk.dmg"
                fi
            ;;
            iPad1,1 | iPod3,1 )
                device_ramdisk_iosvers
                if [[ $device_vers == "3"* ]]; then
                    device_ramdisk_ios3exploit
                fi
            ;;
        esac
    fi
    log "Done"
}

device_ramdisk_ios3exploit() {
    log "iOS 3.x detected, running exploit commands"
    local offset="$($ssh -p $ssh_port root@127.0.0.1 "echo -e 'p\nq\n' | fdisk -e /dev/rdisk0" | grep AF | head -1)"
    offset="${offset##*-}"
    offset="$(echo ${offset%]*} | tr -d ' ')"
    offset=$((offset+64))
    log "Got offset $offset"
    $ssh -p $ssh_port root@127.0.0.1 "echo -e 'e 3\nAF\n\n${offset}\n8\nw\ny\nq\n' | fdisk -e /dev/rdisk0"
    echo
    log "Writing exploit ramdisk"
    $scp -P $ssh_port ../resources/firmware/src/target/$device_model/9B206/exploit root@127.0.0.1:/
    $ssh -p $ssh_port root@127.0.0.1 "dd of=/dev/rdisk0s3 if=/exploit bs=64k count=1"
    if [[ $device_type == "iPad1,1" ]]; then
        $scp -P $ssh_port ../saved/iPad1,1/iBoot3_$device_ecid root@127.0.0.1:/mnt1/iBEC
    fi
    log "fstab"
    $scp -P $ssh_port $jelbrek/fstab_new root@127.0.0.1:/mnt1/private/etc/fstab
    case $device_vers in
        3.1.3 | 3.2* ) opt='y';;
    esac
    if [[ $opt == 'y' ]]; then
        untether="${device_type}_${device_build}.tar"
        log "Sending $untether"
        $scp -P $ssh_port $jelbrek/greenpois0n/$untether root@127.0.0.1:/mnt1
        log "Extracting $untether"
        $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /mnt1/$untether -C /mnt1; rm /mnt1/$untether"
        log "Mounting data partition"
        $ssh -p $ssh_port root@127.0.0.1 "mount.sh pv"
        device_send_rdtar cydiasubstrate.tar
        device_send_rdtar cydiahttpatch.tar
        if [[ $device_vers == "3.1.3" || $device_vers == "3.2" ]]; then
            device_send_rdtar freeze.tar data
        fi
        if [[ $ipsw_openssh == 1 ]]; then
            device_send_rdtar sshdeb.tar
        fi
    fi
}

device_ramdisk_datetime() {
    log "Running command to Update DateTime"
    $ssh -p $ssh_port root@127.0.0.1 "date -s @$(date +%s)"
}

device_ramdisk_iosvers() {
    device_vers=
    device_build=
    device_ramdisk_datetime
    if (( device_proc < 7 )); then
        log "Mounting root filesystem"
        $ssh -p $ssh_port root@127.0.0.1 "mount.sh root"
        sleep 1
    fi
    log "Getting iOS version"
    $scp -P $ssh_port root@127.0.0.1:/mnt1/System/Library/CoreServices/SystemVersion.plist .
    if [[ $platform == "macos" ]]; then
        rm -f BuildVer Version
        plutil -extract 'ProductVersion' xml1 SystemVersion.plist -o Version
        device_vers=$(cat Version | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
        plutil -extract 'ProductBuildVersion' xml1 SystemVersion.plist -o BuildVer
        device_build=$(cat BuildVer | sed -ne '/<string>/,/<\/string>/p' | sed -e "s/<string>//" | sed "s/<\/string>//" | sed '2d')
    else
        device_vers=$(cat SystemVersion.plist | grep -i ProductVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
        device_build=$(cat SystemVersion.plist | grep -i ProductBuildVersion -A 1 | grep -oPm1 "(?<=<string>)[^<]+")
    fi
}

menu_ramdisk() {
    local loop
    local menu_items=("Connect to SSH" "Dump Blobs")
    local reboot="reboot_bak"
    if (( device_proc >= 7 )); then
        menu_items+=("Dump SEP Firmware")
        reboot="/sbin/reboot"
    else
        menu_items+=("Dump Baseband/Activation")
    fi
    if [[ $1 == "18C66" ]]; then
        menu_items+=("Install TrollStore")
    elif [[ $device_proc == 7 && $1 == "12"* ]]; then
        log "Ramdisk should now boot and fix iOS 7 not booting."
    elif (( device_proc <= 8 )); then
        menu_items+=("Erase All (iOS 7 and 8)")
    fi
    if (( device_proc >= 5 )); then
        menu_items+=("Erase All (iOS 9+)")
    fi
    case $device_type in
        iPhone3,[13] | iPhone[45]* | iPad1,1 | iPad2,4 | iPod[35],1 ) menu_items+=("Disable/Enable Exploit");;
    esac
    menu_items+=("Clear NVRAM" "Get iOS Version" "Update DateTime" "Reboot Device" "Exit")

    print "* For accessing data, note the following:"
    print "* Host: sftp://127.0.0.1 | User: root | Password: alpine | Port: $ssh_port"
    echo
    print "* Other Useful SSH Ramdisk commands:"
    print "* Clear NVRAM with this command:"
    print "    nvram -c"
    print "* Erase All Content and Settings with this command (iOS 9+ only):"
    print "    nvram oblit-inprogress=5"
    print "* To reboot, use this command:"
    print "    $reboot"
    echo

    while [[ $loop != 1 ]]; do
        mode=
        print "* SSH Ramdisk Menu"
        while [[ -z $mode ]]; do
            input "Select an option:"
            select opt in "${menu_items[@]}"; do
                selected="$opt"
                break
            done
            case $selected in
                "Connect to SSH" ) mode="ssh";;
                "Reboot Device" ) mode="reboot";;
                "Dump Blobs" ) mode="dump-blobs";;
                "Get iOS Version" ) mode="iosvers";;
                "Dump Baseband/Activation" ) mode="dump-bbactrec";;
                "Install TrollStore" ) mode="trollstore";;
                "Erase All (iOS 7 and 8)" ) mode="erase78";;
                "Erase All (iOS 9+)" ) mode="erase9";;
                "Clear NVRAM" ) mode="clearnvram";;
                "Dump SEP Firmware" ) mode="dump-sep";;
                "Disable/Enable Exploit" ) menu_remove4;;
                "Update DateTime" ) mode="datetime";;
                "Exit" ) mode="exit";;
            esac
        done

        case $mode in
            "ssh" )
                log "Use the \"exit\" command to go back to SSH Ramdisk Menu"
                if (( device_proc >= 7 )) && [[ $1 == "12"* ]]; then
                    $ssh -p $ssh_port root@127.0.0.1 &
                    ssh_pid=$!
                    sleep 1
                    kill $ssh_pid
                fi
                $ssh -p $ssh_port root@127.0.0.1
            ;;
            "reboot" ) $ssh -p $ssh_port root@127.0.0.1 "$reboot"; loop=1;;
            "exit" ) loop=1;;
            "dump-blobs" )
                local shsh="../saved/shsh/$device_ecid-$device_type-$(date +%Y-%m-%d-%H%M).shsh"
                if [[ $1 == "12"* ]]; then
                    warn "Dumping blobs may fail on iOS 8 ramdisk."
                    print "* It is recommended to do this on iOS $device_ramdiskver ramdisk instead."
                    read -p "$(input "Select Y to continue, N to go back (y/N) ")" opt
                    if [[ $opt != 'Y' && $opt != 'y' ]]; then
                        continue
                    fi
                elif (( device_proc < 7 )); then
                    warn "This is the wrong place to dump onboard blobs for 32-bit devices."
                    print "* Reboot your device, run the script again and go to Save SHSH Blobs -> Onboard Blobs"
                    print "* For more details, go to: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Saving-onboard-SHSH-blobs-of-current-iOS-version"
                    pause
                    continue
                fi
                log "Attempting to dump blobs"
                $ssh -p $ssh_port root@127.0.0.1 "cat /dev/rdisk1" | dd of=dump.raw bs=256 count=$((0x4000))
                if [[ ! -s dump.raw ]]; then
                    log "Failed with rdisk1, trying again with rdisk2..."
                    $ssh -p $ssh_port root@127.0.0.1 "cat /dev/rdisk2" | dd of=dump.raw bs=256 count=$((0x4000))
                    if [[ ! -s dump.raw ]]; then
                        warn "Failed with rdisk2, cannot continue."
                        continue
                    fi
                fi
                "$dir/img4tool" --convert -s $shsh dump.raw
                if [[ -s $shsh ]]; then
                    log "Onboard blobs should be dumped to $shsh"
                    continue
                fi
                warn "Failed to convert raw dump to SHSH."
                local raw="../saved/shsh/rawdump_${device_ecid}-${device_type}_$(date +%Y-%m-%d-%H%M).raw"
                mv dump.raw $raw
                log "Raw dump saved at: $raw"
                warn "This raw dump is not usable for restoring, you need to convert it first."
                print "* If unable to be converted, this dump is likely not usable for restoring."
            ;;
            "iosvers" )
                if (( device_proc >= 7 )); then
                    print "* Unfortunately the mount command needs to be done manually for 64-bit devices."
                    print "* The mount command also changes depending on the iOS version (which is what we're trying to get here in the first place)"
                    print "* You need to mount filesystems using the appropriate command before continuing (scroll up to see the commands)"
                    warn "Make sure that you know what you are doing when using this option on 64-bit devices."
                    read -p "$(input "Select Y to continue, N to go back (y/N) ")" opt
                    if [[ $opt != 'Y' && $opt != 'y' ]]; then
                        continue
                    fi
                fi
                device_ramdisk_iosvers
                if [[ -n $device_vers ]]; then
                    log "Retrieved the current iOS version"
                    print "* iOS Version: $device_vers ($device_build)"
                else
                    warn "Something wrong happened. Failed to get iOS version."
                fi
            ;;
            "dump-bbactrec" ) device_dumprd;;
            "trollstore" )
                print "* Make sure that your device is on iOS 14 or 15 before continuing."
                print "* If your device is on iOS 13 or below, TrollStore will NOT work."
                read -p "$(input "Select Y to continue, N to go back (y/N) ")" opt
                if [[ $opt != 'Y' && $opt != 'y' ]]; then
                    continue
                fi
                log "Checking for latest TrollStore"
                local latest="$(curl https://api.github.com/repos/opa334/TrollStore/releases/latest | $jq -r ".tag_name")"
                local current="$(cat ../saved/TrollStore_version 2>/dev/null || echo "none")"
                log "Latest version: $latest, current version: $current"
                if [[ $current != "$latest" ]]; then
                    rm -f ../saved/TrollStore.tar ../saved/PersistenceHelper_Embedded
                fi
                if [[ -s ../saved/TrollStore.tar && -s ../saved/PersistenceHelper_Embedded ]]; then
                    cp ../saved/TrollStore.tar ../saved/PersistenceHelper_Embedded .
                else
                    rm -f ../saved/TrollStore.tar ../saved/PersistenceHelper_Embedded
                    log "Downloading files for latest TrollStore"
                    download_file https://github.com/opa334/TrollStore/releases/download/$latest/PersistenceHelper_Embedded PersistenceHelper_Embedded
                    download_file https://github.com/opa334/TrollStore/releases/download/$latest/TrollStore.tar TrollStore.tar
                    cp TrollStore.tar PersistenceHelper_Embedded ../saved
                    echo "$latest" > ../saved/TrollStore_version
                fi
                tar -xf TrollStore.tar
                log "Installing TrollStore to Tips"
                $ssh -p $ssh_port root@127.0.0.1 "mount_filesystems"
                local tips="$($ssh -p $ssh_port root@127.0.0.1 "find /mnt2/containers/Bundle/Application/ -name \"Tips.app\"")"
                $scp -P $ssh_port PersistenceHelper_Embedded TrollStore.app/trollstorehelper ../resources/sshrd/trollstore.sh root@127.0.0.1:$tips
                rm -r PersistenceHelper_Embedded TrollStore*
                $ssh -p $ssh_port root@127.0.0.1 "bash $tips/trollstore.sh; rm $tips/trollstore.sh"
                log "Done!"
            ;;
            "erase78" )
                log "Please read the message below:"
                warn "This will do a \"Erase All Content and Settings\" procedure for iOS 7 and 8 devices."
                warn "Do NOT do this if your device is jailbroken untethered!!!"
                print "* This procedure will do step 6 of this tutorial: https://reddit.com/r/LegacyJailbreak/comments/13of20g/tutorial_new_restoringerasingwipingrescuing_a/"
                print "* Note that it may also be better to do this process manually instead by following the commands in the tutorial."
                print "* For iOS 8 devices, also remove this file if you will be doing it manually: /mnt2/mobile/Library/SpringBoard/LockoutStateJournal.plist"
                if (( device_proc >= 7 )); then
                    print "* If your device is on iOS 7, make sure to boot an iOS 8 ramdisk afterwards to fix booting."
                fi
                print "* When the device boots back up, trigger a restore by entering wrong passwords 10 times."
                read -p "$(input "Select Y to continue, N to go back (y/N) ")" opt
                if [[ $opt != 'Y' && $opt != 'y' ]]; then
                    continue
                fi
                $ssh -p $ssh_port root@127.0.0.1 "/sbin/mount_hfs /dev/disk0s1s1 /mnt1; /sbin/mount_hfs /dev/disk0s1s2 /mnt2; cp /com.apple.springboard.plist /mnt1/"
                $ssh -p $ssh_port root@127.0.0.1 "cd /mnt2/mobile/Library/Preferences; mv com.apple.springboard.plist com.apple.springboard.plist.bak; ln -s /com.apple.springboard.plist ./com.apple.springboard.plist"
                $ssh -p $ssh_port root@127.0.0.1 "rm /mnt2/mobile/Library/SpringBoard/LockoutStateJournal.plist"
                $ssh -p $ssh_port root@127.0.0.1 "sync; cd /; /sbin/umount /mnt2; /sbin/umount /mnt1; sync; /sbin/reboot"
                log "Done, your device should reboot now"
                print "* Proceed to trigger a restore by entering wrong passwords 10 times."
                loop=1
            ;;
            "dump-sep" )
                log "Please read the message below:"
                print "* To dump SEP Firmware, do the following:"
                print "    - Mount filesystems using the appropriate command for your iOS version (scroll up to see the commands)"
                print "    - Grab the file sep-firmware.img4 from /mnt1/usr/standalone or /mnt1/usr/standalone/firmware"
                print "* Better do this process manually since Legacy iOS Kit does not know your iOS version"
                pause
            ;;
            "clearnvram" )
                log "Sending command for clearing NVRAM..."
                $ssh -p $ssh_port root@127.0.0.1 "/usr/sbin/nvram -c"
                log "Done"
            ;;
            "erase9" )
                warn "This will do a \"Erase All Content and Settings\" procedure for iOS 9+ devices."
                warn "Do NOT do this if your device is jailbroken untethered!!! (mostly iOS 9.3.4/9.1 and lower)"
                read -p "$(input "Select Y to continue, N to go back (y/N) ")" opt
                if [[ $opt != 'Y' && $opt != 'y' ]]; then
                    continue
                fi
                log "Sending command for erasing all content and settings..."
                $ssh -p $ssh_port root@127.0.0.1 "nvram oblit-inprogress=5"
                log "Done. Reboot to apply changes, or clear NVRAM now to cancel erase"
            ;;
            "remove4" ) device_ramdisk_setnvram;;
            "datetime" ) device_ramdisk_datetime;;
        esac
    done
}

shsh_save_onboard64() {
    print "* There are other ways for dumping onboard blobs for 64-bit devices as listed below:"
    print "* It is recommended to use SSH Ramdisk option to dump onboard blobs instead: Other Utilities -> SSH Ramdisk"
    print "* For A8 and newer, you can also use SSHRD_Script: https://github.com/verygenericname/SSHRD_Script"
    echo
    if [[ $device_mode != "Normal" ]]; then
        warn "Device must be in normal mode and jailbroken, cannot continue."
        print "* Use the SSH Ramdisk option instead."
        return
    fi
    log "Proceeding to dump onboard blobs on normal mode"
    device_ssh_message
    device_iproxy
    device_sshpass
    local shsh="../saved/shsh/$device_ecid-$device_type-$device_vers-$device_build.shsh"
    $ssh -p $ssh_port root@127.0.0.1 "cat /dev/disk1" | dd of=dump.raw bs=256 count=$((0x4000))
    "$dir/img4tool" --convert -s $shsh dump.raw
    if [[ ! -s $shsh ]]; then
        warn "Failed to convert raw dump to SHSH."
        if [[ -s dump.raw ]]; then
            local raw="../saved/shsh/rawdump_${device_ecid}-${device_type}-${device_vers}-${device_build}_$(date +%Y-%m-%d-%H%M).raw"
            mv dump.raw $raw
            log "Raw dump saved at: $raw"
            warn "This raw dump is not usable for restoring, you need to convert it first."
            print "* If unable to be converted, this dump is likely not usable for restoring."
        fi
        error "Saving onboard SHSH blobs failed." "It is recommended to dump onboard SHSH blobs on SSH Ramdisk instead."
    fi
    log "Successfully saved $device_vers blobs: $shsh"
}

shsh_save_onboard() {
    if (( device_proc >= 7 )); then
        shsh_save_onboard64
        return
    elif [[ $device_proc == 4 ]] || [[ $device_proc == 6 && $platform == "macos" ]]; then
        device_buttons
    else
        device_enter_mode kDFU
    fi
    if [[ $device_proc == 4 && $device_pwnrec != 1 ]]; then
        patch_ibss
        log "Sending iBSS..."
        $irecovery -f pwnediBSS.dfu
    fi
    sleep 1
    patch_ibec
    log "Sending iBEC..."
    $irecovery -f pwnediBEC.dfu
    if [[ $device_pwnrec == 1 ]]; then
        $irecovery -c "go"
    fi
    sleep 3
    device_find_mode Recovery
    log "Dumping raw dump now"
    (echo -e "/send ../resources/payload\ngo blobs\n/exit") | $irecovery2 -s
    $irecovery2 -g dump.raw
    log "Rebooting device"
    $irecovery -n
    local raw
    local err
    shsh_convert_onboard $1
    err=$?
    if [[ $1 == "dump" ]]; then
        raw="../saved/shsh/rawdump_${device_ecid}-${device_type}_$(date +%Y-%m-%d-%H%M)_${shsh_onboard_iboot}.raw"
    else
        raw="../saved/shsh/rawdump_${device_ecid}-${device_type}-${device_target_vers}-${device_target_build}_$(date +%Y-%m-%d-%H%M)_${shsh_onboard_iboot}.raw"
    fi
    if [[ $1 == "dump" ]] || [[ $err != 0 && -s dump.raw ]]; then
        mv dump.raw $raw
        log "Raw dump saved at: $raw"
        warn "This raw dump is not usable for restoring, you need to convert it first."
        print "* If unable to be converted, this dump is likely not usable for restoring."
        print "* For the IPSW to download and use, see the raw dump iBoot version above"
        print "* Then go here to find the matching iOS version: https://theapplewiki.com/wiki/IBoot_(Bootloader)"
    fi
}

shsh_convert_onboard() {
    local shsh="../saved/shsh/${device_ecid}-${device_type}_$(date +%Y-%m-%d-%H%M).shsh"
    if (( device_proc < 7 )); then
        shsh="../saved/shsh/${device_ecid}-${device_type}-${device_target_vers}-${device_target_build}.shsh"
        # remove ibob for powdersn0w/dra downgraded devices. fixes unknown magic 69626f62
        local blob=$(xxd -p dump.raw | tr -d '\n')
        local bobi="626f6269"
        local blli="626c6c69"
        if [[ $blob == *"$bobi"* ]]; then
            log "Detected \"ibob\". Fixing... (This happens on DRA/powdersn0w downgraded devices)"
            rm -f dump.raw
            printf "%s" "${blob%"$bobi"*}${blli}${blob##*"$blli"}" | xxd -r -p > dump.raw
        fi
        shsh_onboard_iboot="$(cat dump.raw | strings | grep iBoot | head -1)"
        log "Raw dump iBoot version: $shsh_onboard_iboot"
        if [[ $1 == "dump" ]]; then
            return
        fi
        log "Converting raw dump to SHSH blob"
        "$dir/ticket" dump.raw dump.shsh "$ipsw_path.ipsw" -z
        log "Attempting to validate SHSH blob"
        "$dir/validate" dump.shsh "$ipsw_path.ipsw" -z
        if [[ $? != 0 ]]; then
            warn "Saved SHSH blobs might be invalid. Did you select the correct IPSW?"
        fi
    else
        "$dir/img4tool" --convert -s dump.shsh dump.raw
    fi
    if [[ ! -s dump.shsh ]]; then
        warn "Converting onboard SHSH blobs failed."
        return 1
    fi
    mv dump.shsh $shsh
    log "Successfully saved $device_target_vers blobs: $shsh"
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
        $tsschecker -d $device_type -e $device_ecid --server-url "http://cydia.saurik.com/TSS/controller?action=2/" -s -g 0x1111111111111111 --buildid $build >/dev/null
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
    print "* Platform: $platform ($platform_ver - $platform_arch) $live_cdusb_str"
    echo
    print "* Device: $device_name (${device_type} - ${device_model}ap) in $device_mode mode"
    device_manufacturing
    if [[ $device_unactivated == 1 ]]; then
        print "* Device is not activated, select Attempt Activation to activate."
    fi
    if [[ $device_type == "$device_disable_bbupdate" && $device_use_bb != 0 ]] && (( device_proc < 7 )); then
        warn "Disable bbupdate flag detected, baseband update is disabled. Proceed with caution"
        if [[ $device_deadbb == 1 ]]; then
            warn "dead-bb flag detected, baseband dump/stitching is disabled. Your device will not activate after restore"
        else
            print "* Current device baseband will be dumped and stitched to custom IPSW"
            print "* Stitching is supported in these restores/downgrades: 8.4.1/6.1.3, Other (tethered or with SHSH), powdersn0w"
            warn "Note that stitching baseband does not always work! There is a chance of non-working baseband after the restore"
        fi
    elif [[ -n $device_disable_bbupdate ]]; then
        warn "Disable bbupdate flag detected, but this flag is not supported for this device"
    fi
    if [[ -n $device_disable_bbupdate ]]; then
        print "* For more details, go to: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Baseband-Update"
    fi
    if [[ $ipsw_jailbreak == 1 ]] && (( device_proc < 7 )); then
        warn "Jailbreak flag detected. Jailbreak option enabled."
    fi
    if [[ $device_proc != 1 ]] && (( device_proc < 7 )); then
        if [[ $device_actrec == 1 ]]; then
            warn "Activation records flag detected. Proceed with caution"
            print "* Stitching is supported in these restores/downgrades: 8.4.1/6.1.3, Other with SHSH, powdersn0w"
        fi
        if [[ $device_pwnrec == 1 ]]; then
            warn "Pwned recovery flag detected. Assuming device is in pwned recovery mode."
        elif [[ $device_skip_ibss == 1 ]]; then
            warn "Skip iBSS flag detected. Assuming device is in pwned iBSS mode."
        fi
        if [[ $ipsw_gasgauge_patch == 1 ]]; then
            warn "gasgauge-patch flag detected. multipatch enabled."
            print "* This supports up to iOS 8.4.1 only. iOS 9 will not work"
        fi
        if [[ $ipsw_skip_first == 1 ]]; then
            warn "skip-first flag detected. Skipping first restore and flashing NOR IPSW only for powdersn0w 4.2.x and lower"
        fi
    elif (( device_proc >= 7 )) && (( device_proc <= 10 )); then
        if [[ $restore_useskipblob == 1 ]]; then
            warn "skip-blob flag detected. futurerestore will have --skip-blob enabled."
        fi
        if [[ $restore_usepwndfu64 == 1 ]]; then
            warn "use-pwndfu flag detected. futurerestore will have --use-pwndfu enabled."
        fi
    fi
    if [[ -n $device_build ]]; then
        print "* iOS Version: $device_vers ($device_build)"
    else
        print "* iOS Version: $device_vers"
    fi
    if [[ $device_proc != 1 && $device_mode == "DFU" ]] && (( device_proc < 7 )); then
        print "* To get iOS version, go to: Other Utilities -> Get iOS Version"
    fi
    if [[ $device_proc != 1 ]]; then
        print "* ECID: $device_ecid"
    fi
    if [[ -n $device_pwnd ]]; then
        print "* Pwned: $device_pwnd"
    fi
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
            if (( device_proc < 7 )); then
                menu_items+=("Jailbreak Device")
                if [[ $device_proc != 1 && $device_type != "iPod2,1" ]]; then
                    case $device_mode in
                        "Recovery" | "DFU" ) menu_items+=("Just Boot");;
                    esac
                fi
            fi
            if [[ $device_unactivated == 1 ]]; then
                menu_items+=("Attempt Activation")
            elif [[ $device_mode == "Recovery" ]]; then
                menu_items+=("Exit Recovery Mode")
            fi
            case $device_type in
                iPad2,[123] ) menu_items+=("FourThree Utility");;
            esac
        fi
        if [[ $device_proc != 1 && $device_type != "iPod2,1" ]]; then
            menu_items+=("Save SHSH Blobs")
        fi
        if [[ $device_mode == "Normal" ]]; then
            case $device_vers in
                [12].*  ) :;;
                [1289]* ) menu_items+=("Sideload IPA");;
            esac
            menu_items+=("App Management" "Data Management" "Device Management")
        fi
        menu_items+=("Other Utilities" "Exit")
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Restore/Downgrade" ) menu_restore;;
            "Jailbreak Device" ) device_jailbreak_confirm;;
            "Save SHSH Blobs" ) menu_shsh;;
            "Sideload IPA" ) menu_ipa "$selected";;
            "App Management" ) menu_appmanage;;
            "Data Management" ) menu_datamanage;;
            "Device Management" ) menu_devicemanage;;
            "Other Utilities" ) menu_other;;
            "FourThree Utility" ) menu_fourthree;;
            "Attempt Activation" ) device_activate;;
            "Exit Recovery Mode" ) mode="exitrecovery";;
            "Just Boot" ) menu_justboot;;
            "Exit" ) mode="exit";;
        esac
    done
}

menu_appmanage() {
    local menu_items
    local selected
    local back

    menu_print_info
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Install IPA (AppSync)" "List User Apps" "List System Apps" "List All Apps" "Go Back")
        print " > Main Menu > App Management"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Install IPA (AppSync)" ) menu_ipa "$selected";;
            "List User Apps"   ) $ideviceinstaller list --user;;
            "List System Apps" ) $ideviceinstaller list --system;;
            "List All Apps"    ) $ideviceinstaller list --all;;
            "Go Back" ) back=1;;
        esac
    done
}

menu_datamanage() {
    local menu_items=()
    local selected
    local back

    menu_print_info
    print "* Note: For \"Raw File System\" your device must be jailbroken and have AFC2"
    print "*       For most jailbreaks, install \"Apple File Conduit 2\" in Cydia/Zebra/Sileo"
    print "* Note 2: The \"Erase All Content and Settings\" option works on iOS 9+ only"
    print "* Note 3: You may need to select Pair Device first to get some options working."
    print "* Note 4: Backups do not include apps. Only some app data and settings"
    print "* For dumping apps, go to: https://www.reddit.com/r/LegacyJailbreak/wiki/guides/crackingapps"
    if (( device_det < 4 )) && [[ $device_det != 1 ]]; then
        warn "Device is on lower than iOS 4. Backup and Restore options are not available."
    else
        menu_items+=("Backup" "Restore")
    fi
    if [[ -z $ifuse ]]; then
        warn "ifuse not installed. Mount Device options are not available. Install ifuse in Homebrew/MacPorts or your package manager to fix this"
    else
        menu_items+=("Mount Device" "Mount Device (Raw File System)" "Unmount Device")
    fi
    menu_items+=("Connect to SSH" "Cydia App Install")
    case $device_det in
        [91] ) menu_items+=("Erase All Content and Settings");;
    esac
    menu_items+=("Pair Device" "Go Back")
    while [[ -z "$mode" && -z "$back" ]]; do
        echo
        print " > Main Menu > Data Management"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Go Back" ) back=1;;
            "Backup"  ) mode="device_backup_create";;
            "Restore" ) menu_backup_restore;;
            "Erase All Content and Settings" ) mode="device_erase";;
            "Mount Device" ) mkdir ../mount 2>/dev/null; $ifuse ../mount; log "Device (Media) should now be mounted on mount folder";;
            "Mount Device (Raw File System)" ) mkdir ../mount 2>/dev/null; $ifuse --root ../mount; log "Device (root) should now be mounted on mount folder";;
            "Unmount Device" ) log "Attempting to umount device from mount folder"; umount ../mount;;
            "Connect to SSH" ) device_ssh;;
            "Cydia App Install" )
                echo
                print "* Cydia App Install: You need to have working AFC2 or SSH for transferring the .deb files to your device."
                print "* This must be done manually. Place the .deb files you want to install to this path:"
                print "    > /var/root/Media/Cydia/AutoInstall"
                print "* Using the \"Mount Device (Raw File System)\" or \"Connect to SSH\" options."
                print "* Create the folders as needed if they do not exist."
                print "* Reboot your device after transferring the .deb files to start the installation."
                echo
            ;;
            "Pair Device" ) device_pair;;
        esac
    done
}

menu_backup_restore() {
    local menu_items
    local selected
    local back

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_print_info
        local backupdir="../saved/backups/${device_ecid}_${device_type}"
        if [[ ! -d $backupdir ]]; then
            mkdir -p $backupdir
        fi
        local backups=($(ls $backupdir 2>/dev/null))
        if [[ -z "${backups[*]}" ]]; then
            print "* No backups (saved/backups)"
        else
            print "* Backups list (saved/backups):"
            for b in "${backups[@]}"; do
                menu_items+=("$(basename $b)")
            done
        fi
        menu_items+=("Go Back")
        echo
        print " > Main Menu > Data Management > Restore"
        input "Select option to restore:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Go Back" ) back=1;;
            * ) device_backup="$selected"; mode="device_backup_restore";;
        esac
    done
}

menu_fourthree() {
    local menu_items
    local selected
    local back

    ipa_path=
    ipsw_fourthree=
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Step 1: Restore" "Step 2: Partition" "Step 3: OS Install")
        if [[ $device_mode == "Normal" ]]; then
            menu_items+=("Reinstall App" "Boot iOS 4.3.x")
        fi
        menu_items+=("Go Back")
        menu_print_info
        print "* FourThree Utility: Dualboot iPad 2 to iOS 4.3.x"
        print "* This is a 3 step process for the device. Follow through the steps to successfully set up a dualboot."
        print "* Please read the README here: https://github.com/LukeZGD/FourThree-iPad2"
        echo
        print " > Main Menu > FourThree Utility"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Step 1: Restore" ) ipsw_fourthree=1; menu_ipsw "iOS 6.1.3" "fourthree";;
            "Step 2: Partition" ) mode="device_fourthree_step2";;
            "Step 3: OS Install" ) mode="device_fourthree_step3";;
            "Reinstall App" ) mode="device_fourthree_app";;
            "Boot iOS 4.3.x" ) mode="device_fourthree_boot";;
            "Go Back" ) back=1;;
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
            print "* Make sure that AppSync Unified (iOS 5+) is installed on your device."
        else
            print "* Sideload IPA is for iOS 9 and newer only. Sideloading will require an Apple ID."
            print "* Your Apple ID and password will only be sent to Apple servers."
            print "* Make sure that the device is activated and connected to the Internet."
            print "* There is also the option to use Dadoum Sideloader: https://github.com/Dadoum/Sideloader"
            print "* If you have AppSync installed, go to App Management -> Install IPA (AppSync) instead."
            if [[ $platform == "macos" ]]; then
                echo
                warn "\"Sideload IPA\" is currently not supported on macOS."
                print "* Use Sideloadly or AltServer instead for this."
                print "* You also might be looking for the \"Install IPA (AppSync)\" option instead."
                pause
                break
            fi
        fi
        echo
        if [[ -n $ipa_path ]]; then
            print "* Selected IPA: $ipa_path"
            menu_items+=("Install IPA")
        elif [[ $1 == "Install"* ]]; then
            print "* Select IPA files to install (multiple selection)"
        else
            print "* Select IPA file to install (or select Use Dadoum Sideloader)"
            menu_items+=("Use Dadoum Sideloader")
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
                    mode="device_ideviceinstaller"
                else
                    mode="device_altserver"
                fi
            ;;
            "Use Dadoum Sideloader" )
                local arch="$platform_arch"
                local sideloader="sideloader-gtk-"
                case $arch in
                    "armhf" )
                        warn "Dadoum Sideloader does not support armhf/armv7. arm64 or x86_64 only."
                        pause
                        continue
                    ;;
                    "arm64" ) arch="aarch64";;
                esac
                sideloader+="$arch-linux-gnu"
                log "Checking for latest Sideloader"
                local latest="$(curl https://api.github.com/repos/Dadoum/Sideloader/releases | $jq -r ".[0].tag_name")"
                local current="$(cat ../saved/Sideloader_version 2>/dev/null || echo "none")"
                log "Latest version: $latest, current version: $current"
                if [[ $current != "$latest" ]]; then
                    rm -f ../saved/$sideloader
                fi
                if [[ ! -e ../saved/$sideloader ]]; then
                    download_file https://github.com/Dadoum/Sideloader/releases/download/$latest/$sideloader.zip $sideloader.zip
                    unzip -o -j $sideloader.zip $sideloader -d ../saved
                fi
                echo "$latest" > ../saved/Sideloader_version
                device_pair
                log "Launching Dadoum Sideloader"
                chmod +x ../saved/$sideloader
                ../saved/$sideloader
            ;;
            "Go Back" ) back=1;;
        esac
    done
}

menu_zenity_check() {
    if [[ $platform == "linux" && ! $(command -v zenity) ]]; then
        warn "zenity not found in PATH. Install zenity to have a working file picker."
    fi
}

menu_ipa_browse() {
    local newpath
    input "Select your IPA file(s) in the file selection window."
    if [[ $mac_cocoa == 1 ]]; then
        newpath="$($cocoadialog fileselect --with-extensions ipa)"
    else
        menu_zenity_check
        newpath="$($zenity --file-selection --multiple --file-filter='IPA | *.ipa' --title="Select IPA file(s)")"
    fi
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
            iPad[23]* | iPhone4,1 | iPhone5,[12] | iPod5,1 )
                menu_items+=("iOS 8.4.1");;
        esac
        case $device_type in
            iPad2,[123] | iPhone4,1 )
                menu_items+=("iOS 6.1.3");;
        esac
        if (( device_proc < 7 )); then
            menu_items+=("Cydia Blobs")
        fi
        if [[ $device_mode != "none" ]]; then
            menu_items+=("Onboard Blobs")
            if (( device_proc < 7 )); then
                menu_items+=("Onboard Blobs (Raw Dump)")
            fi
        fi
        menu_items+=("Convert Raw Dump" "Go Back")
        menu_print_info
        if [[ $device_mode != "none" && $device_proc == 4 ]]; then
            warn "Dumping onboard blobs might not work for this device, proceed with caution"
            print "* Legacy iOS Kit only fully supports dumping onboard blobs for A5(X) and A6(X) devices and newer"
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
            "Onboard Blobs (Raw Dump)" ) mode="save-onboard-dump";;
            "Cydia Blobs" ) mode="save-cydia-blobs";;
            "Convert Raw Dump" ) menu_shsh_convert;;
            "Go Back" ) back=1;;
        esac
    done
}

menu_shsh_onboard() {
    local menu_items
    local selected
    local back

    ipsw_path=
    if (( device_proc >= 7 )); then
        mode="save-onboard-blobs"
    fi
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Select IPSW")
        menu_print_info
        if [[ $device_mode != "none" && $device_proc == 4 ]]; then
            warn "Dumping onboard blobs might not work for this device, proceed with caution"
            print "* Legacy iOS Kit only fully supports dumping onboard blobs for A5(X) and A6(X) devices and newer"
            echo
        fi
        if [[ -n $ipsw_path ]]; then
            print "* Selected IPSW: $ipsw_path.ipsw"
            print "* IPSW Version: $device_target_vers-$device_target_build"
            if [[ $device_mode == "Normal" && $device_target_vers != "$device_vers" ]]; then
                warn "Selected IPSW does not seem to match the current version."
                if (( device_proc < 7 )); then
                    print "* Ignore this warning if this is a DRA/powdersn0w downgraded device."
                fi
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

menu_shsh_convert() {
    local menu_items
    local selected
    local back

    ipsw_path=
    shsh_path=
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Select Raw Dump")
        menu_print_info
        if [[ -n $shsh_path ]]; then
            print "* Selected dump: $shsh_path"
            if (( device_proc < 7 )); then
                shsh_onboard_iboot="$(cat "$shsh_path" | strings | grep iBoot | head -1)"
                print "* Raw dump iBoot version: $shsh_onboard_iboot"
                print "* Go here to find the matching iOS version: https://theapplewiki.com/wiki/IBoot_(Bootloader)"
                menu_items+=("Select IPSW")
            else
                menu_items+=("Convert Raw Dump")
            fi
        else
            print "* Select raw dump file to continue"
        fi
        if [[ -n $ipsw_path ]]; then
            echo
            print "* Selected IPSW: $ipsw_path.ipsw"
            print "* IPSW Version: $device_target_vers-$device_target_build"
            menu_items+=("Convert Raw Dump")
        elif (( device_proc < 7 )); then
            echo
            print "* Select IPSW of the raw dump's iOS version to continue"
        fi
        menu_items+=("Go Back")
        echo
        print " > Main Menu > Save SHSH Blobs > Convert Raw Dump"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Select IPSW" ) menu_ipsw_browse;;
            "Select Raw Dump" ) menu_shshdump_browse;;
            "Convert Raw Dump" ) mode="convert-onboard-blobs";;
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
            iPhone1,2 | iPod2,1 )
                menu_items+=("4.1" "3.1.3");;
        esac
        case $device_type in
            iPhone3,[13] | iPad1,1 | iPod3,1 )
                menu_items+=("powdersn0w (any iOS)");;
        esac
        if (( device_proc < 7 )); then
            menu_items+=("Latest iOS ($device_latest_vers)")
        elif [[ $platform == "linux" ]]; then
            if (( device_proc > 10 )); then
                menu_items+=("Latest iOS")
            else
                menu_items+=("Latest iOS ($device_latest_vers)")
            fi
        fi
        case $device_type in
            iPhone4,1 | iPhone5,[1234] | iPad2,4 | iPod5,1 )
                local text2="7.1.x"
                case $device_type in
                    iPhone5,[1234] ) text2="7.x";;
                esac
                menu_items+=("Other (powdersn0w $text2 blobs)")
            ;;
            iPhone1,[12] | iPhone2,1 | iPhone3,[23] | iPod[1234],1 )
                if [[ -z $1 ]]; then
                    menu_items+=("Other (Custom IPSW)")
                fi
            ;;
        esac
        if [[ $device_proc != 1 ]]; then
            if [[ $device_type != "iPod2,1" ]] && (( device_proc <= 10 )); then
                menu_items+=("Other (Use SHSH Blobs)")
            fi
            if (( device_proc >= 7 )) && (( device_proc <= 10 )); then
                menu_items+=("Set Nonce Only")
            elif [[ $device_proc == 5 || $device_proc == 6 ]]; then
                menu_items+=("Other (Tethered)")
            fi
            case $device_type in
                iPhone3,[23] | iPod[34],1 ) menu_items+=("Other (Tethered)");;
            esac
            if (( device_proc < 7 )); then
                menu_items+=("DFU IPSW")
            fi
        fi
        menu_items+=("IPSW Downloader" "Go Back")
        menu_print_info
        if [[ $1 == "ipsw" ]]; then
            print " > Main Menu > Other Utilities > Create Custom IPSW"
        else
            print " > Main Menu > Restore/Downgrade"
        fi
        if [[ -z $1 ]]; then
            if [[ $device_proc == 1 ]]; then
                print "* Select \"Other (Custom IPSW)\" to restore to other iOS versions (2.0 to 3.1.2)"
                echo
            fi
            if [[ $device_type == "iPod2,1" ]]; then
                print "* Select \"Other (Custom IPSW)\" to restore to other iOS versions (2.1.1 to 3.0)"
                echo
            fi
            if [[ $device_type == "iPod2,1" || $device_type == "iPhone2,1" ]] && [[ $device_newbr != 0 ]]; then
                print "* New bootrom devices might be incompatible with older iOS versions"
                echo
            fi
        fi
        case $device_type in
            iPad2,4      ) print "* iPad2,4 does not support 6.1.3 downgrades, you need blobs for 6.1.3 or 7.1.x"; echo;;
            iPhone5,[34] ) print "* iPhone 5C does not support 8.4.1 downgrades, you need blobs for 8.4.1 or 7.x"; echo;;
            iPhone3,2    ) print "* iPhone3,2 does not support downgrades with powdersn0w"; echo;;
            iPod4,1      ) print "* iPod touch 4 does not support any untethered downgrades without blobs"; echo;;
        esac
        if [[ $platform == "macos" ]] && (( device_proc >= 7 )); then
            print "* Note: Restoring to latest iOS for 64-bit devices is not supported on macOS, use iTunes/Finder instead for that"
            if [[ $mac_cocoa == 1 ]]; then
                warn "Restoring 64-bit devices is broken on OS X 10.11 El Capitan. Use macOS 10.12 Sierra or newer for this."
                pause
                break
            fi
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
            "Other (Custom IPSW)" ) mode="customipsw";;
            "DFU IPSW" ) mode="dfuipsw${1}";;
            "More versions" ) menu_restore_more "$1";;
            "Latest iOS" ) mode="restore-latest";;
            "IPSW Downloader" ) menu_ipsw_downloader "$1";;
            * ) menu_ipsw "$selected" "$1";;
        esac
    done
}

menu_ipsw_downloader() {
    local menu_items
    local selected
    local back
    local vers

    while [[ -z "$back" ]]; do
        menu_items=("Enter Build Version")
        if [[ -n $vers ]]; then
            menu_items+=("Start Download")
        fi
        menu_items+=("Go Back")
        menu_print_info
        if [[ $1 == "ipsw" ]]; then
            print " > Main Menu > Other Utilities > Create Custom IPSW > IPSW Downloader"
        else
            print " > Main Menu > Restore/Downgrade > IPSW Downloader"
        fi
        print "* To know more about build version, go here: https://theapplewiki.com/wiki/Firmware"
        if [[ -n $vers ]]; then
            print "* Build Version entered: $vers"
        else
            print "* Enter build version to continue"
        fi
        echo
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Enter Build Version" )
                print "* Enter the build version of the IPSW you want to download."
                device_enter_build
                vers="$device_rd_build"
            ;;
            "Start Download" )
                device_target_build="$vers"
                ipsw_download
                log "IPSW downloading is done"
                pause
            ;;
            "Go Back" ) back=1;;
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
                menu_items+=("4.3.5" "4.3.4" "4.3.2" "4.3.1" "4.3" "4.2.1")
                menu_items+=("4.0.2" "4.0.1" "4.0" "3.1.2" "3.1" "3.0.1" "3.0")
            ;;
            iPod2,1 ) menu_items+=("4.0.2" "4.0" "3.1.2" "3.1.1");;
        esac
        menu_items+=("Go Back")
        menu_print_info
        if [[ $1 == "ipsw" ]]; then
            print " > Main Menu > Other Utilities > Create Custom IPSW"
        else
            print " > Main Menu > Restore/Downgrade"
        fi
        if [[ -z $1 && $device_type == "iPod2,1" && $device_newbr != 0 ]]; then
            warn "These versions are for old bootrom devices only. They may not work on your device"
            echo
        elif [[ $device_type == "iPod2,1" ]]; then
            warn "These versions might not restore/boot properly"
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

ipsw_latest_set() {
    local newpath
    case $device_type in
        iPad3,[456]    ) newpath="iPad_32bit";;
        iPad4,[123456] ) newpath="iPad_64bit";;
        iPad6,[34]     ) newpath="iPadPro_9.7";;
        iPad6,[78]     ) newpath="iPadPro_12.9";;
        iPad6,1[12]    ) newpath="iPad_64bit_TouchID_ASTC";;
        iPhone5,[1234] ) newpath="iPhone_4.0_32bit";;
        iPhone10,[36]  ) newpath="iPhone10,3,iPhone10,6";;
        iPod[79],1     ) newpath="iPodtouch";;
        iPad4,[789] | iPad5*     ) newpath="iPad_64bit_TouchID";;
        iPhone6,[12] | iPhone8,4 ) newpath="iPhone_4.0_64bit";;
        iPhone7,1 | iPhone8,2    ) newpath="iPhone_5.5";;
        iPhone7,2 | iPhone8,1    ) newpath="iPhone_4.7";;
        iPhone9,[13] | iPhone10,[14] ) newpath="iPhone_4.7_P3";;
        iPhone9,[24] | iPhone10,[25] ) newpath="iPhone_5.5_P3";;
        * ) newpath="${device_type}";;
    esac
    device_type2="$newpath"
    newpath+="_${device_target_vers}_${device_target_build}"
    ipsw_custom_set $newpath
    ipsw_dfuipsw="../${newpath}_DFUIPSW"
    newpath+="_Restore"
    ipsw_latest_path="$newpath"
}

ipsw_hwmodel_set() {
    local hwmodel
    case $device_type in
        iPhone5,[12] ) hwmodel="iphone5";;
        iPhone5,[34] ) hwmodel="iphone5b";;
        iPad3,[456] ) hwmodel="ipad3b";;
        iPhone6*    ) hwmodel="iphone6";;
        iPhone7*    ) hwmodel="iphone7";;
        iPhone8,4   ) hwmodel="iphone8b";;
        iPhone8*    ) hwmodel="iphone8";;
        iPhone9*    ) hwmodel="iphone9";;
        iPad4,[123] ) hwmodel="ipad4";;
        iPad4,[456] ) hwmodel="ipad4b";;
        iPad4,[789] ) hwmodel="ipad4bm";;
        iPad5,[12]  ) hwmodel="ipad5";;
        iPad5,[34]  ) hwmodel="ipad5b";;
        iPad6,[34]  ) hwmodel="ipad6b";;
        iPad6,[78]  ) hwmodel="ipad6d";;
        *           ) hwmodel="$device_model";;
    esac
    ipsw_hwmodel="$hwmodel"
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
    elif [[ $2 == "fourthree" ]]; then
        nav=" > Main Menu > FourThree Utility > Step 1: Restore"
        start="Start Restore"
    elif [[ $1 == "Set Nonce Only" ]]; then
        nav=" > Main Menu > Restore/Downgrade > $1"
        start="Set Nonce"
        device_target_setnonce=1
    else
        nav=" > Main Menu > Restore/Downgrade > $1"
        start="Start Restore"
    fi

    ipsw_cancustomlogo=
    ipsw_cancustomlogo2=
    ipsw_customlogo=
    ipsw_customrecovery=
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
                    [643]* ) ipsw_canhacktivate=1;;
                esac
            ;;
            [6543]* )
                device_target_vers="$1"
                if [[ $device_target_vers != "3.0"* ]]; then
                    ipsw_canhacktivate=1
                fi
                if [[ $device_type == "iPhone2,1" && $1 != "4.1" ]]; then
                    ipsw_cancustomlogo=1
                fi
            ;;
        esac
        if [[ $device_type != "iPhone"* ]]; then
            ipsw_canhacktivate=
        fi
        if [[ $device_proc == 1 ]]; then
            ipsw_cancustomlogo=1
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
            ipsw_latest_set
            newpath="$ipsw_latest_path"
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
        if [[ $1 == "Other (Use SHSH Blobs)" || $1 == "Set Nonce Only" ]]; then
            device_target_other=1
            if [[ $device_type == "iPhone2,1" ]]; then
                ipsw_canhacktivate=1
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
        print "* Only select unmodified IPSW for the selection. Do not select custom IPSWs"
        echo
        if [[ $1 == *"powdersn0w"* ]]; then
            menu_items+=("Select Base IPSW")
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                print "* Target Version: $device_target_vers-$device_target_build"
                ipsw_print_warnings powder
                ipsw_cancustomlogo2=
                case $device_target_vers in
                    [456]* ) ipsw_cancustomlogo2=1;;
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
                    iPad1,1 ) lo=3.2; hi=5.1;;
                    iPod3,1 ) lo=4.0; hi=5.1;;
                esac
                print "* Any iOS version from $lo to $hi is supported"
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
                if [[ $ipsw_base_validate == 0 ]]; then
                    print "* Selected Base IPSW is validated"
                else
                    warn "Selected Base IPSW failed validation, proceed with caution"
                fi
                if [[ $device_proc != 4 ]]; then
                    menu_items+=("Select Base SHSH")
                fi
                echo
            else
                print "* Select Base $text2 IPSW to continue"
                echo
            fi
            if [[ $device_proc == 4 ]]; then
                shsh_path=1
            else
                if [[ -n $shsh_path ]]; then
                    print "* Selected Base $text2 SHSH: $shsh_path"
                    if [[ $shsh_validate == 0 ]]; then
                        print "* Selected SHSH file is validated"
                    else
                        warn "Selected SHSH file failed validation, proceed with caution"
                        if (( device_proc < 5 )); then
                            warn "Validation might be a false negative for A4 and older devices."
                        fi
                        echo
                    fi
                elif [[ $2 != "ipsw" ]]; then
                    print "* Select Base $text2 SHSH to continue"
                    echo
                fi
            fi
            if [[ -n $ipsw_path && -n $ipsw_base_path ]] && [[ -n $shsh_path || $2 == "ipsw" ]]; then
                menu_items+=("$start")
            fi

        elif [[ $2 == "fourthree" ]]; then
            menu_items+=("Download Target IPSW" "Select Base IPSW")
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target (iOS 6.1.3) IPSW: $ipsw_path.ipsw"
                ipsw_print_warnings
            else
                print "* Select Target (iOS 6.1.3) IPSW to continue"
            fi
            echo
            if [[ -n $ipsw_base_path ]]; then
                print "* Selected Base (iOS 4.3.x) IPSW: $ipsw_base_path.ipsw"
                print "* Base Version: $device_base_vers-$device_base_build"
                if [[ $ipsw_base_validate == 0 ]]; then
                    print "* Selected Base IPSW is validated"
                else
                    warn "Selected Base IPSW failed validation, proceed with caution"
                fi
                echo
            else
                print "* Select Base (iOS 4.3.x) IPSW to continue"
                echo
            fi
            if [[ -n $ipsw_path && -n $ipsw_base_path ]]; then
                menu_items+=("$start")
            fi

        elif [[ $1 == *"Tethered"* ]]; then
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                print "* Target Version: $device_target_vers-$device_target_build"
                ipsw_print_warnings
            else
                print "* Select Target IPSW to continue"
            fi
            warn "This is a tethered downgrade. Not recommended unless you know what you are doing."
            print "* For more info, go to: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Restore-Downgrade and read the \"Other (Tethered)\" section"
            if [[ -n $ipsw_path ]]; then
                menu_items+=("$start")
            fi
            echo

        elif [[ $1 == "Other"* || $1 == "Set Nonce Only" ]]; then
            # menu for other (shsh) restores
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                print "* Target Version: $device_target_vers-$device_target_build"
                ipsw_print_warnings
                menu_items+=("Select Target SHSH")
            else
                print "* Select Target IPSW to continue"
            fi
            if (( device_proc > 6 )); then
                print "* Check the SEP/BB compatibility chart: https://docs.google.com/spreadsheets/d/1Mb1UNm6g3yvdQD67M413GYSaJ4uoNhLgpkc7YKi3LBs"
            fi
            echo
            if [[ -n $shsh_path ]]; then
                print "* Selected Target SHSH: $shsh_path"
                if (( device_proc > 6 )); then
                    shsh_generator=$(cat "$shsh_path" | grep "<string>0x" | cut -c10-27)
                    print "* Generator: $shsh_generator"
                fi
                if [[ $shsh_validate == 0 ]]; then
                    print "* Selected SHSH file is validated"
                else
                    warn "Selected SHSH file failed validation, proceed with caution"
                    if (( device_proc >= 7 )); then
                        print "* If this is an OTA/onboard/factory blob, it may be fine to use for restoring"
                    elif (( device_proc < 5 )); then
                        warn "Validation might be a false negative for A4 and older devices."
                    fi
                    echo
                fi
                if (( device_proc >= 7 )); then
                    print "* Note: For OTA/onboard/factory blobs, try enabling the skip-blob flag"
                    print "* The skip-blob flag can also help if the restore fails with validated blobs"
                fi
                echo

            elif [[ $2 != "ipsw" ]]; then
                print "* Select Target SHSH to continue"
                echo
            fi
            if [[ -n $ipsw_path ]] && [[ -n $shsh_path || $2 == "ipsw" ]]; then
                menu_items+=("$start")
            fi

        else
            # menu for ota/latest versions
            menu_items+=("Download Target IPSW")
            if [[ -n $ipsw_path ]]; then
                print "* Selected Target IPSW: $ipsw_path.ipsw"
                ipsw_print_warnings
                menu_items+=("$start")
            elif [[ $device_proc == 1 && $device_type != "iPhone1,2" ]]; then
                menu_items+=("$start")
            else
                print "* Select $1 IPSW to continue"
            fi
            if [[ $ipsw_canhacktivate == 1 ]] && [[ $device_type == "iPhone2,1" || $device_proc == 1 ]]; then
                print "* Hacktivation is supported for this restore"
            fi
            if [[ $device_latest_vers == "18"* ]]; then
                warn "Restoring to iOS 18 or newer is not supported. Try using pymobiledevice3 instead for that"
                pause
                return
            fi
            echo
        fi

        if [[ $ipsw_cancustomlogo2 == 1 ]]; then
            print "* You can select your own custom Apple logo image. This is optional and an experimental option"
            print "* Note: The images must be in PNG format, and up to 320x480 resolution only"
            print "* Note 2: The custom images might not work, current support is spotty"
            if [[ -n $ipsw_customlogo ]]; then
                print "* Custom Apple logo: $ipsw_customlogo"
            else
                print "* No custom Apple logo selected"
            fi
            menu_items+=("Select Apple Logo")
            echo
        elif [[ $ipsw_cancustomlogo == 1 ]]; then
            print "* You can select your own custom logo and recovery image. This is optional and an experimental option"
            print "* Note: The images must be in PNG format, and up to 320x480 resolution only"
            print "* Note 2: The custom images might not work, current support is spotty"
            if [[ -n $ipsw_customlogo ]]; then
                print "* Custom Apple logo: $ipsw_customlogo"
            else
                print "* No custom Apple logo selected"
            fi
            if [[ -n $ipsw_customrecovery ]]; then
                print "* Custom recovery logo: $ipsw_customrecovery"
            else
                print "* No custom recovery logo selected"
            fi
            menu_items+=("Select Apple Logo" "Select Recovery Logo")
            echo
        fi
        menu_items+=("Go Back")

        if [[ $device_use_bb != 0 && $device_type != "$device_disable_bbupdate" ]] &&
           (( device_proc > 4 )) && (( device_proc < 7 )); then
            print "* This restore will use $device_use_vers baseband"
            echo
        elif [[ $device_use_bb2 == 1 ]]; then
            if [[ $device_target_vers == "$device_latest_vers" ]]; then
                print "* This restore will use $device_use_vers baseband if the jailbreak option is disabled"
                echo
            elif [[ $device_proc == 1 || $device_target_vers == "4.1" ]] && [[ $device_type != "iPhone3"* ]]; then
                print "* This restore will have baseband update disabled if the jailbreak option is enabled"
                echo
            else
                print "* This restore will have baseband update disabled"
                echo
            fi
        elif [[ $device_use_bb2 == 2 ]]; then
            if [[ $device_target_vers == "$device_latest_vers" ]]; then
                print "* This restore will use $device_use_vers baseband"
                echo
            else
                print "* This restore will have baseband update disabled"
                echo
            fi
        fi

        print "$nav"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Create IPSW" ) mode="custom-ipsw";;
            "$start" ) mode="downgrade";;
            "Select Target IPSW" ) menu_ipsw_browse "$1";;
            "Select Base IPSW" ) menu_ipsw_browse "base";;
            "Select Target SHSH" ) menu_shsh_browse "$1";;
            "Select Base SHSH" ) menu_shsh_browse "base";;
            "Download Target IPSW" ) ipsw_download "../$newpath";;
            "Select Apple Logo" ) menu_logo_browse "boot";;
            "Select Recovery Logo" ) menu_logo_browse "recovery";;
            "Go Back" ) back=1;;
        esac
    done
}

ipsw_print_warnings() {
    if [[ $ipsw_validate == 0 ]]; then
        print "* Selected Target IPSW is validated"
    else
        warn "Selected Target IPSW failed validation, proceed with caution"
    fi
    if [[ $1 == "powder" ]]; then
        case $device_target_build in
            8[ABC]* ) warn "iOS 4.2.1 and lower are hit or miss. It may not restore/boot properly";;
            #7[CD]*  ) warn "Jailbreak option is not supported for this version. It is recommended to select 3.1.3 instead";;
            8E* ) warn "iOS 4.2.x for the CDMA 4 is not supported. It may not restore/boot properly";;
            8*  ) warn "Not all devices support iOS 4. It may not restore/boot properly";;
            7B* ) warn "Not all 3.2.x versions will work. It may not restore/boot properly";;
            7*  ) warn "iOS 3.1.x for the touch 3 is not supported. It will get stuck at the activation screen";;
        esac
        return
    fi
    case $device_type in
        "iPhone3"* )
            if [[ $device_target_vers == "4.2"* ]]; then
                warn "iOS 4.2.x for $device_type might fail to boot after the restore/jailbreak."
                print "* It is recommended to select another version instead."
            fi
        ;;
        "iPod4,1" )
            if [[ $device_target_vers == "4.2.1" ]]; then
                warn "iOS 4.2.1 for iPod4,1 might fail to boot after the restore/jailbreak."
                print "* It is recommended to select another version instead."
            elif [[ $device_target_build == "8B118" ]]; then
                warn "iOS 4.1 (8B118) for iPod4,1 might fail to boot after the restore/jailbreak."
                print "* It is recommended to select 8B117 or another version instead."
            fi
        ;;
        "iPhone2,1" )
            if [[ $device_target_vers == "3.0"* && $device_newbr != 0 ]]; then
                warn "3.0.x versions are for old bootrom devices only. It will fail to restore/boot if your device is not compatible."
                print "* It is recommended to select 3.1 or newer instead."
            fi
        ;;
    esac
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
    if [[ $ipsw_fourthree == 1 ]]; then
        ipsw_custom="../${device_type}_${device_target_vers}_${device_target_build}_FourThree"
        return
    fi

    ipsw_custom="../${device_type}_${device_target_vers}_${device_target_build}_Custom"
    if [[ -n $1 ]]; then
        ipsw_custom="../$1_Custom"
    fi

    if [[ $device_actrec == 1 ]]; then
        ipsw_custom+="A"
    fi
    if [[ $device_deadbb == 1 ]]; then
        ipsw_custom+="D"
    elif [[ $device_type == "$device_disable_bbupdate" ]]; then
        ipsw_custom+="B"
    fi
    if [[ $ipsw_gasgauge_patch == 1 ]]; then
        ipsw_custom+="G"
    fi
    if [[ $ipsw_hacktivate == 1 ]]; then
        ipsw_custom+="H"
    fi
    if [[ $ipsw_jailbreak == 1 ]]; then
        ipsw_custom+="J"
    fi
    if [[ $device_proc == 1 && $device_type != "iPhone1,2" ]]; then
        ipsw_custom2="$ipsw_custom"
    fi
    if [[ -n $ipsw_customlogo || -n $ipsw_customrecovery ]]; then
        ipsw_custom+="L"
        if [[ $device_proc == 1 && $device_type != "iPhone1,2" ]]; then
            ipsw_customlogo2=1
        fi
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
    if [[ $device_target_powder == 1 && $device_target_vers == "4.3"* ]]; then
        ipsw_custom+="-$device_ecid"
    fi
}

menu_logo_browse() {
    local newpath
    input "Select your $1 image file in the file selection window."
    if [[ $mac_cocoa == 1 ]]; then
        newpath="$($cocoadialog fileselect --with-extensions png)"
    else
        menu_zenity_check
        newpath="$($zenity --file-selection --file-filter='PNG | *.png' --title="Select $1 image file")"
    fi
    [[ ! -s "$newpath" ]] && read -p "$(input "Enter path to $1 image file (or press Ctrl+C to cancel): ")" newpath
    [[ ! -s "$newpath" ]] && return
    log "Selected $1 image file: $newpath"
    case $1 in
        "boot" ) ipsw_customlogo="$newpath";;
        "recovery" ) ipsw_customrecovery="$newpath";;
    esac
}

menu_ipsw_browse() {
    local versionc
    local newpath
    local text="Target"
    local picker

    local menu_items=($(ls ../$device_type*Restore.ipsw 2>/dev/null))
    if [[ $1 == "base" ]]; then
         text="Base"
         menu_items=()
         case $device_type in
            iPhone3,[13] ) menu_items=($(ls ../${device_type}_7.1.2*Restore.ipsw 2>/dev/null));;
            iPad1,1 | iPod3,1 ) menu_items=($(ls ../${device_type}_5.1.1*Restore.ipsw 2>/dev/null));;
            iPhone5* ) menu_items=($(ls ../${device_type}_7*Restore.ipsw 2>/dev/null));;
            * ) menu_items=($(ls ../${device_type}_7.1*Restore.ipsw 2>/dev/null));;
        esac
    fi
    case $1 in
        "iOS 10.3.3" ) versionc="10.3.3";;
        "iOS 8.4.1" ) versionc="8.4.1";;
        "iOS 6.1.3" ) versionc="6.1.3";;
        "Latest iOS"* ) versionc="$device_latest_vers";;
        [6543]* ) versionc="$1";;
    esac
    if [[ $versionc == "$device_latest_vers" ]]; then
        menu_items=()
    elif [[ -n $versionc ]]; then
        menu_items=($(ls ../${device_type}_${versionc}*Restore.ipsw 2>/dev/null))
    fi
    menu_items+=("Open File Picker" "Enter Path" "Go Back")

    if [[ "${menu_items[0]}" == *".ipsw" ]]; then
        print "* Select $text IPSW Menu"
        while true; do
            input "Select an option:"
            select opt in "${menu_items[@]}"; do
                selected="$opt"
                break
            done
            case $selected in
                "Open File Picker" ) picker=1; break;;
                "Enter Path" ) break;;
                *.ipsw ) newpath="$selected"; break;;
                "Go Back" ) return;;
            esac
        done
    else
        picker=1
    fi

    if [[ $picker == 1 ]]; then
        input "Select your $text IPSW file in the file selection window."
        if [[ $mac_cocoa == 1 ]]; then
            newpath="$($cocoadialog fileselect --with-extensions ipsw)"
        else
            menu_zenity_check
            newpath="$($zenity --file-selection --file-filter='IPSW | *Restore.ipsw' --title="Select $text IPSW file")"
        fi
    fi
    if [[ ! -s "$newpath" ]]; then
        print "* Enter the full path to the IPSW file to be used."
        print "* You may also drag and drop the IPSW file to the Terminal window."
        read -p "$(input "Path to $text IPSW file (or press Enter/Return or Ctrl+C to cancel): ")" newpath
    fi
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
            1[1234]* | 15[ABCD]* )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    elif [[ $device_proc == 7 ]]; then
        # SEP/BB check for iPhone 5S, iPad Air 1/mini 2
        case $device_target_build in
            1[123]* | 14A* | 15[ABCD]* )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    elif [[ $device_latest_vers == "15"* ]]; then
        # SEP/BB check for iPhone 6S/6S+/SE 2016/7/7+, iPad Air 2/mini 4, iPod touch 7
        case $device_target_build in
            1[234567]* )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    elif [[ $device_latest_vers == "16"* ]]; then
        case $device_target_build in
            20[GH]* ) :;; # 16.6 and newer only
            18[CDEFGH]* | 19* )
                if [[ $device_type == "iPhone10,3" || $device_type == "iPhone10,6" ]]; then
                    log "Selected IPSW ($device_target_vers) is not supported as target version."
                    print "* Latest SEP/BB is not compatible."
                    pause
                    return
                else
                    warn "Please read: You will need to follow a guide regarding activation files before and after the restore."
                    print "* You will encounter issues activating if you do not follow this."
                    print "* Link to guide: https://gist.github.com/pixdoet/2b58cce317a3bc7158dfe10c53e3dd32"
                    pause
                fi
            ;;
            * )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    elif [[ $device_checkm8ipad == 1 ]]; then
        case $device_target_build in
            1[89]* )
                warn "Please read: You will need to follow a guide regarding activation files before and after the restore."
                print "* You will encounter issues activating if you do not follow this."
                print "* Link to guide: https://gist.github.com/pixdoet/2b58cce317a3bc7158dfe10c53e3dd32"
                pause
            ;;
            * )
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                print "* Latest SEP/BB is not compatible."
                pause
                return
            ;;
        esac
    fi

    case $1 in
        "base" )
            local check_vers="7.1"
            local base_vers="7.1.x"
            case $device_type in
                iPhone5,[1234] )
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
                iPad2,[123] )
                    # fourthree
                    check_vers="4.3"
                    base_vers="4.3.x"
                ;;
            esac
            if [[ $device_base_vers != "$check_vers"* ]]; then
                log "Selected IPSW is not for iOS $base_vers."
                if [[ $device_proc == 4 ]]; then
                    print "* You need to select iOS $base_vers IPSW for the base to use powdersn0w."
                elif [[ $ipsw_fourthree == 1 ]]; then
                    print "* You need to select iOS $base_vers IPSW for the base to use FourThree."
                else
                    print "* You need iOS $base_vers IPSW and SHSH blobs for your device to use powdersn0w."
                fi
                pause
                return
            elif [[ $device_target_build == "$device_base_build" ]]; then
                log "The base version and the target version cannot be the same."
                pause
                return
            fi
            ipsw_verify "$newpath" "$device_base_build"
            if [[ $? != 0 ]]; then
                return
            fi
            ipsw_base_path="$newpath"
            return
        ;;
        *"powdersn0w"* )
            if [[ $device_target_build == "14"* ]]; then
                log "Selected IPSW ($device_target_vers) is not supported as target version."
                case $device_type in
                    iPhone5,[12] ) print "* If you want untethered iOS 10, use p0insettia plus: https://github.com/LukeZGD/p0insettia-plus";;
                esac
                pause
                return
            elif [[ $device_target_build == "11D257" && $device_type == "iPhone3"* ]] ||
                 [[ $device_target_build == "9B206" && $device_proc == 4 ]]; then
                log "Selected IPSW ($device_target_vers) is not supported as target version. You need to select it as base IPSW."
                pause
                return
            elif [[ $device_target_build == "$device_base_build" ]]; then
                log "The base version and the target version cannot be the same."
                pause
                return
            fi
            versionc="powder"
        ;;
    esac
    if [[ $versionc == "powder" ]]; then
        :
    elif [[ -n $versionc && $device_target_vers != "$versionc" ]]; then
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
    local text="Target"
    local val="$ipsw_path.ipsw"
    [[ $1 == "base" ]] && text="Base"

    input "Select your $text SHSH file in the file selection window."
    if [[ $mac_cocoa == 1 ]]; then
        newpath="$($cocoadialog fileselect)"
    else
        menu_zenity_check
        newpath="$($zenity --file-selection --file-filter='SHSH | *.bshsh2 *.shsh *.shsh2' --title="Select $text SHSH file")"
    fi
    if [[ ! -s "$newpath" ]]; then
        print "* Enter the full path to the SHSH file to be used."
        print "* You may also drag and drop the SHSH file to the Terminal window."
        read -p "$(input "Path to $text SHSH file (or press Enter/Return or Ctrl+C to cancel): ")" newpath
    fi
    [[ ! -s "$newpath" ]] && return
    log "Selected SHSH file: $newpath"
    log "Validating..."
    if (( device_proc >= 7 )); then
        unzip -o -j "$val" BuildManifest.plist
        shsh_validate=$("$dir/img4tool" -s "$newpath" --verify BuildManifest.plist | tee /dev/tty | grep -c "APTicket is BAD!")
    else
        if [[ $1 == "base" ]]; then
            val="$ipsw_base_path.ipsw"
        fi
        "$dir/validate" "$newpath" "$val" -z
        shsh_validate=$?
    fi
    if [[ $shsh_validate != 0 ]]; then
        warn "Validation failed. Did you select the correct IPSW/SHSH?"
        if (( device_proc < 5 )); then
            warn "Validation might be a false negative for A4 and older devices."
        fi
        pause
    fi
    shsh_path="$newpath"
}

menu_shshdump_browse() {
    local newpath
    input "Select your raw dump file in the file selection window."
    if [[ $mac_cocoa == 1 ]]; then
        newpath="$($cocoadialog fileselect --with-extensions raw)"
    else
        menu_zenity_check
        newpath="$($zenity --file-selection --file-filter='Raw Dump | *.dump *.raw' --title="Select Raw Dump")"
    fi
    [[ ! -s "$newpath" ]] && read -p "$(input "Enter path to raw dump file (or press Ctrl+C to cancel): ")" newpath
    [[ ! -s "$newpath" ]] && return
    log "Selected raw dump file: $newpath"
    shsh_path="$newpath"
}

menu_flags() {
    local menu_items
    local selected
    local back

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=()
        case $device_type in
            iPhone[45]* | iPad2,[67] | iPad3,[56] ) menu_items+=("Enable disable-bbupdate flag");;
        esac
        if (( device_proc >= 7 )); then
            menu_items+=("Enable skip-blob flag")
        else
            menu_items+=("Enable activation-records flag" "Enable jailbreak flag")
            if (( device_proc >= 5 )); then
                menu_items+=("Enable skip-ibss flag")
            fi
        fi
        case $device_type in
            iPhone4,1 ) menu_items+=("Enable gasgauge-patch flag");;
            iPhone3,[13] | iPad1,1 | iPod3,1 ) menu_items+=("Enable skip-first flag");;
        esac
        menu_items+=("Go Back")
        menu_print_info
        print " > Main Menu > Other Utilities > Enable Flags"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Enable disable-bbupdate flag" )
                warn "This will enable the --disable-bbupdate flag."
                print "* This will disable baseband update for custom IPSWs."
                print "* This will enable usage of dumped baseband and stitch to IPSW."
                print "* This applies to the following: iPhone 4S, 5, 5C, iPad 4, mini 1"
                print "* Do not enable this if you do not know what you are doing."
                local opt
                read -p "$(input 'Do you want to enable the disable-bbupdate flag? (y/N): ')" opt
                if [[ $opt == 'y' || $opt == 'Y' ]]; then
                    device_disable_bbupdate="$device_type"
                    back=1
                fi
            ;;
            "Enable activation-records flag" )
                warn "This will enable the --activation-records flag."
                print "* This will enable usage of dumped activation records and stitch to IPSW."
                print "* Do not enable this if you do not know what you are doing."
                local opt
                read -p "$(input 'Do you want to enable the activation-records flag? (y/N): ')" opt
                if [[ $opt == 'y' || $opt == 'Y' ]]; then
                    device_actrec=1
                    back=1
                fi
            ;;
            "Enable skip-ibss flag" )
                warn "This will enable the --skip-ibss flag."
                print "* This will assume that a pwned iBSS has already been sent to the device."
                print "* Do not enable this if you do not know what you are doing."
                local opt
                read -p "$(input 'Do you want to enable the skip-ibss flag? (y/N): ')" opt
                if [[ $opt == 'y' || $opt == 'Y' ]]; then
                    device_skip_ibss=1
                    back=1
                fi
            ;;
            "Enable jailbreak flag" )
                warn "This will enable the --jailbreak flag."
                print "* This will enable the jailbreak option for the custom IPSW."
                print "* This is only useful for 4.1 and lower, where jailbreak option is disabled in most cases."
                print "* It is disabled for those versions by default because of issues with the custom IPSW jailbreak."
                print "* The recommended method is to jailbreak after the restore instead."
                print "* Do not enable this if you do not know what you are doing."
                local opt
                read -p "$(input 'Do you want to enable the jailbreak flag? (y/N): ')" opt
                if [[ $opt == 'y' || $opt == 'Y' ]]; then
                    ipsw_jailbreak=1
                    back=1
                fi
            ;;
            "Enable gasgauge-patch flag" )
                warn "This will enable the --gasgauge-patch flag."
                print "* This will enable \"multipatch\" for the custom IPSW."
                print "* This is especially useful for iPhone 4S devices that have issues restoring due to battery replacement."
                print "* This issue is called \"gas gauge\" error, also known as error 29 in iTunes."
                print "* By enabling this, firmware components for 6.1.3 or lower will be used for restoring to get past the error."
                local opt
                read -p "$(input 'Do you want to enable the gasgauge-patch flag? (y/N): ')" opt
                if [[ $opt == 'y' || $opt == 'Y' ]]; then
                    ipsw_gasgauge_patch=1
                    back=1
                fi
            ;;
            "Enable skip-first flag" )
                warn "This will enable the --skip-first flag."
                print "* This will skip first restore and flash NOR IPSW only for powdersn0w 4.2.x and lower."
                print "* Do not enable this if you do not know what you are doing."
                local opt
                read -p "$(input 'Do you want to enable the skip-ibss flag? (y/N): ')" opt
                if [[ $opt == 'y' || $opt == 'Y' ]]; then
                    ipsw_skip_first=1
                    back=1
                fi
            ;;
            "Enable skip-blob flag" )
                warn "This will enable the --skip-blob flag."
                print "* This will enable the skip blob flag of futurerestore."
                print "* This can be used to skip blob verification for OTA/onboard/factory SHSH blobs."
                print "* Do not enable this if you do not know what you are doing."
                local opt
                read -p "$(input 'Do you want to enable the skip-blob flag? (y/N): ')" opt
                if [[ $opt == 'y' || $opt == 'Y' ]]; then
                    restore_useskipblob=1
                    back=1
                fi
            ;;
            "Go Back" ) back=1;;
        esac
    done
}

menu_devicemanage() {
    local menu_items
    local selected
    local back

    menu_print_info
    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Export Device Info" "Export Battery Info" "Pair Device" "Shutdown Device" "Restart Device" "Enter Recovery Mode" "Go Back")
        print " > Main Menu > Device Management"
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Export Device Info" )
                mkdir -p ../saved/info 2>/dev/null
                log "Running ideviceinfo"
                local info="../saved/info/device-$device_ecid-$device_type-$(date +%Y-%m-%d-%H%M).txt"
                $ideviceinfo > $info
                if [[ $? != 0 ]]; then
                    $ideviceinfo -s > $info
                fi
                log "Device Info exported to: $info"
            ;;
            "Export Battery Info" )
                mkdir -p ../saved/info 2>/dev/null
                log "Running idevicediagnostics"
                local info="../saved/info/battery-$device_ecid-$device_type-$(date +%Y-%m-%d-%H%M).txt"
                $idevicediagnostics ioregentry AppleSmartBattery > $info
                if [[ $? != 0 ]]; then
                    $idevicediagnostics ioregentry AppleARMPMUCharger > $info
                fi
                log "Battery Info exported to: $info"
            ;;
            "Pair Device" ) device_pair;;
            "Shutdown Device" ) mode="shutdown";;
            "Restart Device" ) mode="restart";;
            "Enter Recovery Mode" ) mode="enterrecovery";;
            "Go Back" ) back=1;;
        esac
    done
}

menu_other() {
    local menu_items
    local selected
    local back

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=()
        if [[ $device_mode != "none" && $device_proc != 1 ]] && (( device_proc < 7 )); then
            if [[ $device_mode == "Normal" ]]; then
                menu_items+=("Enter kDFU Mode")
            fi
            if [[ $device_type != "iPod2,1" && $debug_mode == 1 ]]; then
                menu_items+=("Just Boot")
            fi
            case $device_proc in
                [56] ) menu_items+=("Send Pwned iBSS");;
                *    ) menu_items+=("Enter pwnDFU Mode");;
            esac
            menu_items+=("Clear NVRAM")
            case $device_type in
                iPhone3,[13] | iPhone[45]* | iPad1,1 | iPad2,4 | iPod[35],1 ) menu_items+=("Disable/Enable Exploit");;
                iPhone2,1 ) menu_items+=("Install alloc8 Exploit");;
            esac
            if [[ $device_mode == "Normal" ]]; then
                case $device_type in
                    iPhone1* )
                        case $device_vers in
                            3.1.3 | 4.[12]* ) menu_items+=("Hacktivate Device" "Revert Hacktivation");;
                        esac
                    ;;
                    iPhone[23],1 )
                        case $device_vers in
                            3.1* | [456]* ) menu_items+=("Hacktivate Device" "Revert Hacktivation");;
                        esac
                    ;;
                esac
            else
                menu_items+=("Get iOS Version" "Activation Records")
            fi
            case $device_type in
                iPhone[45]* | iPad2,[67] | iPad3,[56] ) menu_items+=("Dump Baseband");;
            esac
        fi
        if [[ $device_mode != "none" ]]; then
            if (( device_proc >= 7 )) && (( device_proc <= 10 )); then
                menu_items+=("Enter pwnDFU Mode")
            fi
            if (( device_proc <= 10 )) && [[ $device_latest_vers != "16"* && $device_checkm8ipad != 1 && $device_proc != 1 ]]; then
                menu_items+=("SSH Ramdisk")
            fi
            if [[ $device_mode == "Normal" ]]; then
                menu_items+=("Attempt Activation" "Activation Records")
            fi
            if [[ $device_mode != "DFU" ]]; then
                menu_items+=("DFU Mode Helper")
            fi
        fi
        if (( device_proc < 7 )); then
            menu_items+=("Create Custom IPSW")
        fi
        if [[ $device_proc != 1 ]] && (( device_proc < 11 )); then
            menu_items+=("Enable Flags")
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
            "Hacktivate Device" ) mode="device_hacktivate";;
            "Revert Hacktivation" ) mode="device_reverthacktivate";;
            "Create Custom IPSW" ) menu_restore ipsw;;
            "Enter kDFU Mode" ) mode="kdfu";;
            "Disable/Enable Exploit" ) menu_remove4;;
            "SSH Ramdisk" ) mode="device_enter_ramdisk";;
            "Clear NVRAM" ) mode="ramdisknvram";;
            "Send Pwned iBSS" | "Enter pwnDFU Mode" ) mode="pwned-ibss";;
            "(Re-)Install Dependencies" ) install_depends;;
            "Attempt Activation" ) device_activate;;
            "Install alloc8 Exploit" ) mode="device_alloc8";;
            "Dump Baseband" ) mode="baseband";;
            "Activation Records" ) mode="actrec";;
            "DFU Mode Helper" ) mode="enterdfu";;
            "Get iOS Version" ) mode="getversion";;
            "Enable Flags" ) menu_flags;;
            "Go Back" ) back=1;;
        esac
    done
}

device_pair() {
    log "Attempting idevicepair"
    "$dir/idevicepair" pair
    if [[ $? != 0 ]]; then
        log "Unlock and press \"Trust\" on the device before pressing Enter/Return."
        pause
        log "Attempting idevicepair"
    fi
    "$dir/idevicepair" pair
}

device_ssh() {
    print "* Note: This is for connecting via SSH to devices that are already jailbroken and have OpenSSH installed."
    print "* If this is not what you want, you might be looking for the \"SSH Ramdisk\" option instead."
    echo
    device_ssh_message
    device_iproxy no-logging
    device_sshpass
    log "Connecting to device SSH..."
    print "* For accessing data, note the following:"
    print "* Host: sftp://127.0.0.1 | User: $ssh_user | Password: <your password> (default is alpine) | Port: $ssh_port"
    $ssh -p $ssh_port ${ssh_user}@127.0.0.1
    kill $iproxy_pid
}

device_alloc8() {
    device_enter_mode pwnDFU
    device_ipwndfu alloc8
    log "Done!"
    print "* This may take several tries. It can fail a lot with \"Operation timed out\" error."
    print "* If it fails, try to unplug and replug your device then run the script again."
    print "* You may also need to force restart the device and re-enter DFU mode before retrying."
    print "* To retry, just go back to: Other Utilities -> Install alloc8 Exploit"
}

device_jailbreak_confirm() {
    if [[ $device_proc == 1 ]]; then
        print "* The \"Jailbreak Device\" option is not supported for this device."
        print "* To jailbreak, go to \"Restore/Downgrade\" instead, select 4.2.1, 4.1, or 3.1.3, then enable the jailbreak option."
        pause
        return
    elif [[ $device_vers == *"iBoot"* || $device_vers == "Unknown"* ]]; then
        device_vers=
        while [[ -z $device_vers ]]; do
            read -p "$(input 'Enter current iOS version (eg. 6.1.3): ')" device_vers
        done
    else
        case $device_vers in
            5* | 6.0* | 6.1 | 6.1.[12] )
                print "* Your device on iOS $device_vers will be jailbroken using g1lbertJB."
                print "* No data will be lost, but please back up your data just in case."
                print "* Ignore the \"Error Code 1\" and \"Error Code 102\" errors, this is normal and part of the jailbreaking process."
                if [[ $device_proc == 4 ]]; then
                    print "* Note: If the process fails somewhere, you can just enter DFU mode and attempt jailbreaking again from there."
                fi
                read -p "$(input "Select Y to continue, N to go back (y/N) ")" opt
                if [[ $opt != 'Y' && $opt != 'y' ]]; then
                    return
                fi
                mode="device_jailbreak_gilbert"
                return
            ;;
        esac
    fi
    log "Checking if your device and version is supported..."
    if [[ $device_type == "iPad2"* && $device_vers == "4"* ]]; then
        warn "This will be a semi-tethered jailbreak. checkm8-a5 is required to boot to a jailbroken state."
        print "* To boot jailbroken later, go to: Main Menu -> Just Boot"
        pause
    elif [[ $device_type == "iPhone3,3" ]]; then
        case $device_vers in
            4.2.9 | 4.2.10 )
                warn "This will be a semi-tethered jailbreak."
                print "* To boot jailbroken later, go to: Main Menu -> Just Boot"
                pause
            ;;
        esac
    elif [[ $device_proc == 5 ]]; then
        print "* Note: It would be better to jailbreak using sideload or custom IPSW methods for A5 devices."
        print "* Especially since this method may require the usage of checkm8-a5."
    elif [[ $device_proc == 6 && $platform == "linux" ]]; then
        print "* Note: It would be better to jailbreak using sideload or custom IPSW methods for A6 devices on Linux."
    fi
    if [[ $device_proc == 5 ]] || [[ $device_proc == 6 && $platform == "linux" ]]; then
        case $device_vers in
            7.1* )
                print "* For this version, Pangu on Windows/Mac can also be used instead of this option."
                print "* https://ios.cfw.guide/installing-pangu7/"
            ;;
            7.0* )
                print "* For this version, evasi0n7 on Windows/Mac can also be used instead of this option."
                print "* https://ios.cfw.guide/installing-evasi0n7/"
            ;;
            6.1.[3456] )
                print "* For this version, p0sixspwn on Windows/Mac can also be used instead of this option."
                print "* https://ios.cfw.guide/installing-p0sixspwn/"
            ;;
            10* | 9* )
                print "* Note: If you need to sideload, you can use Legacy iOS Kit's \"Sideload IPA\" option."
            ;;
        esac
    fi
    print "* For more details, go to: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Jailbreaking"
    echo
    case $device_vers in
        8.2 | 8.[10]* )
            if [[ $device_proc == 5 ]]; then
                warn "This version ($device_vers) is broken for daibutsu A5(X)."
                print "* Supported iOS 8 versions for A5(X) are 8.3 to 8.4.1 only for now."
                print "* For this version, use Home Depot patched with ohd and sideload it to your device."
                print "* https://github.com/LukeZGD/ohd"
                pause
                return
            fi
        ;;
        9.0* )
            print "* For this version, use Pangu9 on older macOS to jailbreak your device."
            print "* https://ios.cfw.guide/installing-pangu9/"
            pause
            return
        ;;
        9.3.[56] )
            print "* For this version, download kok3shi9 and sideload it to your device."
            print "* https://kok3shidoll.web.app/kok3shi9_32.html"
            pause
            return
        ;;
        10* )
            print "* For this version, download socket and sideload it to your device."
            print "* https://github.com/staturnzz/socket"
            pause
            return
        ;;
        9.3.[1234] | 9.3 | 9.2* | 9.1 | [8765]* | 4.3* | 4.2.[8761] | 4.[10]* | 3.2* | 3.1.3 ) :;;
        3.[10]* )
            if [[ $device_type != "iPhone2,1" ]]; then
                warn "This version ($device_vers) is not supported for jailbreaking with SSHRD."
                print "* Supported versions are: 3.1.3 to 9.3.4 (excluding 9.0.x)"
                pause
                return
            fi
        ;;
        * )
            warn "This version ($device_vers) is not supported for jailbreaking with SSHRD."
            print "* Supported versions are: 3.1.3 to 9.3.4 (excluding 9.0.x)"
            pause
            return
        ;;
    esac
    if [[ $device_type == "iPhone2,1" && $device_vers == "3"* ]]; then
        warn "For 3.x versions on the 3GS, the \"Jailbreak Device\" option will only work on devices restored with Legacy iOS Kit."
        print "* This applies to all 3.x versions on the 3GS only. They require usage of the \"Restore/Downgrade\" option first."
        echo
    elif [[ $device_vers == "7"* ]]; then
        warn "The iOS 7 untethers may cause issues to your device after jailbreaking with this method."
        print "* You may encounter issues like slowdowns/freezing and losing baseband functionality."
        print "* It is recommended to instead dump blobs and restore with the jailbreak option enabled."
        print "* Or use other methods like jailbreaking with evasi0n7/Pangu if your device is not OTA updated."
    fi
    print "* By selecting Jailbreak Device, your device will be jailbroken using Ramdisk Method."
    print "* Before continuing, make sure that your device does not have a jailbreak yet."
    print "* No data will be lost, but please back up your data just in case."
    read -p "$(input "Select Y to continue, N to go back (y/N) ")" opt
    if [[ $opt != 'Y' && $opt != 'y' ]]; then
        return
    fi
    mode="device_jailbreak"
}

device_jailbreak() {
    device_ramdisk jailbreak
}

device_jailbreak_gilbert() {
    pushd ../resources/jailbreak/g1lbertJB >/dev/null
    log "Copying freeze.tar to Cydia.tar"
    cp ../freeze.tar payload/common/Cydia.tar
    log "Running g1lbertJB..."
    "../../$dir/gilbertjb"
    rm payload/common/Cydia.tar
    popd >/dev/null
}

device_ssh_message() {
    print "* Make sure to have OpenSSH installed on your iOS device."
    if [[ $device_det == 1 ]] && (( device_proc < 7 )); then
        print "* Install all updates in Cydia/Zebra."
        print "* Make sure to also have Dropbear installed from my repo."
        print "* Repo: https://lukezgd.github.io/repo"
    fi
    print "* Only proceed if you have these requirements installed using Cydia/Zebra/Sileo."
    print "* You will be prompted to enter the root/mobile password of your iOS device."
    print "* The default password is: alpine"
}

device_dump() {
    local arg="$1"
    local dump="../saved/$device_type/$arg-$device_ecid.tar"
    local dmps
    local dmp2
    case $arg in
        "baseband" ) dmps="/usr/local/standalone";;
        "activation" )
            dmp2="private/var/root/Library/Lockdown"
            case $device_vers in
                [34567]* ) dmps="/$dmp2";;
                8* | 9.[012]* ) dmps="/private/var/mobile/Library/mad";;
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
        device_ssh_message
        device_iproxy
        device_sshpass
        if [[ $arg == "activation" ]]; then
            log "Creating $arg.tar"
            $ssh -p $ssh_port ${ssh_user}@127.0.0.1 "mkdir -p /tmp/$dmp2; find $dmps; cp -R $dmps/* /tmp/$dmp2"
            $ssh -p $ssh_port ${ssh_user}@127.0.0.1 "cd /tmp; tar -cvf $arg.tar $dmp2"
            log "Copying $arg.tar"
            $scp -P $ssh_port ${ssh_user}@127.0.0.1:/tmp/$arg.tar .
            mv $arg.tar $arg-$device_ecid.tar
        else
            device_dumpbb
        fi
        cp $arg-$device_ecid.tar $dump
    elif [[ $device_mode == "DFU" ]]; then
        log "This operation requires an SSH ramdisk, proceeding"
        print "* I recommend dumping baseband/activation on Normal mode instead of Recovery/DFU mode if possible"
        device_enter_ramdisk $arg
        device_dumprd
        $ssh -p $ssh_port root@127.0.0.1 "nvram auto-boot=0; reboot_bak"
        log "Done, device should reboot to recovery mode now"
        log "Just exit recovery mode if needed: Other Utilities -> Exit Recovery Mode"
        if [[ $mode != "baseband" && $mode != "actrec" ]]; then
            log "Put your device back in kDFU/pwnDFU mode to proceed"
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

device_dumpbb() {
    local bb2="Mav5"
    local root="/"
    local root2="/"
    local tmp="/tmp"
    case $device_type in
        iPhone4,1 ) bb2="Trek";;
        iPhone5,[34] ) bb2="Mav7Mav8";;
    esac
    if [[ $1 == "rd" ]]; then
        root="/mnt1/"
        root2=
        tmp="/mnt2/tmp"
    fi
    log "Creating baseband.tar"
    case $device_vers in
        5* ) $scp -P $ssh_port root@127.0.0.1:${root}usr/standalone/firmware/$bb2-personalized.zip .;;
        6* ) $scp -P $ssh_port root@127.0.0.1:${root}usr/local/standalone/firmware/Baseband/$bb2/$bb2-personalized.zip .;;
    esac
    case $device_vers in
        [56]* )
            mkdir -p usr/local/standalone/firmware/Baseband/$bb2
            unzip $bb2-personalized.zip -d usr/local/standalone/firmware/Baseband/$bb2
            cp $bb2-personalized.zip usr/local/standalone/firmware/Baseband/$bb2
        ;;
        * )
            $ssh -p $ssh_port root@127.0.0.1 "cd $root; tar -cvf $tmp/baseband.tar ${root2}usr/local/standalone/firmware"
            $scp -P $ssh_port root@127.0.0.1:$tmp/baseband.tar .
            if [[ ! -s baseband.tar ]]; then
                error "Dumping baseband tar failed. Please run the script again" \
                "* If your device is on iOS 9 or newer, make sure to set the version of the SSH ramdisk correctly."
            fi
            tar -xvf baseband.tar -C .
            rm baseband.tar
            pushd usr/local/standalone/firmware/Baseband/$bb2 >/dev/null
            zip -r0 $bb2-personalized.zip *
            unzip -o $bb2-personalized.zip -d .
            popd >/dev/null
        ;;
    esac
    if [[ $device_type == "iPhone4,1" ]]; then
        mkdir -p usr/standalone/firmware
        cp usr/local/standalone/firmware/Baseband/$bb2/$bb2-personalized.zip usr/standalone/firmware
    fi
    tar -cvf baseband-$device_ecid.tar usr
}

device_dumprd() {
    local dump="../saved/$device_type"
    local dmps
    local dmp2
    local vers
    local tmp="/mnt2/tmp"

    device_ramdisk_iosvers
    vers=$device_vers
    if [[ -z $vers ]]; then
        warn "Something wrong happened. Failed to get iOS version."
        print "* Please reboot the device into normal operating mode, then perform a clean \"slide to power off\", then try again."
        $ssh -p $ssh_port root@127.0.0.1 "reboot_bak"
        return
    fi
    log "Mounting filesystems"
    $ssh -p $ssh_port root@127.0.0.1 "mount.sh"
    sleep 1

    case $device_type in
        iPhone[45]* | iPad2,[67] | iPad3,[56] )
            log "Dumping both baseband and activation tars"
            device_dumpbb rd
            print "* Reminder to backup dump tars if needed"
            if [[ -s $dump/baseband-$device_ecid.tar ]]; then
                read -p "$(input "Baseband dump exists in $dump/baseband-$device_ecid.tar. Overwrite? (y/N) ")" opt
                if [[ $opt == 'Y' || $opt == 'y' ]]; then
                    log "Deleting existing dumped baseband"
                    rm $dump/baseband-$device_ecid.tar
                fi
            fi
            cp baseband-$device_ecid.tar $dump
        ;;
    esac

    dmp2="root/Library/Lockdown"
    case $vers in
        [34567]* ) dmps="$dmp2";;
        8* | 9.[012]* ) dmps="mobile/Library/mad";;
        * )
            dmps="containers/Data/System/*/Library/activation_records"
            dmp2+="/activation_records"
        ;;
    esac
    log "Creating activation.tar"
    $ssh -p $ssh_port root@127.0.0.1 "mkdir -p $tmp/private/var/$dmp2; cp -R /mnt2/$dmps/* $tmp/private/var/$dmp2"
    $ssh -p $ssh_port root@127.0.0.1 "cd $tmp; tar -cvf $tmp/activation.tar private/var/$dmp2"
    log "Copying activation.tar"
    print "* Reminder to backup dump tars if needed"
    $scp -P $ssh_port root@127.0.0.1:$tmp/activation.tar .
    if [[ ! -s activation.tar ]]; then
        error "Dumping activation record tar failed. Please run the script again" \
        "If your device is on iOS 9 or newer, make sure to set the version of the SSH ramdisk correctly."
    fi
    mv activation.tar activation-$device_ecid.tar
    if [[ -s $dump/activation-$device_ecid.tar ]]; then
        read -p "$(input "Activation records dump exists in $dump/activation-$device_ecid.tar. Overwrite? (y/N) ")" opt
        if [[ $opt == 'Y' || $opt == 'y' ]]; then
            log "Deleting existing dumped activation"
            rm $dump/activation-$device_ecid.tar
        fi
    fi
    cp activation-$device_ecid.tar $dump
    $ssh -p $ssh_port root@127.0.0.1 "rm -f $tmp/*.tar"
}

device_activate() {
    log "Attempting to activate device with ideviceactivation"
    if [[ $device_type == "iPhone"* ]] && (( device_proc <= 4 )); then
        print "* For iPhone 4 and older devices, make sure to have a valid SIM card."
        case $device_type in
            iPhone2,1 ) print "* For hacktivation, go to \"Restore/Downgrade\" or \"Hacktivate Device\" instead.";;
            iPhone1*  ) print "* For hacktivation, go to \"Restore/Downgrade\" instead.";;
        esac
    fi
    $ideviceactivation activate
    if [[ $device_type == "iPod"* ]] && (( device_det <= 3 )); then
        $ideviceactivation itunes
    fi
    print "* If it returns an error, just try again."
    device_unactivated=$($ideviceactivation state | grep -c "Unactivated")
    pause
}

device_hacktivate() {
    local type="$device_type"
    local build="$device_build"
    if [[ $device_type == "iPhone3,1" ]]; then
        type="iPhone2,1"
        case $device_vers in
            4.2.1 ) build="8C148a";;
            5.1.1 ) build="9B206";;
            6.1   ) build="10B141";;
        esac
        log "Checking ideviceactivation status..."
        $ideviceactivation activate
    fi
    local patch="../resources/firmware/FirmwareBundles/Down_${type}_${device_vers}_${build}.bundle/lockdownd.patch"
    print "* Note: This is for hacktivating devices that are already restored, jailbroken, and have OpenSSH installed."
    print "* If this is not what you want, you might be looking for the \"Restore/Downgrade\" option instead."
    print "* From there, enable both \"Jailbreak Option\" and \"Hacktivate Option.\""
    echo
    print "* Hacktivate Device: This will use SSH to patch lockdownd on your device."
    print "* Hacktivation is for iOS versions 3.1 to 6.1.6."
    pause
    device_iproxy
    device_sshpass
    log "Getting lockdownd"
    $scp -P $ssh_port root@127.0.0.1:/usr/libexec/lockdownd .
    log "Patching lockdownd"
    $bspatch lockdownd lockdownd.patched "$patch"
    log "Renaming original lockdownd"
    $ssh -p $ssh_port root@127.0.0.1 "[[ ! -e /usr/libexec/lockdownd.orig ]] && mv /usr/libexec/lockdownd /usr/libexec/lockdownd.orig"
    log "Copying patched lockdownd to device"
    $scp -P $ssh_port lockdownd.patched root@127.0.0.1:/usr/libexec/lockdownd
    $ssh -p $ssh_port root@127.0.0.1 "chmod +x /usr/libexec/lockdownd; reboot"
    log "Done. Your device should reboot now"
}

device_reverthacktivate() {
    print "* This will use revert hacktivation for this device."
    print "* This option can only be used if the hacktivation is done using Legacy iOS Kit's \"Hacktivate Device\" option."
    pause
    device_iproxy
    print "* The default root password is: alpine"
    device_sshpass
    log "Reverting lockdownd"
    $ssh -p $ssh_port root@127.0.0.1 "[[ -e /usr/libexec/lockdownd.orig ]] && rm /usr/libexec/lockdownd && mv /usr/libexec/lockdownd.orig /usr/libexec/lockdownd"
    $ssh -p $ssh_port root@127.0.0.1 "chmod +x /usr/libexec/lockdownd; reboot"
    log "Done. Your device should reboot now"
}

restore_customipsw() {
    print "* You are about to restore with a custom IPSW."
    print "* This option is only for restoring with IPSWs NOT made with Legacy iOS Kit, like whited00r or GeekGrade."
    if [[ $device_newbr == 1 ]]; then
        warn "Your device is a new bootrom model and some custom IPSWs might not be compatible."
        print "* For iPhone 3GS, after restoring you will need to go to Other Utilities -> Install alloc8 Exploit"
    else
        warn "Do NOT use this option for powdersn0w or jailbreak IPSWs with Legacy iOS Kit!"
    fi
    if [[ $platform == "macos" ]] && [[ $device_type == "iPod2,1" || $device_proc == 1 ]]; then
        echo
        warn "Restoring to 2.x might not work on newer macOS versions."
        print "* Try installing usbmuxd from MacPorts, and run 'sudo usbmuxd -pf' in another Terminal window"
        print "* Another option is to just do 2.x restores on Linux instead."
        print "* For more info, go to: https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Troubleshooting#restoring-to-iphoneosios-2x-on-macos"
    fi
    if [[ $device_proc == 1 ]]; then
        echo
        print "* Note that you might need to restore twice, due to NOR flash."
        print "* For iPhone 2G/3G, the second restore may fail due to baseband."
        print "* You can exit recovery mode after by going to: Main Menu -> Exit Recovery Mode"
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
    # replacing llb with an invalid img3/im4p to make the restore fail, the device will then fallback to true dfu mode
    # https://theapplewiki.com/wiki/DFU_Mode#Enter_True_Hardware_DFU_Mode_Automatically
    # this function theoretically works on 64-bit devices, but restoring the dfu ipsw requires entering dfu for pwned restore
    # which defeats the point of doing a dfu ipsw in the first place, so dfu ipsw is available for 32-bit devices only
    print "* You are about to restore with a DFU IPSW."
    print "* This will force the device to enter DFU mode, which is useful for devices with broken buttons."
    print "* All device data will be wiped! Only proceed if you have backed up your data."
    print "* Expect the restore to fail and the device to be stuck in DFU mode."
    pause
    device_target_vers="$device_latest_vers"
    device_target_build="$device_latest_build"
    ipsw_latest_set
    ipsw_path="../$ipsw_latest_path"
    if [[ -s "$ipsw_path.ipsw" && ! -e "$ipsw_dfuipsw.ipsw" ]]; then
        ipsw_verify "$ipsw_path" "$device_target_build"
    elif [[ ! -e "$ipsw_path.ipsw" ]]; then
        ipsw_download "$ipsw_path"
    fi
    if [[ -s "$ipsw_dfuipsw.ipsw" ]]; then
        log "Found existing DFU IPSW. Skipping IPSW creation."
    else
        cp $ipsw_path.ipsw temp.ipsw
        local llb="${device_model}ap"
        local all="Firmware/all_flash"
        local applelogo
        if (( device_proc >= 6 )); then
            ipsw_hwmodel_set
            case $device_type in
                iPhone9,[13] ) llb="d10";;
                iPhone9,[24] ) llb="d11";;
                iPhone[78]* | iPad6,1* ) llb="$device_model";;
                * ) llb="$ipsw_hwmodel"
            esac
            case $device_type in
                iPhone5,[1234] ) applelogo="applelogo@2x~iphone.s5l8950x.img3";;
                iPad3,[456] ) applelogo="applelogo@2x~ipad.s5l8955x.img3";;
                iPhone* ) applelogo="applelogo@2x~iphone.im4p";;
                iPad* ) applelogo="applelogo@2x~ipad.im4p";;
            esac
        else
            all="$all_flash"
            device_fw_key_check
            applelogo=$(echo $device_fw_key | $jq -j '.keys[] | select(.image == "AppleLogo") | .filename')
        fi
        llb="LLB.$llb.RELEASE"
        if (( device_proc >= 7 )); then
            llb+=".im4p"
        else
            llb+=".img3"
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

device_enter_build() {
    while true; do
        device_rd_build=
        read -p "$(input 'Enter build version (eg. 10B329): ')" device_rd_build
        case $device_rd_build in
            *[A-Z]* )
                if [[ $device_rd_build != *.* ]]; then
                    break
                fi
            ;;
            "" )
                if [[ $1 != "required" ]]; then
                    break
                fi
            ;;
        esac
        log "Build version input is not valid. Please try again"
    done
}

menu_justboot() {
    local menu_items
    local selected
    local back
    local vers

    while [[ -z "$mode" && -z "$back" ]]; do
        menu_items=("Enter Build Version" "Select IPSW" "Custom Bootargs")
        if [[ -n $vers ]]; then
            menu_items+=("Just Boot")
        fi
        menu_items+=("Go Back")
        menu_print_info
        print " > Main Menu > Just Boot"
        print "* You are about to do a tethered boot."
        print "* To know more about build version, go here: https://theapplewiki.com/wiki/Firmware"
        echo
        if [[ -n $ipsw_justboot_path ]]; then
            print "* Selected IPSW: $ipsw_justboot_path.ipsw"
            print "* IPSW Version: $device_target_vers-$device_target_build"
        elif [[ -n $vers ]]; then
            print "* Build Version entered: $vers"
        else
            print "* Enter build version or select IPSW to continue"
        fi
        echo
        if [[ -n $device_bootargs ]]; then
            print "* Custom Bootargs: $device_bootargs"
        else
            print "* You may enter custom bootargs (optional, experimental option)"
            print "* Default Bootargs: -v pio-error=0"
        fi
        echo
        input "Select an option:"
        select opt in "${menu_items[@]}"; do
            selected="$opt"
            break
        done
        case $selected in
            "Enter Build Version" )
                print "* Enter the build version of your device's current iOS version to boot."
                device_enter_build
                case $device_rd_build in
                    *[bcdefgkmpquv] )
                        log "iOS beta detected. Entering build version is not supported. Select the IPSW instead."
                        pause
                        continue
                    ;;
                esac
                ipsw_justboot_path=
                vers="$device_rd_build"
            ;;
            "Select IPSW" )
                menu_ipsw_browse
                ipsw_justboot_path="$ipsw_path"
                vers="$device_target_build"
                device_rd_build="$vers"
            ;;
            "Custom Bootargs" ) read -p "$(input 'Enter custom bootargs: ')" device_bootargs;;
            "Just Boot" ) mode="device_justboot";;
            "Go Back" ) back=1;;
        esac
    done
}

device_justboot() {
    if [[ -z $device_bootargs ]]; then
        device_bootargs="-v pio-error=0"
    fi
    device_ramdisk justboot
}

device_enter_ramdisk() {
    if (( device_proc >= 7 )); then
        device_ramdisk64
        return
    elif (( device_proc >= 5 )) && [[ $device_vers == "9"* || $device_vers == "10"* ]]; then
        device_rd_build="13A452"
    elif (( device_proc >= 5 )) && (( device_det <= 8 )) && [[ $device_mode == "Normal" ]]; then
        :
    elif (( device_proc >= 5 )); then
        print "* To mount /var (/mnt2) for iOS 9-10, I recommend using 9.0.2 (13A452)."
        print "* If not sure, just press Enter/Return. This will select the default version."
        device_enter_build
    fi
    device_ramdisk $1
}

device_ideviceinstaller() {
    log "Installing selected IPA(s) to device using ideviceinstaller..."
    IFS='|' read -r -a ipa_files <<< "$ipa_path"
    for i in "${ipa_files[@]}"; do
        log "Installing: $i"
        $ideviceinstaller install "$i"
    done
}

device_altserver() {
    local altserver="../saved/AltServer-$platform"
    local sha1="4bca48e9cda0517cc965250a797f97d5e8cc2de6"
    local anisette="../saved/anisette-server-$platform"
    local arch="$platform_arch"
    case $arch in
        "armhf" ) arch="armv7"; sha1="20e9ea770dbedb5c3c20f8b966be977efa2fa4cc";;
        "arm64" ) arch="aarch64"; sha1="535926e5a14dc8f59f3f99197ca4122c7af8dfaf";;
    esac
    altserver+="_$arch"
    anisette+="_$arch"
    if [[ $($sha1sum $altserver 2>/dev/null | awk '{print $1}') != "$sha1" ]]; then
        rm -f $altserver
    fi
    if [[ ! -e $altserver ]]; then
        download_file https://github.com/NyaMisty/AltServer-Linux/releases/download/v0.0.5/AltServer-$arch AltServer-$arch
        mv AltServer-$arch $altserver
    fi
    log "Checking for latest anisette-server"
    local latest="$(curl https://api.github.com/repos/LukeZGD/Provision/releases/latest | $jq -r ".tag_name")"
    local current="$(cat ../saved/anisette-server_version 2>/dev/null || echo "none")"
    log "Latest version: $latest, current version: $current"
    if [[ $current != "$latest" ]]; then
        rm -f $anisette
    fi
    if [[ ! -e $anisette ]]; then
        download_file https://github.com/LukeZGD/Provision/releases/download/$latest/anisette-server-$arch anisette-server-$arch
        mv anisette-server-$arch $anisette
        echo "$latest" > ../saved/anisette-server_version
    fi
    chmod +x $altserver $anisette
    log "Running Anisette"
    $anisette &
    anisette_pid=$!
    log "Anisette PID: $anisette_pid"
    local ready=0
    log "Waiting for Anisette"
    while [[ $ready != 1 ]]; do
        [[ $(curl 127.0.0.1:6969 2>/dev/null) ]] && ready=1
        sleep 1
    done
    export ALTSERVER_ANISETTE_SERVER=http://127.0.0.1:6969
    altserver="env ALTSERVER_ANISETTE_SERVER=$ALTSERVER_ANISETTE_SERVER $altserver"
    device_pair
    log "Enter Apple ID details to continue."
    print "* Your Apple ID and password will only be sent to Apple servers."
    local apple_id
    local apple_pass
    while [[ -z $apple_id ]]; do
        read -p "$(input 'Apple ID: ')" apple_id
    done
    print "* Your password input will not be visible, but it is still being entered."
    while [[ -z $apple_pass ]]; do
        read -s -p "$(input 'Password: ')" apple_pass
    done
    echo
    log "Running AltServer-Linux with given Apple ID details..."
    pushd ../saved >/dev/null
    $altserver -u $device_udid -a "$apple_id" -p "$apple_pass" "$ipa_path"
    popd >/dev/null
}

restore_latest64() {
    local idevicerestore2="${idevicerestore}2"
    local opt="-l"
    local opt2
    warn "Restoring to iOS 18 or newer is not supported. Try using pymobiledevice3 instead for that"
    input "Restore/Update Select Option"
    print "* Restore will do factory reset and update the device, all data will be cleared"
    print "* Update will only update the device to the latest version"
    print "* Or press Ctrl+C to cancel"
    read -p "$(input "Select Y to Restore, select N to Update (Y/n) ")" opt2
    if [[ $opt2 != 'n' && $opt2 != 'N' ]]; then
        opt+="e"
    fi
    $idevicerestore2 $opt
    mv *.ipsw ..
}

device_fourthree_step2() {
    if [[ $device_mode != "Normal" ]]; then
        error "Device is not in normal mode. Place the device in normal mode to proceed." \
        "The device must also be restored already with Step 1: Restore."
    fi
    print "* Make sure that the device is already restored with Step 1: Restore before proceeding."
    pause
    device_iproxy
    device_sshpass alpine
    device_fourthree_check 2
    if [[ $? == 2 ]]; then
        warn "Step 2 has already been completed. Cannot continue."
        return
    fi
    print "* How much GB do you want to allocate/leave to the 6.1.3 data partition?"
    print "* The rest of the space will be allocated to the 4.3.x system."
    print "* If unsure, set it to 3 (this means 3 GB for 6.1.3, the rest for 4.3.x)."
    local size
    until [[ -n $size ]] && [ "$size" -eq "$size" ]; do
        read -p "$(input 'iOS 6.1.3 Data Partition Size (in GB): ')" size
    done
    log "iOS 6.1.3 Data Partition Size: $size GB"
    size=$((size*1024*1024*1024))
    log "Sending package files"
    $scp -P $ssh_port $jelbrek/dualbootstuff.tar root@127.0.0.1:/tmp
    log "Installing packages"
    $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /tmp/dualbootstuff.tar -C /; dpkg -i /tmp/dualbootstuff/*.deb"
    log "Running TwistedMind2"
    $ssh -p $ssh_port root@127.0.0.1 "rm /TwistedMind2*; TwistedMind2 -d1 $size -s2 879124480 -d2 max"
    local tm2="$($ssh -p $ssh_port root@127.0.0.1 "ls /TwistedMind2*")"
    $scp -P $ssh_port root@127.0.0.1:$tm2 TwistedMind2
    kill $iproxy_pid
    log "Rebooting to SSH ramdisk for the next procedure"
    device_ramdisk TwistedMind2
    log "Done, proceed to Step 3 after the device boots"
}

device_fourthree_step3() {
    if [[ $device_mode != "Normal" ]]; then
        error "Device is not in normal mode. Place the device in normal mode to proceed." \
        "The device must also be set up already with Step 2: Partition."
    fi
    print "* Make sure that the device is set up with Step 2: Partition before proceeding."
    pause
    source ../saved/$device_type/fourthree_$device_ecid
    log "4.3.x version: $device_base_vers-$device_base_build"
    local saved_path="../saved/$device_type/$device_base_build"
    device_iproxy
    device_sshpass alpine
    device_fourthree_check 3
    if [[ $? == 0 ]]; then
        warn "Step 3 has already been completed. Cannot continue."
        return
    fi
    log "Creating filesystems"
    $ssh -p $ssh_port root@127.0.0.1 "mkdir /mnt1 /mnt2"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/newfs_hfs -s -v System -J -b 8192 -n a=8192,c=8192,e=8192 /dev/disk0s3"
    $ssh -p $ssh_port root@127.0.0.1 "/sbin/newfs_hfs -s -v Data -J -b 8192 -n a=8192,c=8192,e=8192 /dev/disk0s4"
    $ssh -p $ssh_port root@127.0.0.1 "mount_hfs /dev/disk0s4 /mnt2"
    log "Sending root filesystem, this will take a while."
    $scp -P $ssh_port $saved_path/RootFS.dmg root@127.0.0.1:/var
    log "Restoring root filesystem"
    $ssh -p $ssh_port root@127.0.0.1 "echo 'y' | asr restore --source /var/RootFS.dmg --target /dev/disk0s3 --erase"
    log "Checking root filesystem"
    $ssh -p $ssh_port root@127.0.0.1 "rm /var/RootFS.dmg; fsck_hfs -f /dev/disk0s3"
    log "Restoring data partition"
    $ssh -p $ssh_port root@127.0.0.1 "umount /mnt2; mount_hfs /dev/disk0s3 /mnt1; mount_hfs /dev/disk0s4 /mnt2; mv /mnt1/private/var/* /mnt2"
    log "Fixing fstab"
    $ssh -p $ssh_port root@127.0.0.1 "echo '/dev/disk0s3 / hfs rw 0 1' | tee /mnt1/private/etc/fstab; echo '/dev/disk0s4 /private/var hfs rw 0 2' | tee -a /mnt1/private/etc/fstab"
    log "Getting lockdownd"
    $scp -P $ssh_port root@127.0.0.1:/mnt1/usr/libexec/lockdownd .
    local patch="../resources/firmware/FirmwareBundles/Down_iPhone2,1_${device_base_vers}_${device_base_build}.bundle/lockdownd.patch"
    log "Patching lockdownd"
    $bspatch lockdownd lockdownd.patched "$patch"
    log "Renaming original lockdownd"
    $ssh -p $ssh_port root@127.0.0.1 "mv /mnt1/usr/libexec/lockdownd /mnt1/usr/libexec/lockdownd.orig"
    log "Copying patched lockdownd to device"
    $scp -P $ssh_port lockdownd.patched root@127.0.0.1:/mnt1/usr/libexec/lockdownd
    $ssh -p $ssh_port root@127.0.0.1 "chmod +x /mnt1/usr/libexec/lockdownd"
    log "Fixing system keybag"
    $ssh -p $ssh_port root@127.0.0.1 "mkdir /mnt2/keybags; ttbthingy; fixkeybag -v2; cp /tmp/systembag.kb /mnt2/keybags"
    log "Remounting data partition"
    $ssh -p $ssh_port root@127.0.0.1 "umount /mnt2; mount_hfs /dev/disk0s4 /mnt1/private/var"
    # idk if copying activation records actually works, probably not
    log "Copying activation records"
    local dmp="private/var/root/Library/Lockdown"
    $ssh -p $ssh_port root@127.0.0.1 "mkdir -p /mnt1/$dmp; cp -Rv /$dmp/* /mnt1/$dmp"
    log "Installing jailbreak"
    $scp -P $ssh_port $jelbrek/freeze.tar root@127.0.0.1:/tmp
    $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /tmp/freeze.tar -C /mnt1"
    if [[ $ipsw_openssh == 1 ]]; then
        log "Installing OpenSSH"
        $scp -P $ssh_port $jelbrek/sshdeb.tar root@127.0.0.1:/tmp
        $ssh -p $ssh_port root@127.0.0.1 "tar -xvf /tmp/sshdeb.tar -C /mnt1"
    fi
    log "Unmounting filesystems"
    $ssh -p $ssh_port root@127.0.0.1 "umount /mnt1/private/var; umount /mnt1"
    log "Sending Kernelcache and LLB"
    $scp -P $ssh_port $saved_path/Kernelcache root@127.0.0.1:/System/Library/Caches/com.apple.kernelcaches/kernelcachb
    $scp -P $ssh_port $saved_path/LLB root@127.0.0.1:/LLB
    device_fourthree_app install
    log "Done!"
}

device_fourthree_app() {
    if [[ $1 != "install" ]]; then
        device_iproxy
        print "* The default root password is: alpine"
        device_sshpass
    fi
    device_fourthree_check
    log "Installing FourThree app"
    $scp -P $ssh_port $jelbrek/fourthree.tar root@127.0.0.1:/tmp
    $ssh -p $ssh_port root@127.0.0.1 "tar -h -xvf /tmp/fourthree.tar -C /; cd /Applications/FourThree.app; chmod 6755 boot.sh FourThree kloader_ios5 /usr/bin/runasroot"
    log "Running uicache"
    $ssh -p $ssh_port mobile@127.0.0.1 "uicache"
}

device_fourthree_boot() {
    device_iproxy
    print "* The default root password is: alpine"
    device_sshpass
    device_fourthree_check
    log "Running FourThree Boot"
    $ssh -p $ssh_port root@127.0.0.1 "/Applications/FourThree.app/FourThree"
}

device_fourthree_check() {
    local opt=$1
    local check
    log "Checking if Step 1 is complete"
    check="$($ssh -p $ssh_port root@127.0.0.1 "ls /dev/disk0s2s1")"
    if [[ $check != "/dev/disk0s2s1" ]]; then
        error "Cannot find /dev/disk0s2s1. Something went wrong with Step 1" \
        "* Redo the FourThree process from Step 1"
    fi
    if [[ $opt == 1 ]]; then
        return 1
    fi
    log "Checking if Step 2 is complete"
    check="$($ssh -p $ssh_port root@127.0.0.1 "ls /dev/disk0s3 2>/dev/null")"
    if [[ $check != "/dev/disk0s3" ]]; then
        if [[ $opt == 2 ]]; then
            return 1
        fi
        error "Cannot find /dev/disk0s3. Something went wrong with Step 2" \
        "* Redo the FourThree process from Step 2"
    fi
    if [[ $opt == 2 ]]; then
        return 2
    fi
    log "Checking if Step 3 is complete"
    local kcb="/System/Library/Caches/com.apple.kernelcaches/kernelcachb"
    local kc="$($ssh -p $ssh_port root@127.0.0.1 "ls $kcb")"
    local llb="$($ssh -p $ssh_port root@127.0.0.1 "ls /LLB")"
    if [[ $kc != "$kcb" || $llb != "/LLB" ]]; then
        if [[ $opt == 3 ]]; then
            return 2
        fi
        error "Cannot find Kernelcache/LLB. Something went wrong with Step 3" \
        "* Redo the FourThree process from Step 3"
    fi
    return 0
}

device_backup_create() {
    device_backup="../saved/backups/${device_ecid}_${device_type}/$(date +%Y-%m-%d-%H%M)"
    print "* A backup of your device will be created using idevicebackup2. Please see the notes above."
    pause
    mkdir -p $device_backup
    pushd "$(dirname $device_backup)"
    dir="../../$dir"
    if [[ -n $dir_env ]]; then
        dir_env="env LD_LIBRARY_PATH=$dir/lib "
    fi
    $dir_env "$dir/idevicebackup2" backup --full "$(basename $device_backup)"
    popd
}

device_backup_restore() {
    print "* The selected backup $device_backup will be restored to the device."
    pause
    device_backup="../saved/backups/${device_ecid}_${device_type}/$device_backup"
    pushd "$(dirname $device_backup)"
    dir="../../$dir"
    if [[ -n $dir_env ]]; then
        dir_env="env LD_LIBRARY_PATH=$dir/lib "
    fi
    $dir_env "$dir/idevicebackup2" restore --system --settings "$(basename $device_backup)"
    popd
}

device_erase() {
    print "* You have selected the option to Erase All Content and Settings."
    print "* As the option says, it will erase all data on the device and reset it to factory settings."
    print "* By the end of the operation, the device will be back on the setup screen."
    print "* If you want to proceed, please type the following: Yes, do as I say"
    read -p "$(input 'Do you want to proceed? ')" opt
    if [[ $opt != "Yes, do as I say" ]]; then
        error "Not proceeding."
    fi
    log "Proceeding."
    $dir_env "$dir/idevicebackup2" erase
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
    local try=("google.com" "www.apple.com" "208.67.222.222")
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

    local checks=(curl git patch unzip xxd zip)
    local check_fail
    for check in "${checks[@]}"; do
        if [[ $debug_mode == 1 ]]; then
            log "Checking for $check in PATH"
        fi
        if [[ ! $(command -v $check) ]]; then
            warn "$check not found in PATH"
            check_fail=1
        fi
    done

    if [[ ! -e "../resources/firstrun" || $(cat "../resources/firstrun") != "$platform_ver" || $check_fail == 1 ]]; then
        install_depends
    fi

    device_get_info
    mkdir -p ../saved/baseband ../saved/$device_type ../saved/shsh

    mode=
    if [[ -n $main_argmode ]]; then
        mode="$main_argmode"
    else
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
            if (( device_proc >= 7 )); then
                warn "Activation records dumping is experimental for 64-bit devices."
                print "* It may not work on newer iOS versions and/or have incomplete files."
                print "* For more info of the files, go here: https://www.reddit.com/r/LegacyJailbreak/wiki/guides/a9ios9activation"
                print "* You may also look into here: https://gist.github.com/pixdoet/2b58cce317a3bc7158dfe10c53e3dd32"
                pause
            fi
            device_dump activation
            log "Activation records dumping is done"
            if (( device_proc < 7 )); then
                print "* To stitch records to IPSW, run Legacy iOS Kit with --activation-records argument:"
                print "    > ./restore.sh --activation-records"
            fi
        ;;
        "save-ota-blobs" ) shsh_save;;
        "kdfu" ) device_enter_mode kDFU;;
        "ramdisknvram" ) device_ramdisk clearnvram;;
        "pwned-ibss" ) device_enter_mode pwnDFU;;
        "save-onboard-blobs" ) shsh_save_onboard;;
        "save-onboard-dump" ) shsh_save_onboard dump;;
        "save-cydia-blobs" ) shsh_save_cydia;;
        "enterrecovery" ) device_enter_mode Recovery;;
        "exitrecovery" ) log "Attempting to exit Recovery mode."; $irecovery -n;;
        "enterdfu" ) device_enter_mode DFU;;
        "dfuipsw" ) restore_dfuipsw;;
        "dfuipswipsw" ) restore_dfuipsw ipsw;;
        "customipsw" ) restore_customipsw;;
        "getversion" ) device_ramdisk getversion;;
        "shutdown" ) $idevicediagnostics shutdown;;
        "restart" ) $idevicediagnostics restart;;
        "restore-latest" ) restore_latest64;;
        "convert-onboard-blobs" ) cp "$shsh_path" dump.raw; shsh_convert_onboard;;
        "remove4" ) device_ramdisk setnvram $rec;;
        "device"* ) $mode;;
        * ) :;;
    esac

    echo
    print "* Save the terminal output now if needed. (macOS: Cmd+S, Linux: Ctrl+Shift+S)"
    print "* Legacy iOS Kit $version_current ($git_hash)"
    print "* Platform: $platform ($platform_ver - $platform_arch) $live_cdusb_str"
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
        "--activation-records" ) device_actrec=1;;
        "--ipsw-hacktivate" ) ipsw_hacktivate=1;;
        "--skip-ibss" ) device_skip_ibss=1;;
        "--pwned-recovery" ) device_pwnrec=1;;
        "--gasgauge-patch" ) ipsw_gasgauge_patch=1;;
        "--dead-bb" ) device_deadbb=1; device_disable_bbupdate=1;;
        "--skip-first" ) ipsw_skip_first=1;;
        "--skip-blob" ) restore_useskipblob=1;;
        "--use-pwndfu" ) restore_usepwndfu64=1;;
        "--dfuhelper" ) main_argmode="device_dfuhelper";;
        "--exit-recovery" ) main_argmode="exitrecovery";;
    esac
done

trap "clean" EXIT
trap "exit 1" INT TERM

clean
othertmp=$(ls "$(dirname "$0")" | grep -c tmp)

if [[ $no_color != 1 ]]; then
    TERM=xterm-256color # fix colors for msys2 terminal
    color_R=$(tput setaf 9)
    color_G=$(tput setaf 10)
    color_B=$(tput setaf 12)
    color_Y=$(tput setaf 208)
    color_N=$(tput sgr0)
fi

if [[ $othertmp != 0 ]]; then
    log "Detected existing tmp folder(s)."
    print "* There might be other Legacy iOS Kit instance(s) running, or residual tmp folder(s) not deleted."
    print "* Running multiple instances is not fully supported and can cause unexpected behavior."
    print "* It is recommended to only use a single instance and/or delete all existing \"tmp\" folders in your Legacy iOS Kit folder before continuing."
    read -p "$(input "Select Y to remove all tmp folders, N to run as is (Y/n) ")" opt
    if [[ $opt != 'N' && $opt != 'n' ]]; then
        rm -r "$(dirname "$0")/tmp"*
    fi
fi

othertmp=$(ls "$(dirname "$0")" | grep -c tmp)
mkdir "$(dirname "$0")/tmp$$"
pushd "$(dirname "$0")/tmp$$" >/dev/null
mkdir ../saved 2>/dev/null

main

popd >/dev/null
