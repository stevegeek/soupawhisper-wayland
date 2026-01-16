#!/bin/bash
# Install SoupaWhisper on Linux
# Supports: Ubuntu, Pop!_OS, Debian, Fedora, Arch
# Supports: X11 and Wayland (including KDE Plasma)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/soupawhisper"
SERVICE_DIR="$HOME/.config/systemd/user"

# Detect session type (X11 or Wayland)
detect_session() {
    if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
    else
        echo "x11"
    fi
}

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
    local session=$(detect_session)

    echo "Detected package manager: $pm"
    echo "Detected session type: $session"
    echo "Installing system dependencies..."

    if [ "$session" = "wayland" ]; then
        case $pm in
            apt)
                sudo apt update
                sudo apt install -y alsa-utils wl-clipboard ydotool libnotify-bin
                ;;
            dnf)
                sudo dnf install -y alsa-utils wl-clipboard ydotool libnotify
                ;;
            pacman)
                sudo pacman -S --noconfirm alsa-utils wl-clipboard ydotool libnotify
                ;;
            zypper)
                sudo zypper install -y alsa-utils wl-clipboard ydotool libnotify-tools
                ;;
            *)
                echo "Unknown package manager. Please install manually:"
                echo "  alsa-utils wl-clipboard ydotool libnotify"
                ;;
        esac

        # Enable ydotool daemon
        echo "Enabling ydotool daemon..."
        systemctl --user enable --now ydotool 2>/dev/null || true

        # Check input group membership
        if ! groups | grep -q '\binput\b'; then
            echo ""
            echo "Adding user to 'input' group for keyboard access..."
            sudo usermod -aG input "$USER"
            echo "NOTE: You need to log out and back in for group changes to take effect."
        fi
    else
        case $pm in
            apt)
                sudo apt update
                sudo apt install -y alsa-utils xclip xdotool libnotify-bin
                ;;
            dnf)
                sudo dnf install -y alsa-utils xclip xdotool libnotify
                ;;
            pacman)
                sudo pacman -S --noconfirm alsa-utils xclip xdotool libnotify
                ;;
            zypper)
                sudo zypper install -y alsa-utils xclip xdotool libnotify-tools
                ;;
            *)
                echo "Unknown package manager. Please install manually:"
                echo "  alsa-utils xclip xdotool libnotify"
                ;;
        esac
    fi
}

# Install Python dependencies
install_python() {
    echo ""
    echo "Installing Python dependencies..."

    if ! command -v poetry &> /dev/null; then
        echo "Poetry not found. Please install Poetry first:"
        echo "  curl -sSL https://install.python-poetry.org | python3 -"
        exit 1
    fi

    poetry install
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

    local session=$(detect_session)
    local venv_path="$SCRIPT_DIR/.venv"

    # Check if venv exists
    if [ ! -d "$venv_path" ]; then
        venv_path=$(poetry env info --path 2>/dev/null || echo "$SCRIPT_DIR/.venv")
    fi

    if [ "$session" = "wayland" ]; then
        cat > "$SERVICE_DIR/soupawhisper.service" << EOF
[Unit]
Description=SoupaWhisper Voice Dictation
After=graphical-session.target
Wants=ydotool.service

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$venv_path/bin/python $SCRIPT_DIR/dictate.py
Restart=on-failure
RestartSec=5

# Wayland environment
Environment=XDG_SESSION_TYPE=wayland
Environment=WAYLAND_DISPLAY=$WAYLAND_DISPLAY

[Install]
WantedBy=default.target
EOF
    else
        # Get current display settings for X11
        local display="${DISPLAY:-:0}"
        local xauthority="${XAUTHORITY:-$HOME/.Xauthority}"

        cat > "$SERVICE_DIR/soupawhisper.service" << EOF
[Unit]
Description=SoupaWhisper Voice Dictation
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$venv_path/bin/python $SCRIPT_DIR/dictate.py
Restart=on-failure
RestartSec=5

# X11 display access
Environment=DISPLAY=$display
Environment=XAUTHORITY=$xauthority

[Install]
WantedBy=default.target
EOF
    fi

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
    echo "  SoupaWhisper Installer"
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
    echo "  poetry run python dictate.py"
    echo ""
    echo "Config: $CONFIG_DIR/config.ini"
    echo "Hotkey: F12 (hold to record)"
    echo "Exit:   Ctrl+C"
}

main "$@"
