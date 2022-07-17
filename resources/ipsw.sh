#!/bin/bash

JailbreakSet() {
    Jailbreak=1
    JBURL="https://github.com/LukeZGD/iOS-OTA-Downgrader-Keys/releases/download/jailbreak"
    [[ -z $IPSWCustom ]] && IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"

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

    [[ $platform == "win" ]] && IPSWCustom="${IPSWCustom}JB"
    if [[ $JBDaibutsu == 1 ]]; then
        JBName="daibutsu"
        IPSWCustom="${IPSWCustom}D"
    elif [[ $OSVer == "8.4.1" ]]; then
        JBName="EtasonJB"
        IPSWCustom="${IPSWCustom}E"
    elif [[ $OSVer == "7.1"* ]]; then
        JBName="Pangu7"
    elif [[ $OSVer == "7"* ]]; then
        JBName="evasi0n7"
    elif [[ $OSVer == "6.1.3" ]]; then
        JBName="p0sixspwn"
    elif [[ $OSVer == "6"* ]]; then
        JBName="evasi0n"
    else
        JBName="unthredeh4il"
    fi
    Log "Using $JBName for the jailbreak"
}

JailbreakOption() {
    Input "Jailbreak Option"
    Echo "* When this option is enabled, your device will be jailbroken on restore."
    if [[ $ProductType == "iPad2,5" || $ProductType == "iPad2,6" || $ProductType == "iPad2,7" ]]; then
        Echo "* Based on some reported issues, Jailbreak Option might be broken for iPad mini 1 devices."
        Echo "* I recommend to disable the option for these devices and sideload EtasonJB, HomeDepot, or daibutsu manually."
    fi
    Echo "* This option is enabled by default (Y)."
    read -p "$(Input 'Enable this option? (Y/n):')" Jailbreak
    if [[ $Jailbreak != 'N' && $Jailbreak != 'n' ]]; then
        JailbreakSet
        Log "Jailbreak option enabled."
    else
        Log "Jailbreak option disabled by user."
    fi

    [[ -z $IPSWCustom ]] && IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"
    if [[ $ProductType == "iPhone3"* ]]; then
        [[ $Jailbreak == 1 ]] && Custom="Custom" || Custom="CustomN"
        IPSWCustom="${ProductType}_${OSVer}_${BuildVer}_${Custom}"
        [[ $OSVer == 4.3* ]] && IPSWCustom="$IPSWCustom-$UniqueChipID"
    fi
    echo

    if [[ $Jailbreak != 1 || $platform == "win" ]]; then
        [[ $ProductType == "iPhone3"* && $OSVer == "7.1.2" ]] && return
    fi
    Input "Memory Option for creating custom IPSW"
    Echo "* This option makes creating the custom IPSW faster, but it requires at least 8GB of RAM."
    Echo "* If you do not have enough RAM, disable this option and make sure that you have enough storage space."
    Echo "* This option is enabled by default (Y)."
    read -p "$(Input 'Enable this option? (Y/n):')" JBMemory
    if [[ $JBMemory == 'N' || $JBMemory == 'n' ]]; then
        Log "Memory option disabled by user."
        JBMemory=
    else
        Log "Memory option enabled."
        JBMemory="-memory"
    fi
    echo
}

JailbreakFiles() {
    local JBSHA1L
    if [[ -e resources/jailbreak/$2 ]]; then
        Log "Verifying $2..."
        JBSHA1L=$(shasum resources/jailbreak/$2 | awk '{print $1}')
        if [[ $JBSHA1L == $3 ]]; then
            return
        fi
        Log "Verifying $2 failed. Deleting existing file for re-download."
        rm resources/jailbreak/$2
    fi
    cd tmp
    SaveFile $1 $2 $3
    mv $2 ../resources/jailbreak
    cd ..
}

IPSWFindVerify() {
    IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
    IPSW7="${ProductType}_7.1.2_11D257_Restore"
    local IPSWDL=$IPSW
    local OSVerDL=$OSVer
    local BuildVerDL=$BuildVer
    if [[ $1 == 712 ]]; then
        IPSWDL=$IPSW7
        OSVerDL="7.1.2"
        BuildVerDL="11D257"
    fi

    if [[ -e "$IPSWCustom.ipsw" ]]; then
        Log "Found existing Custom IPSW. Skipping $OSVerDL IPSW verification."
        return
    fi

    if [[ ! -e "$IPSW.ipsw" ]]; then
        Log "iOS $OSVerDL IPSW for $ProductType cannot be found."
        Echo "* If you already downloaded the IPSW, move/copy it to the directory where the script is located."
        Echo "* Do NOT rename the IPSW as the script will fail to detect it."
        Echo "* The script will now proceed to download it for you. If you want to download it yourself, here is the link: $(cat $Firmware/$BuildVerDL/url)"
        Log "Downloading IPSW... (Press Ctrl+C to cancel)"
        curl -L $(cat $Firmware/$BuildVerDL/url) -o tmp/$IPSWDL.ipsw
        mv tmp/$IPSWDL.ipsw .
    fi

    Log "Verifying $IPSWDL.ipsw..."
    IPSWSHA1=$(cat $Firmware/$BuildVerDL/sha1sum)
    Log "Expected SHA1sum: $IPSWSHA1"
    IPSWSHA1L=$(shasum $IPSWDL.ipsw | awk '{print $1}')
    Log "Actual SHA1sum:   $IPSWSHA1L"
    if [[ $IPSWSHA1L != $IPSWSHA1 ]]; then
        Error "Verifying IPSW failed. Your IPSW may be corrupted or incomplete. Delete/replace the IPSW and run the script again" \
        "SHA1sum mismatch. Expected $IPSWSHA1, got $IPSWSHA1L"
    fi
    Log "IPSW SHA1sum matches."
}

IPSWSetExtract() {
    if [[ -e "$IPSWCustom.ipsw" ]]; then
        Log "Setting restore IPSW to: $IPSWCustom.ipsw"
        IPSWRestore="$IPSWCustom"
    elif [[ -z $IPSWRestore ]]; then
        Log "Setting restore IPSW to: $IPSW.ipsw"
        IPSWRestore="$IPSW"
    fi

    if [[ $1 == "set" ]]; then
        return
    fi
    Log "Extracting IPSW: $IPSWRestore.ipsw"
    unzip -oq "$IPSWRestore.ipsw" -d "$IPSWRestore"/
}

IPSW32() {
    local ExtraArgs
    local JBFiles
    local JBFiles2
    local JBSHA1
    BBUpdate="-bbupdate"

    if [[ -e $IPSWCustom.ipsw ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $JBDaibutsu == 1 ]]; then
        [[ $platform == "win" ]] && ipsw="${ipsw}2"
        ExtraArgs+="-daibutsu "
        echo '#!/bin/bash' > tmp/reboot.sh
        echo "mount_hfs /dev/disk0s1s1 /mnt1; mount_hfs /dev/disk0s1s2 /mnt2" >> tmp/reboot.sh
        echo "nvram -d boot-partition; nvram -d boot-ramdisk" >> tmp/reboot.sh
        echo "/usr/bin/haxx_overwrite -$HWModel" >> tmp/reboot.sh
        #JBFiles=("../resources/jailbreak/sshdeb.tar")                             # uncomment to add openssh to custom ipsw
        #JailbreakFiles $JBURL/sshdeb.tar 0bffece0f8fd939c479159b57e923dd8c06191d3 # uncomment to add openssh to custom ipsw
        JBFiles2=("bin.tar" "cydia.tar" "untether.tar")
        JBSHA1=("98034227c68610f4c7dd48ca9e622314a1e649e7" "2e9e662afe890e50ccf06d05429ca12ce2c0a3a3" "f88ec9a1b3011c4065733249363e9850af5f57c8")
        mkdir -p tmp/jailbreak
        for i in {0..2}; do
            JBURL="https://github.com/LukeZGD/daibutsuCFW/raw/main/build/src/"
            (( i > 0 )) && JBURL+="daibutsu/${JBFiles2[$i]}" || JBURL+="${JBFiles2[$i]}"
            JailbreakFiles $JBURL ${JBFiles2[$i]} ${JBSHA1[$i]}
            cp resources/jailbreak/${JBFiles2[$i]} tmp/jailbreak/
        done

    elif [[ $Jailbreak == 1 ]]; then
        if [[ $OSVer == "8.4.1" ]]; then
            JBFiles=("fstab.tar" "etasonJB-untether.tar" "Cydia8.tar")
            JBSHA1="6459dbcbfe871056e6244d23b33c9b99aaeca970"
            ExtraArgs+="-s 2305"
        elif [[ $OSVer == "6.1.3" ]]; then
            JBFiles=("fstab_rw.tar" "p0sixspwn.tar" "Cydia6.tar")
            JBSHA1="1d5a351016d2546aa9558bc86ce39186054dc281"
            ExtraArgs+="-s 1260"
        fi
        JailbreakFiles $JBURL/${JBFiles[2]} ${JBFiles[2]} $JBSHA1
        for i in {0..2}; do
            JBFiles[$i]=../resources/jailbreak/${JBFiles[$i]}
        done
    fi
    if [[ $platform == "win" ]]; then
        BBUpdate=
        WinBundles="windows/"
    elif [[ $ProductType == "iPad2,3" ]]; then
        BBUpdate=
        [[ $Jailbreak != 1 ]] && IPSWCustom+="N"
        IPSWCustom+="B"
    fi

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Log "Preparing custom IPSW..."
        cd tmp
        if [[ $JBDaibutsu == 1 ]]; then
            cp -R ../resources/firmware/${WinBundles}JailbreakBundles FirmwareBundles
        else
            cp -R ../resources/firmware/${WinBundles}FirmwareBundles FirmwareBundles
        fi
        $ipsw ./../$IPSW.ipsw ./../$IPSWCustom.ipsw $ExtraArgs $BBUpdate $JBMemory ${JBFiles[@]}
        cd ..
    fi

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again" \
        "You may try selecting N for memory option"
    fi
}

IPSW4() {
    local ExtraArgs
    local IV
    local JBFiles
    local JBSHA1
    local Key

    if [[ -e $IPSWCustom.ipsw ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $OSVer == 6.1.3 ]]; then
        IV=b559a2c7dae9b95643c6610b4cf26dbd
        Key=3dbe8be17af793b043eed7af865f0b843936659550ad692db96865c00171959f
    elif [[ $OSVer == 6.1.2 ]]; then
        IV=c939629e3473fdb67deae0c45582506d
        Key=cbcd007712618cb6ab3be147f0317e22e7cceadb344e99ea1a076ef235c2c534
    elif [[ $OSVer == 6.1 ]]; then
        IV=4d76b7e25893839cfca478b44ddef3dd
        Key=891ed50315763dac51434daeb8543b5975a555fb8388cc578d0f421f833da04d
    elif [[ $OSVer == 6.0.1 ]]; then
        IV=44ffe675d6f31167369787a17725d06c
        Key=8d539232c0e906a9f60caa462f189530f745c4abd81a742b4d1ec1cb8b9ca6c3
    elif [[ $OSVer == 6.0 ]]; then
        IV=7891928b9dd0dd919778743a2c8ec6b3
        Key=838270f668a05a60ff352d8549c06d2f21c3e4f7617c72a78d82c92a3ad3a045
    elif [[ $BuildVer == 9B206 ]]; then
        IV=b1846de299191186ce3bbb22432eca12
        Key=e8e26976984e83f967b16bdb3a65a3ec45003cdf2aaf8d541104c26797484138
    elif [[ $BuildVer == 9B208 ]]; then
        IV=71fe96da25812ff341181ba43546ea4f
        Key=6377d34deddf26c9b464f927f18b222be75f1b5547e537742e7dfca305660fea
    elif [[ $OSVer == 5.1 ]]; then
        IV=b1846de299191186ce3bbb22432eca12
        Key=e8e26976984e83f967b16bdb3a65a3ec45003cdf2aaf8d541104c26797484138
    elif [[ $OSVer == 5.0.1 ]]; then
        IV=49eb54980a0024f91b079faf0ee87f67
        Key=c3a49f0059075e1453dacec4c3e4d89bd7a433ee19c8d48e4695d89b4c84a373
    elif [[ $OSVer == 5.0 ]]; then
        IV=15dd404efbb24a842d08dcde21e777a0
        Key=71614af73814c3a8e6724d592ecfccdbace766dad5eb39b0b8313387e94d2964
    elif [[ $OSVer == 4.3.5 ]]; then
        IV=986032eecd861c37ca2a86b6496a3c0d
        Key=b4e300c54a9dd2e648ead50794e9bf2205a489c310a1c70a9fae687368229468
        ExtraArgs="--logo4 "
    elif [[ $OSVer == 4.3.3 ]]; then
        IV=bb3fc29dd226fac56086790060d5c744
        Key=c2ead1d3b228a05b665c91b4b1ab54b570a81dffaf06eaf1736767bcb86e50de
        ExtraArgs="--logo4 --433 "
    elif [[ $OSVer == 4.3 ]]; then
        IV=9f11c07bde79bdac4abb3f9707c4b13c
        Key=0958d70e1a292483d4e32ed1e911d2b16b6260856be67d00a33b6a1801711d32
        ExtraArgs="--logo4 --433 "
    fi

    if [[ $Jailbreak == 1 ]]; then
        if [[ $OSVer == 7.1.2 ]]; then
            JBFiles=(Cydia7.tar panguaxe.tar fstab7.tar)
            JBSHA1=bba5022d6749097f47da48b7bdeaa3dc67cbf2c4
        elif [[ $OSVer == 6.1.3 ]]; then
            JBFiles=(Cydia6.tar p0sixspwn.tar)
            JBSHA1=1d5a351016d2546aa9558bc86ce39186054dc281
        elif [[ $OSVer == 6.* ]]; then
            JBFiles=(Cydia6.tar evasi0n6-untether.tar)
            JBSHA1=1d5a351016d2546aa9558bc86ce39186054dc281
        elif [[ $OSVer == 5.* || $OSVer == 4.3* ]]; then
            JBFiles=(Cydia5.tar unthredeh4il.tar)
            JBSHA1=f5b5565640f7e31289919c303efe44741e28543a
        fi
        [[ $OSVer != 7.1.2 ]] && JBFiles+=(fstab_rw.tar)
        JailbreakFiles $JBURL/${JBFiles[0]} ${JBFiles[0]} $JBSHA1
        for i in {0..2}; do
            JBFiles[$i]=../resources/jailbreak/${JBFiles[$i]}
        done
    fi

    cd tmp
    if [[ $OSVer == "7.1.2" && ! -e $IPSWCustom.ipsw ]]; then
        Log "Preparing custom IPSW..."
        cp -rf ../resources/firmware/FirmwareBundles .
        $ipsw ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -S 50 ${JBFiles[@]}
    elif [[ ! -e $IPSWCustom.ipsw ]]; then
        echo
        Input "Verbose Boot Option"
        Echo "* When enabled, the device will have verbose boot on restore."
        Echo "* This option is enabled by default (Y)."
        read -p "$(Input 'Enable this option? (Y/n):')" opt
        if [[ $opt != 'N' && $opt != 'n' ]]; then
            ExtraArgs+="-b -v"
            Log "Verbose boot option enabled."
        else
            Log "Verbose boot option disabled by user."
        fi
        Log "Preparing custom IPSW with ch3rryflower..."
        cp -rf ../$cherrymac/FirmwareBundles ../$cherrymac/src .
        unzip -j ../$IPSW.ipsw Firmware/all_flash/all_flash.${HWModel}ap.production/iBoot*
        mv iBoot.${HWModel}ap.RELEASE.img3 tmp
        $xpwntool tmp ibot.dec -iv $IV -k $Key
        ../$cherry/bin/iBoot32Patcher ibot.dec ibot.pwned --rsa --boot-partition --boot-ramdisk $ExtraArgs
        $xpwntool ibot.pwned iBoot -t tmp
        echo "0000010: 6365" | xxd -r - iBoot
        echo "0000020: 6365" | xxd -r - iBoot
        $cherrybin ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -derebusantiquis ../$IPSW7.ipsw iBoot ${JBFiles[@]}
    fi
    cd ..

    if [[ $OSVer == 4.3* ]]; then
        Log "iOS 4 Fix" # From ios4fix
        zip -d $IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/manifest
        cd tmp/src/n90ap/Firmware/all_flash/all_flash.n90ap.production
        unzip -j ../../../../../../$IPSW.ipsw Firmware/all_flash/all_flash*/applelogo*
        mv -v applelogo-640x960.s5l8930x.img3 applelogo4-640x960.s5l8930x.img3
        echo "0000010: 34" | xxd -r - applelogo4-640x960.s5l8930x.img3
        echo "0000020: 34" | xxd -r - applelogo4-640x960.s5l8930x.img3
        if [[ $platform == "macos" ]]; then
            plutil -extract 'APTicket' xml1 ../../../../../../$SHSH -o 'apticket.plist'
            cat apticket.plist | sed -ne '/<data>/,/<\/data>/p' | sed -e "s/<data>//" | sed "s/<\/data>//" | awk '{printf "%s",$0}' | base64 --decode > apticket.der
        else
            $xmlstarlet sel -t -m "/plist/dict/key[.='APTicket']" -v "following-sibling::data[1]" ../../../../../../$SHSH > apticket.plist
            sed -i -e 's/[ \t]*//' apticket.plist
            cat apticket.plist | base64 --decode > apticket.der
        fi
        ../../../../../$xpwntool apticket.der applelogoT-640x960.s5l8930x.img3 -t scab_template.img3
        cd ../../..
        zip -r0 ../../../$IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/manifest
        zip -r0 ../../../$IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/applelogo4-640x960.s5l8930x.img3
        zip -r0 ../../../$IPSWCustom.ipsw Firmware/all_flash/all_flash.n90ap.production/applelogoT-640x960.s5l8930x.img3
        cd ../../..
    fi

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again" \
        "You may try selecting N for memory option"
    fi
}

IPSW64() {
    if [[ -e $IPSWCustom.ipsw ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    Log "Preparing custom IPSW..."
    $bspatch $IPSW/Firmware/dfu/$iBSS.im4p $iBSS.im4p resources/patches/$iBSS.patch
    $bspatch $IPSW/Firmware/dfu/$iBEC.im4p $iBEC.im4p resources/patches/$iBEC.patch
    if [[ $ProductType == "iPad4"* ]]; then
        $bspatch $IPSW/Firmware/dfu/$iBSSb.im4p $iBSSb.im4p resources/patches/$iBSSb.patch
        $bspatch $IPSW/Firmware/dfu/$iBECb.im4p $iBECb.im4p resources/patches/$iBECb.patch
        mv -f $iBSSb.im4p $iBECb.im4p $IPSW/Firmware/dfu
    fi
    mv -f $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu
    cd $IPSW
    zip -rq0 ../$IPSWCustom.ipsw *
    cd ..
    mv $IPSW/ $IPSWCustom/

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again"
    fi
}
