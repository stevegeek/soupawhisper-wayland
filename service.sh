#!/bin/bash
# SoupaWhisper service control script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="soupawhisper"

# Detect session type
detect_session() {
    if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
    else
        echo "x11"
    fi
}

install_service() {
    echo "Installing SoupaWhisper service..."
    mkdir -p "$SERVICE_DIR"

    local session=$(detect_session)
    local venv_path="$SCRIPT_DIR/.venv"

    if [ ! -d "$venv_path" ]; then
        echo "Error: Virtual environment not found at $venv_path"
        echo "Run 'poetry install' first."
        exit 1
    fi

    if [ "$session" = "wayland" ]; then
        cat > "$SERVICE_DIR/$SERVICE_NAME.service" << EOF
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
Environment=WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

[Install]
WantedBy=default.target
EOF
    else
        cat > "$SERVICE_DIR/$SERVICE_NAME.service" << EOF
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
Environment=DISPLAY=${DISPLAY:-:0}
Environment=XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}

[Install]
WantedBy=default.target
EOF
    fi

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"
    echo "Service installed and enabled."
    echo "Run '$0 start' to start it."
}

uninstall_service() {
    echo "Uninstalling SoupaWhisper service..."
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null
    rm -f "$SERVICE_DIR/$SERVICE_NAME.service"
    systemctl --user daemon-reload
    echo "Service uninstalled."
}

case "${1:-}" in
    install)
        install_service
        ;;
    uninstall)
        uninstall_service
        ;;
    start)
        systemctl --user start "$SERVICE_NAME"
        echo "SoupaWhisper started."
        ;;
    stop)
        systemctl --user stop "$SERVICE_NAME"
        echo "SoupaWhisper stopped."
        ;;
    restart)
        systemctl --user restart "$SERVICE_NAME"
        echo "SoupaWhisper restarted."
        ;;
    status)
        systemctl --user status "$SERVICE_NAME" --no-pager
        ;;
    logs)
        journalctl --user -u "$SERVICE_NAME" -f
        ;;
    *)
        echo "SoupaWhisper Service Control"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  install    Install and enable the systemd service"
        echo "  uninstall  Remove the systemd service"
        echo "  start      Start the service"
        echo "  stop       Stop the service"
        echo "  restart    Restart the service"
        echo "  status     Show service status"
        echo "  logs       Follow service logs"
        exit 1
        ;;
esac
