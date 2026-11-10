#!/usr/bin/env bats

setup() {
    export THM_ROOT="$BATS_TEST_TMPDIR/root"
    export REPO
    REPO=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    # Test private storage under the test user; production always checks EUID.
    source "$REPO/thm"
    require_root() { :; }
    init_storage
    OPENVPN="$REPO/tests/fake-openvpn.py"
    SOCAT=$(command -v socat)
    dependencies() { :; }
}

teardown() {
    if [ -S "$RUNTIME/management.sock" ]; then
        printf 'signal SIGTERM\nquit\n' | "$SOCAT" -t 1 -T 1 - "UNIX-CONNECT:$RUNTIME/management.sock" >/dev/null 2>&1 || true
    fi
}

import_demo() {
    profiles add demo "$REPO/tests/fixtures/demo.ovpn"
    profiles use demo
}

@test "help and version work without privileges" {
    run "$REPO/thm" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'profile add'* ]]
    run "$REPO/thm" --version
    [ "$output" = 'thm 2.0.0' ]
}

@test "suicide joke works without privileges and leaves files unchanged" {
    local flag
    printf 'keep me\n' >"$BATS_TEST_TMPDIR/sentinel"
    export THM_ROOT="$BATS_TEST_TMPDIR/unused-root"
    for flag in --suicide -k; do
        run "$REPO/thm" "$flag"
        [ "$status" -eq 0 ]
        [[ "$output" == *'Just kidding. Your /boot is safe.'* ]]
        [ ! -e "$THM_ROOT" ]
        [ "$(cat "$BATS_TEST_TMPDIR/sentinel")" = 'keep me' ]
    done
    run "$REPO/thm" --suicide unexpected
    [ "$status" -ne 0 ]
}

@test "profile copy preserves original, spaces, default and private modes" {
    cp "$REPO/tests/fixtures/demo.ovpn" "$BATS_TEST_TMPDIR/my profile.ovpn"
    profiles add demo "$BATS_TEST_TMPDIR/my profile.ovpn"
    profiles use demo
    cmp "$BATS_TEST_TMPDIR/my profile.ovpn" "$CONFIG/profiles/demo.ovpn"
    [ "$(LC_ALL=C ls -ld "$CONFIG" | cut -c1-10)" = drwx------ ]
    [ "$(LC_ALL=C ls -l "$CONFIG/profiles/demo.ovpn" | cut -c1-10)" = -rw------- ]
    run profiles list
    [ "$output" = '* demo' ]
}

@test "invalid names, duplicate profiles and unsupported directives fail" {
    run profiles add ../escape "$REPO/tests/fixtures/demo.ovpn"
    [ "$status" -ne 0 ]
    import_demo
    run profiles add demo "$REPO/tests/fixtures/demo.ovpn"
    [ "$status" -ne 0 ]
    local directive
    for directive in 'up /tmp/hook' 'plugin /tmp/plugin' 'config /tmp/other' 'auth-user-pass' 'ca /tmp/ca' 'management /tmp/sock unix' 'log /tmp/output' '--daemon evil'; do
        cp "$REPO/tests/fixtures/demo.ovpn" "$BATS_TEST_TMPDIR/bad.ovpn"
        printf '%s\n' "$directive" >>"$BATS_TEST_TMPDIR/bad.ovpn"
        run validate_profile "$BATS_TEST_TMPDIR/bad.ovpn"
        [ "$status" -ne 0 ]
    done
}

@test "incomplete blocks, encrypted keys and symlinks fail" {
    cp "$REPO/tests/fixtures/demo.ovpn" "$BATS_TEST_TMPDIR/bad.ovpn"
    printf '<tls-auth>\n' >>"$BATS_TEST_TMPDIR/bad.ovpn"
    run validate_profile "$BATS_TEST_TMPDIR/bad.ovpn"
    [ "$status" -ne 0 ]
    cp "$REPO/tests/fixtures/demo.ovpn" "$BATS_TEST_TMPDIR/bad.ovpn"
    printf '# BEGIN ENCRYPTED PRIVATE KEY\n' >>"$BATS_TEST_TMPDIR/bad.ovpn"
    run validate_profile "$BATS_TEST_TMPDIR/bad.ovpn"
    [ "$status" -ne 0 ]
    ln -s "$REPO/tests/fixtures/demo.ovpn" "$BATS_TEST_TMPDIR/link.ovpn"
    run validate_profile "$BATS_TEST_TMPDIR/link.ovpn"
    [ "$status" -ne 0 ]
}

@test "start waits for readiness, status and ip describe its own connection" {
    import_demo
    export MOCK_MODE=slow
    start_vpn demo
    run show_status status
    [ "$status" -eq 0 ]
    [[ "$output" == *'CONNECTED'* ]]
    run show_status ip
    [ "$output" = '10.23.4.5' ]
    run start_vpn demo
    [ "$status" -eq 0 ]
    [[ "$output" == *'Already connected'* ]]
    stop_vpn
    run show_status status
    [ "$output" = 'Disconnected.' ]
}

@test "different active profile and removal are refused" {
    import_demo
    profiles add other "$REPO/tests/fixtures/demo.ovpn"
    start_vpn demo
    run start_vpn other
    [ "$status" -ne 0 ]
    run profiles remove demo
    [ "$status" -ne 0 ]
    stop_vpn
    profiles remove demo
    [ ! -e "$CONFIG/default" ]
}

@test "disconnect does not terminate an unrelated process" {
    import_demo
    sleep 60 &
    local unrelated=$!
    start_vpn demo
    stop_vpn
    kill -0 "$unrelated"
    kill "$unrelated"
    wait "$unrelated" || true
    run stop_vpn
    [ "$status" -eq 0 ]
}

@test "stale PID and inaccessible endpoint never authorize a signal" {
    printf '99999999\n' >"$RUNTIME/pid"
    printf 'demo\n' >"$RUNTIME/active"
    run stop_vpn
    [ "$status" -ne 0 ]
    [[ "$output" == *'no process was signaled'* ]]
    import_demo
    run start_vpn demo
    [ "$status" -ne 0 ]
}

@test "a second operation cannot acquire or break an existing lock" {
    acquire_lock
    run main profile list
    [ "$status" -ne 0 ]
    [ -f "$RUNTIME/operation.lock/owner" ]
    release_lock
    [ ! -e "$RUNTIME/operation.lock" ]
}

@test "startup timeout requests shutdown and preserves diagnostic log" {
    import_demo
    export MOCK_MODE=timeout
    run bash -c '
        source "$REPO/thm"
        CONNECT_TIMEOUT=2
        require_root() { :; }
        dependencies() { OPENVPN="$REPO/tests/fake-openvpn.py"; SOCAT=$(command -v socat); }
        main start demo
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *'did not become ready'* ]]
    [ -f "$RUNTIME/connection.log" ]
    [ ! -e "$RUNTIME/operation.lock" ]
    [ ! -e "$RUNTIME/active" ]
}

@test "launch errors return failure and keep logs" {
    import_demo
    export MOCK_MODE=launch-failure
    run main start demo
    [ "$status" -ne 0 ]
    [[ "$output" == *'launch failed'* ]]
    [ -f "$RUNTIME/connection.log" ]
}

@test "storage symlinks are rejected" {
    rm -f "$RUNTIME/active"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$RUNTIME/active"
    run init_storage
    [ "$status" -ne 0 ]
    [[ "$output" == *'Refusing symlink'* ]]
}

@test "doctor reports stale locks without altering them" {
    mkdir "$RUNTIME/operation.lock"
    printf '99999999\n' >"$RUNTIME/operation.lock/owner"
    run doctor
    [ "$status" -ne 0 ]
    [[ "$output" == *'Operation lock present'* ]]
    [ "$(cat "$RUNTIME/operation.lock/owner")" = 99999999 ]
}

@test "installer help works from another directory and rejects old options" {
    cd "$BATS_TEST_TMPDIR"
    run bash "$REPO/install.sh" --help
    [ "$status" -eq 0 ]
    run bash "$REPO/install.sh" -v missing.ovpn
    [ "$status" -ne 0 ]
    [[ "$output" == *'replaced by thm profile add'* ]]
}

@test "installer stages files from another directory without changing host" {
    source "$REPO/install.sh"
    require_root() { :; }
    dependencies() { :; }
    export THM_INSTALL_ROOT="$BATS_TEST_TMPDIR/staging"
    cd "$BATS_TEST_TMPDIR"
    install_main
    [ -x "$THM_INSTALL_ROOT/usr/local/bin/thm" ]
    [ -x "$THM_INSTALL_ROOT/usr/local/lib/thm/thm" ]
    cmp "$REPO/lib/vpn.sh" "$THM_INSTALL_ROOT/usr/local/lib/thm/lib/vpn.sh"
}

@test "installer dependency failure writes no program files" {
    run bash -c '
        source "$REPO/install.sh"
        require_root() { :; }
        dependencies() { die "missing mock dependency"; }
        export THM_INSTALL_ROOT="$THM_ROOT/staging"
        install_main
    '
    [ "$status" -ne 0 ]
    [ ! -e "$THM_ROOT/staging" ]
}

@test "interrupted startup requests shutdown and releases its lock" {
    import_demo
    export MOCK_MODE=timeout
    bash -c '
        source "$REPO/thm"
        require_root() { :; }
        dependencies() { OPENVPN="$REPO/tests/fake-openvpn.py"; SOCAT=$(command -v socat); }
        main start demo
    ' >"$BATS_TEST_TMPDIR/interrupted.log" 2>&1 &
    local child=$! attempts=0
    while [ ! -S "$RUNTIME/management.sock" ] && [ "$attempts" -lt 50 ]; do
        sleep 0.1
        attempts=$((attempts + 1))
    done
    [ -S "$RUNTIME/management.sock" ]
    kill -TERM "$child"
    wait "$child" || true
    [ ! -e "$RUNTIME/operation.lock" ]
    [ ! -e "$RUNTIME/active" ]
    [ ! -S "$RUNTIME/management.sock" ]
}

@test "logs follow releases the lock before tailing" {
    printf 'demo log\n' >"$RUNTIME/connection.log"
    tail() { [ "$LOCK_HELD" -eq 0 ] && [ ! -e "$RUNTIME/operation.lock" ]; }
    main logs --follow
}
