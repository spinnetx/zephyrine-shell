#!/usr/bin/env bash
# Обои рабочего стола: mpvpaper на всех мониторах (видео или картинка).
# Файл берётся из симлинка центра настроек (zephyrine-settings, цель wallpaper); нет симлинка или он битый —
# прежнее видео. Симлинк разворачивается здесь (readlink -f), чтобы в командной строке mpvpaper был
# настоящий путь: по нему центр настроек узнаёт, что играет, и перезапускает только при смене.
# Автозапуск — hyprland.lua; перезапуск после смены обоев — `zephyrine-settings wallpaper restart`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FALLBACK=""
if [ -n "${ZEPHYRINE_DEFAULT_WALLPAPER:-}" ] && [ -f "$ZEPHYRINE_DEFAULT_WALLPAPER" ]; then
    FALLBACK="$ZEPHYRINE_DEFAULT_WALLPAPER"
elif [ -f "$SCRIPT_DIR/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
    FALLBACK="$SCRIPT_DIR/wallpapers/japanese-night-village.1920x1080.mp4"
elif [ -f "$SCRIPT_DIR/assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
    FALLBACK="$SCRIPT_DIR/assets/wallpapers/japanese-night-village.1920x1080.mp4"
elif [ -f "/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
    FALLBACK="/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4"
fi

LINK="${ZEPHYRINE_STATE:-$HOME/.local/state/zephyrine}/wallpaper-desktop"
VIDEO="$(readlink -f -- "$LINK" 2>/dev/null)"
[ -f "$VIDEO" ] || VIDEO="$FALLBACK"

exec mpvpaper -o "no-audio --loop --panscan=1.0 --image-display-duration=inf" ALL "$VIDEO"
