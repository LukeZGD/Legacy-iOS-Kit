# iOS 10 restore/continuation bridge. Sourcing defines functions only.
# Called from Kit's existing menus; uses its host-specific USB/pwnDFU tools.

ios10_host_init() {
    ios10_resources="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
    ios10_tools="$(cd "$dir" && pwd)" || return 1
    ios10_python="$(command -v python3)"
    if [[ -z $ios10_python ]] || ! "$ios10_python" -c 'import sys; sys.exit(sys.version_info < (3, 7))'; then
        warn "The iOS 10 installer requires Python 3.7 or newer."
        print "* See the official Kit's Python 3 on older macOS instructions if needed."
        return 1
    fi
    export PYTHONDONTWRITEBYTECODE=1
    local tool
    for tool in hfsplus dmg xpwntool iBoot32Patcher ideviceinfo; do
        [[ -x "$ios10_tools/$tool" ]] || { warn "Required bundled tool missing: $tool"; return 1; }
    done
    return 0
}

ios10_session() {
    "$ios10_python" "$ios10_resources/session.py" --directory "$ios10_session_dir" "$@"
}

ios10_preflight() {
    # These model/board pairs have passed their firmware component and generator
    # checks. Older SHSH restores still need Kit's multipatch bridge validation.
    local target_enabled=0
    case "$device_type:$device_model" in
        iPhone5,1:n41 | iPhone5,2:n42 | iPhone5,3:n48 | iPhone5,4:n49 | \
        iPad3,4:p101 | iPad3,5:p102 | iPad3,6:p103) target_enabled=1;;
    esac
    if [[ $target_enabled != 1 || $device_target_vers != 10.3.4 ||
          $device_target_build != 14G61 || $device_target_other == 1 ||
          $ipsw_gasgauge_patch == 1 || $mode != downgrade ]]; then
        warn "This iOS 10 installer supports iPhone 5, iPhone 5c and iPad 4, Latest iOS 10.3.4 (14G61)."
        print "* The model/board must match. SHSH and other firmware routes are not supported by this jailbreak option. Device preparation has not started."
        return 1
    fi
    if [[ $device_skip_ibss == 1 || $device_pwnrec == 1 || $device_argmode == entry ||
          -n $device_disable_bbupdate || $device_target_tethered == 1 || $device_target_powder == 1 ]]; then
        warn "This restore requires normal identity checks and the standard Latest restore settings."
        return 1
    fi
    [[ -s "$ipsw_path.ipsw" ]] || { warn "Select the stock IPSW before starting."; return 1; }
    [[ "$device_ecid" =~ ^[1-9][0-9]*$ ]] || { warn "A detected device ECID is required."; return 1; }
    ios10_host_init
}

ios10_verify_recovery() {
    $irecovery -q > "$ios10_session_dir/recovery-identity.txt" || return 1
    ios10_session verify-recovery "$ios10_session_dir/recovery-identity.txt"
}

ios10_prepare_session() {
    local parent identifier candidate reuse_source
    local candidates=() memory_args=()
    parent="$(cd .. && pwd)/saved/ios10"
    mkdir -p "$parent" || return 1
    identifier="$("$ios10_python" -c 'import uuid; print(uuid.uuid4())')" || return 1
    ios10_session_dir="$parent/$device_ecid-$identifier"
    local target_args=(--ipsw "$ipsw_path.ipsw" --product "$device_type" --board "${device_model}ap"
                       --version "$device_target_vers" --build "$device_target_build" --ecid "$device_ecid")
    log "Checking for a compatible prepared IPSW"
    local found
    found="$("$ios10_python" "$ios10_resources/reuse.py" list --parent "$parent" "${target_args[@]}")" || return 1
    while IFS= read -r candidate; do
        [[ -n $candidate ]] || continue
        candidates+=("$candidate")
    done <<< "$found"
    if [[ ${#candidates[@]} -gt 0 ]]; then
        input "Reuse existing IPSW?"
        print "* Y reuses a verified image for this device and firmware. N creates a fresh image."
        print "* Previous attempts and logs are preserved. Signing tickets are requested again during restore."
        print "* The most recently prepared compatible image will be checked before reuse."
        select_yesno "Reuse existing IPSW?" 1
        if [[ $? == 1 ]]; then
            reuse_source="${candidates[0]}"
        fi
    fi
    if [[ -n $reuse_source ]]; then
        "$ios10_python" "$ios10_resources/reuse.py" clone --old "$reuse_source" --new "$ios10_session_dir" \
            --tools "$ios10_tools" "${target_args[@]}" || return 1
    else
        ios10_memory_option
        [[ $ipsw_memory != 1 ]] || memory_args=(--memory)
        "$ios10_python" "$ios10_resources/allinone_stage.py" --directory "$ios10_session_dir" \
            --product "$device_type" --board "${device_model}ap" --version "$device_target_vers" \
            --build "$device_target_build" --ecid "$device_ecid" || return 1
        "$ios10_python" "$ios10_resources/prepare.py" --ipsw "$ipsw_path.ipsw" \
            --output "$ios10_session_dir/custom.ipsw" --work "$ios10_session_dir/image" \
            --stage "$ios10_session_dir/stage.tar" --tools "$ios10_tools" \
            --product "$device_type" --board "${device_model}ap" --version "$device_target_vers" \
            --build "$device_target_build" "${memory_args[@]}" || return 1
        ios10_session register-image "$ios10_session_dir/image/preparation.json" || return 1
    fi
    log "Installer session: $ios10_session_dir"
    print "* Saved IPSW and restore logs are kept here for reuse and troubleshooting."
    if [[ $device_mode == Normal ]]; then
        local select_device=()
        [[ -z $device_udid ]] || select_device=(-u "$device_udid")
        "$ios10_tools/ideviceinfo" "${select_device[@]}" -x > "$ios10_session_dir/normal-identity.plist" || return 1
        ios10_session bind-normal "$ios10_session_dir/normal-identity.plist" || return 1
    else
        ios10_verify_recovery || return 1
    fi
    ios10_session verify-boot || return 1
    # Latest uses idevicerestore's normal current-nonce TSS negotiation. The
    # saved-SHSH route remains guarded in preflight pending separate validation.
    shsh_path=
    ipsw_custom="$ios10_session_dir/custom"
}

ios10_memory_option() {
    [[ -z $ipsw_memory ]] || return 0
    input "Memory Option for creating custom IPSW"
    print "* Enable this option to use system RAM during IPSW creation, which can speed up the process."
    print "* This iOS 10 builder uses about 6 GiB for temporary system images; 12 GB RAM or more is recommended."
    print "* On Linux, /dev/shm must have at least 6 GiB available. Final IPSWs and logs are saved to disk."
    select_yesno "Enable this option?" 1
    if [[ $? == 1 ]]; then
        ipsw_memory=1
        log "Memory option enabled."
    else
        ipsw_memory=0
        log "Memory option disabled by user."
    fi
}

ios10_start_capture() {
    local port ports selected count=0
    local choices=()
    if [[ -n $LIK_IOS10_SERIAL_PORT ]]; then
        port="$LIK_IOS10_SERIAL_PORT"
    else
        ports="$("$ios10_python" "$ios10_resources/serial_capture.py" --list-ports)" || return 1
        while IFS= read -r port; do
            [[ -z $port ]] || choices+=("$port")
        done <<< "$ports"
        if [[ ${#choices[@]} == 0 ]]; then
            print "* No DCSD serial port detected. The USB restore log will still be saved."
            return 0
        fi
        selected=0
        if [[ ${#choices[@]} -gt 1 ]]; then
            input "Select DCSD serial port"
            choices+=("Continue without serial capture")
            select_option "${choices[@]}"
            selected=$?
            [[ $selected -lt $((${#choices[@]} - 1)) ]] || return 0
        fi
        port="${choices[$selected]}"
    fi
    ios10_serial_dir="$ios10_session_dir/dcsd-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$ios10_serial_dir" || return 1
    "$ios10_python" "$ios10_resources/serial_capture.py" --port "$port" --directory "$ios10_serial_dir" \
        > "$ios10_serial_dir/host.log" 2>&1 &
    ios10_serial_pid=$!
    while [[ $count -lt 30 ]]; do
        if [[ -s "$ios10_serial_dir/capture.json" ]] && "$ios10_python" - "$ios10_serial_dir/capture.json" <<'PY'
import json, sys
sys.exit(json.load(open(sys.argv[1])).get('state') != 'listening')
PY
        then
            log "DCSD capture listening on $port (115200 baud); no serial commands will be sent"
            print "* Serial log: $ios10_serial_dir/serial.log"
            return 0
        fi
        kill -0 "$ios10_serial_pid" 2>/dev/null || break
        sleep 0.1
        count=$((count + 1))
    done
    warn "DCSD capture could not start. Restore has not started. See $ios10_serial_dir/host.log"
    return 1
}

ios10_stop_capture() {
    if [[ -n $ios10_serial_pid ]]; then
        kill -TERM "$ios10_serial_pid" 2>/dev/null
        wait "$ios10_serial_pid" 2>/dev/null
        ios10_serial_pid=
        print "* DCSD capture saved in $ios10_serial_dir"
    fi
    return 0
}

ios10_enter_pwned_ibss() {
    ios10_session verify-boot || return 1
    # Enter DFU using the normal restore flow.
    device_mode=
    device_dfuhelper DFUreal || return 1
    ios10_verify_recovery || return 1
    # device_send_unpacked_ibss uses these already-verified target components
    # instead of downloading another firmware's iBSS.
    ios10_ibss_dir="$ios10_session_dir/image"
    device_pwnd=
    device_srtg=
    device_mode=DFU
    print "* If pwnDFU fails, relaunch, return to this restore menu, and select Reuse IPSW."
    print "* Manual pwnDFU through Useful Utilities does not work with this custom restore flow."
    device_enter_mode pwnDFU || return 1
    ios10_verify_recovery
}


ios10_after_jumpstart() {
    log "Temporary boot files sent. Wait for the device to finish booting."
    print "* Complete Setup, open Socket (Kit), and tap Install / Continue."
    print "* The app installs the jailbreak assets, Zebra and Procyon on the device."
    print "* When the app says installation is verified, tap Reboot and Verify."
    print "* Reopen the app after reboot to check the untethered boot result."
    print "* No further computer connection is needed for installation. You may close this window."
    print "* If anything fails, use Export Logs in the app. Use only the bundled Socket (Kit) app; do not sideload another Socket app."
    print "* Reports are available through normal AFC in Downloads/Legacy-iOS-Kit/Logs."
    print "* Session: $ios10_session_dir"
}

ios10_jumpstart() {
    warn "This all-in-one build does not provide the previous jump-start route."
    return 1
    local ios10_jumpstart_active=1
    ios10_enter_pwned_ibss || return 1
    log "Booting iOS 10 temporarily to finish the untether installation"
    $irecovery -f "$ios10_session_dir/image/iBEC.jumpstart.img3" || return 1
    sleep 5
    ios10_verify_recovery || return 1
    $irecovery -f "$ios10_session_dir/payload_jumpstart" || return 1
    $irecovery -c go || return 1
    ios10_after_jumpstart
}

ios10_restore_session() {
    ios10_session check-space --workdir "$PWD" || return 1
    ios10_session verify-image || return 1
    ios10_enter_pwned_ibss || return 1
    ios10_session restore-start || return 1
    # The restorer must return its real exit code; text printed afterward must
    # never turn a failure into a successful restore or installer continuation.
    restore_idevicerestore ios10 2>&1 | tee -a "$ios10_session_dir/restore.log"
    local restore_status=("${PIPESTATUS[@]}")
    local result=${restore_status[0]}
    local serial_args=()
    [[ -n $ios10_serial_dir && -s "$ios10_serial_dir/serial.bin" ]] && serial_args=(--serial-log "$ios10_serial_dir/serial.bin")
    "$ios10_python" "$ios10_resources/ticket_audit.py" --log "$ios10_session_dir/restore.log" "${serial_args[@]}" \
        --output "$ios10_session_dir/ticket-audit.json" || warn "Could not summarize ticket evidence; the raw restore log is retained."
    ios10_session restore-result "$result" || return 1
    if [[ $result != 0 ]]; then
        warn "Restore failed (exit $result). Untether installation may be incomplete; inspect the saved restore log."
        print "* Keep the restore log and installer session for diagnosis."
        return "$result"
    fi
    if [[ ${restore_status[1]} != 0 ]]; then
        warn "Restore returned success, but its log could not be saved. Keep this Terminal output before continuing."
        return 1
    fi
    if [[ -n $ios10_serial_dir && -s "$ios10_serial_dir/serial.bin" ]]; then
        "$ios10_python" "$ios10_resources/restore_audit.py" "$ios10_serial_dir/serial.bin" "$ios10_session_dir"
        local audit_result=$?
        case $audit_result in
            0) ;;
            3)
                warn "Restore finished, but the untether installer reported a failure. Keep the logs."
                return 1
                ;;
            *)
                warn "Restore finished, but serial evidence could not confirm the untether installation. This does not prove installation failed."
                print "* Keep the logs if you need to report a boot or jailbreak issue."
                ;;
        esac
    fi
    log "Restore completed. Allow the device to boot normally. No second DFU step or installer app is required."
    print "* Complete Setup normally. Zebra should be available on the Home Screen."
    print "* The first boot may take longer than later boots. Allow time for it to finish."
    case "$device_type" in
        iPad3,[456]) print "* Procyon reports about 7% of iPad 4 boot attempts may fail. If it does not reach the Home Screen, manually reboot and try again.";;
    esac
    return 0

}

ios10_restore_run() (
    # Keep session variables, umask and custom paths out of unrelated Kit flows.
    umask 077
    ios10_preflight || exit 1
    ios10_prepare_session || exit 1
    trap 'ios10_stop_capture' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    ios10_start_capture || exit 1
    ios10_restore_session
    result=$?
    if [[ $result != 0 ]]; then
        warn "This run did not complete all installation checks. Keep the session folder and do not run Socket."
        print "* Session: $ios10_session_dir"
    fi
    exit "$result"
)

ios10_resume_session() (
    umask 077
    ios10_session_dir="$1"
    ios10_host_init || exit 1
    local phase
    phase="$(ios10_session status)" || exit 1
    case $phase in
        awaiting-jumpstart)
            input "Resume iOS 10 Installation"
            select_option "Device is already running after jump-start" "Boot the device using DFU" "Go Back"
            case $? in
                0) ios10_after_jumpstart ;;
                1) ios10_jumpstart ;;
                *) return 0 ;;
            esac
            ;;
        installing|awaiting-coldboot)
            print "* On-device installation is managed by Socket (Kit). Open it to continue or export logs."
            print "* Older builds require their saved logs to be reviewed before recovery; no package operation was repeated."
            ;;
        coldboot-verified)
            log "The ordinary boot was verified. Its saved transport remains available for diagnostics."
            ;;
        *)
            warn "Session is in $phase. Inspect its logs before deciding how to recover."
            print "* Resume will not repeat an erase or assume an interrupted restore succeeded."
            exit 1
            ;;
    esac
)

ios10_resume_menu() {
    ios10_host_init || return 1
    local folder phase index
    local folders=() choices=()
    for folder in ../saved/ios10/"$device_ecid"-*; do
        [[ -s "$folder/session.json" ]] || continue
        phase="$("$ios10_python" "$ios10_resources/session.py" --directory "$folder" status)" || continue
        folders+=("$folder")
        choices+=("${folder##*/} ($phase)")
    done
    choices+=("Go Back")
    input "Resume iOS 10 Installation"
    print "* Open Socket (Kit) on the phone to continue installation after jump-start. This menu never repeats the restore."
    select_option "${choices[@]}"
    index=$?
    [[ $index -ge 0 && $index -lt ${#folders[@]} ]] || return 0
    ios10_resume_session "${folders[$index]}"
}

# A retry is host-only: use the boot files and credentials from the completed
# restore. Never build an image or call a restorer from this path.
ios10_jumpstart_saved_session() (
    umask 077
    ios10_session_dir="$1"
    ios10_host_init || exit 1
    local identity board
    identity="$("$ios10_python" "$ios10_resources/jumpstart.py" identity --directory "$ios10_session_dir")" || exit 1
    IFS=$'\t' read -r device_type board device_target_vers device_target_build device_ecid <<< "$identity"
    device_model="${board%ap}"
    device_proc=6
    mode=ios10-jumpstart
    if [[ $device_skip_ibss == 1 || $device_pwnrec == 1 || $device_argmode == entry ]]; then
        warn "Jump-start retry requires the normal device identity and pwnDFU checks. Relaunch without skip-iBSS or pwned-recovery flags."
        exit 1
    fi
    trap 'ios10_stop_capture' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    ios10_start_capture || exit 1
    ios10_jumpstart
)

ios10_jumpstart_menu() {
    ios10_host_init || return 1
    warn "Only use this option if your custom iOS 10 restore succeeded and the second-stage attempt to enter pwnDFU failed."
    print "* This resumes the saved jump-start. It does not repeat the restore."
    local records folder label selected=0
    local folders=() choices=() filter=()
    [[ -z $device_ecid ]] || filter=(--ecid "$device_ecid")
    records="$("$ios10_python" "$ios10_resources/jumpstart.py" list --directory ../saved/ios10 "${filter[@]}")" || return 1
    while IFS=$'\t' read -r folder label; do
        [[ -n $folder ]] || continue
        folders+=("$folder")
        choices+=("$label")
    done <<< "$records"
    if [[ ${#folders[@]} == 0 ]]; then
        warn "No successful custom iOS 10 restore is awaiting jump-start for this device."
        print "* Keep the original saved/ios10 session folder. This option cannot be used after a failed restore."
        return 1
    fi
    if [[ ${#folders[@]} -gt 1 ]]; then
        choices+=("Go Back")
        input "Select the restored device"
        select_option "${choices[@]}"
        selected=$?
        [[ $selected -ge 0 && $selected -lt ${#folders[@]} ]] || return 0
    fi
    log "Using saved restore: ${choices[$selected]}"
    print "* Session: ${folders[$selected]}"
    ios10_jumpstart_saved_session "${folders[$selected]}"
}
