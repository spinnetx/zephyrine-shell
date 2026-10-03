#!/usr/bin/env bash
# Предпросмотр темы zephyrine без установки (запускать внутри графической сессии).
# Окно greeter-а в тестовом режиме: вход не выполняется, питание не работает.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$HERE/zephyrine"
if [ -f "$HERE/../assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
    VIDEO="$HERE/../assets/wallpapers/japanese-night-village.1920x1080.mp4"
elif [ -f "/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4" ]; then
    VIDEO="/usr/share/zephyrine/assets/wallpapers/japanese-night-village.1920x1080.mp4"
else
    VIDEO="$HERE/../assets/wallpapers/japanese-night-village.1920x1080.mp4"
fi

# В тестовом режиме видео берётся из каталога темы — кладём dev-симлинк
# (файл assets/background.mp4 не коммитить, он в .gitignore темы).
mkdir -p "$THEME/assets"
ln -sfn "$(readlink -f "$VIDEO")" "$THEME/assets/background.mp4"

GREETER="$(command -v sddm-greeter-qt6 || command -v sddm-greeter || true)"
[ -n "$GREETER" ] || { echo "sddm-greeter-qt6 / sddm-greeter не найден" >&2; exit 1; }

echo "Запуск: $GREETER --test-mode --theme $THEME"
exec "$GREETER" --test-mode --theme "$THEME"
