#!/bin/bash
# Install SoupaWhisper on Linux using venv/pip (no Poetry required)
# Supports: Ubuntu, Pop!_OS, Debian, Fedora, Arch, openSUSE

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/soupawhisper"
SERVICE_DIR="$HOME/.config/systemd/user"
VENV_DIR="$SCRIPT_DIR/.venv"

# Detect package manager
detect_package_manager() {
    if command -v apt &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Install system dependencies
install_deps() {
    local pm=$(detect_package_manager)

    echo "Detected package manager: $pm"
    echo "Installing system dependencies..."

    case $pm in
        apt)
            sudo apt update
            sudo apt install -y alsa-utils xclip xdotool libnotify-bin python3-venv
            ;;
        dnf)
            sudo dnf install -y alsa-utils xclip xdotool libnotify python3
            ;;
        pacman)
            sudo pacman -S --noconfirm alsa-utils xclip xdotool libnotify python
            ;;
        zypper)
            sudo zypper install -y alsa-utils xclip xdotool libnotify-tools python3
            ;;
        *)
            echo "Unknown package manager. Please install manually:"
            echo "  alsa-utils xclip xdotool libnotify python3-venv"
            ;;
    esac
}

# Install Python dependencies using venv/pip
install_python() {
    echo ""
    echo "Setting up Python virtual environment..."

    # Create venv if it doesn't exist
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        echo "Created virtual environment at $VENV_DIR"
    else
        echo "Virtual environment already exists at $VENV_DIR"
    fi

    # Activate and install dependencies
    source "$VENV_DIR/bin/activate"

    echo "Upgrading pip..."
    pip install --upgrade pip

    echo "Installing Python dependencies..."
    pip install -r "$SCRIPT_DIR/requirements.txt"

    deactivate
    echo "Python dependencies installed!"
}

# Setup config file
setup_config() {
    echo ""
    echo "Setting up config..."
    mkdir -p "$CONFIG_DIR"

    if [ ! -f "$CONFIG_DIR/config.ini" ]; then
        cp "$SCRIPT_DIR/config.example.ini" "$CONFIG_DIR/config.ini"
        echo "Created config at $CONFIG_DIR/config.ini"
    else
        echo "Config already exists at $CONFIG_DIR/config.ini"
    fi
}

# Install systemd service
install_service() {
    echo ""
    echo "Installing systemd user service..."

    mkdir -p "$SERVICE_DIR"

    # Get current display settings
    local display="${DISPLAY:-:0}"
    local xauthority="${XAUTHORITY:-$HOME/.Xauthority}"

    cat > "$SERVICE_DIR/soupawhisper.service" << EOF
[Unit]
Description=SoupaWhisper Voice Dictation
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV_DIR/bin/python $SCRIPT_DIR/dictate.py
Restart=on-failure
RestartSec=5

# X11 display access
Environment=DISPLAY=$display
Environment=XAUTHORITY=$xauthority

[Install]
WantedBy=default.target
EOF

    echo "Created service at $SERVICE_DIR/soupawhisper.service"

    # Reload and enable
    systemctl --user daemon-reload
    systemctl --user enable soupawhisper

    echo ""
    echo "Service installed! Commands:"
    echo "  systemctl --user start soupawhisper   # Start"
    echo "  systemctl --user stop soupawhisper    # Stop"
    echo "  systemctl --user status soupawhisper  # Status"
    echo "  journalctl --user -u soupawhisper -f  # Logs"
}

# Main
main() {
    echo "==================================="
    echo "  SoupaWhisper Installer (venv)"
    echo "==================================="
    echo ""

    install_deps
    install_python
    setup_config

    echo ""
    read -p "Install as systemd service? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_service
    fi

    echo ""
    echo "==================================="
    echo "  Installation complete!"
    echo "==================================="
    echo ""
    echo "To run manually:"
    echo "  $VENV_DIR/bin/python dictate.py"
    echo ""
    echo "Or activate the venv first:"
    echo "  source $VENV_DIR/bin/activate"
    echo "  python dictate.py"
    echo ""
    echo "Config: $CONFIG_DIR/config.ini"
    echo "Hotkey: F12 (hold to record)"
    echo "Exit:   Ctrl+C"
}

main "$@"
