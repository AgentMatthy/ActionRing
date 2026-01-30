#!/usr/bin/env python3
"""
MX Master 4 Haptic Feedback Trigger

A standalone script to trigger haptic feedback patterns on the Logitech MX Master 4 mouse.

Usage:
    mx4haptic.py <pattern>
    mx4haptic.py --list

Arguments:
    pattern     Pattern number (0-14) or name (click, bump, tick, etc.)

Options:
    -l, --list  List all available patterns
    -v          Verbose output
    -h, --help  Show this help message
"""

import argparse
import sys
from enum import IntEnum
from struct import pack, unpack

try:
    import hid
except ImportError:
    print("Error: 'hidapi' package required. Install with: pip install hidapi")
    sys.exit(1)

LOGITECH_VID = 0x046D

# Named patterns based on feel (can be customized)
PATTERNS = {
    "click": 0,
    "soft": 1,
    "bump": 2,
    "tick": 3,
    "pulse": 4,
    "double": 5,
    "triple": 6,
    "ramp": 7,
    "buzz": 8,
    "alert": 9,
    "notify": 10,
    "success": 11,
    "error": 12,
    "warning": 13,
    "strong": 14,
}


class ReportID(IntEnum):
    Short = 0x10  # 7 bytes
    Long = 0x11   # 20 bytes


class FunctionID(IntEnum):
    IRoot = 0x0000
    IFeatureSet = 0x0001
    IFeatureInfo = 0x0002
    Haptic = 0x0B4E


class MXMaster4:
    device = None

    def __init__(self, path: str, device_idx: int):
        self.path = path
        self.device_idx = device_idx

    @classmethod
    def find(cls):
        devices = hid.enumerate(LOGITECH_VID)

        for device in devices:
            if device["usage_page"] == 65280:
                path = device["path"].decode("utf-8")
                return cls(path, device["interface_number"])

        return None

    def __enter__(self):
        self.device = hid.Device(path=self.path.encode())
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.device:
            self.device.close()

    def write(self, data: bytes):
        if not self.device:
            raise RuntimeError("Device not open")
        self.device.write(data)

    def hidpp(self, feature_idx: FunctionID, *args: int) -> tuple[int, bytes]:
        if len(args) > 16:
            raise ValueError("Too many arguments")

        data = bytes(args)
        if len(data) < 3:
            data += bytes([0]) * (3 - len(data))

        report_id = ReportID.Short if len(data) == 3 else ReportID.Long
        packet = pack(b">BBH3s", report_id, self.device_idx, feature_idx, data)
        self.write(packet)
        return self.read()

    def read(self) -> tuple[int, bytes]:
        response = self.device.read(20)
        (r_report_id, r_device_idx, r_f_idx) = unpack(b">BBH", response[:4])
        
        if r_device_idx != self.device_idx:
            return self.read()

        return r_f_idx, response[4:]

    def haptic(self, pattern: int):
        """Trigger a haptic feedback pattern (0-14)"""
        if not 0 <= pattern <= 14:
            raise ValueError(f"Pattern must be 0-14, got {pattern}")
        self.hidpp(FunctionID.Haptic, pattern)


def parse_pattern(value: str) -> int:
    """Parse pattern from string - either a number or a named pattern"""
    # Try as integer first
    try:
        pattern = int(value)
        if 0 <= pattern <= 14:
            return pattern
        print(f"Error: Pattern number must be 0-14, got {pattern}")
        sys.exit(1)
    except ValueError:
        pass

    # Try as named pattern
    name = value.lower()
    if name in PATTERNS:
        return PATTERNS[name]

    print(f"Error: Unknown pattern '{value}'")
    print(f"Valid names: {', '.join(PATTERNS.keys())}")
    print("Or use a number 0-14")
    sys.exit(1)


def list_patterns():
    """Print all available patterns"""
    print("Available haptic patterns:\n")
    print("  Num  Name")
    print("  ---  ----")
    for name, num in sorted(PATTERNS.items(), key=lambda x: x[1]):
        print(f"  {num:2d}   {name}")
    print("\nUsage: mx4haptic <pattern>")
    print("Example: mx4haptic click")
    print("         mx4haptic 5")


def main():
    parser = argparse.ArgumentParser(
        description="Trigger haptic feedback on MX Master 4 mouse",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n  mx4haptic click\n  mx4haptic 5\n  mx4haptic --list"
    )
    parser.add_argument(
        "pattern",
        nargs="?",
        help="Pattern number (0-14) or name (click, bump, etc.)"
    )
    parser.add_argument(
        "-l", "--list",
        action="store_true",
        help="List all available patterns"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output"
    )

    args = parser.parse_args()

    if args.list:
        list_patterns()
        return

    if not args.pattern:
        parser.print_help()
        sys.exit(1)

    pattern = parse_pattern(args.pattern)

    device = MXMaster4.find()
    if not device:
        print("Error: MX Master 4 not found!")
        print("Make sure the mouse is connected and you have permission to access HID devices.")
        sys.exit(1)

    try:
        with device as dev:
            dev.haptic(pattern)
            if args.verbose:
                # Find pattern name if it exists
                name = next((k for k, v in PATTERNS.items() if v == pattern), None)
                if name:
                    print(f"Triggered haptic pattern: {pattern} ({name})")
                else:
                    print(f"Triggered haptic pattern: {pattern}")
    except Exception as e:
        print(f"Error triggering haptic: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
