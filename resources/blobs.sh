#!/bin/bash

SaveOTABlobs() {
    local APNonce=$1
    local ExtraArgs
    local SHSHChk
    local SHSHContinue
    local SHSHLatest
    local SHSHExisting
    
    if [[ $DeviceProc != 7 && $Baseband != 0 ]]; then
        if [[ ! -e saved/$ProductType/BuildManifest.plist ]]; then
            Log "Downloading BuildManifest of iOS $LatestVer..."
            $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
            mkdir -p saved/$ProductType 2>/dev/null
            mv BuildManifest.plist saved/$ProductType
        fi
        if [[ ! -e saved/$ProductType/BuildManifest.plist ]]; then
            Error "Downloading/verifying BuildManifest failed. Please run the script again"
        fi
        Log "Checking signing status of iOS $LatestVer..."
        SHSHChk=*_${ProductType}_${HWModel}ap_${LatestVer}*.shsh*
        $tsschecker -d $ProductType -i $LatestVer -e $UniqueChipID -m saved/$ProductType/BuildManifest.plist -s -B ${HWModel}ap
        SHSHLatest=$(ls $SHSHChk)
        if [[ ! -e $SHSHLatest ]]; then
            Error "For some reason, the latest version for your device (iOS $LatestVer) is not signed. Cannot continue."
        fi
        Log "Latest version for $ProductType (iOS $LatestVer) is signed."
        rm $SHSHLatest
    fi

    Log "Saving iOS $OSVer blobs with tsschecker..."
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"
    ExtraArgs="-d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s -B ${HWModel}ap -b "
    [[ -n $APNonce ]] && ExtraArgs+="--apnonce $APNonce" || ExtraArgs+="-g 0x1111111111111111"
    SHSHChk=${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-${BuildVer}*.shsh*
    $tsschecker $ExtraArgs
    
    SHSH=$(ls $SHSHChk)
    SHSHExisting=$(ls saved/shsh/$SHSHChk 2>/dev/null)
    if [[ ! -e $SHSH && ! -e $SHSHExisting ]]; then
        Error "Saving $OSVer blobs failed. Please run the script again" \
        "It is also possible that $OSVer for $ProductType is no longer signed"
    
    elif [[ ! -e $SHSH ]]; then
        Log "Saving $OSVer blobs failed, but found existing saved SHSH blobs."
        cp $SHSHExisting .
        SHSH=$(ls $SHSHChk)
        SHSHContinue=1
    fi
    
    if [[ -n $SHSH && $SHSHContinue != 1 ]]; then
        mkdir -p saved/shsh 2>/dev/null
        [[ -z $APNonce ]] && cp "$SHSH" saved/shsh
        Log "Successfully saved $OSVer blobs."
    fi
}

Save712Blobs() {
    local SHSHChk
    SHSH7="${UniqueChipID}-${ProductType}-7.1.2.shsh"
    SHSH="saved/shsh/$SHSH7"
    BuildManifest="BuildManifest_${ProductType}_7.1.2.plist"

    if [[ ! -e resources/manifests/$BuildManifest ]]; then
        Log "Extracting BuildManifest from 7.1.2 IPSW..."
        unzip -o -j $IPSW7.ipsw BuildManifest.plist -d .
        mv BuildManifest.plist resources/manifests/$BuildManifest
    fi

    if [[ -e saved/shsh/$SHSH7 ]]; then
        Log "Found existing saved 7.1.2 blobs."
        return
    fi
    Log "Saving 7.1.2 blobs with tsschecker..."
    $tsschecker -d $ProductType -i 7.1.2 -e $UniqueChipID -m resources/manifests/BuildManifest_${ProductType}_7.1.2.plist -s -b
    SHSHChk=$(ls ${UniqueChipID}_${ProductType}_7.1.2-11D257_*.shsh2)
    [[ ! $SHSHChk ]] && Error "Saving $OSVer blobs failed. Please run the script again"
    mkdir saved/shsh 2>/dev/null
    mv $SHSHChk saved/shsh/$SHSH7
    Log "Successfully saved 7.1.2 blobs."
}
