#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "flask>=3.1",
#     "pyobjc-framework-Quartz>=11.0",
#     "pyobjc-framework-Cocoa>=11.0",
#     "pyobjc-framework-ApplicationServices>=11.0",
# ]
# ///
"""
Anki Remote Control Service

HTTP server that receives commands and sends keyboard strokes to the Anki macOS app.

Endpoints:
    POST /reveal        - Press Return (reveal answer)
    POST /undo          - Press Cmd+Z (undo)
    POST /answer/again  - Press "1" (Again)
    POST /answer/good   - Press "3" (Good)
    POST /custom/<n>    - Press Ctrl+Shift+<n> where n is 0-9
"""

import argparse
import logging
import sys
import time

from flask import Flask, jsonify, request

from AppKit import NSWorkspace, NSRunningApplication
from Quartz import (
    CGEventCreateKeyboardEvent,
    CGEventSetFlags,
    CGEventPostToPid,
    kCGEventFlagMaskCommand,
    kCGEventFlagMaskControl,
    kCGEventFlagMaskShift,
)

logger = logging.getLogger("anki_remote")
app = Flask(__name__)

# macOS virtual keycodes
KEYCODE_MAP: dict[str, int] = {
    "1": 0x12,
    "2": 0x13,
    "3": 0x14,
    "4": 0x15,
    "5": 0x17,
    "6": 0x16,
    "7": 0x1A,
    "8": 0x1C,
    "9": 0x19,
    "0": 0x1D,
    "return": 0x24,
    "z": 0x06,
    "r": 0x0F,
}


_cached_anki_app: NSRunningApplication | None = None


def _find_anki() -> NSRunningApplication:
    """Return the cached Anki NSRunningApplication, refreshing if needed."""
    global _cached_anki_app
    if _cached_anki_app is not None and not _cached_anki_app.isTerminated():
        return _cached_anki_app
    logger.debug("Looking for Anki process...")
    workspace = NSWorkspace.sharedWorkspace()
    for running_app in workspace.runningApplications():
        if running_app.bundleIdentifier() == "net.ankiweb.dtop":
            logger.debug("Found Anki (pid=%s)", running_app.processIdentifier())
            _cached_anki_app = running_app
            return running_app
    raise RuntimeError("Anki is not running")


def _activate_anki() -> None:
    """Bring Anki to the foreground, only if not already active."""
    anki = _find_anki()
    if not anki.isActive():
        anki.activateWithOptions_(0)


def _send_key_to_anki(keycode: int, flags: int = 0) -> None:
    """Send a keystroke directly to the Anki process."""
    anki = _find_anki()
    pid = anki.processIdentifier()
    logger.debug("Sending keycode=0x%02X flags=0x%X to pid=%d", keycode, flags, pid)
    down = CGEventCreateKeyboardEvent(None, keycode, True)
    up = CGEventCreateKeyboardEvent(None, keycode, False)
    if flags:
        CGEventSetFlags(down, flags)
        CGEventSetFlags(up, flags)
    CGEventPostToPid(pid, down)
    CGEventPostToPid(pid, up)


def _send_to_anki(keycode: int, flags: int = 0) -> None:
    """Send a keystroke to Anki."""
    _send_key_to_anki(keycode, flags)


@app.post("/reveal")
def reveal():
    """Press Return in Anki (reveal answer)."""
    logger.info("POST /reveal from %s", request.remote_addr)
    _send_to_anki(KEYCODE_MAP["return"])
    return jsonify({"status": "ok", "action": "reveal"})


@app.post("/undo")
def undo():
    """Press Cmd+Z in Anki (undo)."""
    logger.info("POST /undo from %s", request.remote_addr)
    _send_to_anki(KEYCODE_MAP["z"], kCGEventFlagMaskCommand)
    return jsonify({"status": "ok", "action": "undo"})


@app.post("/replay")
def replay():
    """Press 'R' in Anki (replay audio)."""
    logger.info("POST /replay from %s", request.remote_addr)
    _send_to_anki(KEYCODE_MAP["r"])
    return jsonify({"status": "ok", "action": "replay"})


@app.post("/answer/again")
def answer_again():
    """Press '1' in Anki (Again)."""
    logger.info("POST /answer/again from %s", request.remote_addr)
    _send_to_anki(KEYCODE_MAP["1"])
    return jsonify({"status": "ok", "action": "again"})


@app.post("/answer/good")
def answer_good():
    """Press '3' in Anki (Good)."""
    logger.info("POST /answer/good from %s", request.remote_addr)
    _send_to_anki(KEYCODE_MAP["3"])
    return jsonify({"status": "ok", "action": "good"})


@app.post("/custom/<int:n>")
def custom_command(n: int):
    """Press Ctrl+Shift+<n> in Anki (user-defined shortcut)."""
    logger.info("POST /custom/%d from %s", n, request.remote_addr)
    if n < 0 or n > 9:
        raise ValueError(f"Custom command must be 0-9, got {n}")
    key = str(n)
    flags = kCGEventFlagMaskControl | kCGEventFlagMaskShift
    _send_to_anki(KEYCODE_MAP[key], flags)
    return jsonify({"status": "ok", "action": f"custom_{n}"})


@app.get("/health")
def health():
    """Health check endpoint for watchOS connectivity test."""
    logger.debug("GET /health from %s", request.remote_addr)
    return jsonify({"status": "ok"})


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Anki Remote Control — HTTP server that sends keystrokes to Anki.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
endpoints:
  POST /reveal         press Return (reveal answer)
  POST /undo           press Cmd+Z (undo)
  POST /answer/again   press 1 (Again)
  POST /answer/good    press 3 (Good)
  POST /custom/<0-9>   press Ctrl+Shift+<n>
  GET  /health         health check
""",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="enable verbose/debug logging"
    )
    parser.add_argument(
        "-p", "--port", type=int, default=27701, help="port to listen on (default: 27701)"
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    logger.info("Starting Anki Remote Control on http://0.0.0.0:%d", args.port)
    app.run(host="0.0.0.0", port=args.port, debug=args.verbose, threaded=True)


if __name__ == "__main__":
    main()
