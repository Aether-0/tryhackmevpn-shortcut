# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state is consumed by other sourced modules.
# One private management endpoint, never a process-name or numeric-PID kill.
CONNECT_TIMEOUT=30
STOP_TIMEOUT=10
VPN_STATE=''
VPN_IP=''

management() {
    local response
    response=$(printf '%s\nquit\n' "$1" | "$SOCAT" -t 2 -T 3 - "UNIX-CONNECT:$RUNTIME/management.sock,connect-timeout=2") || return 1
    printf '%s\n' "$response" | tr -d '\r'
}

query_state() {
    local response line
    response=$(management state) || return 1
    line=$(printf '%s\n' "$response" | awk -F, '/^[0-9]+,[A-Z_]+,/ { print $2 "," $4; exit }')
    [ -n "$line" ] || return 1
    VPN_STATE=${line%%,*}
    VPN_IP=${line#*,}
}

verify_endpoint() {
    local response pid
    [ -S "$RUNTIME/management.sock" ] && [ -f "$RUNTIME/pid" ] && [ -f "$RUNTIME/active" ] || return 1
    pid=$(cat "$RUNTIME/pid")
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    response=$(management pid) || return 1
    printf '%s\n' "$response" | awk -v pid="$pid" '$0 == "SUCCESS: pid=" pid { found=1 } END { exit !found }'
}

clear_session() {
    # Only call after the managed endpoint has confirmed shutdown.
    rm -f -- "$RUNTIME/management.sock" "$RUNTIME/pid" "$RUNTIME/active"
}

stop_vpn() {
    if [ ! -S "$RUNTIME/management.sock" ]; then
        if [ -e "$RUNTIME/pid" ] || [ -e "$RUNTIME/active" ]; then
            die 'Connection state cannot be verified. Run thm doctor; no process was signaled.'
        fi
        printf 'Already disconnected.\n'
        return
    fi
    verify_endpoint || die 'Cannot verify the managed endpoint. No process was signaled; run thm doctor.'
    local response end pid
    pid=$(cat "$RUNTIME/pid")
    response=$(management 'signal SIGTERM') || die 'Could not request shutdown; inspect thm logs.'
    [[ "$response" = *'SUCCESS: signal SIGTERM thrown'* ]] || die 'OpenVPN did not acknowledge shutdown.'
    end=$((SECONDS + STOP_TIMEOUT))
    while [ "$SECONDS" -lt "$end" ]; do
        # kill -0 is only a liveness check, never authority to send a signal.
        if { [ ! -e "$RUNTIME/pid" ] && [ ! -S "$RUNTIME/management.sock" ]; } || ! kill -0 "$pid" 2>/dev/null; then
            clear_session
            printf 'Disconnected.\n'
            return
        fi
        sleep 1
    done
    die 'Shutdown did not complete within 10 seconds. State retained; inspect thm doctor and logs.'
}

start_vpn() {
    local name=$1 end response
    if [ -z "$name" ] && [ -f "$CONFIG/default" ]; then name=$(cat "$CONFIG/default"); fi
    [ -n "$name" ] || die 'Select a profile with thm profile use NAME, or run thm start NAME.'
    valid_name "$name"
    validate_profile "$CONFIG/profiles/$name.ovpn"
    if [ -S "$RUNTIME/management.sock" ]; then
        if ! verify_endpoint || ! query_state; then die 'Managed connection is unresponsive; run thm doctor.'; fi
        [ "$(cat "$RUNTIME/active")" = "$name" ] || die 'A different profile is active. Run thm stop first.'
        if [ "$VPN_STATE" = CONNECTED ]; then
            printf 'Already connected: %s (%s)\n' "$name" "$VPN_IP"
            return
        fi
        die "Profile is already running ($VPN_STATE). Inspect status/logs or stop it first."
    fi
    [ ! -e "$RUNTIME/pid" ] && [ ! -e "$RUNTIME/active" ] || die 'Stale or unverifiable connection metadata. Run thm doctor before starting.'
    printf '%s\n' "$name" >"$RUNTIME/active"
    : >"$RUNTIME/connection.log"
    STARTING=1
    "$OPENVPN" --config "$CONFIG/profiles/$name.ovpn" \
        --daemon thm --writepid "$RUNTIME/pid" \
        --log "$RUNTIME/connection.log" \
        --management "$RUNTIME/management.sock" unix \
        --management-hold --script-security 1 --auth-retry none ||
        die 'OpenVPN launch failed. Run sudo thm logs.'
    end=$((SECONDS + CONNECT_TIMEOUT))
    while [ "$SECONDS" -lt "$end" ]; do
        if [ -S "$RUNTIME/management.sock" ] && verify_endpoint; then
            response=$(management 'hold release') || response=''
            if query_state && [ "$VPN_STATE" = CONNECTED ]; then
                STARTING=0
                printf 'Connected: %s (%s)\n' "$name" "$VPN_IP"
                return
            fi
        fi
        sleep 1
    done
    # EXIT cleanup requests a graceful shutdown, retaining evidence on failure.
    die 'Connection did not become ready within 30 seconds. Shutdown requested; inspect sudo thm logs and doctor.'
}

show_status() {
    local command=$1
    if [ ! -S "$RUNTIME/management.sock" ]; then
        if [ -e "$RUNTIME/pid" ] || [ -e "$RUNTIME/active" ]; then die 'Connection state is unknown; run thm doctor.'; fi
        if [ "$command" = status ]; then
            printf 'Disconnected.\n'
            return
        fi
        return 1
    fi
    if ! verify_endpoint || ! query_state; then die 'Cannot read the managed connection; run thm doctor.'; fi
    if [ "$command" = ip ]; then
        [ "$VPN_STATE" = CONNECTED ] && [ -n "$VPN_IP" ] || return 1
        printf '%s\n' "$VPN_IP"
    else
        printf 'Profile: %s\nState: %s\nVPN IP: %s\n' "$(cat "$RUNTIME/active")" "$VPN_STATE" "${VPN_IP:-unassigned}"
    fi
}
