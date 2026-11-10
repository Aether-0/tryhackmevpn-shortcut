#!/bin/bash
set -euo pipefail
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SOURCE/lib/common.sh"
install_main() {
    if [ "$#" -eq 1 ] && { [ "$1" = --help ] || [ "$1" = -h ]; }; then
        printf 'Usage: sudo bash install.sh\nInstall the CLI under /usr/local. Import VPN profiles separately.\n'
        exit 0
    fi
    [ "$#" -eq 0 ] || die 'Usage: sudo bash install.sh (old -v/-n options are replaced by thm profile add).'
    require_root
    dependencies
    for file in thm lib/common.sh lib/profiles.sh lib/vpn.sh lib/learn.sh; do
        [ -f "$SOURCE/$file" ] || die "Missing source: $file"
        bash -n "$SOURCE/$file" || die "Invalid Bash syntax: $file"
    done
    local prefix="${THM_INSTALL_ROOT:-}/usr/local"
    DEST="$prefix/lib/thm"
    [ ! -L "$DEST/lib" ] || die "Refusing symlink at module directory."
    [ ! -L "$DEST/launcher" ] || die "Refusing symlink at launcher path."
    [ ! -L "$DEST" ] || die 'Refusing symlink at installation destination.'
    local directory
    for directory in "$DEST" "$DEST/lib"; do
        if [ -e "$directory" ]; then
            [ -d "$directory" ] && [ -O "$directory" ] || die "Installation directory has an unexpected owner/type: $directory"
        fi
    done
    install -d -m 755 "$DEST" "$DEST/lib" "$prefix/bin"
    for file in thm lib/common.sh lib/profiles.sh lib/vpn.sh lib/learn.sh; do
        [ ! -L "$DEST/$file" ] || die "Refusing symlink: $DEST/$file"
        install -m 644 "$SOURCE/$file" "$DEST/$file"
    done
    chmod 755 "$DEST/thm"
    [ ! -L "$prefix/bin/thm" ] || die 'Refusing to overwrite symlink /usr/local/bin/thm.'
    # A fixed wrapper keeps module resolution independent of the current directory.
    cat >"$DEST/launcher" <<'WRAPPER'
#!/bin/bash
exec /usr/local/lib/thm/thm "$@"
WRAPPER
    install -m 755 "$DEST/launcher" "$prefix/bin/thm"
    rm -- "$DEST/launcher"
    printf 'Installed thm 2.0.0. Run thm --help.\n'
    if [ -e /usr/bin/thm ] || [ -e /opt/thmvpn.ovpn ]; then
        printf 'Legacy installation detected. See README migration instructions; old files were preserved.\n'
    fi

}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then install_main "$@"; fi
