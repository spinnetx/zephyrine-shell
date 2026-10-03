#!/usr/bin/env bash
# Запуск приложения по умолчанию для категории (terminal | files | browser)
# Использует выбор из центра настроек (xdg-mime / gio mime / mimeapps.list)
set -euo pipefail

CATEGORY="${1:-terminal}"
shift || true

get_default_desktop() {
    local mime="$1"
    local app=""
    if command -v xdg-mime >/dev/null 2>&1; then
        app="$(xdg-mime query default "$mime" 2>/dev/null || true)"
    fi
    if [ -z "$app" ] && command -v gio >/dev/null 2>&1; then
        app="$(gio mime "$mime" 2>/dev/null | awk -F': ' '/Приложение по умолчанию|Default application/ {gsub(/[ \t]/, "", $2); print $2}')"
    fi
    if [ -z "$app" ] && [ -f "$HOME/.config/mimeapps.list" ]; then
        app="$(grep -m1 "^${mime}=" "$HOME/.config/mimeapps.list" 2>/dev/null | cut -d= -f2- | cut -d';' -f1 || true)"
    fi
    echo "$app"
}

launch_desktop() {
    local desktop="$1"
    shift
    if [ -n "$desktop" ]; then
        if command -v gtk-launch >/dev/null 2>&1; then
            exec gtk-launch "$desktop" "$@"
        fi
        for dir in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do
            if [ -f "$dir/$desktop" ]; then
                local cmd
                cmd="$(grep -m1 '^Exec=' "$dir/$desktop" | cut -d= -f2- | sed -E 's/%[a-zA-Z]//g' | xargs)"
                if [ -n "$cmd" ]; then
                    exec $cmd "$@"
                fi
            fi
        done
    fi
}

case "$CATEGORY" in
    terminal)
        APP="$(get_default_desktop "x-scheme-handler/terminal")"
        if [ -n "$APP" ]; then
            launch_desktop "$APP" "$@"
        fi
        for t in x-terminal-emulator kitty alacritty foot wezterm xterm; do
            if command -v "$t" >/dev/null 2>&1; then
                exec "$t" "$@"
            fi
        done
        ;;
    files|fileManager)
        APP="$(get_default_desktop "inode/directory")"
        TARGET="${1:-$HOME}"
        if [ -n "$APP" ]; then
            launch_desktop "$APP" "$TARGET"
        fi
        for fm in thunar nautilus nemo dolphin pcmanfm; do
            if command -v "$fm" >/dev/null 2>&1; then
                exec "$fm" "$TARGET"
            fi
        done
        exec xdg-open "$TARGET"
        ;;
    browser)
        APP="$(get_default_desktop "x-scheme-handler/https")"
        [ -z "$APP" ] && APP="$(get_default_desktop "text/html")"
        TARGET="${1:-about:blank}"
        if [ -n "$APP" ]; then
            launch_desktop "$APP" "$TARGET"
        fi
        if command -v xdg-open >/dev/null 2>&1; then
            exec xdg-open "$TARGET"
        fi
        for b in zen-browser firefox google-chrome-stable chromium; do
            if command -v "$b" >/dev/null 2>&1; then
                exec "$b" "$TARGET"
            fi
        done
        ;;
    *)
        echo "Неизвестная категория: $CATEGORY (ожидалось: terminal | files | browser)" >&2
        exit 1
        ;;
esac
