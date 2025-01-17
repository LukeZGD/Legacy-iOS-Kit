#!/bin/bash
set -x
mv /mnt1/usr/libexec/CrashHousekeeping /mnt1/usr/libexec/CrashHousekeeping_o
mv /mnt1/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist /mnt1/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist
rm -rf /mnt1/Library/LaunchDaemons
mv /mnt1/System/Library/LaunchDaemons /mnt1/Library/LaunchDaemons
mv /mnt1/System/Library/NanoLaunchDaemons /mnt1/Library/NanoLaunchDaemons
mkdir -p /mnt1/System/Library/LaunchDaemons
mv /mnt1/Library/LaunchDaemons/bootps.plist /mnt1/System/Library/LaunchDaemons/bootps.plist
mv /mnt1/Library/LaunchDaemons/com.apple.CrashHousekeeping.plist /mnt1/System/Library/LaunchDaemons/com.apple.CrashHousekeeping.plist
mv /mnt1/Library/LaunchDaemons/com.apple.MobileFileIntegrity.plist /mnt1/System/Library/LaunchDaemons/com.apple.MobileFileIntegrity.plist
mv /mnt1/Library/LaunchDaemons/com.apple.mobile.softwareupdated.plist /mnt1/System/Library/LaunchDaemons/com.apple.mobile.softwareupdated.plist_
mv /mnt1/Library/LaunchDaemons/com.apple.softwareupdateservicesd.plist /mnt1/System/Library/LaunchDaemons/com.apple.softwareupdateservicesd.plist_
mv /mnt1/Library/LaunchDaemons/com.apple.jetsamproperties.*.plist /mnt1/System/Library/LaunchDaemons
if [[ $1 != "7.1"* ]]; then # change to "7"* for lyncis 7.0.x
    mv /mnt1/Library/LaunchDaemons/com.apple.mDNSResponder.plist /mnt1/System/Library/LaunchDaemons/com.apple.mDNSResponder.plist_
fi
