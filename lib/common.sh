# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state is consumed by other sourced modules.
# Shared storage, dependency and locking helpers.
CONFIG="${THM_ROOT:-}/etc/thm"
RUNTIME="${THM_ROOT:-}/var/run/thm"
LOCK_HELD=0
LOCK_OWNER=''
STARTING=0
OPENVPN=''
SOCAT=''

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}
require_root() { [ "$EUID" -eq 0 ] || die 'Run this command with sudo. Help, version, learn and resources do not need sudo.'; }

private_dir() {
    local path=$1
    [ ! -L "$path" ] || die "Refusing symlink: $path"
    if [ -e "$path" ]; then
        [ -d "$path" ] && [ -O "$path" ] || die "Directory is not owned by this user: $path"
    else
        mkdir -p -- "$path" || die "Cannot create $path"
    fi
    chmod 700 "$path" || die "Cannot protect $path"
}

init_storage() {
    umask 077
    private_dir "$CONFIG"
    private_dir "$CONFIG/profiles"
    private_dir "$RUNTIME"
    local file
    for file in "$CONFIG/default" "$RUNTIME/active" "$RUNTIME/pid" "$RUNTIME/connection.log" "$RUNTIME/management.sock"; do
        [ ! -L "$file" ] || die "Refusing symlink: $file"
        if [ -e "$file" ]; then
            [ -O "$file" ] || die "Unexpected owner: $file"
            if [ "$file" != "$RUNTIME/management.sock" ]; then
                [ -f "$file" ] || die "Not a regular file: $file"
                chmod 600 "$file"
            fi
        fi
    done
}

find_binary() {
    local name=$1 candidate
    candidate=$(type -P "$name" || true)
    if [ -n "$candidate" ]; then
        printf '%s\n' "$candidate"
        return
    fi
    for candidate in "/opt/homebrew/sbin/$name" "/opt/homebrew/bin/$name" "/usr/local/sbin/$name" "/usr/local/bin/$name" "/usr/sbin/$name"; do
        if [ -f "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

dependencies() {
    OPENVPN=$(find_binary openvpn) || die 'OpenVPN missing. Linux: sudo apt install openvpn socat; macOS: brew install openvpn socat (without sudo).'
    SOCAT=$(find_binary socat) || die 'socat missing. Linux: sudo apt install socat; macOS: brew install socat (without sudo).'
    local version
    version=$("$OPENVPN" --version) || die 'Cannot execute OpenVPN.'
    printf '%s\n' "$version" | awk 'NR == 1 { split($2,v,"."); exit !(v[1] == 2 && v[2] >= 6) }' || die 'OpenVPN 2.6 or newer in the 2.x series is required.'
}

acquire_lock() {
    if ! mkdir "$RUNTIME/operation.lock" 2>/dev/null; then
        die 'Another operation holds the lock, or a stale lock remains. Run sudo thm doctor; see README recovery instructions.'
    fi
    LOCK_OWNER="$$:$RANDOM:$RANDOM"
    LOCK_HELD=1
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    printf '%s\n' "$LOCK_OWNER" >"$RUNTIME/operation.lock/owner"
}

release_lock() {
    if [ "$LOCK_HELD" -eq 1 ]; then
        if [ -L "$RUNTIME/operation.lock/owner" ] || [ "$(cat "$RUNTIME/operation.lock/owner" 2>/dev/null)" != "$LOCK_OWNER" ]; then
            printf 'Lock ownership changed; leaving it untouched.\n' >&2
            LOCK_HELD=0
            return 1
        fi
        rm -f -- "$RUNTIME/operation.lock/owner"
        rmdir "$RUNTIME/operation.lock"
        LOCK_HELD=0
    fi
}

cleanup() {
    local result=$?
    trap - EXIT
    if [ "$STARTING" -eq 1 ] && [ -S "$RUNTIME/management.sock" ]; then
        (stop_vpn) >/dev/null 2>&1 || true
    fi
    release_lock || true
    exit "$result"
}

doctor() {
    local failed=0 path mode
    printf 'thm %s | %s | Bash %s\n' "$THM_VERSION" "$(uname -s)" "$BASH_VERSION"
    if (dependencies); then printf 'Dependencies: OK\n'; else failed=1; fi
    for path in "$CONFIG" "$CONFIG/profiles" "$RUNTIME"; do
        if [ -L "$path" ]; then
            printf 'Unsafe symlink: %s\n' "$path"
            failed=1
        elif [ ! -d "$path" ]; then
            printf 'Not initialized: %s\n' "$path"
        else
            mode=$(LC_ALL=C ls -ld "$path")
            if [ ! -O "$path" ] || [ "${mode:0:10}" != drwx------ ]; then
                printf 'Unsafe directory permissions/owner: %s\n' "$path"
                failed=1
            else printf 'Private directory: %s\n' "$path"; fi
        fi
    done
    if [ -e "$RUNTIME/operation.lock" ]; then
        printf 'Operation lock present. Check running thm commands before manual recovery.\n'
        failed=1
    elif [ -d "$RUNTIME" ] && [ "$failed" -eq 0 ]; then
        SOCAT=$(find_binary socat)
        if [ -S "$RUNTIME/management.sock" ]; then
            if query_state; then printf 'Managed connection: %s (%s)\n' "$VPN_STATE" "$VPN_IP"; else
                printf 'Management socket is inaccessible or unresponsive.\n'
                failed=1
            fi
        elif [ -e "$RUNTIME/pid" ] || [ -e "$RUNTIME/active" ]; then
            printf 'Stale or unverifiable connection metadata; no process will be signaled.\n'
            failed=1
        else printf 'Managed connection: disconnected\n'; fi
    fi
    local profile
    if [ -d "$CONFIG/profiles" ] && [ ! -L "$CONFIG/profiles" ]; then
        for profile in "$CONFIG/profiles/"*.ovpn; do
            [ -e "$profile" ] || continue
            mode=$(LC_ALL=C ls -l "$profile")
            if [ ! -O "$profile" ] || [ "${mode:0:10}" != -rw------- ]; then
                printf 'Unsafe profile owner/permissions: %s\n' "$profile"
                failed=1
            fi
            if (validate_profile "$profile"); then printf 'Profile supported: %s\n' "$(basename "$profile" .ovpn)"; else failed=1; fi
        done
    fi
    return "$failed"
}
