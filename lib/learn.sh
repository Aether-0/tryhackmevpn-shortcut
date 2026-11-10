# shellcheck shell=bash
# Learning helpers run without root and never touch VPN configuration.
ROOMS_SOURCE=https://raw.githubusercontent.com/winterrdog/tryhackme-free-rooms/main/README.md
ROOMS_CREDIT=https://github.com/winterrdog/tryhackme-free-rooms

learning_resources() {
    cat <<'LINKS'
Learning roadmap and room browser:
  https://tryhackme.com/hacktivities
Learning paths:
  https://tryhackme.com/paths
Community free-room catalogue (maintained by winterrdog):
  https://github.com/winterrdog/tryhackme-free-rooms
Official VPN connection guide:
  https://help.tryhackme.com/en/articles/6496038-connecting-to-openvpn-on-linux-and-mac

Examples:
  thm learn linux
  thm learn --topics
  thm learn --random web
LINKS
}

fetch_rooms() {
    local curl_binary content
    curl_binary=$(find_binary curl) || die 'Room browsing needs curl. Install curl, or run thm resources for links.'
    content=$("$curl_binary" --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --connect-timeout 5 \
        --max-time 20 --max-filesize 2097152 "$ROOMS_SOURCE") ||
        die "Could not download the room list. Check your network or visit $ROOMS_CREDIT"
    [ -n "$content" ] || die 'The room source returned an empty list. Try thm resources.'
    # Treat the catalogue as untrusted text; strip terminal control characters.
    printf '%s\n' "$content" | LC_ALL=C tr -d '\000-\010\013-\037\177'
}

room_rows() {
    # Parse only room links, not donation/advertising/external-resource links.
    # Do not include struck-through rooms marked as premium or unavailable.
    awk '
    /^## / { topic=substr($0,4); next }
    /~~/ { next }
    {
        line=$0
        while (match(line, /\[[^]]+\]\(https:\/\/tryhackme[.]com\/(r\/)?room\/[a-zA-Z0-9_-]+\)/)) {
            link=substr(line,RSTART,RLENGTH)
            line=substr(line,RSTART+RLENGTH)
            separator=index(link,"](")
            title=substr(link,2,separator-2)
            sub(/^[Tt]ry[Hh]ack[Mm]e[ \t]*[|][ \t]*/, "", title)
            url=substr(link,separator+2,length(link)-separator-2)
            if (!seen[url]++) print topic " | " title " | " url
        }
    }'
}

browse_rooms() {
    local mode=list content rows result query
    case "${1:-}" in
    --topics)
        mode=topics
        shift
        [ "$#" -eq 0 ] || die 'Usage: thm learn --topics'
        ;;
    --random)
        mode=random
        shift
        ;;
    --) shift ;;
    -*) die 'Usage: thm learn [SEARCH ...] | --topics | --random [SEARCH ...]' ;;
    esac
    query="$*"
    content=$(fetch_rooms) || return 1
    rows=$(printf '%s\n' "$content" | room_rows)
    [ -n "$rows" ] || die 'No supported room links found. The community source may have changed; run thm resources.'
    if [ "$mode" = topics ]; then
        result=$(printf '%s\n' "$rows" | awk -F ' [|] ' '!seen[$1]++ { print $1 }')
    else
        # ENVIRON passes literal search text without regex or awk escape expansion.
        result=$(printf '%s\n' "$rows" | THM_ROOM_QUERY="$query" awk 'index(tolower($0),tolower(ENVIRON["THM_ROOM_QUERY"]))')
        [ -n "$result" ] || {
            printf 'No rooms matched: %s\n' "$query" >&2
            return 1
        }
        if [ "$mode" = random ]; then
            result=$(printf '%s\n' "$result" | awk 'BEGIN { srand() } rand() < 1/NR { chosen=$0 } END { print chosen }')
        fi
    fi
    printf 'Community catalogue by winterrdog: %s\n' "$ROOMS_CREDIT"
    printf 'Room availability and pricing can change; check TryHackMe before joining.\n\n'
    if [ -t 1 ] && command -v less >/dev/null 2>&1; then
        printf '%s\n' "$result" | LESSSECURE=1 LESSOPEN='' less -F -X
    else
        printf '%s\n' "$result"
    fi
}
