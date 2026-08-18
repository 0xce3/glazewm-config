#!/usr/bin/env python3
"""Headless SEGGER J-Link Remote Server controller for the YASB widget."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import time
from pathlib import Path


DEFAULT_REMOTE_PORT = 19020


def app_state_directory() -> Path:
    app_data = os.environ.get("APPDATA")
    base = Path(app_data) if app_data else Path.home() / ".config"
    return base / "glazewm-config"


def process_state_file() -> Path:
    return app_state_directory() / "jlink-yasb.json"


def log_directory() -> Path:
    configured = os.environ.get("JLINK_LOG_DIR")
    return Path(configured).expanduser() if configured else Path.home() / ".jlink-logs"


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def save_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def jlink_directories() -> list[Path]:
    directories: list[Path] = []
    configured = os.environ.get("JLINK_BIN")
    if configured:
        directories.append(Path(configured).expanduser())
    for variable in ("ProgramFiles", "ProgramFiles(x86)"):
        root = os.environ.get(variable)
        if not root:
            continue
        segger = Path(root) / "SEGGER"
        if segger.is_dir():
            directories.extend(
                sorted(
                    (path for path in segger.glob("JLink*") if path.is_dir()),
                    reverse=True,
                )
            )
    return list(dict.fromkeys(directories))


def find_executable(*names: str) -> Path:
    for name in names:
        on_path = shutil.which(name)
        if on_path:
            return Path(on_path)
        for directory in jlink_directories():
            candidate = directory / name
            if candidate.is_file():
                return candidate
    raise FileNotFoundError(
        f"{' or '.join(names)} not found. Install SEGGER J-Link or set JLINK_BIN."
    )


def tcp_port_state(port: int) -> tuple[bool, int]:
    """Return listening state and client count without connecting to the port."""
    if os.name == "nt":
        try:
            result = subprocess.run(
                ["netstat", "-ano", "-p", "TCP"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            listening = False
            clients: set[str] = set()
            for line in result.stdout.splitlines():
                fields = line.split()
                if len(fields) < 4 or fields[0].upper() != "TCP":
                    continue
                local, remote, state = fields[1], fields[2], fields[3].upper()
                try:
                    local_port = int(local.rsplit(":", 1)[1])
                except (IndexError, ValueError):
                    continue
                if local_port != port:
                    continue
                if state == "LISTENING":
                    listening = True
                elif state == "ESTABLISHED":
                    clients.add(remote)
            return listening, len(clients)
        except OSError:
            pass
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.15):
            return True, 0
    except OSError:
        return False, 0


def port_is_open(port: int) -> bool:
    return tcp_port_state(port)[0]


def pid_is_running(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def managed_state() -> dict:
    state = load_json(process_state_file())
    try:
        pid = int(state.get("remote_pid", 0))
    except (TypeError, ValueError):
        pid = 0
    if not pid_is_running(pid):
        state.pop("remote_pid", None)
    return state


def status_payload(expected_state: str | None = None) -> dict | None:
    try:
        find_executable("JLinkRemoteServerCL.exe", "JLinkRemoteServer.exe")
    except FileNotFoundError:
        return None
    remote, clients = tcp_port_state(DEFAULT_REMOTE_PORT)
    if clients:
        state = "connected"
        status = "J-Link client connected"
    elif remote:
        state = "running"
        status = "J-Link Remote Server running; no client connected"
    else:
        state = "stopped"
        status = "J-Link Remote Server stopped"
    if expected_state is not None and state != expected_state:
        return None
    return {
        "state": state,
        "status": status,
        "remote": remote,
        "clients": clients,
        "remote_port": DEFAULT_REMOTE_PORT,
    }


def detached_process(command: list[str], log_name: str) -> subprocess.Popen[bytes]:
    logs = log_directory()
    logs.mkdir(parents=True, exist_ok=True)
    output = (logs / log_name).open("ab")
    creation_flags = (
        getattr(subprocess, "CREATE_NO_WINDOW", 0)
        | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    )
    try:
        return subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=output,
            stderr=subprocess.STDOUT,
            creationflags=creation_flags,
        )
    finally:
        output.close()


def start_remote() -> int:
    state = managed_state()
    if port_is_open(DEFAULT_REMOTE_PORT):
        return 0
    executable = find_executable("JLinkRemoteServerCL.exe", "JLinkRemoteServer.exe")
    process = detached_process(
        [str(executable), "-port", str(DEFAULT_REMOTE_PORT)],
        "remote-yasb.log",
    )
    state["remote_pid"] = process.pid
    save_json(process_state_file(), state)
    for _ in range(30):
        if port_is_open(DEFAULT_REMOTE_PORT):
            return 0
        if process.poll() is not None:
            return process.returncode or 1
        time.sleep(0.1)
    return 1


def stop_pid(pid: int) -> None:
    if not pid_is_running(pid):
        return
    subprocess.run(
        ["taskkill", "/PID", str(pid), "/T", "/F"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )


def stop_remote() -> int:
    state = managed_state()
    try:
        stop_pid(int(state.get("remote_pid", 0)))
    except (TypeError, ValueError):
        pass
    subprocess.run(
        ["taskkill", "/IM", "JLinkRemoteServerCL.exe", "/T", "/F"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    subprocess.run(
        ["taskkill", "/IM", "JLinkRemoteServer.exe", "/T", "/F"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    save_json(process_state_file(), {})
    return 0


def restart_remote() -> int:
    stop_remote()
    return start_remote()


def toggle_remote() -> int:
    return stop_remote() if port_is_open(DEFAULT_REMOTE_PORT) else start_remote()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    commands.add_parser("status-connected")
    commands.add_parser("status-running")
    commands.add_parser("status-stopped")
    commands.add_parser("start-remote")
    commands.add_parser("stop-remote")
    commands.add_parser("restart-remote")
    commands.add_parser("toggle-remote")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "status":
            payload = status_payload()
            if payload is not None:
                print(json.dumps(payload))
            return 0
        if args.command == "status-connected":
            payload = status_payload("connected")
            if payload is not None:
                print(json.dumps(payload))
            return 0
        if args.command == "status-running":
            payload = status_payload("running")
            if payload is not None:
                print(json.dumps(payload))
            return 0
        if args.command == "status-stopped":
            payload = status_payload("stopped")
            if payload is not None:
                print(json.dumps(payload))
            return 0
        if args.command == "start-remote":
            return start_remote()
        if args.command == "stop-remote":
            return stop_remote()
        if args.command == "restart-remote":
            return restart_remote()
        if args.command == "toggle-remote":
            return toggle_remote()
    except (FileNotFoundError, OSError, ValueError) as error:
        print(str(error), file=os.sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
