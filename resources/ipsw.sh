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

    [[ $platform == "win" || $LinuxARM == 1 ]] && IPSWCustom+="JB"
    if [[ $JBDaibutsu == 1 ]]; then
        JBName="daibutsu"
        IPSWCustom+="D"
    elif [[ $OSVer == "8.4.1" ]]; then
        JBName="EtasonJB"
        IPSWCustom+="E"
    elif [[ $OSVer == "7.1.2" ]]; then
        JBName="Pangu7"
    elif [[ $OSVer == "6"* && $ProductType == "iPhone3"* ]]; then
        JBName="powdersn0w"
    elif [[ $OSVer == "6.1.3" ]]; then
        JBName="p0sixspwn"
    else
        JBName="unthredeh4il"
    fi
    Log "Using $JBName for the jailbreak"
}

JailbreakOption() {
    if [[ $ProductType == "iPhone3,3" && $OSVer != "7.1.2" ]]; then
        IPSWCustom="${ProductType}_${OSVer}_${BuildVer}_Custom"
        return
    fi

    Input "Jailbreak Option"
    Echo "* When this option is enabled, your device will be jailbroken on restore."
    if [[ $OSVer == "6.1.3" ]]; then
        Echo "* I recommend to enable this for iOS 6.1.3, since it is hard to get p0sixspwn to work."
    elif [[ $OSVer == "8.4.1" ]]; then
        Echo "* Based on some reported issues, Jailbreak Option might not work properly for iOS 8.4.1."
        Echo "* I recommend to disable the option for these devices and sideload EtasonJB, HomeDepot, or daibutsu manually."
    elif [[ $OSVer == "5.1" ]]; then
        Echo "* Based on some reported issues, Jailbreak Option might not work properly for iOS 5.1."
        Echo "* I recommend to use other versions instead, such as 5.1.1."
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
        [[ $OSVer == 4.3* ]] && IPSWCustom+="-$UniqueChipID"
    elif [[ $ProductType == "$DisableBBUpdate" ]]; then
        Log "Baseband update will be disabled for the custom IPSW."
        if [[ $ProductType != "iPad2,3" ]]; then
            Log "WARNING - With baseband update disabled, activation errors might occur."
            Echo "* If you do not have other means for activation, this is not recommended."
            Input "Press Enter/Return to continue anyway (or press Ctrl+C to cancel)"
            read -s
        fi
        Baseband=0
        IPSWCustom+="B"
        if [[ $platform != "win" && $LinuxARM != 1 && $Jailbreak != 1 ]]; then
            IPSWCustom+="N"
        fi
    fi
    echo

    [[ $platform == "win" || -e "$IPSWCustom.ipsw" ]] && return
    if [[ $Jailbreak != 1 ]]; then
        if [[ $ProductType == "iPhone3"* ]]; then
            [[ $OSVer == "7.1.2" ]] && return
        elif [[ $ProductType != "$DisableBBUpdate" ]]; then
            return
        fi
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
        JBSHA1L=$($sha1sum resources/jailbreak/$2 | awk '{print $1}')
        if [[ $JBSHA1L == $3 ]]; then
            return
        fi
        Log "Verifying $2 failed. Deleting existing file for re-download."
        rm resources/jailbreak/$2
    fi
    cd tmp
    SaveFile $1 $2 $3
    mv $2 ../resources/jailbreak/
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

    if [[ ! -e "$IPSWDL.ipsw" ]]; then
        Log "iOS $OSVerDL IPSW for $ProductType cannot be found."
        Echo "* If you already downloaded the IPSW, move/copy it to the directory where the script is located."
        Echo "* Do NOT rename the IPSW as the script will fail to detect it."
        Echo "* The script will now proceed to download it for you. If you want to download it yourself, here is the link: $(cat $Firmware/$BuildVerDL/url)"
        Log "Downloading IPSW... (Press Ctrl+C to cancel)"
        curl -L $(cat $Firmware/$BuildVerDL/url) -o tmp/$IPSWDL.ipsw
        mv tmp/$IPSWDL.ipsw ./
    fi

    Log "Verifying $IPSWDL.ipsw..."
    IPSWSHA1=$(cat $Firmware/$BuildVerDL/sha1sum)
    Log "Expected SHA1sum: $IPSWSHA1"
    IPSWSHA1L=$($sha1sum $IPSWDL.ipsw | awk '{print $1}')
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
    local BBUpdate="-bbupdate"
    local ExtraArgs
    local JBFiles
    local JBFiles2
    local JBSHA1
    local WinBundles

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
        # uncomment the 2 lines below to add openssh to daibutsu cfw
        #JBFiles=("../resources/jailbreak/sshdeb.tar")                                        # uncomment to add openssh to custom ipsw
        #JailbreakFiles $JBURL/sshdeb.tar sshdeb.tar 0bffece0f8fd939c479159b57e923dd8c06191d3 # uncomment to add openssh to custom ipsw
        JBFiles2=("bin.tar" "cydia.tar" "untether.tar")
        JBSHA1=("98034227c68610f4c7dd48ca9e622314a1e649e7" "2e9e662afe890e50ccf06d05429ca12ce2c0a3a3" "f88ec9a1b3011c4065733249363e9850af5f57c8")
        mkdir -p tmp/jailbreak
        for i in {0..2}; do
            JBURL="https://github.com/LukeZGD/daibutsuCFW/raw/main/build/src/"
            (( i > 0 )) && JBURL+="daibutsu/"
            JBURL+="${JBFiles2[$i]}"
            JailbreakFiles $JBURL ${JBFiles2[$i]} ${JBSHA1[$i]}
            cp resources/jailbreak/${JBFiles2[$i]} tmp/jailbreak/
        done

    elif [[ $Jailbreak == 1 ]]; then
        if [[ $OSVer == "8.4.1" ]]; then
            JBFiles=("fstab.tar" "etasonJB-untether.tar" "Cydia8.tar")
            JBSHA1="6459dbcbfe871056e6244d23b33c9b99aaeca970"
        elif [[ $OSVer == "6.1.3" ]]; then
            JBFiles=("fstab_rw.tar" "p0sixspwn.tar" "Cydia6.tar")
            JBSHA1="1d5a351016d2546aa9558bc86ce39186054dc281"
        fi
        ExtraArgs+="-S 50"
        JailbreakFiles $JBURL/${JBFiles[2]} ${JBFiles[2]} $JBSHA1
        for i in {0..2}; do
            JBFiles[$i]=../resources/jailbreak/${JBFiles[$i]}
        done
        # adding sshdeb works for 6.1.3 only from what i've tested, doesn't seem to work on etasonjb ipsws
        #JBFiles+=("../resources/jailbreak/sshdeb.tar")                                       # uncomment to add openssh to custom ipsw
        #JailbreakFiles $JBURL/sshdeb.tar sshdeb.tar 0bffece0f8fd939c479159b57e923dd8c06191d3 # uncomment to add openssh to custom ipsw
    fi
    [[ $ProductType == "$DisableBBUpdate" ]] && BBUpdate=
    [[ $platform == "win" || $LinuxARM == 1 ]] && WinBundles="windows/"

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
    local config="config"
    local JBFiles=()
    local JBFiles2
    local JBSHA1

    if [[ -e $IPSWCustom.ipsw ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $OSVer == "4.3"* ]]; then
        IPSW4Cherry
        return
    elif [[ $ProductType == "iPhone3,3" && $OSVer != "7.1.2" ]]; then
        IPSW4Powder
        return
    fi

    if [[ $Jailbreak == 1 ]]; then
        if [[ $OSVer == "7.1.2" ]]; then
            JBFiles=(Cydia7.tar panguaxe.tar fstab7.tar)
            JBSHA1=bba5022d6749097f47da48b7bdeaa3dc67cbf2c4
        elif [[ $OSVer == "6."* ]]; then
            JBFiles=(Cydia6.tar)
            JBSHA1=1d5a351016d2546aa9558bc86ce39186054dc281
        else
            JBFiles=(Cydia5.tar unthredeh4il.tar fstab_rw.tar)
            JBSHA1=f5b5565640f7e31289919c303efe44741e28543a
        fi
        JBFiles2="${JBFiles[0]}"
        JailbreakFiles $JBURL/$JBFiles2 $JBFiles2 $JBSHA1
        for i in {0..2}; do
            JBFiles[$i]=../resources/jailbreak/${JBFiles[$i]}
        done
    fi

    cd tmp
    if [[ $OSVer == "7.1.2" && ! -e $IPSWCustom.ipsw ]]; then
        Log "Preparing custom IPSW..."
        cp -R ../resources/firmware/FirmwareBundles .
        $ipsw ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -S 50 ${JBFiles[@]}
    elif [[ ! -e $IPSWCustom.ipsw ]]; then
        echo
        Input "Verbose Boot Option"
        Echo "* When enabled, the device will have verbose boot on restore."
        Echo "* This option is enabled by default (Y)."
        read -p "$(Input 'Enable this option? (Y/n):')" opt
        if [[ $opt != 'N' && $opt != 'n' ]]; then
            config="configv"
            Log "Verbose boot option enabled."
        else
            Log "Verbose boot option disabled by user."
        fi

        Log "Preparing custom IPSW with powdersn0w..."
        cp -R ../resources/firmware/powdersn0wBundles ./FirmwareBundles
        cp -R ../resources/firmware/src .
        if [[ $Jailbreak == 1 && $OSVer == "6."* ]]; then
            JBFiles=()
            rm FirmwareBundles/${config}.plist
            mv FirmwareBundles/${config}JB.plist FirmwareBundles/${config}.plist
            cp ../resources/jailbreak/Cydia6.tar src/cydia6.tar
        fi
        mv FirmwareBundles/${config}.plist FirmwareBundles/config.plist
        $powdersn0w ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -base ../$IPSW7.ipsw ${JBFiles[@]}
    fi
    cd ..

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again" \
        "You may try selecting N for memory option"
    fi
}

IPSW4Cherry() {
    local ExtraArgs="--logo4 "
    local IV
    local JBFiles
    local JBSHA1
    local Key

    if [[ $OSVer == "4.3.5" ]]; then
        IV=986032eecd861c37ca2a86b6496a3c0d
        Key=b4e300c54a9dd2e648ead50794e9bf2205a489c310a1c70a9fae687368229468
    elif [[ $OSVer == "4.3.3" ]]; then
        IV=bb3fc29dd226fac56086790060d5c744
        Key=c2ead1d3b228a05b665c91b4b1ab54b570a81dffaf06eaf1736767bcb86e50de
        ExtraArgs+="--433 "
    elif [[ $OSVer == "4.3" ]]; then
        IV=9f11c07bde79bdac4abb3f9707c4b13c
        Key=0958d70e1a292483d4e32ed1e911d2b16b6260856be67d00a33b6a1801711d32
        ExtraArgs+="--433 "
    fi

    if [[ $Jailbreak == 1 ]]; then
        JBFiles=(Cydia5.tar unthredeh4il.tar fstab_rw.tar)
        JBSHA1=f5b5565640f7e31289919c303efe44741e28543a
        JailbreakFiles $JBURL/${JBFiles[0]} ${JBFiles[0]} $JBSHA1
        for i in {0..2}; do
            JBFiles[$i]=../resources/jailbreak/${JBFiles[$i]}
        done
    fi

    Log "ch3rryflower will be used instead of powdersn0w for iOS 4.3.x"
    SaveExternal ch3rryflower
    if [[ $platform == "linux" ]]; then
        # patch cherry temp path from /tmp to ././ (current dir)
        cd tmp
        echo "QlNESUZGNDA4AAAAAAAAAEUAAAAAAAAAQKoEAAAAAABCWmg5MUFZJlNZCmbVYQAABtRYTCAAIEAAQAAAEAIAIAAiNNA9QgyYiW0geDDxdyRThQkApm1WEEJaaDkxQVkmU1kFCpb0AACoSA7AAABAAAikAAACAAigAFCDJiApUmmnpMCTNJOaootbhBXWMbqkjO/i7kinChIAoVLegEJaaDkXckU4UJAAAAAA" | base64 -d | tee cherry.patch >/dev/null
        $bspatch ../$cherry/cherry ../$cherry/cherry2 cherry.patch
        chmod +x ../$cherry/cherry2
        cd ..
        cherrybin+="2"
    fi

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

    cd tmp
    Log "Preparing custom IPSW with ch3rryflower..."
    cp -R ../$cherrymac/FirmwareBundles ../$cherrymac/src .
    unzip -j ../$IPSW.ipsw Firmware/all_flash/all_flash.${HWModel}ap.production/iBoot*
    mv iBoot.${HWModel}ap.RELEASE.img3 tmp
    $xpwntool tmp ibot.dec -iv $IV -k $Key
    ../$cherry/bin/iBoot32Patcher ibot.dec ibot.pwned --rsa --boot-partition --boot-ramdisk $ExtraArgs
    $xpwntool ibot.pwned iBoot -t tmp
    echo "0000010: 6365" | xxd -r - iBoot
    echo "0000020: 6365" | xxd -r - iBoot
    $cherrybin ../$IPSW.ipsw ../$IPSWCustom.ipsw $JBMemory -derebusantiquis ../$IPSW7.ipsw iBoot ${JBFiles[@]}
    cd ..

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again" \
        "You may try selecting N for memory option"
    fi

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
}

IPSW4Powder() {
    Log "powdersn0w v2.0b3 will be used instead of powdersn0w_pub for iPhone3,3" # powdersn0w_pub doesn't have n92 exploit
    SaveExternal powdersn0w # downloads powdersn0w from https://dora2ios.github.io/download/konayuki/powdersn0w_v2.0b3.zip

    powderdir="../resources/powdersn0w/macosx_x86_64"
    cd tmp
    cp -R $powderdir/FirmwareBundles $powderdir/src .
    powdersn0w="$powderdir/ipsw"

    if [[ $platform != "macos" ]]; then
        echo "QlNESUZGNDA2AAAAAAAAAEkAAAAAAAAA4HscAAAAAABCWmg5MUFZJlNZcLcTFwAAB+DBQKAABAAIQCBCACAAIjEaNCDJiDaAhcW9PF3JFOFCQcLcTFxCWmg5MUFZJlNZidWPbQAOTMKswAAAAJAAEAAACKAAAAigAFCDJiBNUpoPU+qqe5IkMxAqd8VISW223BKUbv4u5IpwoSETqx7aQlpoORdyRThQkAAAAAA=" | base64 -d | tee ipsw.patch >/dev/null
        $bspatch $powderdir/ipsw $powderdir/ipsw_patched ipsw.patch
        powdersn0w="darling $(pwd)/$powderdir/ipsw_patched"
        if [[ ! $(which darling) ]]; then
            Error "Cannot find darling. darling is required to create custom IPSW."
        fi
    fi
# above patch changes temp path from /tmp to ././ (current dir)
# only modifies xpwn part, hopefully doesn't violate nbsk license. here is the equivalent diff (based on gpl code released):
: '
main.c:
187c188
<             strcpy(tmpFileBuffer, "/tmp/rootXXXXXX");
---
>             strcpy(tmpFileBuffer, "././/rootXXXXXX");
outputstate.c:
292c292
<       strcpy(tmpFileBuffer, "/tmp/pwnXXXXXX");
---
>       strcpy(tmpFileBuffer, "././/pwnXXXXXX");
'
    Log "Preparing custom IPSW with powdersn0w..."
    $powdersn0w ../$IPSW.ipsw ../$IPSWCustom.ipsw -useDRA ../$IPSW7.ipsw
    cd ..

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again"
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
    mv -f $iBSS.im4p $iBEC.im4p $IPSW/Firmware/dfu/
    if [[ $ProductType == "iPad4"* ]]; then
        $bspatch $IPSW/Firmware/dfu/$iBSSb.im4p $iBSSb.im4p resources/patches/$iBSSb.patch
        $bspatch $IPSW/Firmware/dfu/$iBECb.im4p $iBECb.im4p resources/patches/$iBECb.patch
        mv -f $iBSSb.im4p $iBECb.im4p $IPSW/Firmware/dfu/
    fi
    cd $IPSW
    zip -r0 ../$IPSWCustom.ipsw *
    cd ..
    mv $IPSW/ $IPSWCustom/

    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again"
    fi
}

IPSW32Other() {
    local BBUpdate="-bbupdate"
    IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_CustomW"
    if [[ -e $IPSWCustom.ipsw ]]; then
        Log "Found existing Custom IPSW. Skipping IPSW creation."
        return
    fi

    if [[ $platform != "win" ]]; then
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
    fi

    if [[ $ProductType == "$DisableBBUpdate" ]]; then
        BBUpdate=
        Log "Baseband update will be disabled for the custom IPSW."
        if [[ $ProductType != "iPad2,3" ]]; then
            Log "WARNING - With baseband update disabled, activation errors might occur."
            Echo "* If you do not have other means for activation, this is not recommended."
            Input "Press Enter/Return to continue anyway (or press Ctrl+C to cancel)"
            read -s
        fi
        Baseband=0
        IPSWCustom+="B"
    fi

    Log "Generating firmware bundle..."
    local IPSWSHA256=$($sha256sum "$IPSW.ipsw")
    [[ $platform == "win" ]] && IPSWSHA256=$(echo $IPSWSHA256 | cut -c 2-)
    local FirmwareBundle=FirmwareBundles/${IPSWType}_${OSVer}_${BuildVer}.bundle
    local NewPlist=tmp/$FirmwareBundle/Info.plist

    mkdir -p tmp/$FirmwareBundle
    cp resources/firmware/powdersn0wBundles/config2.plist tmp/FirmwareBundles/config.plist
    unzip -j "$IPSW.ipsw" Firmware/all_flash/all_flash.${HWModel}ap.production/manifest
    mv manifest tmp/$FirmwareBundle/

    local FWKey=$(cat $FWKeys/index.html)
    local RamdiskName=$(echo $FWKey | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .filename')
    local RamdiskIV=$(echo $FWKey | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .iv')
    local RamdiskKey=$(echo $FWKey | $jq -j '.keys[] | select(.image | startswith("RestoreRamdisk")) | .key')
    cd tmp
    unzip -j "$IPSW.ipsw" $RamdiskName
    $xpwntool $RamdiskName Ramdisk.dec -iv $RamdiskIV -k $RamdiskKey -decrypt
    $xpwntool Ramdisk.dec Ramdisk.raw
    $hfsplus Ramdisk.raw extract usr/local/share/restore/options.$HWModel.plist
    cd ..
    local RootSize=$($xmlstarlet sel -t -m "plist/dict/key[.='SystemPartitionSize']" -v "following-sibling::integer[1]" tmp/options.$HWModel.plist)

    printf '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Filename</key>
	<string>'>$NewPlist;printf "$IPSW.ipsw">>$NewPlist;printf '</string>
	<key>RootFilesystem</key>
	<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("RootFS")) | .filename'>>$NewPlist;printf '</string>
	<key>RootFilesystemKey</key>
	<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("RootFS")) | .key'>>$NewPlist;printf '</string>
	<key>RootFilesystemSize</key>
	<integer>'>>$NewPlist;printf $RootSize>>$NewPlist;printf '</integer>
	<key>RamdiskOptionsPath</key>
	<string>/usr/local/share/restore/options.'>>$NewPlist;printf $HWModel>>$NewPlist;printf '.plist</string>
	<key>SHA256</key>
	<string>'>>$NewPlist;printf $IPSWSHA256>>$NewPlist;printf '</string>
	<key>FilesystemPackage</key>
	<dict/>
	<key>RamdiskPackage</key>
	<dict/>
	<key>Firmware</key>
	<dict>
		<key>iBSS</key>
		<dict>
			<key>File</key>
			<string>Firmware/dfu/'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .filename'>>$NewPlist;printf '</string>
			<key>IV</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .iv'>>$NewPlist;printf '</string>
			<key>Key</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("iBSS")) | .key'>>$NewPlist;printf '</string>
			<key>Decrypt</key>
			<true/>
			<key>Patch</key>
			<true/>
		</dict>
		<key>iBEC</key>
		<dict>
			<key>File</key>
			<string>Firmware/dfu/'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .filename'>>$NewPlist;printf '</string>
			<key>IV</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .iv'>>$NewPlist;printf '</string>
			<key>Key</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("iBEC")) | .key'>>$NewPlist;printf '</string>
			<key>Decrypt</key>
			<true/>
			<key>Patch</key>
			<true/>
		</dict>
		<key>Restore Ramdisk</key>
		<dict>
			<key>File</key>
			<string>'>>$NewPlist;printf $RamdiskName>>$NewPlist;printf '</string>
			<key>IV</key>
			<string>'>>$NewPlist;printf $RamdiskIV>>$NewPlist;printf '</string>
			<key>Key</key>
			<string>'>>$NewPlist;printf $RamdiskKey>>$NewPlist;printf '</string>
			<key>Decrypt</key>
			<true/>
		</dict>
		<key>RestoreDeviceTree</key>
		<dict>
			<key>File</key>
			<string>Firmware/all_flash/all_flash.'>>$NewPlist;printf $HWModel>>$NewPlist;printf 'ap.production/'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("DeviceTree")) | .filename'>>$NewPlist;printf '</string>
			<key>IV</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("DeviceTree")) | .iv'>>$NewPlist;printf '</string>
			<key>Key</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("DeviceTree")) | .key'>>$NewPlist;printf '</string>
			<key>DecryptPath</key>
			<string>Downgrade/'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("DeviceTree")) | .filename'>>$NewPlist;printf '</string>
		</dict>
		<key>RestoreLogo</key>
		<dict>
			<key>File</key>
			<string>Firmware/all_flash/all_flash.'>>$NewPlist;printf $HWModel>>$NewPlist;printf 'ap.production/'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("AppleLogo")) | .filename'>>$NewPlist;printf '</string>
			<key>IV</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("AppleLogo")) | .iv'>>$NewPlist;printf '</string>
			<key>Key</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("AppleLogo")) | .key'>>$NewPlist;printf '</string>
			<key>DecryptPath</key>
			<string>Downgrade/'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("AppleLogo")) | .filename'>>$NewPlist;printf '</string>
		</dict>
		<key>RestoreKernelCache</key>
		<dict>
            <key>File</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("Kernelcache")) | .filename'>>$NewPlist;printf '</string>
			<key>IV</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("Kernelcache")) | .iv'>>$NewPlist;printf '</string>
			<key>Key</key>
			<string>'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("Kernelcache")) | .key'>>$NewPlist;printf '</string>
			<key>DecryptPath</key>
			<string>Downgrade/'>>$NewPlist;echo $FWKey | $jq -j '.keys[] | select(.image | startswith("Kernelcache")) | .filename'>>$NewPlist;printf '</string>
			<key>Decrypt</key>
			<true/>
			<key>Patch</key>
			<false/>
        </dict>
	</dict>
</dict>
</plist>\n'>>$NewPlist
    cat $NewPlist

    Log "Preparing custom IPSW..."
    cd tmp
    $powdersn0w "$IPSW.ipsw" ../$IPSWCustom.ipsw $BBUpdate $JBMemory
    cd ..
    if [[ ! -e $IPSWCustom.ipsw ]]; then
        Error "Failed to find custom IPSW. Please run the script again"
    fi
}
