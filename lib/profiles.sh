# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state is consumed by other sourced modules.
# Configuration is data, never shell code.
valid_name() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die 'Profile names must contain letters, digits, underscores or hyphens and start with a letter or digit.'; }

validate_profile() {
    local file=$1
    [ -f "$file" ] && [ -r "$file" ] && [ ! -L "$file" ] || die "Not a readable regular profile: $file"
    # Allowlist prevents scripts/plugins, nested configs and process overrides.
    awk '
    BEGIN { block=""; client=0; remote=0; ca=0; cert=0; key=0; dev=0 }
    { sub(/\r$/, "") }
    /^[ \t]*([#;]|$)/ { next }
    {
        line=$0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
        if (block != "") {
            if (line == "</" block ">") { block="" }
            next
        }
        if (line ~ /^<(ca|cert|key|tls-auth|tls-crypt|tls-crypt-v2)>$/) {
            block=substr(line,2,length(line)-2)
            if (block=="ca") ca=1; if (block=="cert") cert=1; if (block=="key") key=1
            next
        }
        split(line, fields, /[ \t]+/); option=fields[1]
        if (option=="client") client=1
        if (option=="remote") remote=1
        if (option=="dev") {
            if (line !~ /^dev[ \t]+tun([ \t]+[#;].*)?$/) { bad=1; exit }
            dev=1
        }
        allowed=" client dev proto remote resolv-retry nobind persist-key persist-tun remote-cert-tls cipher auth verb mute sndbuf rcvbuf key-direction tun-mtu mssfix explicit-exit-notify auth-nocache allow-compression data-ciphers data-ciphers-fallback tls-version-min tls-version-max connect-retry connect-retry-max connect-timeout remote-random float fast-io reneg-sec route route-ipv6 redirect-gateway dhcp-option pull pull-filter topology inactive ping ping-restart ping-timer-rem compress comp-lzo mute-replay-warnings verify-x509-name tls-cipher tls-ciphersuites "
        if (index(allowed," " option " ")==0) { bad=1; exit }
    }
    END { exit (bad || block!="" || !client || !remote || !ca || !cert || !key || !dev) }
    ' "$file" || die 'Unsupported profile. Require client, remote, dev tun and inline CA/certificate/key; external files, scripts, plugins, nested configs and management overrides are unsupported.'
    if LC_ALL=C awk '/BEGIN ENCRYPTED PRIVATE KEY|Proc-Type: 4,ENCRYPTED/ { found=1 } END { exit !found }' "$file"; then
        die 'Encrypted private keys require interactive authentication, which is unsupported.'
    fi
}

profiles() {
    local action=${1:-} name=${2:-} file=${3:-} path current=''
    case "$action" in
    add)
        [ "$#" -eq 3 ] || die 'Usage: thm profile add NAME FILE'
        valid_name "$name"
        validate_profile "$file"
        path="$CONFIG/profiles/$name.ovpn"
        [ ! -e "$path" ] && [ ! -L "$path" ] || die 'Profile exists; remove it before importing a replacement.'
        (
            set -C
            cat -- "$file" >"$path"
        ) || die 'Profile import failed.'
        chmod 600 "$path"
        printf 'Imported %s. Select it with: sudo thm profile use %s\n' "$name" "$name"
        ;;
    list)
        [ "$#" -eq 1 ] || die 'Usage: thm profile list'
        if [ -f "$CONFIG/default" ]; then current=$(cat "$CONFIG/default"); fi
        for path in "$CONFIG/profiles/"*.ovpn; do
            [ -f "$path" ] || continue
            name=$(basename "$path" .ovpn)
            if [ "$name" = "$current" ]; then printf '* %s\n' "$name"; else printf '  %s\n' "$name"; fi
        done
        ;;
    use | remove)
        [ "$#" -eq 2 ] || die "Usage: thm profile $action NAME"
        valid_name "$name"
        path="$CONFIG/profiles/$name.ovpn"
        [ -f "$path" ] && [ ! -L "$path" ] || die 'Profile does not exist.'
        if [ "$action" = use ]; then
            printf '%s\n' "$name" >"$CONFIG/default"
            printf 'Default profile: %s\n' "$name"
        else
            if [ -f "$RUNTIME/active" ] && [ "$(cat "$RUNTIME/active")" = "$name" ]; then die 'Stop this profile before removing it.'; fi
            rm -- "$path"
            if [ -f "$CONFIG/default" ] && [ "$(cat "$CONFIG/default")" = "$name" ]; then rm -- "$CONFIG/default"; fi
            printf 'Removed %s\n' "$name"
        fi
        ;;
    *) die 'Usage: thm profile {add NAME FILE|list|use NAME|remove NAME}' ;;
    esac
}
