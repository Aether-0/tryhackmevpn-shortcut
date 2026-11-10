# Dummy-data terminal demo

The fixture contains placeholder certificates. This demo uses a Unix-socket mock,
not a VPN, and needs only Python 3 and socat. Run from the repository root in a
disposable Bash shell:

~~~bash
export THM_ROOT
THM_ROOT=$(mktemp -d /tmp/thm-demo.XXXXXX)
source ./thm
require_root() { :; } # Override exists only in this disposable demo shell.
dependencies() {
    OPENVPN="$THM_SOURCE/tests/fake-openvpn.py"
    SOCAT=$(command -v socat)
}
main profile add demo "$THM_SOURCE/tests/fixtures/demo.ovpn"
main profile use demo
main start
main status
main ip
main stop
~~~

See [demo.cast](demo.cast) for an asciinema v2 recording with dummy data. Replay
with "asciinema play docs/demo.cast". Temporary data is retained for inspection.
