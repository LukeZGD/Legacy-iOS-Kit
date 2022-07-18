#!/bin/bash

SaveOTABlobs() {
    local APNonce=$1
    local ExtraArgs
    local SHSHChk=${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-${BuildVer}*.shsh*
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"

    if [[ $(ls saved/shsh/$SHSHChk 2>/dev/null) ]]; then
        Log "Found existing saved $OSVer blobs."
        return
    fi

    Log "Saving iOS $OSVer blobs with tsschecker..."
    ExtraArgs="-d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s -B ${HWModel}ap -b "
    [[ -n $APNonce ]] && ExtraArgs+="--apnonce $APNonce" || ExtraArgs+="-g 0x1111111111111111"
    $tsschecker $ExtraArgs
    SHSH=$(ls $SHSHChk)
    if [[ -n $SHSH ]]; then
        mkdir -p saved/shsh 2>/dev/null
        [[ -z $APNonce ]] && cp "$SHSH" saved/shsh
        Log "Successfully saved $OSVer blobs."
    else
        Error "Saving $OSVer blobs failed. Please run the script again" \
        "It is also possible that $OSVer for $ProductType is no longer signed"
    fi
}

Save712Blobs() {
    local SHSHChk
    BuildManifest="saved/$ProductType/BuildManifest.plist"
    SHSH="saved/shsh/${UniqueChipID}-${ProductType}-7.1.2.shsh"

    if [[ -e $SHSH ]]; then
        Log "Found existing saved 7.1.2 blobs."
        return
    fi

    if [[ ! -e $BuildManifest && -e $IPSW7.ipsw ]]; then
        Log "Extracting BuildManifest from 7.1.2 IPSW..."
        unzip -o -j $IPSW7.ipsw BuildManifest.plist -d .
        mkdir -p saved/$ProductType 2>/dev/null
        mv BuildManifest.plist $BuildManifest
    elif [[ ! -e $BuildManifest ]]; then
        Log "Downloading BuildManifest for 7.1.2..."
        $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
        mkdir -p saved/$ProductType 2>/dev/null
        mv BuildManifest.plist $BuildManifest
    fi

    Log "Saving 7.1.2 blobs with tsschecker..."
    $tsschecker -d $ProductType -i 7.1.2 -e $UniqueChipID -m $BuildManifest -s -b
    SHSHChk=$(ls ${UniqueChipID}_${ProductType}_7.1.2-11D257_*.shsh2)
    [[ -z $SHSHChk ]] && Error "Saving $OSVer blobs failed. Please run the script again"
    mkdir saved/shsh 2>/dev/null
    mv $SHSHChk $SHSH
    Log "Successfully saved 7.1.2 blobs."
}
