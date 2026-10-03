#!/usr/bin/env bash
# Обои рабочего стола: mpvpaper на всех мониторах (видео или картинка).
# Файл берётся из симлинка центра настроек (zephyrine-settings, цель wallpaper); нет симлинка или он битый —
# прежнее видео. Симлинк разворачивается здесь (readlink -f), чтобы в командной строке mpvpaper был
# настоящий путь: по нему центр настроек узнаёт, что играет, и перезапускает только при смене.
# Автозапуск — hyprland.lua; перезапуск после смены обоев — `zephyrine-settings wallpaper restart`.
LINK="${ZEPHYRINE_STATE:-$HOME/.local/state/zephyrine}/wallpaper-desktop"
FALLBACK="${ZEPHYRINE_DEFAULT_WALLPAPER:-/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4}"

VIDEO="$(readlink -f -- "$LINK" 2>/dev/null)"
[ -f "$VIDEO" ] || VIDEO="$FALLBACK"

exec mpvpaper -o "no-audio --loop --panscan=1.0 --image-display-duration=inf" ALL "$VIDEO"
