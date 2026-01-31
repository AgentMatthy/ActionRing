#!/usr/bin/env python3
"""
MX Master 4 Haptic Feedback Daemon

A persistent daemon that keeps the HID connection open for instant haptic feedback.
Communicates via Unix socket for minimal latency.

Usage:
    Start daemon: mx4haptic-daemon.py --daemon
    Send pattern:  echo "3" | nc -U /tmp/mx4haptic.sock
                   or: mx4haptic-daemon.py <pattern>
"""

import argparse
import os
import signal
import socket
import sys
from enum import IntEnum
from struct import pack, unpack
from threading import Thread

try:
    import hid
except ImportError:
    print("Error: 'hidapi' package required. Install with: pip install hidapi")
    sys.exit(1)

SOCKET_PATH = "/tmp/mx4haptic.sock"
LOGITECH_VID = 0x046D

PATTERNS = {
    "click": 0, "soft": 1, "bump": 2, "tick": 3, "pulse": 4,
    "double": 5, "triple": 6, "ramp": 7, "buzz": 8, "alert": 9,
    "notify": 10, "success": 11, "error": 12, "warning": 13, "strong": 14,
}


class ReportID(IntEnum):
    Short = 0x10
    Long = 0x11


class FunctionID(IntEnum):
    IRoot = 0x0000  # Root function for pings/version queries
    Haptic = 0x0B4E


class MXMaster4:
    def __init__(self, path: str, device_idx: int):
        self.path = path
        self.device_idx = device_idx
        self.device = None

    @classmethod
    def find(cls):
        devices = hid.enumerate(LOGITECH_VID)
        for device in devices:
            if device["usage_page"] == 65280:
                return cls(device["path"].decode("utf-8"), device["interface_number"])
        return None

    def open(self):
        self.device = hid.Device(path=self.path.encode())
        return self

    def close(self):
        if self.device:
            self.device.close()
            self.device = None

    def is_open(self):
        return self.device is not None

    def write(self, data: bytes):
        if not self.device:
            raise RuntimeError("Device not open")
        self.device.write(data)

    def hidpp(self, feature_idx: FunctionID, *args: int) -> tuple[int, bytes]:
        data = bytes(args)
        if len(data) < 3:
            data += bytes([0]) * (3 - len(data))
        report_id = ReportID.Short if len(data) == 3 else ReportID.Long
        packet = pack(b">BBH3s", report_id, self.device_idx, feature_idx, data)
        self.write(packet)
        return self.read()

    def read(self) -> tuple[int, bytes]:
        if not self.device:
            raise RuntimeError("Device not open")
        response = self.device.read(20)
        (r_report_id, r_device_idx, r_f_idx) = unpack(b">BBH", response[:4])
        if r_device_idx != self.device_idx:
            return self.read()
        return r_f_idx, response[4:]

    def haptic(self, pattern: int):
        if not 0 <= pattern <= 14:
            return
        try:
            self.hidpp(FunctionID.Haptic, pattern)
        except Exception:
            pass  # Silently ignore errors to avoid blocking


def parse_pattern(value: str) -> int:
    """Parse pattern from string - either a number or a named pattern"""
    value = value.strip()
    if not value:
        return -1
    try:
        pattern = int(value)
        return pattern if 0 <= pattern <= 14 else -1
    except ValueError:
        return PATTERNS.get(value.lower(), -1)


def run_daemon():
    """Run the haptic daemon - keeps device open for instant response"""
    # Clean up old socket
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    device = MXMaster4.find()
    if not device:
        print("Error: MX Master 4 not found!", file=sys.stderr)
        sys.exit(1)

    device.open()
    print(f"Daemon started, listening on {SOCKET_PATH}", file=sys.stderr)

    # Handle graceful shutdown
    def shutdown(signum, frame):
        print("\nShutting down...", file=sys.stderr)
        device.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    # Create Unix socket
    server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    server.bind(SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o666)  # Allow any user to send

    # Keepalive state - only send pings when menu is open
    keepalive_active = False
    KEEPALIVE_INTERVAL = 0.25  # 250ms between pings when active

    while True:
        try:
            # Use short timeout when keepalive active, long timeout otherwise
            server.settimeout(KEEPALIVE_INTERVAL if keepalive_active else None)
            data = server.recv(64)
            if data:
                cmd = data.decode("utf-8").strip()
                if cmd == "wake":
                    # Menu opened - start keepalive and immediately ping to wake device
                    keepalive_active = True
                    try:
                        if device.device:
                            device.hidpp(FunctionID.IRoot, 0x00, 0x00, 0x00)
                    except Exception:
                        pass
                elif cmd == "sleep":
                    # Menu closed - stop keepalive
                    keepalive_active = False
                else:
                    pattern = parse_pattern(cmd)
                    if pattern >= 0:
                        device.haptic(pattern)
        except socket.timeout:
            # Only reached when keepalive is active
            try:
                if device.device:
                    device.hidpp(FunctionID.IRoot, 0x00, 0x00, 0x00)
            except Exception:
                pass
        except Exception as e:
            # Try to reconnect if device was disconnected
            try:
                device.close()
                new_device = MXMaster4.find()
                if new_device:
                    device = new_device
                    device.open()
            except Exception:
                pass


def send_to_daemon(pattern: str) -> bool:
    """Send a pattern to the running daemon"""
    if not os.path.exists(SOCKET_PATH):
        return False
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        client.sendto(pattern.encode("utf-8"), SOCKET_PATH)
        client.close()
        return True
    except Exception:
        return False


def main():
    parser = argparse.ArgumentParser(description="MX Master 4 Haptic Daemon")
    parser.add_argument("pattern", nargs="?", help="Pattern to trigger (0-14 or name)")
    parser.add_argument("-d", "--daemon", action="store_true", help="Run as daemon")
    parser.add_argument("-l", "--list", action="store_true", help="List patterns")
    args = parser.parse_args()

    if args.list:
        print("Patterns:", ", ".join(f"{v}={k}" for k, v in sorted(PATTERNS.items(), key=lambda x: x[1])))
        return

    if args.daemon:
        run_daemon()
        return

    if not args.pattern:
        parser.print_help()
        sys.exit(1)

    # Try daemon first (fast path)
    if send_to_daemon(args.pattern):
        return

    # Fallback: direct connection (slower)
    pattern = parse_pattern(args.pattern)
    if pattern < 0:
        print(f"Invalid pattern: {args.pattern}", file=sys.stderr)
        sys.exit(1)

    device = MXMaster4.find()
    if not device:
        print("Error: MX Master 4 not found!", file=sys.stderr)
        sys.exit(1)

    device.open()
    device.haptic(pattern)
    device.close()


if __name__ == "__main__":
    main()
