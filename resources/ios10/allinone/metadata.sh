#!/bin/bash
# Called only by the bootstrap's existing startup job, AFTER firmware.sh.
# Never launch a second firmware.sh: it deletes other pending status-tmp files.
set -e
[[ -s /var/root/lik-aio-installed ]] || exit 1
[[ ! -f /var/root/lik-aio-metadata-complete ]] || exit 0
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
/bin/su -c /usr/bin/uicache mobile
printf 'Automatic package metadata and icon registration completed.\n' > /var/root/lik-aio-metadata-complete
if [[ -d /var/mobile/Media/LegacyiOSKitLogs ]]; then
    cp /var/root/lik-aio-metadata-complete /var/mobile/Media/LegacyiOSKitLogs/first-boot.txt
    chown 501:501 /var/mobile/Media/LegacyiOSKitLogs/first-boot.txt
fi
