#!/usr/bin/env python3
"""
MX Master 4 Haptic Feedback Daemon

A persistent daemon that keeps the HID connection open for instant haptic feedback.
Communicates via Unix socket for minimal latency.

Usage:
    Start daemon: mx4haptic-daemon.py --daemon
    Send pattern:  mx4haptic-daemon.py <pattern>
"""

import argparse
import os
import signal
import socket
import sys
import time
from enum import IntEnum
from struct import pack, unpack
from threading import Thread, Lock

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

# Reliability settings
HEALTH_CHECK_INTERVAL = 30.0  # Seconds between health checks when idle
RECONNECT_DELAY = 1.0  # Seconds between reconnection attempts
MAX_RECONNECT_ATTEMPTS = 5  # Max attempts before backing off
RECONNECT_BACKOFF = 10.0  # Seconds to wait after max attempts


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
        self._lock = Lock()

    @classmethod
    def find(cls):
        """Find and return an MXMaster4 instance, or None if not found."""
        try:
            devices = hid.enumerate(LOGITECH_VID)
            for device in devices:
                if device["usage_page"] == 65280:
                    return cls(device["path"].decode("utf-8"), device["interface_number"])
        except Exception:
            pass
        return None

    def open(self):
        """Open the HID device connection."""
        with self._lock:
            if self.device:
                return self
            self.device = hid.Device(path=self.path.encode())
            return self

    def close(self):
        """Close the HID device connection."""
        with self._lock:
            if self.device:
                try:
                    self.device.close()
                except Exception:
                    pass
                self.device = None

    def is_open(self):
        """Check if device handle is open (not necessarily valid)."""
        return self.device is not None

    def write(self, data: bytes):
        """Write data to the HID device."""
        if not self.device:
            raise RuntimeError("Device not open")
        self.device.write(data)

    def hidpp(self, feature_idx: FunctionID, *args: int) -> tuple[int, bytes]:
        """Send a HID++ command and read the response."""
        data = bytes(args)
        if len(data) < 3:
            data += bytes([0]) * (3 - len(data))
        report_id = ReportID.Short if len(data) == 3 else ReportID.Long
        packet = pack(b">BBH3s", report_id, self.device_idx, feature_idx, data)
        self.write(packet)
        return self.read()

    def read(self) -> tuple[int, bytes]:
        """Read a response from the HID device."""
        if not self.device:
            raise RuntimeError("Device not open")
        response = self.device.read(20, timeout=1000)  # 1 second timeout
        if not response:
            raise TimeoutError("Device read timeout")
        (r_report_id, r_device_idx, r_f_idx) = unpack(b">BBH", response[:4])
        if r_device_idx != self.device_idx:
            return self.read()
        return r_f_idx, response[4:]

    def ping(self) -> bool:
        """Send a ping to verify device is responsive. Returns True if successful."""
        try:
            with self._lock:
                if not self.device:
                    return False
                self.hidpp(FunctionID.IRoot, 0x00, 0x00, 0x00)
                return True
        except Exception:
            return False

    def haptic(self, pattern: int) -> bool:
        """Trigger haptic feedback. Returns True if successful."""
        if not 0 <= pattern <= 14:
            return False
        try:
            with self._lock:
                if not self.device:
                    return False
                self.hidpp(FunctionID.Haptic, pattern)
                return True
        except Exception:
            return False


class HapticDaemon:
    """Reliable haptic feedback daemon with automatic reconnection."""

    def __init__(self):
        self.device: MXMaster4 | None = None
        self.server: socket.socket | None = None
        self.running = False
        self.keepalive_active = False
        self.last_health_check = 0.0
        self.reconnect_attempts = 0

    def log(self, msg: str):
        """Log a message with timestamp."""
        timestamp = time.strftime("%H:%M:%S")
        print(f"[{timestamp}] {msg}", file=sys.stderr)

    def connect_device(self) -> bool:
        """Attempt to connect to the MX Master 4. Returns True if successful."""
        # Close existing connection if any
        if self.device:
            self.device.close()
            self.device = None

        device = MXMaster4.find()
        if not device:
            return False

        try:
            device.open()
            # Verify connection with a ping
            if device.ping():
                self.device = device
                self.reconnect_attempts = 0
                self.log("Connected to MX Master 4")
                return True
            else:
                device.close()
                return False
        except Exception as e:
            self.log(f"Connection failed: {e}")
            return False

    def ensure_connected(self) -> bool:
        """Ensure device is connected, attempting reconnection if needed."""
        # Already connected and responsive?
        if self.device and self.device.ping():
            return True

        # Need to reconnect
        self.log("Device unresponsive, attempting reconnection...")

        # Apply backoff after too many attempts
        if self.reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
            self.log(f"Max reconnect attempts reached, waiting {RECONNECT_BACKOFF}s...")
            time.sleep(RECONNECT_BACKOFF)
            self.reconnect_attempts = 0

        self.reconnect_attempts += 1
        if self.connect_device():
            return True

        time.sleep(RECONNECT_DELAY)
        return False

    def health_check(self):
        """Perform periodic health check to detect stale connections."""
        now = time.time()
        if now - self.last_health_check < HEALTH_CHECK_INTERVAL:
            return

        self.last_health_check = now

        if self.device and not self.device.ping():
            self.log("Health check failed, device unresponsive")
            self.ensure_connected()

    def setup_socket(self):
        """Create and configure the Unix socket."""
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.server.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o666)
        self.log(f"Listening on {SOCKET_PATH}")

    def cleanup(self):
        """Clean up resources on shutdown."""
        self.running = False
        if self.device:
            self.device.close()
        if self.server:
            self.server.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

    def handle_command(self, cmd: str):
        """Process a command received via socket."""
        if cmd == "wake":
            # Menu opened - activate keepalive
            self.keepalive_active = True
            self.ensure_connected()
            if self.device:
                self.device.ping()  # Wake the device
        elif cmd == "sleep":
            # Menu closed - deactivate keepalive
            self.keepalive_active = False
        elif cmd == "status":
            # Debug command
            status = "connected" if (self.device and self.device.is_open()) else "disconnected"
            self.log(f"Status: {status}, keepalive: {self.keepalive_active}")
        else:
            pattern = parse_pattern(cmd)
            if pattern >= 0:
                if not self.device or not self.device.haptic(pattern):
                    # Haptic failed, try to reconnect and retry once
                    if self.ensure_connected() and self.device:
                        self.device.haptic(pattern)

    def run(self):
        """Main daemon loop."""
        # Initial connection
        if not self.connect_device():
            self.log("Warning: MX Master 4 not found, will retry on first request")

        self.setup_socket()
        self.running = True
        self.last_health_check = time.time()

        # Keepalive interval
        KEEPALIVE_INTERVAL = 0.25

        while self.running:
            try:
                # Adjust timeout based on state
                if self.keepalive_active:
                    timeout = KEEPALIVE_INTERVAL
                else:
                    timeout = HEALTH_CHECK_INTERVAL

                self.server.settimeout(timeout)
                data = self.server.recv(64)

                if data:
                    cmd = data.decode("utf-8").strip()
                    self.handle_command(cmd)

            except socket.timeout:
                # Timeout - perform maintenance
                if self.keepalive_active:
                    # Send keepalive ping
                    if self.device:
                        if not self.device.ping():
                            self.ensure_connected()
                else:
                    # Perform health check
                    self.health_check()

            except Exception as e:
                self.log(f"Error in main loop: {e}")
                time.sleep(0.1)  # Prevent tight loop on repeated errors


def run_daemon():
    """Run the haptic daemon."""
    daemon = HapticDaemon()

    def shutdown(signum, frame):
        daemon.log("Shutting down...")
        daemon.cleanup()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    daemon.run()


def parse_pattern(value: str) -> int:
    """Parse pattern from string - either a number or a named pattern."""
    value = value.strip()
    if not value:
        return -1
    try:
        pattern = int(value)
        return pattern if 0 <= pattern <= 14 else -1
    except ValueError:
        return PATTERNS.get(value.lower(), -1)


def send_to_daemon(pattern: str) -> bool:
    """Send a pattern to the running daemon."""
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
    parser.add_argument("-s", "--status", action="store_true", help="Check daemon status")
    args = parser.parse_args()

    if args.list:
        print("Patterns:", ", ".join(f"{v}={k}" for k, v in sorted(PATTERNS.items(), key=lambda x: x[1])))
        return

    if args.status:
        if send_to_daemon("status"):
            print("Daemon is running (check stderr for status)")
        else:
            print("Daemon is not running")
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
