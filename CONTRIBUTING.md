# Contributing

Keep runtime code compatible with Bash 3.2. Avoid associative arrays, namerefs,
mapfile, coproc, GNU-only timeout/flock/readlink options, and interface parsing.

Install development dependencies:

~~~bash
# Kali / Ubuntu / Debian
sudo apt install shellcheck shfmt bats socat python3
# macOS (without sudo)
brew install shellcheck shfmt bats-core socat python
~~~

Run from the repository root:

~~~bash
shellcheck -x thm install.sh uninstall.sh lib/*.sh
shfmt -d -i 4 thm install.sh uninstall.sh lib/*.sh tests/*.bats
TMPDIR=/tmp bats tests
~~~

Tests source the CLI, replace the privilege check only in the test process, and
use a temporary THM_ROOT directory. The production EUID check has no environment
bypass. The Python helper imitates OpenVPN over Unix sockets; it creates no tunnel.
No root, credentials, or TryHackMe access are needed. Room-browser tests use a
synthetic Markdown fixture and mock curl; they need no network access.

THM_ROOT relocates storage for development. THM_INSTALL_ROOT stages installation
for packaging tests. Never use untrusted paths for privileged real operations.
A staged wrapper still targets the final /usr/local installation.

Test lifecycle errors, interrupted startup, permission handling, and profile
trust boundaries. CI cannot prove real networking works. Manually check Linux
connection, routing, reconnect, and disconnect before release. For macOS, check
Homebrew discovery under sudo and use /bin/bash as well as modern Bash.
