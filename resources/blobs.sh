#!/bin/bash

SaveOTABlobs() {
    local ExtraArgs
    local SHSHChk
    local SHSHContinue
    local SHSHExisting
    
    Log "Saving $OSVer blobs with tsschecker..."
    BuildManifest="resources/manifests/BuildManifest_${ProductType}_${OSVer}.plist"
    ExtraArgs="-d $ProductType -i $OSVer -e $UniqueChipID -m $BuildManifest -o -s"
    if [[ $DeviceProc == 7 ]]; then
        local APNonce=$($irecovery -q | grep "NONC" | cut -c 7-)
        Log "APNonce: $APNonce"
        ExtraArgs+=" -B ${HWModel}ap --apnonce $APNonce"
        SHSHChk=${UniqueChipID}_${ProductType}_${HWModel}ap_${OSVer}-${BuildVer}_${APNonce}.shsh*
    else
        SHSHChk=${UniqueChipID}_${ProductType}_${OSVer}-${BuildVer}*.shsh*
    fi
    $tsschecker $ExtraArgs
    
    SHSH=$(ls $SHSHChk)
    SHSHExisting=$(ls saved/shsh/$SHSHChk 2>/dev/null)
    if [[ ! $SHSH && ! $SHSHExisting ]]; then
        Log "Saving $OSVer blobs failed. Trying again with fallback tsschecker..."
        $tsschecker2 $ExtraArgs
    
        SHSH=$(ls $SHSHChk)
        if [[ ! $SHSH ]]; then
            Error "Saving $OSVer blobs failed. Please run the script again" \
            "It is also possible that $OSVer for $ProductType is no longer signed"
        fi
    
    elif [[ ! $SHSH ]]; then
        Log "Saving $OSVer blobs failed, but found existing saved SHSH blobs. Continuing..."
        cp $SHSHExisting .
        SHSH=$(ls $SHSHChk)
        SHSHContinue=1
    fi
    
    if [[ ! -z $SHSH && $SHSHContinue != 1 ]]; then
        mkdir -p saved/shsh 2>/dev/null
        [[ ! $SHSHExisting ]] && cp "$SHSH" saved/shsh
        Log "Successfully saved $OSVer blobs."
    fi
}
