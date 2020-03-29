#!/bin/bash

# 8.4.1 iBSS IV and Keys
iv_k93=781b9672a86ba1b41f8b7fa0af714c94 #iPad2,1
key_k93=bbd7bf676dbcc6ba93c76d496b7af39ae7772eaaad2ec9fb71dc1fd004827784
iv_k94=883c92ed915e4d2481570a062583495b #iPad2,2
key_k94=ccfadf3732904885d38f963cce035d7e03b387b67212d526503c85773b58e52f
iv_k95=460116385cca6d5596221c58ae122669 #iPad2,3
key_k95=7852f1fd93d9d49ebea44021081e8f1dffa336d0d3e9517374f8be451dd92eb7
iv_k93a=976aa656929ac699fff36715de96876d #iPad2,4
key_k93a=5fe5c47b5620c2b40b1ca2bd1764a92d568901a24e1caf8faf0cf0f84ae11b4e
iv_p105=b21abc8689b0dea8f6e613f9f970e241 #iPad2,5
key_p105=b9ed63e4a31f5d9d4d7dddc527e65fd31d1ea48c70204e6b44551c1e6dfc52b5
iv_p106=56231fd62c6296ed0c8c411bcef602e0 #iPad2,6
key_p106=cdb2142489e5e936fa8f3540bd036f62ed0f27ddb6fec96b9fbfec5a65bc5f17
iv_p107=fa39c596b6569e572d90f0820e4e4357 #iPad2,7
key_p107=34b359fcc729a0f0d2853e786a78b245ed36a9212c8296aaab95dc0401cf07de
iv_j1=c3ea87ed43788dfc3e268abdf1af27dd #iPad3,1
key_j1=cd3dd7eee07b9ce8b180d1526632cf86dc7fef7d52352d06af354598ab9cf2ef
iv_j2=32fcd912cb9a472ef2a6db72596ae01c #iPad3,2
key_j2=076720d5a07e8011bdda6f6eafaf4845b40a441615cd1d7c1a9cca438ce7db17
iv_j2a=e6b041970cd611c8a1561a4c210bc476 #iPad3,3
key_j2a=aec6a888d45bd26106ac620d7d4ec0c160ab80276deedc1b50ce8f5d99dcc9af
iv_p101=a5892a58c90b6d3fb0e0b20db95070d7 #iPad3,4
key_p101=75612774968009e3f85545ac0088d0d0bb9cb4e2c2970e8f88489be0b9dfe103
iv_p102=fba6d9aaec7237891c80390e6ffa88bf #iPad3,5
key_p102=92909dca9bfdb9193131f9ad9b628b1a4971b1cbab52c0ddd114a6253fad96c0
iv_p103=1d99e780d96c32a25ca7e4b1c7fe14c0 #iPad3,6
key_p103=4e2c14927693d61e1da375e340061521c9376007163f6ab55afbe1a03b901fd3
iv_n94=147cdef921ed14a5c10631c5e6e02d1e #iPhone4,1
key_n94=6ea1eb62a9f403ee212c1f6b3039df093963b46739c6093407190fe3d750c69c
iv_n41=bd0c8b039a819604a30f0d39adf88572 #iPhone5,1
key_n41=baf05fe0282f78c18c2e3842be4f9021919d586b55594281f5b5abd0f6e61495
iv_n42=fdad2b7a35384fa2ffc7221213ca1082 #iPhone5,2
key_n42=74cd68729b800a20b1f8e8a3cb5517024a09f074eaa05b099db530fb5783275e
iv_n48=dbecd5f265e031835584e6bfbdb4c47f #iPhone5,3
key_n48=248f86d983626b75d26718fa52732eca64466ab73df048f278e034a272041f7e
iv_n49=039241f2b0212bb7c7b62ab4deec263f #iPhone5,4
key_n49=d0b49d366469ae2b1580d7d31b1bcf783d835e4fac13cfe9f9a160fa95010ac4
iv_n78=e0175b03bc29817adc312638884e0898 #iPod5,1
key_n78=0a0e0aedc8171669c9af6a229930a395959df55dcd8a3ee1fe0f4c009007df3c

# 6.1.3 iBSS IV and Keys
iv_k93_613=b69f753dccd09c9b98d345ec73bbf044 #iPad2,1
key_k93_613=6e4cce9ea6f2ec346cba0b279beab1b43e44a0680f1fde789a00f66a1e68ffab
iv_k94_613=bc3c9f168d7fb86aa219b7ad8039584b #iPad2,2
key_k94_613=b1bd1dc5e6076054392be054d50711ae70e8fcf31a47899fb90ab0ff3111b687
iv_k95_613=56f964ee19bfd31f06e43e9d8fe93902 #iPad2,3
key_k95_613=0bb841b8f1922ae73d85ed9ed0d7a3583a10af909787857c15af2691b39bba30
iv_n94_613=d3fe01e99bd0967e80dccfc0739f93d5 #iPhone4,1
key_n94_613=35343d5139e0313c81ee59dbae292da26e739ed75b3da5db9da7d4d26046498c

function BasebandDetect {
    if [ $ProductType == iPad2,2 ]; then
        BasebandURL=http://appldnld.apple.com/iOS9.3.5/031-74153-20160825-1250B23E-6717-11E6-AB83-973F34D2D062/iPad2,2_9.3.5_13G36_Restore.ipsw
        Baseband=Firmware/ICE3_04.12.09_BOOT_02.13.Release.bbfw
    elif [ $ProductType == iPad2,3 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/041-80042-20190722-68F07B91-8EA1-4A3B-A930-35314A006ECB/iPad2,3_9.3.6_13G37_Restore.ipsw
        Baseband=Firmware/Phoenix-3.6.03.Release.bbfw
    elif [ $ProductType == iPad2,6 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/041-80040-20190722-B1E89CC8-5209-40C3-AEE9-63C29D38BDEB/iPad2,6_9.3.6_13G37_Restore.ipsw
        Baseband=Firmware/Mav5-11.80.00.Release.bbfw
    elif [ $ProductType == iPad2,7 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/041-80041-20190722-673B8756-0A63-4BB6-9855-ACE2381695AF/iPad2,7_9.3.6_13G37_Restore.ipsw
        Baseband=Firmware/Mav5-11.80.00.Release.bbfw
    elif [ $ProductType == iPad3,2 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/041-80039-20190722-E632D5D2-2F3C-498F-B83F-7067D9D90B33/iPad3,2_9.3.6_13G37_Restore.ipsw
        Baseband=Firmware/Mav4-6.7.00.Release.bbfw
    elif [ $ProductType == iPad3,3 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/041-80044-20190722-6C65AD27-69D8-499C-BC15-DE7AC74DE2BD/iPad3,3_9.3.6_13G37_Restore.ipsw
        Baseband=Firmware/Mav4-6.7.00.Release.bbfw
    elif [ $ProductType == iPad3,5 ] || [ $ProductType == iPad3,6 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/091-25014-20190722-0C1B95A6-992C-11E9-A2EE-E1C9A77C2E40/iPad_32bit_10.3.4_14G61_Restore.ipsw 
        Baseband=Firmware/Mav5-11.80.00.Release.bbfw
    elif [ $ProductType == iPhone4,1 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/041-80043-20190722-6C65AD27-69D8-499C-BC15-DE7AC74DE2BD/iPhone4,1_9.3.6_13G37_Restore.ipsw
        Baseband=Firmware/Trek-6.7.00.Release.bbfw
    elif [ $ProductType == iPhone5,1 ] || [ $ProductType == iPhone5,2 ]; then
        BasebandURL=http://updates-http.cdn-apple.com/2019/ios/091-25277-20190722-0C1B94DE-992C-11E9-A2EE-E2C9A77C2E40/iPhone_4.0_32bit_10.3.4_14G61_Restore.ipsw
        Baseband=Firmware/Mav5-11.80.00.Release.bbfw
    else # For Wi-Fi only devices
        Baseband=0
    fi
}

function Clean {
    # Clean up files (called on MainMenu and trap dependency)
    rm -rf iP*/ tmp/ $(ls ${UniqueChipID}_${ProductType}_${DowngradeVersion}-*.shsh2 2>/dev/null) $(ls *.bbfw 2>/dev/null) BuildManifest.plist
}

function MainMenu {
    Clean
    mkdir tmp
    
    if [ $(lsusb | grep -c '1227') == 1 ]; then
        read -p "[Input] Device in DFU mode detected. Is the device in kDFU mode? (y/N) " kDFUManual
        if [[ $kDFUManual == y ]] || [[ $kDFUManual == Y ]]; then
            read -p "[Input] Enter ProductType (eg. iPad2,1): " ProductType
            if [ $(which irecovery) ]; then
                # Get ECID with irecovery (optional)
                echo "[Log] Getting UniqueChipID (ECID) with irecovery..."
                UniqueChipID=$(sudo irecovery -q | grep 'ECID:' | cut -c 7-)
            else
                read -p "[Input] Enter UniqueChipID (ECID): " UniqueChipID
            fi
            BasebandDetect
            echo "[Log] Downgrading device $ProductType in kDFU mode..."
            Mode='Downgrade'
            SelectVersion
        else
            echo "[Error] Please put the device in normal mode and jailbroken before proceeding"
            exit
        fi
    elif [ ! $ProductType ]; then
        echo "[Error] Please plug the device in and trust this computer before proceeding"
        exit
    fi
    BasebandDetect
    
    echo "Main Menu"
    echo
    echo "HardwareModel: $HardwareModel"
    echo "ProductType: $ProductType"
    echo "ProductVersion: $ProductVersion"
    echo "UniqueChipID (ECID): $UniqueChipID"
    echo
    echo "[Input] Select an option:"
    select opt in "Downgrade device" "Save OTA blobs" "Just put device in kDFU mode" "(Re-)Install Dependencies" "Exit"; do
        case $opt in
            "Downgrade device" ) Mode='Downgrade'; SelectVersion; break;;
            "Save OTA blobs" ) Mode='SaveOTABlobs'; SelectVersion; break;;
            "Just put device in kDFU mode" ) Mode='kDFU'; Select841; break;;
            "(Re-)Install Dependencies" ) InstallDependencies; break;;
            "Exit" ) exit;;
            *) MainMenu;;
        esac
    done
}

function SelectVersion {
    if [ $ProductType == iPad2,1 ] || [ $ProductType == iPad2,2 ] ||
       [ $ProductType == iPad2,3 ] || [ $ProductType == iPhone4,1 ]; then
        echo "[Input] Select iOS version:"
        if [[ $Mode == 'Downgrade' ]]; then
            select opt in "iOS 8.4.1" "iOS 6.1.3" "Other" "Back"; do
                case $opt in
                    "iOS 8.4.1" ) Select841; break;;
                    "iOS 6.1.3" ) Select613; break;;
                    "Other" ) SelectOther; break;;
                    "Back" ) MainMenu; break;;
                    *) SelectVersion;;
                esac
            done
        else
            select opt in "iOS 8.4.1" "iOS 6.1.3" "Back"; do
                case $opt in
                    "iOS 8.4.1" ) Select841; break;;
                    "iOS 6.1.3" ) Select613; break;;
                    "Back" ) MainMenu; break;;
                    *) SelectVersion;;
                esac
            done
        fi
    elif [[ $Mode == 'Downgrade' ]]; then
        echo "[Input] Select iOS version:"
        select opt in "iOS 8.4.1" "Other" "Back"; do
            case $opt in
                "iOS 8.4.1" ) Select841; break;;
                "Other" ) SelectOther; break;;
                "Back" ) MainMenu; break;;
                *) SelectVersion;;
            esac
        done
    else
        Select841
    fi
}

function Select841 {
    echo "iOS 8.4.1 $Mode"
    iBSS="iBSS.$HardwareModelLower.RELEASE"
    DowngradeVersion="8.4.1"
    DowngradeBuildVer="12H321"
    iv=iv_$HardwareModelLower
    key=key_$HardwareModelLower
    Action
}

function Select613 {
    echo "iOS 6.1.3 $Mode"
    iBSS="iBSS.${HardwareModelLower}ap.RELEASE"
    DowngradeVersion="6.1.3"
    DowngradeBuildVer="10B329"
    iv=iv_${HardwareModelLower}_613
    key=key_${HardwareModelLower}_613
    Action
}

function SelectOther {
    echo "Other $Mode"
    iBSS="iBSS.$HardwareModelLower.RELEASE"
    iv=iv_$HardwareModelLower
    key=key_$HardwareModelLower
    NotOTA=1
    read -p "[Input] Path to IPSW (drag IPSW to terminal window): " IPSW
    IPSW="$(basename "$IPSW" .ipsw)"
    read -p "[Input] Path to SHSH (drag SHSH to terminal window): " SHSH
    Downgrade
}

function Action {
    if [[ $Mode == 'Downgrade' ]]; then
        Downgrade
    elif [[ $Mode == 'SaveOTABlobs' ]]; then
        SaveOTABlobs
    elif [[ $Mode == 'kDFU' ]]; then
        kDFU
    fi
}

function SaveOTABlobs {
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${DowngradeVersion}.plist"
    echo "[Log] Saving $DowngradeVersion blobs with tsschecker..."
    env "LD_PRELOAD=libcurl.so.3" resources/tools/tsschecker_$platform -d $ProductType -i $DowngradeVersion -o -s -e $UniqueChipID -m $BuildManifest
    SHSH=$(ls ${UniqueChipID}_${ProductType}_${DowngradeVersion}-*.shsh2)
    if [ ! -e "$SHSH" ]; then
        echo "[Error] Saving $DowngradeVersion blobs failed. Please run the script again"
        echo "It is also possible that $DowngradeVersion for $ProductType is no longer signed"
        exit
    fi
    mkdir -p saved/shsh 2>/dev/null
    cp "$SHSH" saved/shsh
}

function kDFU {
    if [ ! -e saved/$iBSS.dfu ]; then
        # Downloading 8.4.1 iBSS for "other" downgrades
        # This is because this script only provides 8.4.1 iBSS IV and Keys
        echo "[Log] Downloading iBSS..."
        dllink=$(cat resources/firmware/${ProductType}/${DowngradeBuildVer}/url)
        resources/tools/pzb_$platform -g Firmware/dfu/${iBSS}.dfu -o $iBSS.dfu $dllink
        mkdir -p saved/$ProductType 2>/dev/null
        mv $iBSS.dfu saved/$ProductType
    fi
    echo "[Log] Decrypting iBSS..."
    echo "IV = ${!iv}"
    echo "Key = ${!key}"
    resources/tools/xpwntool_$platform saved/$ProductType/$iBSS.dfu tmp/iBSS.dec -k ${!key} -iv ${!iv} -decrypt
    dd bs=64 skip=1 if=tmp/iBSS.dec of=tmp/iBSS.dec2
    echo "[Log] Patching iBSS..."
    bspatch tmp/iBSS.dec2 tmp/pwnediBSS resources/patches/$iBSS.patch
    
    # Regular kloader only works on iOS 6 to 9, so other versions are provided for iOS 5 and 10
    if [[ $VersionDetect == 1 ]]; then
        kloader='kloader_hgsp'
    elif [[ $VersionDetect == 5 ]]; then
        kloader='kloader5'
    else
        kloader='kloader'
    fi

    if [[ $VersionDetect == 1 ]]; then
        # SSH is unreliable/not working on iOS 10 devices, so ifuse+MTerminal is used instead
        # It's less convenient, but it should work every time
        if [ ! $(which ifuse) ]; then
            echo "[Error] ifuse not found. Please re-install dependencies and try again"
            echo "For macOS systems, install osxfuse and ifuse with brew"
            exit
        fi
        WifiAddr=$(ideviceinfo -s | grep 'WiFiAddress' | cut -c 14-)
        WifiAddrDecr=$(echo $(printf "%x\n" $(expr $(printf "%d\n" 0x$(echo "${WifiAddr}" | tr -d ':')) - 1)) | sed 's/\(..\)/\1:/g;s/:$//')
        echo '#!/bin/bash' > tmp/pwn.sh
        echo "nvram wifiaddr=$WifiAddrDecr
        chmod 755 kloader_hgsp
        ./kloader_hgsp pwnediBSS" >> tmp/pwn.sh
        echo "[Log] Mounting device with ifuse..."
        mkdir mount
        ifuse mount
        echo "[Log] Copying stuff to device..."
        cp "tmp/pwn.sh" "resources/tools/$kloader" "tmp/pwnediBSS" "mount/"
        echo "[Log] Unmounting device..."
        sudo umount mount
        echo
        echo "[Log] Open MTerminal and run these commands:"
        echo
        echo '$ su'
        echo "(enter root password, default is 'alpine')"
        echo "# cd Media"
        echo "# chmod +x pwn.sh"
        echo "# ./pwn.sh"
    else
        # SSH: Send kloader and pwnediBSS to device root and run kloader as root
        echo "Make sure SSH is installed and working on the device!"
        echo "Please enter Wi-Fi IP address of device for SSH connection"
        read -p "[Input] IP Address: " IPAddress
        echo "[Log] Coonecting to device via SSH... Please enter root password when prompted (default is 'alpine')"
        echo "[Log] Copying stuff to device..."
        scp resources/tools/$kloader tmp/pwnediBSS root@$IPAddress:/
        if [ $? == 1 ]; then
            echo "[Error] Cannot connect to device via SSH. Please check your ~/.ssh/known_hosts file and try again"
            exit
        fi
        echo "[Log] Entering kDFU mode..."
        ssh root@$IPAddress "chmod 755 /$kloader && /$kloader /pwnediBSS" &
    fi
    echo
    echo "Press home/power button once when screen goes black on the device"
    FindDFU
}

function FindDFU {
    echo "[Log] Finding device in DFU mode..."
    while [[ $DFUDevice != 1 ]]; do
        DFUDevice=$(lsusb | grep -c "1227")
        sleep 2
    done
    echo "[Log] Found device in DFU mode."
}

function Downgrade {
    # Firmware keys for 8.4.1 and 6.1.3
    rm -rf resources/firmware
    echo "[Log] Downloading firmware keys..."
    curl -L https://github.com/LukeZGD/32bit-OTA-Downgrader/archive/firmware.zip -o tmp/firmware.zip
    unzip -q tmp/firmware.zip -d tmp
    mkdir resources/firmware
    mv tmp/32bit-OTA-Downgrader-firmware/firmware/* resources/firmware
    
    if [ ! $NotOTA ]; then
        SaveOTABlobs
        IPSW="${ProductType}_${DowngradeVersion}_${DowngradeBuildVer}_Restore"
        if [ ! -e "$IPSW.ipsw" ]; then
            echo "[Log] iOS $DowngradeVersion IPSW is missing, downloading IPSW..."
            curl -L $(cat resources/firmware/${ProductType}/${DowngradeBuildVer}/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
        echo "[Log] Verifying IPSW..."
        SHA1IPSW=$(cat resources/firmware/${ProductType}/${DowngradeBuildVer}/sha1sum)
        SHA1IPSWL=$(sha1sum "$IPSW.ipsw" | awk '{print $1}')
        if [ $SHA1IPSW != $SHA1IPSWL ]; then
            echo "[Error] SHA1 of IPSW does not match!"
            read -p "[Input] Continue anyway? (y/N)" Continue
            if [[ $Continue != y ]] && [[ $Continue != Y ]]; then
                exit
            fi
        fi
        echo "[Log] Extracting iBSS from IPSW..."
        mkdir -p saved/$ProductType 2>/dev/null
        unzip -j "$IPSW.ipsw" Firmware/dfu/$iBSS.dfu -d saved/$ProductType
    fi
    
    if [ ! $kDFUManual ]; then
        kDFU
    fi
    
    echo "[Log] Extracting IPSW..."
    unzip -q "$IPSW.ipsw" -d "$IPSW/"
    
    echo "[Log] Preparing for futurerestore (starting local server)..."
    cd resources
    sudo python3 -m http.server 80 &
    cd ..
    
    if [ $Baseband == 0 ]; then
        echo "[Log] Device $ProductType has no baseband"
        echo "[Log] Proceeding to futurerestore..."
        sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t "$SHSH" --no-baseband --use-pwndfu "$IPSW.ipsw"
    else
        if [ ! -e saved/$ProductType/*.bbfw ]; then
            echo "[Log] Downloading baseband..."
            resources/tools/pzb_$platform -g $Baseband -o $Baseband $BasebandURL
            resources/tools/pzb_$platform -g BuildManifest.plist -o BuildManifest.plist $BasebandURL
            mkdir -p saved/$ProductType 2>/dev/null
            cp $(ls *.bbfw) BuildManifest.plist saved/$ProductType
        else
            cp saved/$ProductType/*.bbfw saved/$ProductType/BuildManifest.plist .
        fi
        if [ ! -e *.bbfw ]; then
            echo "[Error] Downloading baseband failed!"
            echo "Your device is still in kDFU mode, you may run the script again"
            echo "If you continue, futurerestore can attempt to download the baseband again"
            read -p "[Input] Continue anyway? (y/N)" Continue
            if [[ $Continue == y ]] || [[ $Continue == Y ]]; then
                echo "[Log] Proceeding to futurerestore..."
                sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t "$SHSH" --latest-baseband --use-pwndfu "$IPSW.ipsw"
            else
                exit
            fi
        fi
        if [[ $Continue != y ]] && [[ $Continue != Y ]]; then
            echo "[Log] Proceeding to futurerestore..."
            sudo env "LD_PRELOAD=libcurl.so.3" resources/tools/futurerestore_$platform -t "$SHSH" -b $(ls *.bbfw) -p BuildManifest.plist --use-pwndfu "$IPSW.ipsw"
        fi
    fi
        
    echo
    echo "[Log] futurerestore done!"    
    echo "[Log] Stopping local server..."
    (ps aux | awk '/python3/ {print "sudo kill -9 "$2}' | bash) 2>/dev/null
    echo "[Log] Downgrade script done!"
    exit
}

function InstallDependencies {
    echo "Install Dependencies"

    . /etc/os-release 2>/dev/null
    if [[ $(which pacman) ]] || [[ $NAME == "Arch Linux" ]]; then
        Arch
    elif [[ $NAME == "Ubuntu" ]] && [[ $VERSION_ID == "16.04" ]]; then
        Ubuntu
    elif [[ $(which apt) ]] || [[ $NAME == "Ubuntu" ]] && [[ $VERSION_ID == "18.04" ]]; then
        Ubuntu
        Ubuntu1804
    elif [[ $OSTYPE == "darwin"* ]]; then
        macOS
    else
        echo "[Input] Distro not detected/supported. Please select manually"
        select opt in "Ubuntu Xenial" "Ubuntu Bionic" "Arch Linux" "macOS"; do
        case $opt in
            "Ubuntu Xenial" ) Ubuntu; break;;
            "Ubuntu Bionic" ) Ubuntu; Ubuntu1804; break;;
            "Arch Linux" ) Arch; break;;
            "macOS" ) macOS; break;;
        esac
    done
    fi
    echo "[Log] Install script done! Please run the script again to proceed"
}

function Arch {
    echo "[Log] Installing dependencies for Arch with pacman..."
    sudo pacman -Sy --noconfirm bsdiff curl ifuse libcurl-compat libpng12 libzip openssh openssl-1.0 python unzip usbutils
    sudo pacman -S --noconfirm libimobiledevice usbmuxd
    sudo ln -sf /usr/lib/libzip.so.5 /usr/lib/libzip.so.4
}

function macOS {
    read -p "[Input] Warning: macOS dependency install script is not fully tested and supported. Continue anyway? (y/N) " Continue
    if [[ $Continue != y ]] && [[ $Continue != Y ]]; then
        echo "[Error] Please install these dependencies manually with brew to proceed:"
        echo "libimobiledevice, usbmuxd, libzip, lsusb, osxfuse, ifuse"
        exit
    fi
    if [[ ! $(which brew) ]]; then
        echo "[Log] Homebrew is not detected/installed, installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    fi
    echo "[Log] Installing dependencies for macOS with Homebrew..."
    brew uninstall --ignore-dependencies usbmuxd
    brew uninstall --ignore-dependencies libimobiledevice
    brew install --HEAD usbmuxd
    brew install --HEAD libimobiledevice
    brew install libzip lsusb
    brew cask install osxfuse
    brew install ifuse
}

function Ubuntu {
    echo "[Log] Running APT update..." 
    sudo apt update
    echo "[Log] Installing dependencies for Ubuntu with APT..."
    sudo apt -y install bsdiff curl ifuse libimobiledevice-utils libzip4 python3 usbmuxd
}

function Ubuntu1804 {
    echo "[Log] Installing dependencies for Ubuntu 18.04 with APT..."
    sudo apt -y install binutils
    mkdir tmp
    cd tmp
    apt download -o=dir::cache=. libcurl3
    ar x libcurl3* data.tar.xz
    tar xf data.tar.xz
    sudo cp usr/lib/x86_64-linux-gnu/libcurl.so.4.* /usr/lib/libcurl.so.3
    curl -L http://mirrors.edge.kernel.org/ubuntu/pool/main/libp/libpng/libpng12-0_1.2.54-1ubuntu1.1_amd64.deb -o libpng12.deb
    sudo dpkg -i libpng12.deb
    cd ..
}

# --- MAIN SCRIPT STARTS HERE ---

trap Clean INT TERM EXIT
clear
echo "******* 32bit-OTA-Downgrader *******"
echo "    Downgrade script by LukeZGD     "
echo

if [[ $OSTYPE == "linux-gnu" ]]; then
    platform='linux'
elif [[ $OSTYPE == "darwin"* ]]; then
    platform='macos'
else
    echo "[Error] OSTYPE unknown/not supported"
    echo "Supports Linux and macOS only"
    exit
fi
if [[ ! $(ping -c1 google.com 2>/dev/null) ]]; then
    echo "[Error] Please check your Internet connection before proceeding"
    exit
fi
if [[ $(uname -m) != 'x86_64' ]]; then
    echo "[Error] Only x86_64 distributions are supported. Use a 64-bit distro and try again"
    exit
fi

HardwareModel=$(ideviceinfo -s | grep 'HardwareModel' | cut -c 16-)
HardwareModelLower=$(echo $HardwareModel | tr '[:upper:]' '[:lower:]' | sed 's/.\{2\}$//')
ProductType=$(ideviceinfo -s | grep 'ProductType' | cut -c 14-)
[ ! $ProductType ] && ProductType=$(ideviceinfo | grep 'ProductType' | cut -c 14-)
ProductVersion=$(ideviceinfo -s | grep 'ProductVersion' | cut -c 17-)
VersionDetect=$(echo $ProductVersion | cut -c 1)
UniqueChipID=$(ideviceinfo -s | grep 'UniqueChipID' | cut -c 15-)

if [ ! $(which bspatch) ] || [ ! $(which ideviceinfo) ] || [ ! $(which lsusb) ] || [ ! $(which ssh) ] || [ ! $(which python3) ]; then
    InstallDependencies
else
    chmod +x resources/tools/*
    MainMenu
fi
