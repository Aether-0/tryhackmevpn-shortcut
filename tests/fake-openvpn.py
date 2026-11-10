#!/usr/bin/env python3
"""Test-only OpenVPN stand-in. Unix sockets only; never creates a VPN."""
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

args = sys.argv[1:]
if "--version" in args:
    print("OpenVPN 2.6.0 mock")
    sys.exit(0)
if "--serve" not in args:
    if os.environ.get("MOCK_MODE") == "launch-failure":
        sys.exit(1)
    subprocess.Popen(
        [sys.executable, __file__, "--serve"] + args,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True,
    )
    sys.exit(0)

def option(name):
    return args[args.index(name) + 1]

sock_path = Path(option("--management"))
pid_path = Path(option("--writepid"))
log_path = Path(option("--log"))
mode = os.environ.get("MOCK_MODE", "")
server = socket.socket(socket.AF_UNIX)
server.bind(str(sock_path))
server.listen()
server.settimeout(10)
pid_path.write_text(str(os.getpid()) + "\n")
log_path.write_text("Mock OpenVPN starting\n")
queries = 0
running = True
try:
    while running:
        conn, _ = server.accept()
        with conn:
            conn.sendall(b">INFO:mock management\n")
            for raw in conn.makefile("rb"):
                command = raw.decode().strip()
                with log_path.open("a") as log:
                    log.write(command + "\n")
                if command == "quit":
                    break
                if command == "pid":
                    conn.sendall(f"SUCCESS: pid={os.getpid()}\r\n".encode())
                elif command == "hold release":
                    conn.sendall(b"SUCCESS: hold release succeeded\r\n")
                elif command == "state":
                    queries += 1
                    ready = mode != "timeout" and (mode != "slow" or queries > 2)
                    state = "CONNECTED,SUCCESS,10.23.4.5" if ready else "AUTH,,"
                    conn.sendall(f"1700000000,{state},vpn.example.invalid\r\nEND\r\n".encode())
                elif command == "signal SIGTERM":
                    conn.sendall(b"SUCCESS: signal SIGTERM thrown\r\n")
                    running = False
                else:
                    conn.sendall(b"ERROR: unknown command\r\n")
except (TimeoutError, BrokenPipeError, ConnectionResetError):
    pass
finally:
    server.close()
    sock_path.unlink(missing_ok=True)
    pid_path.unlink(missing_ok=True)
