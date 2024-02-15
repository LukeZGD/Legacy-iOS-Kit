#!/bin/bash
app=$(find /mnt2/containers/Bundle/Application/ -name "Tips.app")
if [[ ! -e ${app}/Tips_TROLLSTORE_BACKUP ]]; then
    mv ${app}/Tips ${app}/Tips_TROLLSTORE_BACKUP
    mv ${app}/PersistenceHelper_Embedded ${app}/Tips
    /usr/sbin/chown 33 ${app}/Tips
    chmod 755 ${app}/Tips ${app}/trollstorehelper
    /usr/sbin/chown 0 ${app}/trollstorehelper
    touch ${app}/.TrollStorePersistenceHelper
fi
