# TryHackMe VPN Shortcut

A small Bash CLI for named TryHackMe OpenVPN profiles, accurate connection status,
private logs, diagnostics, and room discovery. Originally created by Zaw Wanz.

Version 2.0 keeps your terminal free and controls only its own OpenVPN connection.

## Platform support

| Platform | Status |
| --- | --- |
| Kali, Ubuntu, Debian | Primary target; Ubuntu CI uses mocked connections |
| macOS | Experimental; CI checks with /bin/bash, real VPN testing pending |
| Other Linux distributions | Not validated |
| Windows | Unsupported |

Requires Bash 3.2+, OpenVPN 2.6+ (2.x), socat, and standard Unix utilities.
Real Linux networking must be verified before publishing a release.

## Quick start

Install dependencies on Kali, Ubuntu, or Debian:

~~~bash
sudo apt update
sudo apt install openvpn socat curl
~~~

On macOS, use Homebrew as your normal user:

~~~bash
brew install openvpn socat curl
~~~

Install the CLI:

~~~bash
git clone https://github.com/Aether-0/tryhackmevpn-shortcut.git
cd tryhackmevpn-shortcut
sudo bash install.sh
~~~

Download your connection pack from TryHackMe, then import it:

~~~bash
sudo thm profile add personal "$HOME/Downloads/my-profile.ovpn"
sudo thm profile use personal
sudo thm start
sudo thm status
sudo thm ip
sudo thm stop
~~~

The installer checks dependencies before copying files into /usr/local. It does
not install packages, create boot services, or change sudoers. Help, version,
and the learning commands work without sudo; profile and connection commands require sudo.

See [TryHackMe's official connection guide](https://help.tryhackme.com/en/articles/6496038-connecting-to-openvpn-on-linux-and-mac).
This independent project is unaffiliated with TryHackMe and serves users who
prefer a scriptable terminal workflow.

## Commands

| Command | Behavior |
| --- | --- |
| profile add NAME FILE | Copy a trusted profile; preserve the original |
| profile list | List profiles; * marks the default |
| profile use NAME | Select the default for future connections |
| profile remove NAME | Remove an inactive profile |
| start [NAME] | Connect the named profile or selected default |
| stop | Stop only this tool's OpenVPN instance |
| restart | Restart the active profile, or connect the default if stopped |
| status | Show profile, connection state, and VPN IP |
| ip | Print the VPN IP only; nonzero exit unless connected |
| logs [--follow] | Show the last 50 log lines; optionally follow |
| doctor | Inspect dependencies, storage, locks, profiles, and connection |
| learn [SEARCH ...] / -l / --learn / rooms | Browse and search the community room catalogue |
| learn --topics | List topics such as Linux, web, networking, and forensics |
| learn --random [SEARCH ...] | Pick a room, optionally within a topic/search |
| resources | Show learning paths, room browser, and VPN help links offline |
| --help / --version | Show help or version without sudo |
| -k / --suicide | Harmless terminal joke; changes no files and needs no sudo |

The original -s/--start, -S/--stop, and -h/--help aliases remain supported.
Errors return nonzero. A cleanly disconnected status returns zero.
Starting the already connected profile creates no duplicate process. Stop before
starting a different profile. Only one connection is managed.

Profile names start with a letter or digit and contain letters, digits,
underscores, or hyphens. Existing names are never overwritten; stop, remove, and
import again to replace one. Removing the default clears the selection.

## Find something to learn

~~~bash
thm -l                       # Original free-room list command
thm learn linux              # Search titles, categories, and URLs
thm rooms "privilege escalation"
thm learn --topics           # Show available categories
thm learn --random web       # Suggest one matching room
thm resources                # Offline learning and help links
~~~

Room browsing fetches the current community catalogue maintained by
[winterrdog](https://github.com/winterrdog/tryhackme-free-rooms). It requires curl
and an internet connection, but no VPN or sudo. Search is case-insensitive and
literal. Results include titles, topics, and room links. Entries struck through
by the maintainer are skipped, and duplicate URLs are shown once.

This community list is not an official guarantee of free access: room availability
and pricing may change. Check TryHackMe before joining. The CLI strips terminal
control characters and never executes downloaded content.

An interactive terminal uses less if installed; pipes and systems without less
receive plain text. Downloads fail visibly with a timeout. There is no local
catalogue cache; resources still works offline.

## Profile and process safety

Import only trusted, self-contained certificate profiles. The supported subset
requires client, dev tun, remote, and inline CA, certificate, and key blocks.
Inline TLS keys are supported. External files, password/MFA prompts, encrypted
private keys, scripts, plugins, nested configuration, and process overrides are
unsupported. Unknown directives fail; the CLI never silently rewrites TLS settings.

This conservative validation is not a sandbox or certificate validator. OpenVPN
validates certificates/configuration when connecting. Test fixtures contain
placeholder certificates and cannot connect to a VPN.

Profiles are in /etc/thm/profiles, with the default in /etc/thm/default.
Runtime metadata, logs, and the management socket are in /var/run/thm.
Directories use mode 0700; files use 0600. Runtime logs may disappear on reboot.
Logs may contain addresses and certificate/account names: review before sharing.
Git ignores profiles, keys, and logs, except the explicit dummy fixture.

OpenVPN starts on a private management socket with a management hold. The CLI
waits up to 30 seconds for CONNECTED instead of assuming an interface name.
Shutdown uses that endpoint's SIGTERM command after checking its PID against
private metadata. No process-name kill or unverified numeric-PID signal is used.

Sessions survive terminal closure. OpenVPN can perform its normal reconnection,
visible in status; there is no additional background supervisor. Automatic boot
connections, DNS integration, systemd/launchd services, and generic OpenVPN profile
support are outside this release. CONNECTED means OpenVPN initialized; it does
not guarantee a lab host is reachable or that system DNS changed.

## Troubleshooting

~~~bash
sudo thm doctor
sudo thm logs
~~~

- Missing dependencies: install with apt or Homebrew. Intel and Apple Silicon
  Homebrew locations are checked when sudo changes PATH.
- Startup failure: inspect logs for TLS/authentication, routing, and configuration
  errors. Cleanup requests graceful shutdown where possible and preserves
  unverifiable state.
- Different profile active: stop first.
- Unsupported profile: download a fresh self-contained THM certificate profile.
  Do not weaken certificate verification to bypass errors.
- Existing lock: check whether another CLI operation is still running.

### Manual recovery

Inspect running commands with ps -ef and inspect the paths reported by doctor.
Locks are never broken automatically based on age or PID alone. Only after
confirming no thm operation is running, remove the owner file and empty directory:

~~~bash
sudo cat /var/run/thm/operation.lock/owner
sudo rm /var/run/thm/operation.lock/owner
sudo rmdir /var/run/thm/operation.lock
~~~

If a management endpoint is inaccessible and metadata remains, inspect OpenVPN
processes and their arguments. Rebooting is the simplest safe recovery when
ownership is unclear. After confirming the managed process has exited, remove
only its stale metadata, preserving connection.log:

~~~bash
sudo rm -f /var/run/thm/management.sock /var/run/thm/pid /var/run/thm/active
~~~

Never use a process-name kill to recover.

## Migration from version 1

The old installer -v and -n options are replaced by profile add. Import your
original download or trusted /opt/thmvpn.ovpn, then select a default.
The installer preserves legacy files. Check type -a thm and use
/usr/local/bin/thm explicitly if /usr/bin/thm takes precedence. After verifying the
new install, you may manually remove the legacy /usr/bin/thm and /opt/thmvpn.ovpn.

The old destructive behavior has been removed. The -k/--suicide command remains
as a harmless joke that only prints text. The original -l/--learn room browser
is preserved and extended with search, topics, and random selection.
Connection commands now require explicit sudo.

## Uninstall

~~~bash
sudo thm stop
sudo bash uninstall.sh
~~~

Run from the repository. Program files are removed; profiles, logs, and legacy
installations are preserved.

## Development and release

See [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md), and
[the dummy-data terminal demo](docs/demo.md).

Before tagging: require green CI, a real Linux connect/status/IP/stop test,
verified private permissions, and an unrelated VPN left untouched. macOS remains
experimental until a real Mac passes equivalent checks. Never publish real
profiles, private keys, or unreviewed logs with recordings.
