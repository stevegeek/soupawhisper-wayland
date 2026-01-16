#!/usr/bin/env python3
"""
SoupaWhisper - Voice dictation tool using faster-whisper.
Hold the hotkey to record, release to transcribe and copy to clipboard.
Supports both X11 and Wayland.
"""

import argparse
import configparser
import subprocess
import tempfile
import threading
import signal
import sys
import os
import select
from pathlib import Path

# Preload CUDA libraries from pip packages before importing faster_whisper
def preload_cuda_libs():
    """Preload pip-installed CUDA libraries using ctypes."""
    import ctypes
    import glob
    try:
        import nvidia.cublas.lib
        import nvidia.cudnn.lib

        # Find and load cublas
        cublas_path = nvidia.cublas.lib.__path__[0]
        for lib in glob.glob(f"{cublas_path}/libcublas.so*"):
            try:
                ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
            except OSError:
                pass

        # Find and load cudnn
        cudnn_path = nvidia.cudnn.lib.__path__[0]
        for lib in glob.glob(f"{cudnn_path}/libcudnn*.so*"):
            try:
                ctypes.CDLL(lib, mode=ctypes.RTLD_GLOBAL)
            except OSError:
                pass
    except ImportError:
        pass  # CUDA libs not installed via pip, use system libs

preload_cuda_libs()

import evdev
from evdev import ecodes
from faster_whisper import WhisperModel

__version__ = "0.2.0"

# Load configuration
CONFIG_PATH = Path.home() / ".config" / "soupawhisper" / "config.ini"

# Detect Wayland
IS_WAYLAND = os.environ.get("XDG_SESSION_TYPE") == "wayland" or "WAYLAND_DISPLAY" in os.environ

# Map key names to evdev keycodes
KEY_MAP = {
    "f1": ecodes.KEY_F1, "f2": ecodes.KEY_F2, "f3": ecodes.KEY_F3, "f4": ecodes.KEY_F4,
    "f5": ecodes.KEY_F5, "f6": ecodes.KEY_F6, "f7": ecodes.KEY_F7, "f8": ecodes.KEY_F8,
    "f9": ecodes.KEY_F9, "f10": ecodes.KEY_F10, "f11": ecodes.KEY_F11, "f12": ecodes.KEY_F12,
    "f13": ecodes.KEY_F13, "f14": ecodes.KEY_F14, "f15": ecodes.KEY_F15, "f16": ecodes.KEY_F16,
    "f17": ecodes.KEY_F17, "f18": ecodes.KEY_F18, "f19": ecodes.KEY_F19, "f20": ecodes.KEY_F20,
    "scroll_lock": ecodes.KEY_SCROLLLOCK, "pause": ecodes.KEY_PAUSE,
    "insert": ecodes.KEY_INSERT, "home": ecodes.KEY_HOME, "end": ecodes.KEY_END,
    "pageup": ecodes.KEY_PAGEUP, "pagedown": ecodes.KEY_PAGEDOWN,
}


def load_config():
    config = configparser.ConfigParser()

    # Defaults
    defaults = {
        "model": "base.en",
        "device": "cpu",
        "compute_type": "int8",
        "key": "f12",
        "auto_type": "true",
        "notifications": "true",
    }

    if CONFIG_PATH.exists():
        config.read(CONFIG_PATH)

    return {
        "model": config.get("whisper", "model", fallback=defaults["model"]),
        "device": config.get("whisper", "device", fallback=defaults["device"]),
        "compute_type": config.get("whisper", "compute_type", fallback=defaults["compute_type"]),
        "key": config.get("hotkey", "key", fallback=defaults["key"]),
        "auto_type": config.getboolean("behavior", "auto_type", fallback=True),
        "notifications": config.getboolean("behavior", "notifications", fallback=True),
    }


CONFIG = load_config()


def get_hotkey_code(key_name):
    """Map key name to evdev keycode."""
    key_name = key_name.lower()
    if key_name in KEY_MAP:
        return KEY_MAP[key_name]
    else:
        print(f"Unknown key: {key_name}, defaulting to f12")
        return ecodes.KEY_F12


HOTKEY_CODE = get_hotkey_code(CONFIG["key"])
HOTKEY_NAME = CONFIG["key"].upper()
MODEL_SIZE = CONFIG["model"]
DEVICE = CONFIG["device"]
COMPUTE_TYPE = CONFIG["compute_type"]
AUTO_TYPE = CONFIG["auto_type"]
NOTIFICATIONS = CONFIG["notifications"]


def find_keyboard_devices():
    """Find keyboard input devices."""
    devices = []
    for path in evdev.list_devices():
        try:
            device = evdev.InputDevice(path)
            caps = device.capabilities()
            # Check if device has EV_KEY capability and has F-keys
            if ecodes.EV_KEY in caps:
                keys = caps[ecodes.EV_KEY]
                if ecodes.KEY_F1 in keys or ecodes.KEY_F10 in keys:
                    devices.append(device)
        except (PermissionError, OSError):
            continue
    return devices


class Dictation:
    def __init__(self):
        self.recording = False
        self.record_process = None
        self.temp_file = None
        self.model = None
        self.model_loaded = threading.Event()
        self.model_error = None
        self.running = True
        self.notification_id = 0  # For replacing notifications

        # Load model in background
        print(f"Loading Whisper model ({MODEL_SIZE})...")
        threading.Thread(target=self._load_model, daemon=True).start()

    def _load_model(self):
        try:
            self.model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE)
            self.model_loaded.set()
            print(f"Model loaded. Ready for dictation!")
            print(f"Hold [{HOTKEY_NAME}] to record, release to transcribe.")
            print("Press Ctrl+C to quit.")
        except Exception as e:
            self.model_error = str(e)
            self.model_loaded.set()
            print(f"Failed to load model: {e}")
            if "cudnn" in str(e).lower() or "cuda" in str(e).lower():
                print("Hint: Try setting device = cpu in your config, or install cuDNN.")

    def notify(self, title, message, icon="dialog-information", timeout=2000):
        """Send a desktop notification that replaces the previous one."""
        if not NOTIFICATIONS:
            return
        try:
            # Use gdbus to call notification daemon directly - supports replacement on KDE
            result = subprocess.run(
                [
                    "gdbus", "call", "--session",
                    "--dest", "org.freedesktop.Notifications",
                    "--object-path", "/org/freedesktop/Notifications",
                    "--method", "org.freedesktop.Notifications.Notify",
                    "SoupaWhisper",  # app_name
                    str(self.notification_id),  # replaces_id (0 = new, >0 = replace)
                    icon,  # app_icon
                    title,  # summary
                    message,  # body
                    "[]",  # actions
                    "{}",  # hints
                    str(timeout),  # timeout
                ],
                capture_output=True,
                text=True
            )
            # Parse the returned notification ID for future replacement
            # Output format: (uint32 123,)
            if result.stdout:
                import re
                match = re.search(r'\(uint32 (\d+),\)', result.stdout)
                if match:
                    self.notification_id = int(match.group(1))
        except Exception:
            # Fallback to notify-send
            subprocess.run(
                ["notify-send", "-a", "SoupaWhisper", "-i", icon, "-t", str(timeout), title, message],
                capture_output=True
            )

    def start_recording(self):
        if self.recording or self.model_error:
            return

        self.recording = True
        self.temp_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
        self.temp_file.close()

        # Record using arecord (ALSA) - works on most Linux systems
        self.record_process = subprocess.Popen(
            [
                "arecord",
                "-f", "S16_LE",  # Format: 16-bit little-endian
                "-r", "16000",   # Sample rate: 16kHz (what Whisper expects)
                "-c", "1",       # Mono
                "-t", "wav",
                self.temp_file.name
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        print("Recording...")
        self.notify("Recording...", f"Release {HOTKEY_NAME} when done", "audio-input-microphone", 30000)

    def stop_recording(self):
        if not self.recording:
            return

        self.recording = False

        if self.record_process:
            self.record_process.terminate()
            self.record_process.wait()
            self.record_process = None

        print("Transcribing...")

        # Wait for model if not loaded yet
        self.model_loaded.wait()

        if self.model_error:
            print(f"Cannot transcribe: model failed to load")
            self.notify("Error", "Model failed to load", "dialog-error", 3000)
            return

        # Transcribe
        try:
            segments, info = self.model.transcribe(
                self.temp_file.name,
                beam_size=5,
                vad_filter=True,
            )

            text = " ".join(segment.text.strip() for segment in segments)

            if text:
                # Copy to clipboard
                if IS_WAYLAND:
                    process = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE)
                else:
                    process = subprocess.Popen(
                        ["xclip", "-selection", "clipboard"],
                        stdin=subprocess.PIPE
                    )
                process.communicate(input=text.encode())

                # Type it into the active input field
                if AUTO_TYPE:
                    if IS_WAYLAND:
                        # Use Ctrl+V to paste from clipboard (works with any keyboard layout)
                        subprocess.run(["ydotool", "key", "29:1", "47:1", "47:0", "29:0"])  # Ctrl+V
                    else:
                        subprocess.run(["xdotool", "type", "--clearmodifiers", text])

                print(f"Copied: {text}")
                self.notify("Copied!", text[:100] + ("..." if len(text) > 100 else ""), "emblem-ok-symbolic", 3000)
            else:
                print("No speech detected")
                self.notify("No speech detected", "Try speaking louder", "dialog-warning", 2000)

        except Exception as e:
            print(f"Error: {e}")
            self.notify("Error", str(e)[:50], "dialog-error", 3000)
        finally:
            # Cleanup temp file
            if self.temp_file and os.path.exists(self.temp_file.name):
                os.unlink(self.temp_file.name)

    def stop(self):
        print("\nExiting...")
        self.running = False
        os._exit(0)

    def run(self):
        """Main event loop using evdev for keyboard input."""
        devices = find_keyboard_devices()
        if not devices:
            print("Error: No keyboard devices found.")
            print("Make sure you have permission to read /dev/input/event* devices.")
            print("You may need to add your user to the 'input' group:")
            print("  sudo usermod -aG input $USER")
            print("Then log out and back in.")
            sys.exit(1)

        print(f"Monitoring {len(devices)} keyboard device(s)...")
        for d in devices:
            print(f"  - {d.name}")

        # Create a dict mapping fd to device
        fd_to_device = {dev.fd: dev for dev in devices}

        while self.running:
            # Use select to wait for events from any device
            r, _, _ = select.select(fd_to_device.keys(), [], [], 0.1)
            for fd in r:
                device = fd_to_device[fd]
                try:
                    for event in device.read():
                        if event.type == ecodes.EV_KEY and event.code == HOTKEY_CODE:
                            if event.value == 1:  # Key pressed
                                self.start_recording()
                            elif event.value == 0:  # Key released
                                self.stop_recording()
                except BlockingIOError:
                    pass


def check_dependencies():
    """Check that required system commands are available."""
    missing = []

    # Audio recording
    if subprocess.run(["which", "arecord"], capture_output=True).returncode != 0:
        missing.append(("arecord", "alsa-utils"))

    # Clipboard
    if IS_WAYLAND:
        if subprocess.run(["which", "wl-copy"], capture_output=True).returncode != 0:
            missing.append(("wl-copy", "wl-clipboard"))
    else:
        if subprocess.run(["which", "xclip"], capture_output=True).returncode != 0:
            missing.append(("xclip", "xclip"))

    # Auto-typing
    if AUTO_TYPE:
        if IS_WAYLAND:
            if subprocess.run(["which", "ydotool"], capture_output=True).returncode != 0:
                missing.append(("ydotool", "ydotool"))
        else:
            if subprocess.run(["which", "xdotool"], capture_output=True).returncode != 0:
                missing.append(("xdotool", "xdotool"))

    if missing:
        print("Missing dependencies:")
        for cmd, pkg in missing:
            print(f"  {cmd} - install: sudo pacman -S {pkg}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="SoupaWhisper - Push-to-talk voice dictation"
    )
    parser.add_argument(
        "-v", "--version",
        action="version",
        version=f"SoupaWhisper {__version__}"
    )
    parser.parse_args()

    print(f"SoupaWhisper v{__version__}")
    print(f"Session: {'Wayland' if IS_WAYLAND else 'X11'}")
    print(f"Config: {CONFIG_PATH}")
    print(f"Hotkey: {HOTKEY_NAME}")

    check_dependencies()

    dictation = Dictation()

    # Handle Ctrl+C gracefully
    def handle_sigint(sig, frame):
        dictation.stop()

    signal.signal(signal.SIGINT, handle_sigint)

    dictation.run()


if __name__ == "__main__":
    main()
