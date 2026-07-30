#!/usr/bin/env python3
"""Headless, portable SEGGER J-Link server controller for the YASB widget."""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable


DEFAULT_REMOTE_PORT = 19020
DEFAULT_GDB_PORT = 2331
DEFAULT_SPEED = 4000
DEFAULT_INTERFACE = "SWD"


def app_state_directory() -> Path:
    app_data = os.environ.get("APPDATA")
    base = Path(app_data) if app_data else Path.home() / ".config"
    return base / "glazewm-config"


def process_state_file() -> Path:
    return app_state_directory() / "jlink-yasb.json"


def manager_state_file() -> Path:
    return app_state_directory() / "jlink-manager.json"


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


def last_device() -> str:
    return str(load_json(manager_state_file()).get("device", "")).strip()


def save_device(device: str) -> None:
    save_json(manager_state_file(), {"device": device})


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


def xml_device_names(paths: Iterable[Path]) -> set[str]:
    names: set[str] = set()
    for directory in paths:
        if not directory.is_dir():
            continue
        for xml_file in directory.rglob("*.xml"):
            try:
                root = ET.parse(xml_file).getroot()
            except (ET.ParseError, OSError):
                continue
            for chip_info in root.iter("ChipInfo"):
                name = chip_info.get("Name", "").strip()
                if name:
                    names.add(name)
    return names


def exported_device_name(line: str) -> str:
    if not line.strip():
        return ""
    try:
        fields = next(csv.reader([line], skipinitialspace=True))
    except csv.Error:
        fields = [line]
    return (fields[1] if len(fields) > 1 else fields[0]).strip()


def discover_devices() -> list[str]:
    names: set[str] = set()
    try:
        commander = find_executable("JLink.exe")
        with tempfile.TemporaryDirectory(prefix="jlink-yasb-") as temp:
            temporary = Path(temp)
            export_file = temporary / "devices.txt"
            command_file = temporary / "commands.jlink"
            command_file.write_text(
                f'ExpDevList "{export_file}"\nExit\n',
                encoding="ascii",
            )
            subprocess.run(
                [commander, "-NoGui", "1", "-CommandFile", command_file],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=30,
            )
            if export_file.exists():
                for line in export_file.read_text(
                    encoding="utf-8", errors="replace"
                ).splitlines():
                    name = exported_device_name(line)
                    if name:
                        names.add(name)
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        pass

    xml_paths = jlink_directories()
    app_data = os.environ.get("APPDATA")
    if app_data:
        xml_paths.append(Path(app_data) / "SEGGER" / "JLinkDevices")
    names.update(xml_device_names(xml_paths))
    return sorted(names, key=str.casefold)


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

    # Portable fallback for non-Windows development and validation.
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
    for key in ("remote_pid", "gdb_pid"):
        try:
            pid = int(state.get(key, 0))
        except (TypeError, ValueError):
            pid = 0
        if not pid_is_running(pid):
            state.pop(key, None)
    return state


def status_payload() -> dict:
    state = managed_state()
    remote, remote_clients = tcp_port_state(DEFAULT_REMOTE_PORT)
    gdb, gdb_clients = tcp_port_state(DEFAULT_GDB_PORT)
    device = str(state.get("device") or last_device() or "no target")
    active_clients = max(remote_clients, gdb_clients)
    if active_clients and gdb:
        icon, label, status = "󰘳", "GDB Active", "GDB client connected and active"
    elif active_clients:
        icon, label, status = "󰐊", "Active", "Remote client connected and active"
    elif remote and gdb:
        icon, label, status = "󰘳", "R+G", "Remote and GDB running"
    elif gdb:
        icon, label, status = "󰘳", "GDB", "GDB running"
    elif remote:
        icon, label, status = "󰒋", "Remote", "Remote running"
    else:
        icon, label, status = "󰌘", "Off", "J-Link servers stopped"
    return {
        "icon": icon,
        "label": label,
        "status": status,
        "remote": remote,
        "gdb": gdb,
        "clients": active_clients,
        "device": device,
        "remote_port": DEFAULT_REMOTE_PORT,
        "gdb_port": DEFAULT_GDB_PORT,
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


def start_gdb(device: str) -> int:
    device = device.strip()
    if not device:
        raise ValueError("No J-Link target selected.")
    if port_is_open(DEFAULT_GDB_PORT):
        return 0
    remote_result = start_remote()
    if remote_result:
        return remote_result

    executable = find_executable("JLinkGDBServerCL.exe")
    logs = log_directory()
    logs.mkdir(parents=True, exist_ok=True)
    native_log = logs / "gdb-yasb.jlink.log"
    native_log.unlink(missing_ok=True)
    command = [
        str(executable),
        "-select",
        f"ip=127.0.0.1:{DEFAULT_REMOTE_PORT}",
        "-device",
        device,
        "-if",
        os.environ.get("JLINK_INTERFACE", DEFAULT_INTERFACE),
        "-speed",
        os.environ.get("JLINK_SPEED", str(DEFAULT_SPEED)),
        "-port",
        str(DEFAULT_GDB_PORT),
        "-nogui",
        "-nosilent",
        "-logtofile",
        "-log",
        str(native_log),
    ]
    process = detached_process(command, "gdb-yasb.log")
    state = managed_state()
    state.update({"gdb_pid": process.pid, "device": device})
    save_json(process_state_file(), state)
    save_device(device)
    return 0


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


def stop_server_images(*image_names: str) -> None:
    for image_name in image_names:
        subprocess.run(
            ["taskkill", "/IM", image_name, "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )


def stop_managed(name: str) -> None:
    state = managed_state()
    key = f"{name}_pid"
    try:
        stop_pid(int(state.get(key, 0)))
    except (TypeError, ValueError):
        pass
    state.pop(key, None)
    save_json(process_state_file(), state)


def stop_gdb() -> int:
    stop_managed("gdb")
    stop_server_images("JLinkGDBServerCL.exe", "JLinkGDBServer.exe")
    return 0


def stop_remote() -> int:
    # A GDB server connected through the Remote Server cannot remain usable.
    stop_gdb()
    stop_managed("remote")
    stop_server_images("JLinkRemoteServerCL.exe", "JLinkRemoteServer.exe")
    return 0


def restart_remote() -> int:
    state = managed_state()
    restart_gdb_afterwards = port_is_open(DEFAULT_GDB_PORT)
    device = str(state.get("device") or last_device()).strip()
    stop_remote()
    result = start_remote()
    if result or not restart_gdb_afterwards:
        return result
    return start_gdb(device)


def restart_gdb() -> int:
    device = str(managed_state().get("device") or last_device()).strip()
    if not device:
        raise ValueError("No previous J-Link target is available.")
    stop_gdb()
    return start_gdb(device)


def stop_all() -> int:
    state = managed_state()
    for key in ("gdb_pid", "remote_pid"):
        try:
            stop_pid(int(state.get(key, 0)))
        except (TypeError, ValueError):
            pass
    stop_server_images(
        "JLinkGDBServerCL.exe",
        "JLinkGDBServer.exe",
        "JLinkRemoteServerCL.exe",
        "JLinkRemoteServer.exe",
    )
    preserved = {"device": state["device"]} if state.get("device") else {}
    save_json(process_state_file(), preserved)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    commands.add_parser("targets")
    commands.add_parser("start-remote")
    commands.add_parser("stop-remote")
    commands.add_parser("restart-remote")
    commands.add_parser("stop-gdb")
    commands.add_parser("restart-gdb")
    commands.add_parser("stop")
    gdb = commands.add_parser("start-gdb")
    gdb.add_argument("--device", default="")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "status":
            # ASCII-safe JSON also works when YASB inherits a legacy Windows
            # console code page instead of UTF-8.
            print(json.dumps(status_payload()))
            return 0
        if args.command == "targets":
            print(json.dumps(discover_devices()))
            return 0
        if args.command == "start-remote":
            return start_remote()
        if args.command == "stop-remote":
            return stop_remote()
        if args.command == "restart-remote":
            return restart_remote()
        if args.command == "start-gdb":
            return start_gdb(args.device or last_device())
        if args.command == "stop-gdb":
            return stop_gdb()
        if args.command == "restart-gdb":
            return restart_gdb()
        if args.command == "stop":
            return stop_all()
    except (FileNotFoundError, OSError, ValueError) as error:
        print(str(error), file=os.sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
