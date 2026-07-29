#!/usr/bin/env python3
"""Portable SEGGER J-Link manager with a Textual terminal UI."""

from __future__ import annotations

import argparse
import os
import queue
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

try:
    from textual.app import App, ComposeResult
    from textual.containers import Horizontal, Vertical
    from textual.widgets import (
        Button,
        DataTable,
        Footer,
        Header,
        Input,
        Label,
        RichLog,
        Static,
        TabbedContent,
        TabPane,
    )
except ImportError as error:
    raise SystemExit(
        "Missing dependency 'textual'. Install it with:\n"
        "  py -m pip install -r glazewm/requirements-jlink.txt"
    ) from error


@dataclass(frozen=True)
class Config:
    jlink_bin: Path | None
    device: str
    interface: str
    speed: int
    gdb_port: int
    remote_port: int
    log_directory: Path


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if not value:
        return default
    try:
        return int(value)
    except ValueError as error:
        raise SystemExit(f"{name} must be an integer, got {value!r}.") from error


def parse_args() -> Config:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jlink-bin", default=os.environ.get("JLINK_BIN", ""))
    parser.add_argument("--device", default=os.environ.get("JLINK_DEVICE", ""))
    parser.add_argument("--interface", default=os.environ.get("JLINK_INTERFACE", "SWD"))
    parser.add_argument("--speed", type=int, default=env_int("JLINK_SPEED", 4000))
    parser.add_argument("--gdb-port", type=int, default=env_int("JLINK_GDB_PORT", 2331))
    parser.add_argument("--remote-port", type=int, default=env_int("JLINK_REMOTE_PORT", 19020))
    parser.add_argument(
        "--log-directory",
        default=os.environ.get("JLINK_LOG_DIR", str(Path.home() / ".jlink-logs")),
    )
    args = parser.parse_args()
    return Config(
        jlink_bin=Path(args.jlink_bin).expanduser() if args.jlink_bin else None,
        device=args.device.strip(),
        interface=args.interface,
        speed=args.speed,
        gdb_port=args.gdb_port,
        remote_port=args.remote_port,
        log_directory=Path(args.log_directory).expanduser(),
    )


def jlink_directories(config: Config) -> list[Path]:
    directories: list[Path] = []
    if config.jlink_bin:
        directories.append(config.jlink_bin)
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


def find_executable(config: Config, *names: str) -> Path:
    for name in names:
        on_path = shutil.which(name)
        if on_path:
            return Path(on_path)
        for directory in jlink_directories(config):
            candidate = directory / name
            if candidate.is_file():
                return candidate
    joined = " or ".join(names)
    raise FileNotFoundError(
        f"{joined} not found. Install SEGGER J-Link, add it to PATH, "
        "or set JLINK_BIN."
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


def discover_devices(config: Config) -> list[str]:
    names: set[str] = set()
    try:
        commander = find_executable(config, "JLink.exe")
        with tempfile.TemporaryDirectory(prefix="jlink-manager-") as temp:
            temp_path = Path(temp)
            export_file = temp_path / "devices.txt"
            command_file = temp_path / "commands.jlink"
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
                names.update(
                    line.strip()
                    for line in export_file.read_text(
                        encoding="utf-8", errors="replace"
                    ).splitlines()
                    if line.strip()
                )
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        pass

    xml_paths = jlink_directories(config)
    app_data = os.environ.get("APPDATA")
    if app_data:
        xml_paths.append(Path(app_data) / "SEGGER" / "JLinkDevices")
    names.update(xml_device_names(xml_paths))
    return sorted(names, key=str.casefold)


def port_is_open(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return True
    except OSError:
        return False


class ManagedProcess:
    def __init__(self, name: str, log_queue: queue.Queue[str]) -> None:
        self.name = name
        self.log_queue = log_queue
        self.process: subprocess.Popen[str] | None = None
        self.external = False

    @property
    def running(self) -> bool:
        return self.external or (
            self.process is not None and self.process.poll() is None
        )

    @property
    def status(self) -> str:
        if self.external:
            return "running (external)"
        if self.process is None:
            return "stopped"
        code = self.process.poll()
        return f"running (PID {self.process.pid})" if code is None else f"exited ({code})"

    def write(self, message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        self.log_queue.put(f"[{stamp}] {message}")

    def start(
        self,
        command: list[str],
        external_port: int,
        native_log: Path | None = None,
    ) -> None:
        if self.running:
            self.write("Already running.")
            return
        if port_is_open(external_port):
            self.external = True
            self.write(f"Using an existing server on port {external_port}.")
            return

        creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self.process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=creation_flags,
        )
        self.write(f"Started PID {self.process.pid}: {' '.join(map(str, command))}")
        threading.Thread(target=self._read_output, daemon=True).start()
        if native_log:
            threading.Thread(
                target=self._tail_file,
                args=(native_log,),
                daemon=True,
            ).start()

    def _read_output(self) -> None:
        assert self.process is not None
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.log_queue.put(line.rstrip())
        code = self.process.wait()
        self.write(f"Process exited with code {code}.")

    def _tail_file(self, path: Path) -> None:
        position = 0
        while self.process is not None and self.process.poll() is None:
            position = self._read_file_from(path, position)
            time.sleep(0.1)
        self._read_file_from(path, position)

    def _read_file_from(self, path: Path, position: int) -> int:
        try:
            with path.open("r", encoding="utf-8", errors="replace") as log_file:
                log_file.seek(position)
                for line in log_file:
                    self.log_queue.put(line.rstrip())
                return log_file.tell()
        except OSError:
            return position

    def stop(self) -> None:
        if self.external:
            self.write("External process left running.")
            self.external = False
            return
        if not self.running or self.process is None:
            return
        self.write(f"Stopping PID {self.process.pid}.")
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=3)


class JLinkManager(App[None]):
    TITLE = "SEGGER J-Link Manager"
    SUB_TITLE = "Remote and GDB server control"
    CSS = """
    Screen {
        background: #282828;
        color: #ebdbb2;
    }
    #status {
        height: 3;
        padding: 0 1;
        background: #3c3836;
        border-bottom: solid #fabd2f;
    }
    #controls {
        height: 3;
        padding: 0 1;
    }
    Button {
        margin-right: 1;
    }
    #target-panel {
        height: 14;
        padding: 0 1;
        border: round #665c54;
    }
    #target-search {
        margin-bottom: 1;
    }
    #target-table {
        height: 1fr;
    }
    TabbedContent {
        height: 1fr;
    }
    RichLog {
        background: #1d2021;
        color: #d5c4a1;
        padding: 0 1;
        scrollbar-color: #fabd2f;
    }
    .selected-target {
        color: #fabd2f;
    }
    """
    BINDINGS = [
        ("j", "start_remote", "Start Remote"),
        ("g", "start_gdb", "Start GDB"),
        ("x", "stop_all", "Stop all"),
        ("ctrl+q", "quit", "Quit"),
    ]

    def __init__(self, config: Config) -> None:
        super().__init__()
        self.config = config
        self.devices: list[str] = []
        self.filtered_devices: list[str] = []
        self.selected_device = config.device
        self.remote_queue: queue.Queue[str] = queue.Queue()
        self.gdb_queue: queue.Queue[str] = queue.Queue()
        self.remote = ManagedProcess("Remote", self.remote_queue)
        self.gdb = ManagedProcess("GDB", self.gdb_queue)

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(id="status")
        with Horizontal(id="controls"):
            yield Button("Start Remote", id="start-remote", variant="primary")
            yield Button("Start GDB", id="start-gdb", variant="success")
            yield Button("Stop All", id="stop-all", variant="error")
            yield Label("", id="selected-target", classes="selected-target")
        with Vertical(id="target-panel"):
            yield Input(placeholder="Filter targets by any part of the name...", id="target-search")
            yield DataTable(id="target-table", cursor_type="row", zebra_stripes=True)
        with TabbedContent(initial="remote-tab"):
            with TabPane("Remote log", id="remote-tab"):
                yield RichLog(id="remote-log", wrap=True, highlight=True, auto_scroll=True)
            with TabPane("GDB log", id="gdb-tab"):
                yield RichLog(id="gdb-log", wrap=True, highlight=True, auto_scroll=True)
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#target-table", DataTable)
        table.add_column("Supported J-Link target")
        self.set_interval(0.1, self.refresh_runtime)
        self.run_worker(self.load_devices, thread=True, name="device-discovery")
        self.update_status()
        if self.selected_device:
            self.query_one("#selected-target", Label).update(
                f"Target: {self.selected_device}"
            )

    def load_devices(self) -> None:
        devices = discover_devices(self.config)
        self.call_from_thread(self.set_devices, devices)

    def set_devices(self, devices: list[str]) -> None:
        self.devices = devices
        self.apply_filter(self.query_one("#target-search", Input).value)
        target_log = self.query_one("#gdb-log", RichLog)
        if devices:
            target_log.write(f"Loaded {len(devices)} supported targets.")
        else:
            target_log.write(
                "[yellow]No target database found. Check the J-Link installation "
                "or set JLINK_BIN.[/yellow]"
            )

    def apply_filter(self, query: str) -> None:
        needle = query.casefold()
        self.filtered_devices = [
            device for device in self.devices if needle in device.casefold()
        ]
        table = self.query_one("#target-table", DataTable)
        table.clear(columns=False)
        for device in self.filtered_devices:
            table.add_row(device, key=device)

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "target-search":
            self.apply_filter(event.value)

    def select_current_target(self) -> None:
        table = self.query_one("#target-table", DataTable)
        if not self.filtered_devices or table.cursor_row < 0:
            return
        index = min(table.cursor_row, len(self.filtered_devices) - 1)
        self.selected_device = self.filtered_devices[index]
        self.query_one("#selected-target", Label).update(
            f"Target: {self.selected_device}"
        )
        self.query_one("#gdb-log", RichLog).write(
            f"Selected target: [bold yellow]{self.selected_device}[/bold yellow]"
        )

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        self.selected_device = str(event.row_key.value)
        self.query_one("#selected-target", Label).update(
            f"Target: {self.selected_device}"
        )

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "target-search":
            self.select_current_target()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        actions = {
            "start-remote": self.action_start_remote,
            "start-gdb": self.action_start_gdb,
            "stop-all": self.action_stop_all,
        }
        action = actions.get(event.button.id or "")
        if action:
            action()

    def action_start_remote(self) -> None:
        try:
            executable = find_executable(
                self.config, "JLinkRemoteServerCL.exe", "JLinkRemoteServer.exe"
            )
            self.remote.start(
                [str(executable), "-port", str(self.config.remote_port)],
                self.config.remote_port,
            )
        except (FileNotFoundError, OSError) as error:
            self.remote.write(f"ERROR: {error}")

    def action_start_gdb(self) -> None:
        if not self.selected_device:
            self.gdb.write("ERROR: Select a target from the filtered list first.")
            self.query_one("#target-search", Input).focus()
            return
        self.action_start_remote()
        try:
            executable = find_executable(self.config, "JLinkGDBServerCL.exe")
            self.config.log_directory.mkdir(parents=True, exist_ok=True)
            native_log = self.config.log_directory / "gdb.jlink.log"
            native_log.unlink(missing_ok=True)
            command = [
                str(executable),
                "-select",
                f"ip=127.0.0.1:{self.config.remote_port}",
                "-device",
                self.selected_device,
                "-if",
                self.config.interface,
                "-speed",
                str(self.config.speed),
                "-port",
                str(self.config.gdb_port),
                "-nogui",
                "-nosilent",
                "-logtofile",
                "-log",
                str(native_log),
            ]
            self.gdb.start(command, self.config.gdb_port, native_log=native_log)
        except (FileNotFoundError, OSError) as error:
            self.gdb.write(f"ERROR: {error}")

    def action_stop_all(self) -> None:
        self.gdb.stop()
        self.remote.stop()

    def refresh_runtime(self) -> None:
        self.drain_queue(self.remote_queue, "#remote-log")
        self.drain_queue(self.gdb_queue, "#gdb-log")
        self.update_status()

    def drain_queue(self, source: queue.Queue[str], log_id: str) -> None:
        log = self.query_one(log_id, RichLog)
        while True:
            try:
                line = source.get_nowait()
            except queue.Empty:
                break
            log.write(line)

    def update_status(self) -> None:
        target = self.selected_device or "not selected"
        self.query_one("#status", Static).update(
            f"Remote: {self.remote.status}  |  Port {self.config.remote_port}\n"
            f"GDB:    {self.gdb.status}  |  Port {self.config.gdb_port}  |  "
            f"{target} / {self.config.interface} / {self.config.speed} kHz"
        )

    def on_unmount(self) -> None:
        self.action_stop_all()


def main() -> None:
    JLinkManager(parse_args()).run()


if __name__ == "__main__":
    main()
