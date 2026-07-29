#!/usr/bin/env python3
"""Portable SEGGER J-Link manager with a Textual terminal UI."""

from __future__ import annotations

import argparse
import csv
import json
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
    from textual.binding import Binding
    from textual.containers import Vertical
    from textual.screen import ModalScreen
    from textual.theme import Theme
    from textual.widgets import (
        DataTable,
        Footer,
        Header,
        Input,
        RichLog,
        Static,
        TabbedContent,
        TabPane,
    )
except ImportError as error:
    raise SystemExit(
        "Missing dependency 'textual'. Install it with:\n"
        "  py -m pip install -r glazewm/requirements-tui.txt"
    ) from error


GRUVBOX_SOFT_DARK = Theme(
    name="gruvbox-soft-dark",
    primary="#fabd2f",
    secondary="#fe8019",
    accent="#fabd2f",
    foreground="#ebdbb2",
    background="#282828",
    surface="#32302f",
    panel="#3c3836",
    success="#b8bb26",
    warning="#fabd2f",
    error="#fb4934",
    dark=True,
    variables={
        "border": "#fabd2f",
        "border-blurred": "#665c54",
        "block-cursor-background": "#504945",
        "block-cursor-foreground": "#fabd2f",
        "footer-background": "#1d2021",
        "footer-foreground": "#a89984",
        "footer-key-background": "transparent",
        "footer-key-foreground": "#fabd2f",
        "footer-description-background": "transparent",
        "footer-description-foreground": "#d5c4a1",
        "input-cursor-background": "#fabd2f",
        "input-cursor-foreground": "#282828",
        "input-selection-background": "#504945",
        "scrollbar": "#665c54",
        "scrollbar-hover": "#928374",
        "scrollbar-active": "#fabd2f",
        "scrollbar-background": "#1d2021",
    },
)


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


def state_file() -> Path:
    app_data = os.environ.get("APPDATA")
    base = Path(app_data) if app_data else Path.home() / ".config"
    return base / "glazewm-config" / "jlink-manager.json"


def load_last_device() -> str:
    try:
        data = json.loads(state_file().read_text(encoding="utf-8"))
        return str(data.get("device", "")).strip()
    except (OSError, ValueError, TypeError):
        return ""


def save_last_device(device: str) -> None:
    path = state_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps({"device": device}, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


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


def exported_device_name(line: str) -> str:
    line = line.strip()
    if not line:
        return ""
    try:
        fields = next(csv.reader([line], skipinitialspace=True))
    except csv.Error:
        fields = [line]
    # ExpDevList uses CSV records: vendor, device name, core, ...
    return (fields[1] if len(fields) > 1 else fields[0]).strip()


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
                for line in export_file.read_text(
                    encoding="utf-8", errors="replace"
                ).splitlines():
                    name = exported_device_name(line)
                    if name:
                        names.add(name)
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


class TargetPicker(ModalScreen[str | None]):
    CSS = """
    TargetPicker {
        align: center middle;
        background: #000000 70%;
    }
    #picker {
        width: 80%;
        height: 80%;
        padding: 1 2;
        background: #32302f;
        color: #ebdbb2;
        border: round #fabd2f;
    }
    #picker-title {
        height: 2;
        color: #fabd2f;
        text-style: bold;
    }
    #picker-help {
        height: 2;
        color: #a89984;
    }
    #target-search {
        margin-bottom: 1;
        background: #1d2021;
        color: #ebdbb2;
        border: tall #665c54;
    }
    #target-search:focus {
        border: tall #fabd2f;
    }
    #target-search > .input--placeholder {
        color: #928374;
    }
    #target-search > .input--cursor {
        background: #fabd2f;
        color: #282828;
    }
    #target-search > .input--selection {
        background: #504945;
        color: #fbf1c7;
    }
    #target-table {
        height: 1fr;
        background: #1d2021;
        color: #d5c4a1;
        border: none;
        scrollbar-background: #1d2021;
        scrollbar-color: #665c54;
        scrollbar-color-hover: #928374;
        scrollbar-color-active: #fabd2f;
    }
    #target-table > .datatable--header {
        background: #3c3836;
        color: #fabd2f;
        text-style: bold;
    }
    #target-table > .datatable--even-row {
        background: #1d2021;
        color: #d5c4a1;
    }
    #target-table > .datatable--odd-row {
        background: #282828;
        color: #d5c4a1;
    }
    #target-table > .datatable--cursor {
        background: #504945;
        color: #fabd2f;
        text-style: bold;
    }
    #target-table > .datatable--hover {
        background: #3c3836;
        color: #ebdbb2;
    }
    """
    BINDINGS = [Binding("escape", "cancel", "Cancel", priority=True)]

    def __init__(self, devices: list[str], selected: str = "") -> None:
        super().__init__()
        self.devices = devices
        self.filtered_devices = devices
        self.selected = selected

    def compose(self) -> ComposeResult:
        with Vertical(id="picker"):
            yield Static("Select GDB target", id="picker-title")
            yield Static(
                "Type to filter, use Up/Down, press Enter to confirm, Esc to cancel.",
                id="picker-help",
            )
            yield Input(
                placeholder="Filter supported J-Link targets...",
                id="target-search",
            )
            yield DataTable(id="target-table", cursor_type="row", zebra_stripes=True)

    def on_mount(self) -> None:
        table = self.query_one("#target-table", DataTable)
        table.add_column("Supported J-Link target")
        self.apply_filter("")
        self.query_one("#target-search", Input).focus()

    def apply_filter(self, query: str) -> None:
        needle = query.casefold()
        self.filtered_devices = [
            device for device in self.devices if needle in device.casefold()
        ]
        table = self.query_one("#target-table", DataTable)
        table.clear(columns=False)
        for device in self.filtered_devices:
            table.add_row(device, key=device)
        if self.selected in self.filtered_devices:
            table.move_cursor(row=self.filtered_devices.index(self.selected))

    def choose_current(self) -> None:
        table = self.query_one("#target-table", DataTable)
        if not self.filtered_devices or table.cursor_row < 0:
            return
        index = min(table.cursor_row, len(self.filtered_devices) - 1)
        self.dismiss(self.filtered_devices[index])

    def on_input_changed(self, event: Input.Changed) -> None:
        self.apply_filter(event.value)

    def on_input_submitted(self, _event: Input.Submitted) -> None:
        self.choose_current()

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        self.dismiss(str(event.row_key.value))

    def action_cancel(self) -> None:
        self.dismiss(None)


class JLinkManager(App[None]):
    TITLE = "SEGGER J-Link Manager"
    SUB_TITLE = "Remote and GDB server control"
    CSS = """
    Screen {
        background: #282828;
        color: #ebdbb2;
        scrollbar-background: #1d2021;
        scrollbar-color: #665c54;
        scrollbar-color-hover: #928374;
        scrollbar-color-active: #fabd2f;
    }
    Header {
        background: #3c3836;
        color: #fabd2f;
    }
    Footer {
        background: #1d2021;
        color: #a89984;
    }
    #status {
        height: 3;
        padding: 0 1;
        background: #3c3836;
        color: #ebdbb2;
        border-bottom: solid #fabd2f;
    }
    TabbedContent {
        height: 1fr;
        background: #282828;
    }
    Tabs {
        background: #282828;
        color: #a89984;
        border-bottom: solid #504945;
    }
    Tab {
        background: #282828;
        color: #a89984;
    }
    Tab:hover {
        background: #3c3836;
        color: #ebdbb2;
    }
    Tab.-active {
        background: #3c3836;
        color: #fabd2f;
        text-style: bold;
    }
    TabPane {
        background: #282828;
    }
    RichLog {
        background: #1d2021;
        color: #d5c4a1;
        padding: 0 1;
        border: round #504945;
        scrollbar-background: #1d2021;
        scrollbar-color: #665c54;
        scrollbar-color-hover: #928374;
        scrollbar-color-active: #fabd2f;
    }
    """
    BINDINGS = [
        Binding("j", "start_remote", "Start Remote"),
        Binding("g", "start_gdb", "Start GDB"),
        Binding("x", "stop_all", "Stop all"),
        Binding("ctrl+q", "quit", "Quit", priority=True),
    ]

    def __init__(self, config: Config) -> None:
        super().__init__()
        self.config = config
        self.device_is_explicit = bool(config.device)
        self.selected_device = config.device or load_last_device()
        self.picker_loading = False
        self.remote_queue: queue.Queue[str] = queue.Queue()
        self.gdb_queue: queue.Queue[str] = queue.Queue()
        self.remote = ManagedProcess("Remote", self.remote_queue)
        self.gdb = ManagedProcess("GDB", self.gdb_queue)

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(id="status")
        with TabbedContent(initial="remote-tab"):
            with TabPane("Remote log", id="remote-tab"):
                yield RichLog(id="remote-log", wrap=True, highlight=True, auto_scroll=True)
            with TabPane("GDB log", id="gdb-tab"):
                yield RichLog(id="gdb-log", wrap=True, highlight=True, auto_scroll=True)
        yield Footer(show_command_palette=False)

    def on_mount(self) -> None:
        self.register_theme(GRUVBOX_SOFT_DARK)
        self.theme = GRUVBOX_SOFT_DARK.name
        self.set_interval(0.1, self.refresh_runtime)
        self.update_status()

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
        if self.gdb.running:
            self.gdb.write("Already running.")
            return
        if self.device_is_explicit:
            self.start_gdb_for_selected_target()
            return
        if self.picker_loading:
            self.gdb.write("Target list is already loading.")
            return
        self.picker_loading = True
        self.gdb.write("Loading supported J-Link targets...")
        self.run_worker(
            self.load_target_picker,
            thread=True,
            name="target-discovery",
            exclusive=True,
        )

    def load_target_picker(self) -> None:
        devices = discover_devices(self.config)
        self.call_from_thread(self.show_target_picker, devices)

    def show_target_picker(self, devices: list[str]) -> None:
        self.picker_loading = False
        if not devices:
            self.gdb.write(
                "ERROR: No target database found. Check the J-Link installation "
                "or set JLINK_BIN."
            )
            return
        self.push_screen(
            TargetPicker(devices, self.selected_device),
            self.target_selected,
        )

    def target_selected(self, device: str | None) -> None:
        if not device:
            self.gdb.write("Target selection cancelled.")
            return
        self.selected_device = device
        try:
            save_last_device(device)
        except OSError as error:
            self.gdb.write(f"WARNING: Could not save the target selection: {error}")
        self.gdb.write(f"Selected target: {device}")
        self.start_gdb_for_selected_target()

    def start_gdb_for_selected_target(self) -> None:
        if not self.selected_device:
            self.gdb.write("ERROR: No GDB target selected.")
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
