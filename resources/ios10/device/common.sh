# Shared by the temporary, key-authenticated installer. This file only defines
# functions/paths; sourcing it does not change the filesystem or launch a job.
D=/usr/local/share/lik-ios10
R=/usr/lik
export PATH=/usr/lik:/usr/bin:/bin:/usr/sbin:/sbin
export LC_ALL=C
umask 077

fail() { printf 'Installer stopped: %s\n' "$*" >&2; exit 1; }

read_identity() {
    { IFS= read -r SESSION; IFS= read -r PRODUCT; IFS= read -r BOARD
      IFS= read -r VERSION; IFS= read -r BUILD; IFS= read -r ECID; } < "$D/identity"
    [[ "$SESSION" =~ ^[a-f0-9-]{36}$ ]] || fail 'Invalid session identifier'
    case "$PRODUCT:$BOARD:$VERSION:$BUILD" in
        iPhone5,3:n48ap:10.3.3:14G60|iPhone5,4:n49ap:10.3.3:14G60|\
        iPhone5,1:n41ap:10.3.3:14G60|iPhone5,2:n42ap:10.3.3:14G60|\
        iPhone5,1:n41ap:10.3.4:14G61|iPhone5,2:n42ap:10.3.4:14G61|\
        iPhone5,3:n48ap:10.3.4:14G61|iPhone5,4:n49ap:10.3.4:14G61|\
        iPad3,4:p101ap:10.3.3:14G60|iPad3,5:p102ap:10.3.3:14G60|\
        iPad3,6:p103ap:10.3.3:14G60|iPad3,5:p102ap:10.3.4:14G61|\
        iPad3,6:p103ap:10.3.4:14G61|iPad3,4:p101ap:10.3.4:14G61) ;;
        *) fail 'Unsupported staged identity' ;;
    esac
    J="/var/root/lik-ios10/$SESSION"
}

assert_identity() {
    [[ "$EUID" == 0 ]] || fail 'Root access is unavailable'
    [[ "$($R/sysctl -n hw.machine)" == "$PRODUCT" ]] || fail 'ProductType mismatch'
    shopt -s nocasematch
    [[ "$($R/sysctl -n hw.model)" == "$BOARD" ]] || fail 'HardwareModel mismatch'
    shopt -u nocasematch
    [[ "$($R/sw_vers -productVersion)" == "$VERSION" ]] || fail 'ProductVersion mismatch'
    [[ "$($R/sw_vers -buildVersion)" == "$BUILD" ]] || fail 'BuildVersion mismatch'
}

assert_jumpstart() {
    assert_identity
    [[ " $($R/sysctl -n kern.bootargs) " == *' lik_ios10_jumpstart=1 '* ]] ||
        fail 'The temporary DFU jump-start boot is required before installation'
}

phase() {
    if [[ -L "$J" || -L "$J/phase" ]]; then fail 'Unexpected journal symlink'; fi
    if [[ -f "$J/phase" ]]; then "$R/cat" "$J/phase"
    elif [[ -e "$J" ]]; then printf 'incomplete-journal\n'
    else printf 'new\n'; fi
}

write_phase() {
    printf '%s\n' "$1" > "$J/phase.new"
    "$R/sync"
    "$R/mv" -f "$J/phase.new" "$J/phase"
    "$R/sync"
}

init_journal() {
    [[ ! -L /var/root/lik-ios10 && ! -L "$J" ]] || fail 'Unexpected journal symlink'
    "$R/mkdir" -p /var/root/lik-ios10
    "$R/chmod" 700 /var/root/lik-ios10
    if [[ ! -e "$J" ]]; then
        "$R/mkdir" "$J"
        "$R/cp" "$D/identity" "$J/identity"
        write_phase new
    fi
    "$R/cmp" "$D/identity" "$J/identity" || fail 'Journal belongs to a different restore'
}

sha256() {
    local answer
    answer=$("$R/openssl" dgst -sha256 "$1") || return 1
    answer=${answer##* }
    [[ "$answer" =~ ^[a-f0-9]{64}$ ]] || return 1
    printf '%s\n' "$answer"
}

verify_stage() {
    local expected name actual
    while read -r expected name; do
        [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || fail 'Invalid staging checksum'
        case "$name" in /usr/lik/*|"$D/"*|/Applications/LIKTools.app/*|/Library/LaunchDaemons/org.legacyioskit.ios10.transport.plist|/System/Library/LaunchDaemons/org.legacyioskit.ios10.diagnostics.plist) ;;
            *) fail 'Unexpected staging checksum path' ;; esac
        [[ -f "$name" && ! -L "$name" ]] || fail "Staged file missing: $name"
        actual=$(sha256 "$name") || fail "Could not hash $name"
        [[ "$actual" == "$expected" ]] || fail "Staged file changed: $name"
    done < "$D/SHA256SUMS"
}

assert_fresh() {
    local path
    for path in /.installed_socket /var/root/procyon /var/lib/dpkg/status \
                /usr/libexec/wifiFirmwareLoaderLegacy_orig /var/db/com.apple.xpc.launchd/disabled_orig.plist; do
        [[ ! -e "$path" && ! -L "$path" ]] || fail "Existing jailbreak/untether state: $path"
    done
    [[ -f /usr/libexec/wifiFirmwareLoaderLegacy && ! -L /usr/libexec/wifiFirmwareLoaderLegacy ]] ||
        fail 'Stock Wi-Fi loader is missing or already redirected'
}

capture() {
    local label="$1" name hash
    local paths=()
    [[ "$label" == before || "$label" == after || "$label" == failure ]] || fail 'Invalid capture label'
    for name in etc/racoon usr/libexec/wifiFirmwareLoaderLegacy usr/libexec/wifiFirmwareLoaderLegacy_orig \
        usr/libexec/backboardd var/db/com.apple.xpc.launchd/disabled.plist \
        var/db/com.apple.xpc.launchd/disabled_orig.plist var/root/procyon \
        var/lib/dpkg/status var/lib/dpkg/info/com.staturnz.procyon.postinst; do
        [[ ! -e "/$name" && ! -L "/$name" ]] || paths+=("$name")
    done
    "$R/tar" -cpf "$J/$label.tar.new" -C / "${paths[@]}"
    "$R/mv" "$J/$label.tar.new" "$J/$label.tar"
    {
        printf 'session=%s\nboot=' "$SESSION"
        "$R/sysctl" -n kern.boottime
        for name in /System/Library/Caches/com.apple.kernelcaches/kernelcache \
            /System/Library/Caches/com.apple.dyld/dyld_shared_cache_armv7s; do
            hash=$(sha256 "$name") || fail "Cannot hash installed firmware: $name"
            printf '%s  %s\n' "$hash" "$name"
        done
    } > "$J/$label.identity"
    "$R/sync"
}

verify_untether() {
    [[ -L /usr/libexec/wifiFirmwareLoaderLegacy ]] || fail 'Untether Wi-Fi trigger missing'
    [[ "$("$R/readlink" /usr/libexec/wifiFirmwareLoaderLegacy)" == /usr/sbin/racoon ]] ||
        fail 'Unexpected Wi-Fi trigger target'
    "$R/cmp" "$D/procyon-disabled.plist" /var/db/com.apple.xpc.launchd/disabled.plist ||
        fail 'Procyon launchd service configuration mismatch'
    [[ -s /etc/racoon/stage2 && -s /var/root/procyon/stage3.bin ]] || fail 'Generated untether stages missing'
    local stages=(/var/root/procyon/stage1/part*.conf) file
    [[ -f "${stages[0]}" ]] || fail 'Generated stage 1 is missing'
    for file in racoon.conf backboardd wifiFirmwareLoaderLegacy disabled.plist; do
        [[ -s "/var/root/procyon/backup/$file" ]] || fail "Procyon backup missing: $file"
    done
    "$R/cmp" /usr/libexec/wifiFirmwareLoaderLegacy_orig /var/root/procyon/backup/wifiFirmwareLoaderLegacy ||
        fail 'Wi-Fi loader backup mismatch'
}
