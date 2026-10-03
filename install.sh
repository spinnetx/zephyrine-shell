#!/usr/bin/env bash
#
# install.sh — Инсталлятор оболочки Zephyrine Shell

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ACTION="install"
MODE=""
INSTALL_SDDM=0
PURGE=0

usage() {
    cat <<EOF
Использование: $0 [ПАРАМЕТРЫ]

Параметры установки:
  --system       Установка в систему (/usr) — требует sudo (по умолчанию)
  --user         Установка в домашний каталог (~/.local) без sudo
  --sddm         Установить и активировать тему SDDM Zephyrine (требует sudo)

Параметры удаления:
  --uninstall    Удалить Zephyrine Shell (из системы или ~/.local)
  --purge        Вместе с --uninstall удалить пользовательские настройки (~/.config/zephyrine) и кэш
  --sddm         Вместе с --uninstall откатить тему SDDM (требует sudo)

Общие параметры:
  -h, --help     Показать эту справку
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) ACTION="uninstall"; shift ;;
        --purge)     PURGE=1; shift ;;
        --system)    MODE="system"; shift ;;
        --user)      MODE="user"; shift ;;
        --sddm)      INSTALL_SDDM=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Неизвестный параметр: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# 1. Режим деинсталляции
if [ "$ACTION" = "uninstall" ]; then
    echo "=========================================="
    echo "    Удаление Zephyrine Shell"
    echo "=========================================="
    
    if [ -z "$MODE" ]; then
        if [ -f "/usr/bin/zephyrine-session" ]; then
            MODE="system"
        elif [ -f "$HOME/.local/bin/zephyrine-session" ]; then
            MODE="user"
        else
            MODE="system"
        fi
    fi
    echo "Режим удаления: $MODE"

    if [ "$MODE" = "system" ]; then
        echo "==> Удаление из /usr (требуются права администратора)..."
        sudo make uninstall PREFIX=/usr
    else
        echo "==> Удаление из $HOME/.local..."
        make user-uninstall
    fi

    if [ "$INSTALL_SDDM" -eq 1 ] || [ -d "/usr/share/sddm/themes/zephyrine" ]; then
        if [ -f "sddm/install-theme.sh" ]; then
            echo "==> Откат темы экрана входа SDDM..."
            sudo ./sddm/install-theme.sh --revert || true
        fi
    fi

    if [ "$PURGE" -eq 1 ]; then
        echo "==> Очистка пользовательских настроек и кэша (--purge)..."
        rm -rf "$HOME/.config/zephyrine"
        rm -rf "$HOME/.local/state/zephyrine"
        rm -rf "$HOME/.cache/zephyrine"
        if [ -L "$HOME/.config/quickshell/zephyrine" ]; then
            rm -f "$HOME/.config/quickshell/zephyrine"
        fi
        echo "  Удалены конфигурационные файлы: ~/.config/zephyrine, ~/.local/state/zephyrine"
    else
        echo
        echo "Примечание: Пользовательские настройки сохранены в ~/.config/zephyrine."
        echo "Для полной очистки запустите: $0 --uninstall --purge"
    fi

    echo
    echo "=========================================="
    echo "  Zephyrine Shell успешно удалён!"
    echo "=========================================="
    exit 0
fi

# 2. Режим установки
if [ -z "$MODE" ]; then
    MODE="system"
fi

echo "=========================================="
echo "    Установка Zephyrine Shell"
echo "=========================================="
echo "Режим: $MODE"

# Проверка утилиты сборки make
if ! command -v make >/dev/null 2>&1; then
    echo "  [ОШИБКА] Утилита make не найдена. Установите пакет base-devel или make." >&2
    exit 1
fi

# 2. Проверка ключевых и рекомендуемых зависимостей
echo "==> Проверка зависимостей..."
CORE_DEPS=(
    "Hyprland:hyprland"
    "qs:quickshell"
    "mpvpaper:mpvpaper (AUR)"
    "hyprlock:hyprlock"
    "hypridle:hypridle"
    "wpctl:wireplumber"
    "brightnessctl:brightnessctl"
    "playerctl:playerctl"
    "socat:socat"
    "jq:jq"
    "python3:python"
    "luac:lua"
)

MISSING_CORE=()
for item in "${CORE_DEPS[@]}"; do
    cmd="${item%%:*}"
    pkg="${item##*:}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_CORE+=("$cmd ($pkg)")
    fi
done

if [ ${#MISSING_CORE[@]} -gt 0 ]; then
    echo "  [ВНИМАНИЕ] Не найдены следующие обязательные компоненты:" >&2
    for dep in "${MISSING_CORE[@]}"; do
        echo "    - $dep" >&2
    done
    echo "  Установите их для корректной работы оболочки (pacman/yay)." >&2
    echo
fi

OPT_DEPS=(
    "nmcli:networkmanager"
    "bluetoothctl:bluez-utils"
    "powerprofilesctl:power-profiles-daemon"
    "grim:grim"
    "slurp:slurp"
    "satty:satty"
    "ffmpeg:ffmpeg"
    "wl-copy:wl-clipboard"
)
MISSING_OPT=()
for item in "${OPT_DEPS[@]}"; do
    cmd="${item%%:*}"
    pkg="${item##*:}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_OPT+=("$cmd ($pkg)")
    fi
done

if [ ${#MISSING_OPT[@]} -gt 0 ]; then
    echo "  [ИНФОРМАЦИЯ] Рекомендуемые пакеты (опционально):"
    for dep in "${MISSING_OPT[@]}"; do
        echo "    - $dep"
    done
    echo
fi

# 3. Выполнение установки
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

# 4. Установка темы SDDM
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
echo "  - Центр управления: zephyrine-settings (или SUPER+I)"
echo "  - Лаунчер: SUPER (одиночный) или SUPER+Space"
echo "  - Уведомления: SUPER+N"
echo "  - Меню питания: SUPER+Escape"
echo "  - Экран блокировки: SUPER+L"
echo
