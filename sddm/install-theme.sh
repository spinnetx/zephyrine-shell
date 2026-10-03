#!/usr/bin/env bash
# Установка темы SDDM «zephyrine». Запускать с root:  sudo ./install-theme.sh
# Откат на ltmnight:                              sudo ./install-theme.sh --revert
# SDDM НЕ перезапускается: тема применится при следующем выходе из сессии / входе.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/zephyrine"
if [ -f "$HERE/../assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
    VIDEO_SRC="$HERE/../assets/wallpapers/japanese-night-village.1920x1080.mp4"
elif [ -f "/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
    VIDEO_SRC="/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4"
else
    VIDEO_SRC="$HERE/../wallpapers/japanese-night-village.1920x1080.mp4"
fi
# Видео — то, что выбрано в центре настроек (симлинк wallpaper-desktop пользователя, вызвавшего sudo).
# Нет симлинка / битый / выбрана картинка (SDDM-теме нужно видео) — прежнее видео выше.
if [ -n "${SUDO_USER:-}" ]; then
    SEL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    SEL="$(readlink -f -- "$SEL_HOME/.local/state/zephyrine/wallpaper-desktop" 2>/dev/null || true)"
    case "${SEL,,}" in
        *.mp4|*.mkv|*.webm|*.mov|*.avi|*.m4v|*.gif)
            if [ -f "$SEL" ]; then VIDEO_SRC="$SEL"; fi ;;
    esac
fi
DEST="/usr/share/sddm/themes/zephyrine"
FALLBACK_THEME="ltmnight"
NEW_THEME="zephyrine"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Нужны права root: sudo $0 ${1:-}" >&2
    exit 1
fi

# Все файлы SDDM-конфига, где задан Current=
conf_files_with_current() {
    local f
    for f in /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
        [ -f "$f" ] && grep -q '^[[:space:]]*Current=' "$f" && echo "$f"
    done
    return 0
}

set_theme() {
    local theme="$1" f found=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        found=1
        if grep -q "^[[:space:]]*Current=$theme[[:space:]]*$" "$f"; then
            echo "  $f: уже Current=$theme"
            continue
        fi
        # Бэкап НЕ в /etc/sddm.conf.d: SDDM читает там ВСЕ файлы (не только *.conf), и
        # копия со старым Current= перекрыла бы новое значение (так уже случалось).
        mkdir -p /var/backups/sddm-theme
        cp -a "$f" "/var/backups/sddm-theme/$(basename "$f").bak-$STAMP"
        echo "  $f: бэкап -> /var/backups/sddm-theme/$(basename "$f").bak-$STAMP"
        sed -i "s/^[[:space:]]*Current=.*/Current=$theme/" "$f"
        echo "  $f: Current=$theme"
    done < <(conf_files_with_current)
    if [ "$found" -eq 0 ]; then
        mkdir -p /etc/sddm.conf.d
        printf '[Theme]\nCurrent=%s\n' "$theme" > /etc/sddm.conf.d/10-zephyrine-theme.conf
        echo "  создан /etc/sddm.conf.d/10-zephyrine-theme.conf (Current=$theme)"
    fi
}

if [ "${1:-}" = "--revert" ]; then
    echo "==> Откат: Current=$FALLBACK_THEME"
    set_theme "$FALLBACK_THEME"
    echo "Готово. Применится при следующем выходе из сессии / входе (sddm не перезапускался)."
    exit 0
fi

[ -d "$SRC" ] || { echo "Нет каталога темы: $SRC" >&2; exit 1; }
[ -f "$VIDEO_SRC" ] || { echo "Нет видео: $VIDEO_SRC" >&2; exit 1; }

echo "==> Копирую тему в $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -r --no-preserve=ownership,mode "$SRC"/. "$DEST"/
# dev-симлинк/копия видео из каталога разработки не нужна — кладём настоящий файл ниже
rm -f "$DEST/assets/background.mp4" "$DEST/.gitignore"
mkdir -p "$DEST/assets"

echo "==> Копирую видео-фон ($(basename "$VIDEO_SRC")) в $DEST/assets/background.mp4"
echo "    (greeter работает от пользователя sddm и не читает /home/$USER — поэтому копия)"
cp --dereference "$VIDEO_SRC" "$DEST/assets/background.mp4"

echo "==> Права: root:root, каталоги 755, файлы 644"
chown -R root:root "$DEST"
find "$DEST" -type d -exec chmod 755 {} +
find "$DEST" -type f -exec chmod 644 {} +

if id sddm >/dev/null 2>&1 && command -v runuser >/dev/null; then
    if runuser -u sddm -- test -r "$DEST/assets/background.mp4"; then
        echo "    проверка: пользователь sddm читает видео — OK"
    else
        echo "    ВНИМАНИЕ: пользователь sddm НЕ может прочитать видео" >&2
    fi
fi

# Аватар: SDDM берёт его из /usr/share/sddm/faces/<логин>.face.icon (из ~/.face.icon он не прочитает —
# greeter работает от пользователя sddm, а /home закрыт). Файл ~/.face без .icon SDDM не видит.
USER_NAME="${SUDO_USER:-}"
if [ -n "$USER_NAME" ]; then
    USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
    for face in "$USER_HOME/.face.icon" "$USER_HOME/.face"; do
        if [ -f "$face" ]; then
            install -D -m 644 "$face" "/usr/share/sddm/faces/$USER_NAME.face.icon"
            echo "==> Аватар: $face -> /usr/share/sddm/faces/$USER_NAME.face.icon"
            break
        fi
    done
fi

echo "==> Включаю тему в SDDM"
set_theme "$NEW_THEME"

echo
echo "Готово. SDDM не перезапускался — тема применится при следующем выходе из сессии / входе."
echo "Откат: sudo $0 --revert"
