#!/bin/bash
set -euo pipefail
if [ "$#" -eq 1 ] && { [ "$1" = --help ] || [ "$1" = -h ]; }; then
    printf 'Usage: sudo bash uninstall.sh\nRemoves program files only. Profiles and logs are preserved.\n'
    exit 0
fi
[ "$#" -eq 0 ] || {
    printf 'Unexpected arguments.\n' >&2
    exit 1
}
[ "$EUID" -eq 0 ] || {
    printf 'Run with sudo.\n' >&2
    exit 1
}
if [ -e /var/run/thm/operation.lock ] || [ -e /var/run/thm/active ] || [ -S /var/run/thm/management.sock ]; then
    printf 'Stop the managed connection and resolve any stale state before uninstalling.\n' >&2
    exit 1
fi
for file in /usr/local/bin/thm /usr/local/lib/thm/thm /usr/local/lib/thm/lib/common.sh /usr/local/lib/thm/lib/profiles.sh /usr/local/lib/thm/lib/vpn.sh; do
    [ ! -L "$file" ] || {
        printf 'Refusing symlink: %s\n' "$file" >&2
        exit 1
    }
done
for file in /usr/local/bin/thm /usr/local/lib/thm/thm /usr/local/lib/thm/lib/common.sh /usr/local/lib/thm/lib/profiles.sh /usr/local/lib/thm/lib/vpn.sh; do
    rm -f -- "$file"
done
rmdir /usr/local/lib/thm/lib /usr/local/lib/thm 2>/dev/null || true
printf 'Program removed. Profiles in /etc/thm and logs in /var/run/thm were preserved.\n'
