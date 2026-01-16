# SoupaWhisper

A simple push-to-talk voice dictation tool for Linux using faster-whisper. Hold a key to record, release to transcribe, and it automatically copies to clipboard and types into the active input.

Supports both **X11** and **Wayland** (including KDE Plasma).

## Requirements

- Python 3.10+
- Poetry
- Linux with X11 or Wayland (ALSA audio)

## Supported Distros

- Ubuntu / Pop!_OS / Debian (apt)
- Fedora (dnf)
- Arch Linux (pacman)
- openSUSE (zypper)

## Supported Desktop Environments

- GNOME (X11/Wayland)
- KDE Plasma (X11/Wayland)
- Sway, Hyprland, and other wlroots-based compositors
- Any X11-based desktop

## Installation

```bash
git clone https://github.com/ksred/soupawhisper.git
cd soupawhisper
chmod +x install.sh
./install.sh
```

The installer will:
1. Detect your package manager
2. Install system dependencies
3. Install Python dependencies via Poetry
4. Set up the config file
5. Optionally install as a systemd service

### Manual Installation

#### X11

```bash
# Ubuntu/Debian
sudo apt install alsa-utils xclip xdotool libnotify-bin

# Fedora
sudo dnf install alsa-utils xclip xdotool libnotify

# Arch
sudo pacman -S alsa-utils xclip xdotool libnotify

# Then install Python deps
poetry install
```

#### Wayland (KDE, GNOME, Sway, etc.)

```bash
# Arch
sudo pacman -S alsa-utils wl-clipboard ydotool libnotify

# Enable ydotool daemon (required for auto-typing)
systemctl --user enable --now ydotool

# Add yourself to input group (for keyboard monitoring)
sudo usermod -aG input $USER
# Log out and back in for group changes to take effect

# Then install Python deps
poetry install
```

### GPU Support (Optional)

For NVIDIA GPU acceleration with CUDA 12:

```bash
# Ubuntu/Debian
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install libcudnn9-cuda-12
```

Then edit `~/.config/soupawhisper/config.ini`:
```ini
device = cuda
compute_type = float16
```

#### CUDA 13 Users

If you have CUDA 13 installed, the bundled cuBLAS/cuDNN won't work with faster-whisper (which expects CUDA 12). Install the CUDA 12 libraries via pip:

```bash
poetry run pip install nvidia-cublas-cu12 nvidia-cudnn-cu12
```

The script will automatically detect and use these pip-installed libraries.

## Usage

```bash
poetry run python dictate.py
```

- Hold **F12** to record
- Release to transcribe → copies to clipboard and types into active input
- Press **Ctrl+C** to quit (when running manually)

## Run as a systemd Service

Use the service control script to manage SoupaWhisper as a background service:

```bash
./service.sh install   # Install and enable the service
./service.sh start     # Start the service
./service.sh stop      # Stop the service
./service.sh restart   # Restart the service
./service.sh status    # Check service status
./service.sh logs      # Follow service logs
./service.sh uninstall # Remove the service
```

The service will auto-start on login once installed.

Alternatively, the main installer can also set up the service:

```bash
./install.sh  # Select 'y' when prompted for systemd
```

## Configuration

Edit `~/.config/soupawhisper/config.ini`:

```ini
[whisper]
# Model size: tiny.en, base.en, small.en, medium.en, large-v3
model = base.en

# Device: cpu or cuda (cuda requires cuDNN)
device = cpu

# Compute type: int8 for CPU, float16 for GPU
compute_type = int8

[hotkey]
# Key to hold for recording: f1-f20, scroll_lock, pause, insert, home, end, pageup, pagedown
# Apple keyboards with extended F-keys can use f13-f20
key = f12

[behavior]
# Type text into active input field
auto_type = true

# Show desktop notification
notifications = true
```

Create the config directory and file if it doesn't exist:
```bash
mkdir -p ~/.config/soupawhisper
cp /path/to/soupawhisper/config.example.ini ~/.config/soupawhisper/config.ini
```

## Troubleshooting

**No audio recording:**
```bash
# Check your input device
arecord -l

# Test recording
arecord -d 3 test.wav && aplay test.wav
```

**Permission issues with keyboard:**
```bash
sudo usermod -aG input $USER
# Then log out and back in
```

**cuDNN errors with GPU:**
```
Unable to load any of {libcudnn_ops.so.9...}
```
Install cuDNN 9 (see GPU Support section above) or switch to CPU mode.

## Model Sizes

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| tiny.en | ~75MB | Fastest | Basic |
| base.en | ~150MB | Fast | Good |
| small.en | ~500MB | Medium | Better |
| medium.en | ~1.5GB | Slower | Great |
| large-v3 | ~3GB | Slowest | Best |

For dictation, `base.en` or `small.en` is usually the sweet spot.
