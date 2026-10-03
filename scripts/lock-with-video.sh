#!/usr/bin/env bash
# Экран блокировки с видео: hyprlock с прозрачным фоном + копия видео-обоев на слое overlay.
# Работает благодаря misc.session_lock_xray = true в hyprland.lua (Hyprland продолжает рисовать
# слои под lock-сюрфейсом). Приём: github.com/Jack02134x/hyprlock-mp4-guide.
#
# Порядок: сначала поднимается видео и ждём, пока оно реально появилось на экране (слой overlay на
# каждом мониторе + mpv отдал первый кадр), и только потом hyprlock — иначе на первых долях секунды
# под lock-сюрфейсом виден рабочий стол. Ожидание ограничено (MAX_WAIT), блокировку оно не задерживает
# дольше: если видео не поднялось — hyprlock стартует всё равно.
# Убивается только собственная копия mpvpaper — обои на слое background не трогаем.
# LOCK_DRYRUN=1 — только поднять видео и залогировать тайминги, hyprlock не запускать (для проверки).
pidof hyprlock >/dev/null && exit 0

# Файл — симлинк центра настроек (zephyrine-settings, цель wallpaper); нет/битый — прежнее видео.
VIDEO="$(readlink -f -- "${ZEPHYRINE_STATE:-$HOME/.local/state/zephyrine}/wallpaper-lock" 2>/dev/null)"
if [ ! -f "$VIDEO" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -n "${ZEPHYRINE_DEFAULT_WALLPAPER:-}" ] && [ -f "$ZEPHYRINE_DEFAULT_WALLPAPER" ]; then
        VIDEO="$ZEPHYRINE_DEFAULT_WALLPAPER"
    elif [ -f "$SCRIPT_DIR/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
        VIDEO="$SCRIPT_DIR/wallpapers/japanese-night-village.1920x1080.mp4"
    elif [ -f "$SCRIPT_DIR/assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
        VIDEO="$SCRIPT_DIR/assets/wallpapers/japanese-night-village.1920x1080.mp4"
    elif [ -f "/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
        VIDEO="/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4"
    fi
fi
SOCK="${XDG_RUNTIME_DIR:-/tmp}/lock-video.sock"
MAX_WAIT=30          # × 0.1 с = 3 с
LOG="${XDG_RUNTIME_DIR:-/tmp}/lock-video.log"
rm -f "$SOCK"

start=$(date +%s.%N)
mpvpaper -l overlay -o "no-audio loop --panscan=1.0 --image-display-duration=inf input-ipc-server=$SOCK" ALL "$VIDEO" &
MPV_PID=$!

monitors=$(hyprctl monitors -j | jq 'length')

overlay_ready() {   # слой mpvpaper на уровне overlay (3) на каждом мониторе
    [ "$(hyprctl layers -j | jq '[.[] | .levels["3"][]? | select(.namespace == "mpvpaper")] | length')" -ge "$monitors" ]
}
is_image() {        # картинка вместо видео: у неё нет playback-time, ждём только слой
    case "${VIDEO,,}" in *.png|*.jpg|*.jpeg|*.webp|*.bmp) return 0 ;; esac
    return 1
}
frame_ready() {     # mpv уже проигрывает: playback-time > 0
    is_image && return 0
    [ -S "$SOCK" ] || return 1
    local t
    t=$(echo '{"command":["get_property","playback-time"]}' | socat -t0.2 - "$SOCK" 2>/dev/null | jq -r '.data // empty' 2>/dev/null)
    [ -n "$t" ] && awk -v t="$t" 'BEGIN{exit !(t > 0)}'
}

ok=timeout
for _ in $(seq "$MAX_WAIT"); do
    if overlay_ready && frame_ready; then ok=ready; break; fi
    sleep 0.1
done
sleep 0.15          # запас на коммит кадра композитором
echo "$(date +%T) video $ok in $(awk -v s="$start" -v e="$(date +%s.%N)" 'BEGIN{printf "%.2f", e-s}') s" >> "$LOG"

if [ -n "${LOCK_DRYRUN:-}" ]; then sleep 2; else hyprlock; fi

kill "$MPV_PID" 2>/dev/null
rm -f "$SOCK"
