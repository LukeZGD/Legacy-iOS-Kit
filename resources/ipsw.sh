#!/bin/bash

JailbreakSet() {
    Jailbreak=1
    IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"
    [[ -e "$IPSWCustom.ipsw" ]] && Verify=

    if [[ $ProductType == "iPhone4,1" || $ProductType == "iPhone5,2" ]] && [[ $OSVer == "8.4.1" ]]; then
        Input "Jailbreak Tool Option"
        Echo "* This option is set to daibutsu by default (1)."
        Selection=("daibutsu" "EtasonJB")
        Input "Select your option:"
        select opt in "${Selection[@]}"; do
        case $opt in
            "EtasonJB" ) break;;
            * ) JBDaibutsu=1; break;;
        esac
        done
    elif [[ $ProductType == "iPad2,4" || $ProductType == "iPad2,5" || $ProductType == "iPad2,6" ||
            $ProductType == "iPad2,7" || $ProductType == "iPod5,1" ]] ||
         [[ $ProductType == "iPad3"* && $DeviceProc == 5 ]]; then
         [[ $OSVer == "8.4.1" ]] && JBDaibutsu=1
    fi

    if [[ $JBDaibutsu == 1 ]]; then
        JBName="daibutsu"
        IPSWCustom="${IPSWCustom}D"
    elif [[ $OSVer == "8.4.1" ]]; then
        JBName="EtasonJB"
        IPSWCustom="${IPSWCustom}E"
    elif [[ $OSVer == "6.1.3" ]]; then
        JBName="p0sixspwn"
    fi
    Log "Using $JBName for the jailbreak"
}

MemoryOption() {
    if [[ $Jailbreak == 1 && $Verify == 1 ]]; then
        Input "Memory Option for creating custom IPSW"
        Echo "* This option makes creating the custom IPSW faster, but it requires at least 8GB of RAM."
        Echo "* If you do not have enough RAM, disable this option and make sure that you have enough storage space."
        Echo "* This option is enabled by default (Y)."
        read -p "$(Input 'Enable this option? (Y/n):')" JBMemory
        if [[ $JBMemory == 'N' || $JBMemory == 'n' ]]; then
            Log "Memory option disabled by user."
        else
            Log "Memory option enabled."
        fi
        echo
    fi
}

IPSWFind() {
    IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
    if [[ ! -e "$IPSW.ipsw" && $Verify == 1 ]]; then
        Log "iOS $OSVer IPSW for $ProductType cannot be found."
        Echo "* If you already downloaded the IPSW, move/copy it to the directory where the script is located."
        Echo "* Do NOT rename the IPSW as the script will fail to detect it."
        Echo "* The script will now proceed to download it for you. If you want to download it yourself, here is the link: $(cat $Firmware/$BuildVer/url)"
        Log "Downloading IPSW... (Press Ctrl+C to cancel)"
        curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
        mv tmp/$IPSW.ipsw .
    fi
}

IPSWVerify() {
    Log "Verifying IPSW..."
    IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
    Log "Expected SHA1sum: $IPSWSHA1"
    IPSWSHA1L=$(shasum $IPSW.ipsw | awk '{print $1}')
    Log "Actual SHA1sum:   $IPSWSHA1L"
    if [[ $IPSWSHA1L != $IPSWSHA1 ]]; then
        Error "Verifying IPSW failed. Your IPSW may be corrupted or incomplete. Delete/replace the IPSW and run the script again" \
        "SHA1sum mismatch. Expected $IPSWSHA1, got $IPSWSHA1L"
    fi
    Log "IPSW SHA1sum matches."
}

IPSW32() {
    local Bundle="Down_${ProductType}_${OSVer}_${BuildVer}.bundle"
    local ExtraArgs
    local JBFiles
    local JBSHA1

    if [[ $IPSWRestore == $IPSWCustom ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $JBDaibutsu == 1 ]]; then
        ExtraArgs+="-daibutsu "
        echo '#!/bin/bash' > tmp/reboot.sh
        echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" >> tmp/reboot.sh
        echo "nvram -d boot-partition; nvram -d boot-ramdisk" >> tmp/reboot.sh
        echo "/usr/bin/haxx_overwrite -$HWModel" >> tmp/reboot.sh
        JBFiles2=("bin.tar" "cydia.tar" "untether.tar")
        JBSHA1=("98034227c68610f4c7dd48ca9e622314a1e649e7" "2e9e662afe890e50ccf06d05429ca12ce2c0a3a3" "f88ec9a1b3011c4065733249363e9850af5f57c8")
        cd tmp
        for i in {0..2}; do
            local URL="https://github.com/dora2-iOS/daibutsuCFW/raw/main/build/src/"
            (( i > 0 )) && URL+="daibutsu/${JBFiles2[$i]}" || URL+="${JBFiles2[$i]}"
            if [[ ! -e ../resources/jailbreak/${JBFiles2[$i]} ]]; then
                Log "Downloading ${JBFiles2[$i]}..."
                SaveFile $URL ${JBFiles2[$i]} ${JBSHA1[$i]}
                mv ${JBFiles2[$i]} ../resources/jailbreak
            fi
            JBFiles2[$i]=jailbreak/${JBFiles2[$i]}
        done
        cd ..

    elif [[ $Jailbreak == 1 ]]; then
        if [[ $OSVer == "8.4.1" ]]; then
            JBFiles=("fstab.tar" "etasonJB-untether.tar" "Cydia8.tar")
            JBSHA1="6459dbcbfe871056e6244d23b33c9b99aaeca970"
            ExtraArgs+="-s 2305 "
        elif [[ $OSVer == "6.1.3" ]]; then
            JBFiles=("fstab_rw.tar" "p0sixspwn.tar" "Cydia6.tar")
            JBSHA1="1d5a351016d2546aa9558bc86ce39186054dc281"
            ExtraArgs+="-s 1260 "
        else
            Error "No OSVer selected?"
        fi
        if [[ ! -e resources/jailbreak/${JBFiles[2]} ]]; then
            cd tmp
            Log "Downloading ${JBFiles[2]}..."
            SaveFile https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak/${JBFiles[2]} ${JBFiles[2]} $JBSHA1
            mv ${JBFiles[2]} ../resources/jailbreak
            cd ..
        fi
        for i in {0..2}; do
            JBFiles[$i]=jailbreak/${JBFiles[$i]}
        done
    fi
    ExtraArgs+="-bbupdate"

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        [[ $JBMemory != 'N' && $JBMemory != 'n' ]] && ExtraArgs+=" -memory"
        Log "Preparing custom IPSW..."
        cd resources
        rm -rf FirmwareBundles
        if [[ $JBDaibutsu == 1 && -d firmware/JailbreakBundles/$Bundle ]]; then
            cp -R firmware/JailbreakBundles FirmwareBundles
        else
            cp -R firmware/FirmwareBundles FirmwareBundles
        fi
        $ipsw ./../$IPSW.ipsw ./../$IPSWCustom.ipsw $ExtraArgs ${JBFiles[@]}
        cd ..
    fi
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again" \
        "You may try selecting N for memory option"
    fi

    Log "Setting restore IPSW to: $IPSWCustom.ipsw"
    IPSWRestore=$IPSWCustom
}
