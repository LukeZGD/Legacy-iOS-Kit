#!/bin/bash

SaveOTABlobs() {
    local APNonce=$1
    local ExtraArgs
    local SHSHChk=${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-${BuildVer}*.shsh*
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"

    if [[ $(ls saved/shsh/$SHSHChk 2>/dev/null) && -z $APNonce ]]; then
        SHSH=$(ls saved/shsh/$SHSHChk)
        Log "Found existing saved $OSVer blobs: $SHSH"
        return
    fi

    Log "Saving iOS $OSVer blobs with tsschecker..."
    ExtraArgs="-d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s -B ${HWModel}ap -b "
    [[ -n $APNonce ]] && ExtraArgs+="--apnonce $APNonce" || ExtraArgs+="-g 0x1111111111111111"
    $tsschecker $ExtraArgs
    SHSH=$(ls $SHSHChk)
    if [[ -n $SHSH ]]; then
        mkdir -p saved/shsh 2>/dev/null
        if [[ -n $APNonce ]]; then
            mv "$SHSH" tmp/
            SHSH=$(ls tmp/$SHSHChk)
        else
            mv "$SHSH" saved/shsh/
            SHSH=$(ls saved/shsh/$SHSHChk)
        fi
        Log "Successfully saved $OSVer blobs: $SHSH"
    else
        Error "Saving $OSVer blobs failed. Please run the script again" \
        "It is also possible that $OSVer for $ProductType is no longer signed"
    fi
}

Save712Blobs() {
    local SHSHChk=${UniqueChipID}_${ProductType}_7.1.2-11D257_*.shsh2
    BuildManifest="saved/$ProductType/BuildManifest.plist"
    SHSH="saved/shsh/${UniqueChipID}-${ProductType}-7.1.2.shsh"

    if [[ -e $SHSH ]]; then
        Log "Found existing saved 7.1.2 blobs: $SHSH"
        return
    fi

    if [[ ! -e $BuildManifest ]]; then
        if [[ -e $IPSW7.ipsw ]]; then
            Log "Extracting BuildManifest from 7.1.2 IPSW..."
            unzip -o -j $IPSW7.ipsw BuildManifest.plist -d .
        else
            Log "Downloading BuildManifest for 7.1.2..."
            $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
        fi
        mkdir -p saved/$ProductType 2>/dev/null
        mv BuildManifest.plist $BuildManifest
    fi

    Log "Saving 7.1.2 blobs with tsschecker..."
    $tsschecker -d $ProductType -i 7.1.2 -e $UniqueChipID -m $BuildManifest -s -b
    SHSHChk=$(ls $SHSHChk)
    [[ -z $SHSHChk ]] && Error "Saving 7.1.2 blobs failed. Please run the script again"
    mkdir -p saved/shsh 2>/dev/null
    mv $SHSHChk $SHSH
    Log "Successfully saved 7.1.2 blobs: $SHSH"
}

SaveLatestBlobs() {
    local APNonce=$($irecovery -q | grep "NONC" | cut -c 7-)
    local SHSHChk=${UniqueChipID}_${ProductType}_${LatestVer}-${LatestBuildVer}_*.shsh2
    SHSH="shsh/${UniqueChipID}-${ProductType}-${LatestVer}.shsh"
    Log "Saving $LatestVer blobs with tsschecker..."
    mkdir -p saved/$ProductType shsh 2>/dev/null
    cp -f $IPSWRestore/BuildManifest.plist saved/$ProductType/
    $tsschecker -d $ProductType -i $LatestVer -e $UniqueChipID -m saved/$ProductType/BuildManifest.plist -s -b --apnonce $($irecovery -q | grep "NONC" | cut -c 7-)
    SHSHChk=$(ls $SHSHChk)
    [[ -z $SHSHChk ]] && Error "Saving $LatestVer blobs failed. Please run the script again"
    mv $SHSHChk $SHSH
    Log "Successfully saved $LatestVer blobs: $SHSH"
}
