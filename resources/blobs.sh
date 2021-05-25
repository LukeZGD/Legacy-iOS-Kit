#!/bin/bash

SaveOTABlobs() {
    local SHSHChk
    local SHSHExisting
    
    Log "Saving $OSVer blobs with tsschecker..."
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"
    if [[ $DeviceProc == 7 ]]; then
        APNonce=$($irecovery -q | grep "NONC" | cut -c 7-)
        Echo "* APNonce: $APNonce"
        $tsschecker -d $ProductType -B ${HWModel}ap -i $OSVer -e $UniqueChipID -m $BuildManifest --apnonce $APNonce -o -s
        SHSHChk=${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-${BuildVer}_${APNonce}.shsh*
    else
        $tsschecker -d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s
        SHSHChk=${UniqueChipID}_${ProductType}_${OSVer}-${BuildVer}*.shsh*
    fi
    SHSH=$(ls $SHSHChk)
    SHSHExisting=$(ls saved/shsh/$SHSHChk 2>/dev/null)
    if [[ ! $SHSH && ! $SHSHExisting ]]; then
        Error "Saving $OSVer blobs failed. Please run the script again" "It is also possible that $OSVer for $ProductType is no longer signed"
    elif [[ ! $SHSH ]]; then
        Log "Saving $OSVer blobs failed, but detected existing saved SHSH blobs. Continuing..."
        cp $SHSHExisting .
        SHSH=$(ls $SHSHChk)
    else
        mkdir -p saved/shsh 2>/dev/null
        [[ ! $SHSHExisting ]] && cp "$SHSH" saved/shsh
        Log "Successfully saved $OSVer blobs."
    fi
}
