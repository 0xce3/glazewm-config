#!/usr/bin/env python3
"""Gruvbox serial-port launcher for pySerial miniterm."""

from __future__ import annotations

import argparse
import codecs
import json
import os
import queue
import subprocess
import sys
import threading
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

try:
    import serial
    from serial.tools import list_ports
    from textual.app import App, ComposeResult
    from textual.binding import Binding
    from textual.containers import Vertical
    from textual.screen import ModalScreen
    from textual.theme import Theme
    from textual.widgets import DataTable, Footer, Header, Input, RichLog, Static
except ImportError as error:
    raise SystemExit(
        "Missing Python dependencies. Install them with:\n"
        "  py -m pip install -r glazewm/requirements-tui.txt"
    ) from error


COMMON_BAUD_RATES = (9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600)

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
    port: str
    baud: int
    encoding: str


@dataclass(frozen=True)
class PortInfo:
    device: str
    description: str
    hwid: str

    @property
    def label(self) -> str:
        details = self.description if self.description and self.description != "n/a" else ""
        return f"{self.device}  {details}".rstrip()


def parse_args() -> Config:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default=os.environ.get("SERIAL_PORT", ""))
    parser.add_argument(
        "--baud",
        type=int,
        default=int(os.environ.get("SERIAL_BAUD", "115200")),
    )
    parser.add_argument(
        "--encoding",
        default=os.environ.get("SERIAL_ENCODING", "iso-8859-1"),
    )
    args = parser.parse_args()
    try:
        codecs.lookup(args.encoding)
    except LookupError as error:
        raise SystemExit(f"Unknown serial encoding: {args.encoding}") from error
    return Config(args.port.strip(), args.baud, args.encoding)


def state_file() -> Path:
    app_data = os.environ.get("APPDATA")
    base = Path(app_data) if app_data else Path.home() / ".config"
    return base / "glazewm-config" / "serial-monitor.json"


def load_last_connection() -> tuple[str, int]:
    try:
        data = json.loads(state_file().read_text(encoding="utf-8"))
        return str(data.get("port", "")).strip(), int(data.get("baud", 115200))
    except (OSError, ValueError, TypeError):
        return "", 115200


def save_last_connection(port: str, baud: int) -> None:
    path = state_file()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps({"port": port, "baud": baud}, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def discover_ports() -> list[PortInfo]:
    ports = [
        PortInfo(item.device, item.description or "", item.hwid or "")
        for item in list_ports.comports()
    ]

    def sort_key(port: PortInfo) -> tuple[str, int | str]:
        prefix = port.device.rstrip("0123456789")
        suffix = port.device[len(prefix) :]
        return prefix.casefold(), int(suffix) if suffix.isdigit() else suffix.casefold()

    return sorted(ports, key=sort_key)


class PortPicker(ModalScreen[str | None]):
    CSS = """
    PortPicker {
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
    Input {
        background: #1d2021;
        color: #ebdbb2;
        border: tall #665c54;
    }
    Input:focus {
        border: tall #fabd2f;
    }
    Input > .input--placeholder {
        color: #928374;
    }
    Input > .input--cursor {
        background: #fabd2f;
        color: #282828;
    }
    #port-search {
        margin-bottom: 1;
    }
    #port-table {
        height: 1fr;
        background: #1d2021;
        color: #d5c4a1;
        border: none;
        scrollbar-background: #1d2021;
        scrollbar-color: #665c54;
        scrollbar-color-hover: #928374;
        scrollbar-color-active: #fabd2f;
    }
    #port-table > .datatable--header {
        background: #3c3836;
        color: #fabd2f;
        text-style: bold;
    }
    #port-table > .datatable--even-row {
        background: #1d2021;
        color: #d5c4a1;
    }
    #port-table > .datatable--odd-row {
        background: #282828;
        color: #d5c4a1;
    }
    #port-table > .datatable--cursor {
        background: #504945;
        color: #fabd2f;
        text-style: bold;
    }
    """
    BINDINGS = [Binding("escape", "cancel", "Cancel", priority=True)]

    def __init__(self, ports: list[PortInfo], selected_port: str) -> None:
        super().__init__()
        self.ports = ports
        self.filtered_ports = ports
        self.selected_port = selected_port

    def compose(self) -> ComposeResult:
        with Vertical(id="picker"):
            yield Static("Select COM port", id="picker-title")
            yield Static(
                "Type to filter, use Up/Down, press Enter to continue, Esc to cancel.",
                id="picker-help",
            )
            yield Input(placeholder="Filter COM ports...", id="port-search")
            yield DataTable(id="port-table", cursor_type="row", zebra_stripes=True)

    def on_mount(self) -> None:
        table = self.query_one("#port-table", DataTable)
        table.add_column("Port")
        table.add_column("Hardware ID")
        self.apply_filter("")
        self.query_one("#port-search", Input).focus()

    def apply_filter(self, query: str) -> None:
        needle = query.casefold()
        self.filtered_ports = [
            port
            for port in self.ports
            if needle in f"{port.label} {port.hwid}".casefold()
        ]
        table = self.query_one("#port-table", DataTable)
        table.clear(columns=False)
        for port in self.filtered_ports:
            table.add_row(port.label, port.hwid, key=port.device)
        devices = [port.device for port in self.filtered_ports]
        if self.selected_port in devices:
            table.move_cursor(row=devices.index(self.selected_port))

    def choose_current(self) -> None:
        table = self.query_one("#port-table", DataTable)
        if not self.filtered_ports or table.cursor_row < 0:
            return
        index = min(table.cursor_row, len(self.filtered_ports) - 1)
        self.dismiss(self.filtered_ports[index].device)

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "port-search":
            self.apply_filter(event.value)

    def on_input_submitted(self, _event: Input.Submitted) -> None:
        self.choose_current()

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        self.dismiss(str(event.row_key.value))

    def action_cancel(self) -> None:
        self.dismiss(None)


class BaudPicker(ModalScreen[int | None]):
    CSS = """
    BaudPicker {
        align: center middle;
        background: #000000 70%;
    }
    #baud-picker {
        width: 50%;
        height: 70%;
        padding: 1 2;
        background: #32302f;
        color: #ebdbb2;
        border: round #fabd2f;
    }
    #baud-title {
        height: 2;
        color: #fabd2f;
        text-style: bold;
    }
    #baud-help, #custom-label {
        height: 2;
        color: #a89984;
    }
    #baud-table {
        height: 1fr;
        background: #1d2021;
        color: #d5c4a1;
        border: none;
    }
    #baud-table > .datatable--header {
        background: #3c3836;
        color: #fabd2f;
        text-style: bold;
    }
    #baud-table > .datatable--even-row {
        background: #1d2021;
        color: #d5c4a1;
    }
    #baud-table > .datatable--odd-row {
        background: #282828;
        color: #d5c4a1;
    }
    #baud-table > .datatable--cursor {
        background: #504945;
        color: #fabd2f;
        text-style: bold;
    }
    #custom-baud {
        height: 3;
        background: #1d2021;
        color: #ebdbb2;
        border: tall #665c54;
    }
    #custom-baud:focus {
        border: tall #fabd2f;
    }
    #custom-baud > .input--cursor {
        background: #fabd2f;
        color: #282828;
    }
    """
    BINDINGS = [Binding("escape", "cancel", "Cancel", priority=True)]

    def __init__(self, selected_baud: int) -> None:
        super().__init__()
        self.selected_baud = selected_baud

    def compose(self) -> ComposeResult:
        with Vertical(id="baud-picker"):
            yield Static("Select baud rate", id="baud-title")
            yield Static(
                "Use Up/Down and Enter, or Tab to enter a custom baud rate.",
                id="baud-help",
            )
            yield DataTable(id="baud-table", cursor_type="row", zebra_stripes=True)
            yield Static("Custom baud rate", id="custom-label")
            yield Input(
                value=str(self.selected_baud),
                type="integer",
                id="custom-baud",
            )

    def on_mount(self) -> None:
        table = self.query_one("#baud-table", DataTable)
        table.add_column("Baud rate")
        for baud in COMMON_BAUD_RATES:
            table.add_row(str(baud), key=str(baud))
        if self.selected_baud in COMMON_BAUD_RATES:
            table.move_cursor(row=COMMON_BAUD_RATES.index(self.selected_baud))
        table.focus()

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        self.dismiss(int(str(event.row_key.value)))

    def on_input_submitted(self, event: Input.Submitted) -> None:
        try:
            baud = int(event.value)
            if baud <= 0:
                raise ValueError
        except ValueError:
            self.notify("Baud rate must be a positive integer.", severity="error")
            return
        self.dismiss(baud)

    def action_cancel(self) -> None:
        self.dismiss(None)


class SerialConnection:
    def __init__(self, output: queue.Queue[str], encoding: str) -> None:
        self.output = output
        self.encoding = encoding
        self.serial: serial.SerialBase | None = None
        self.reader: threading.Thread | None = None
        self.stop_event = threading.Event()

    @property
    def connected(self) -> bool:
        return self.serial is not None and self.serial.is_open

    def log(self, message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        self.output.put(f"[{stamp}] {message}")

    def connect(self, port: str, baud: int) -> None:
        self.disconnect()
        self.serial = serial.serial_for_url(
            port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.1,
            write_timeout=1,
            rtscts=False,
            dsrdtr=False,
        )
        self.serial.dtr = True
        self.serial.rts = True
        self.stop_event.clear()
        self.reader = threading.Thread(target=self._read_loop, daemon=True)
        self.reader.start()
        self.log(f"Connected to {port} @ {baud} 8N1 ({self.encoding}).")

    def _read_loop(self) -> None:
        assert self.serial is not None
        decoder = codecs.getincrementaldecoder(self.encoding)(errors="replace")
        partial = ""
        try:
            while not self.stop_event.is_set() and self.serial.is_open:
                data = self.serial.read(self.serial.in_waiting or 1)
                if not data:
                    continue
                partial += decoder.decode(data)
                while "\n" in partial:
                    line, partial = partial.split("\n", 1)
                    self.output.put(line.rstrip("\r"))
        except serial.SerialException as error:
            self.log(f"ERROR: {error}")
        finally:
            partial += decoder.decode(b"", final=True)
            if partial:
                self.output.put(partial.rstrip("\r"))

    def send_line(self, text: str) -> None:
        if not self.connected or self.serial is None:
            raise serial.SerialException("No serial port is connected.")
        self.serial.write((text + "\r\n").encode(self.encoding, errors="replace"))
        self.serial.flush()

    def disconnect(self) -> None:
        if self.serial is None:
            return
        port = self.serial.port
        self.stop_event.set()
        if self.serial.is_open:
            self.serial.close()
        if self.reader and self.reader.is_alive():
            self.reader.join(timeout=1)
        self.serial = None
        self.reader = None
        self.log(f"Disconnected from {port}.")


class SerialMonitor(App[None]):
    TITLE = "Serial Monitor"
    SUB_TITLE = "Textual 8N1 console"
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
        height: 2;
        padding: 0 1;
        background: #3c3836;
        color: #ebdbb2;
        border-bottom: solid #fabd2f;
    }
    #content {
        height: 1fr;
        overflow: hidden hidden;
    }
    #serial-log {
        height: 1fr;
        margin: 1 1 0 1;
        background: #1d2021;
        color: #d5c4a1;
        padding: 0 1;
        border: round #504945;
        scrollbar-background: #1d2021;
        scrollbar-color: #665c54;
        scrollbar-color-hover: #928374;
        scrollbar-color-active: #fabd2f;
    }
    #send-input {
        height: 3;
        margin: 1;
        background: #1d2021;
        color: #ebdbb2;
        border: tall #665c54;
    }
    #send-input:focus {
        border: tall #fabd2f;
    }
    #send-input > .input--placeholder {
        color: #928374;
    }
    #send-input > .input--cursor {
        background: #fabd2f;
        color: #282828;
    }
    """
    BINDINGS = [
        Binding("f2", "connect", "Connect", priority=True),
        Binding("f3", "disconnect", "Disconnect", priority=True),
        Binding("ctrl+q", "quit", "Quit", priority=True),
    ]

    def __init__(self, config: Config) -> None:
        super().__init__()
        self.config = config
        saved_port, saved_baud = load_last_connection()
        self.selected_port = config.port or saved_port
        self.selected_baud = config.baud if config.port else saved_baud
        self.port_is_explicit = bool(config.port)
        self.output: queue.Queue[str] = queue.Queue()
        self.connection = SerialConnection(self.output, config.encoding)

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(id="status")
        with Vertical(id="content"):
            yield RichLog(
                id="serial-log",
                wrap=True,
                highlight=False,
                markup=False,
                auto_scroll=True,
                max_lines=50000,
            )
            yield Input(
                placeholder="Type a command and press Enter to send CRLF...",
                id="send-input",
            )
        yield Footer(show_command_palette=False)

    def on_mount(self) -> None:
        self.register_theme(GRUVBOX_SOFT_DARK)
        self.theme = GRUVBOX_SOFT_DARK.name
        self.set_interval(0.05, self.refresh_runtime)
        self.update_status()

    def action_connect(self) -> None:
        if self.connection.connected:
            self.connection.log("Already connected.")
            return
        if self.port_is_explicit:
            self.connect_selected()
            return
        ports = discover_ports()
        if not ports:
            self.connection.log("ERROR: No serial ports found.")
            return
        self.push_screen(
            PortPicker(ports, self.selected_port),
            self.port_selected,
        )

    def port_selected(self, port: str | None) -> None:
        if port is None:
            self.connection.log("Port selection cancelled.")
            return
        self.selected_port = port
        self.push_screen(
            BaudPicker(self.selected_baud),
            self.baud_selected,
        )

    def baud_selected(self, baud: int | None) -> None:
        if baud is None:
            self.connection.log("Baud-rate selection cancelled.")
            return
        self.selected_baud = baud
        try:
            save_last_connection(self.selected_port, self.selected_baud)
        except OSError as error:
            self.connection.log(f"WARNING: Could not save connection settings: {error}")
        self.connect_selected()

    def connect_selected(self) -> None:
        try:
            self.connection.connect(self.selected_port, self.selected_baud)
            self.query_one("#send-input", Input).focus()
        except (OSError, serial.SerialException, ValueError) as error:
            self.connection.log(f"ERROR: {error}")

    def action_disconnect(self) -> None:
        self.connection.disconnect()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id != "send-input":
            return
        try:
            self.connection.send_line(event.value)
            event.input.value = ""
        except (OSError, serial.SerialException) as error:
            self.connection.log(f"ERROR: {error}")

    def refresh_runtime(self) -> None:
        log = self.query_one("#serial-log", RichLog)
        while True:
            try:
                line = self.output.get_nowait()
            except queue.Empty:
                break
            log.write(line)
        self.update_status()

    def update_status(self) -> None:
        if self.connection.connected:
            status = (
                f"connected  |  {self.selected_port} @ {self.selected_baud} "
                f"8N1  |  {self.config.encoding}"
            )
        else:
            remembered = self.selected_port or "no saved port"
            status = f"disconnected  |  last: {remembered} @ {self.selected_baud}"
        self.query_one("#status", Static).update(status)

    def on_unmount(self) -> None:
        self.connection.disconnect()


class SerialLauncher(App[tuple[str, int] | None]):
    """Select a connection and then leave the terminal entirely to miniterm."""

    TITLE = "Serial"
    SUB_TITLE = "pySerial miniterm launcher"
    CSS = """
    Screen {
        background: #282828;
        color: #ebdbb2;
    }
    Header {
        background: #3c3836;
        color: #fabd2f;
    }
    Footer {
        background: #1d2021;
        color: #a89984;
    }
    #launcher-status {
        height: 1fr;
        content-align: center middle;
        margin: 1;
        padding: 1 2;
        background: #3c3836;
        color: #ebdbb2;
        border: round #fabd2f;
    }
    """
    BINDINGS = [
        Binding("f2", "select", "Select port", priority=True),
        Binding("ctrl+q", "quit", "Quit", priority=True),
    ]

    def __init__(self, config: Config) -> None:
        super().__init__()
        self.config = config
        saved_port, saved_baud = load_last_connection()
        self.selected_port = saved_port
        self.selected_baud = saved_baud

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(
            "Choose a COM port and baud rate.\n"
            "This window will then become a pySerial miniterm session.",
            id="launcher-status",
        )
        yield Footer(show_command_palette=False)

    def on_mount(self) -> None:
        self.register_theme(GRUVBOX_SOFT_DARK)
        self.theme = GRUVBOX_SOFT_DARK.name
        self.call_after_refresh(self.action_select)

    def action_select(self) -> None:
        ports = discover_ports()
        if not ports:
            self.notify(
                "No serial ports found. Connect a device and press F2 to retry.",
                severity="error",
                timeout=8,
            )
            return
        self.push_screen(
            PortPicker(ports, self.selected_port),
            self.port_selected,
        )

    def port_selected(self, port: str | None) -> None:
        if port is None:
            return
        self.selected_port = port
        self.push_screen(BaudPicker(self.selected_baud), self.baud_selected)

    def baud_selected(self, baud: int | None) -> None:
        if baud is None:
            return
        self.selected_baud = baud
        try:
            save_last_connection(self.selected_port, self.selected_baud)
        except OSError as error:
            self.notify(f"Could not save settings: {error}", severity="warning")
        self.exit((self.selected_port, self.selected_baud))


def miniterm_command(config: Config, port: str, baud: int) -> list[str]:
    return [
        sys.executable,
        "-m",
        "serial.tools.miniterm",
        port,
        str(baud),
        "--encoding",
        config.encoding,
        "--eol",
        "CRLF",
        "--dtr",
        "1",
        "--rts",
        "1",
        "--exit-char",
        "17",
    ]


def main() -> None:
    config = parse_args()
    if config.port:
        selection = (config.port, config.baud)
        save_last_connection(*selection)
    else:
        selection = SerialLauncher(config).run()
    if selection is None:
        return
    port, baud = selection
    raise SystemExit(subprocess.call(miniterm_command(config, port, baud)))


if __name__ == "__main__":
    main()
