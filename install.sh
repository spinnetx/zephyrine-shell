#!/usr/bin/env bash
#
# install.sh — Инсталлятор оболочки Zephyrine Shell

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODE="system"
INSTALL_SDDM=0

usage() {
    cat <<EOF
Использование: $0 [ПАРАМЕТРЫ]

Параметры:
  --system       Установка в систему (/usr) — требует sudo (по умолчанию)
  --user         Установка в домашний каталог (~/.local) без sudo
  --sddm         Установить и активировать тему SDDM Zephyrine (требует sudo)
  -h, --help     Показать эту справку
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system) MODE="system"; shift ;;
        --user)   MODE="user"; shift ;;
        --sddm)   INSTALL_SDDM=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Неизвестный параметр: $1" >&2; usage >&2; exit 1 ;;
    esac
done

echo "=========================================="
echo "    Установка Zephyrine Shell"
echo "=========================================="
echo "Режим: $MODE"

# 1. Проверка ключевых зависимостей
echo "==> Проверка зависимостей..."
MISSING_DEPS=()
for cmd in Hyprland qs mpvpaper socat jq python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "  [ВНИМАНИЕ] Не найдены следующие программы:" >&2
    for dep in "${MISSING_DEPS[@]}"; do
        echo "    - $dep" >&2
    done
    echo "  Для корректной работы оболочки установите их через ваш пакетный менеджер (pacman/yay/aur)."
    echo
fi

# 2. Выполнение установки
if [ "$MODE" = "system" ]; then
    echo "==> Установка в /usr (требуются права администратора)..."
    sudo make install PREFIX=/usr
else
    echo "==> Установка в $HOME/.local..."
    make user-install
    echo
    echo "ВНИМАНИЕ: Для запуска сессии убедитесь, что $HOME/.local/bin добавлен в ваш PATH,"
    echo "а также скопируйте сессионный файл в /usr/share/wayland-sessions:"
    echo "  sudo cp desktop/zephyrine.desktop /usr/share/wayland-sessions/"
fi

# 3. Установка темы SDDM
if [ "$INSTALL_SDDM" -eq 1 ]; then
    if [ -f "sddm/install-theme.sh" ]; then
        echo "==> Установка темы экрана входа SDDM..."
        sudo ./sddm/install-theme.sh
    fi
fi

echo
echo "=========================================="
echo "  Zephyrine Shell успешно установлен!"
echo "=========================================="
echo "Как запустить:"
echo "  1. Выберите сессию 'Zephyrine' на экране входа (SDDM/GDM)."
echo "  2. Или запустите вручную из tty: zephyrine-session"
echo
echo "Управление оболочкой:"
echo "  - Центр настроек: zephyrine-settings (или SUPER+I)"
echo "  - Лаунчер: SUPER (одиночный) или SUPER+Space"
echo "  - Уведомления: SUPER+N"
echo "  - Меню питания: SUPER+Escape"
echo "  - Экран блокировки: SUPER+L"
echo
