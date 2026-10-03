#!/usr/bin/env bash
# Вспомогательный вывод для виджетов hyprlock.conf (cmd[update:...]).
# Использование: lock-info.sh date | battery | name
case "$1" in
  date)
    # Дата по-русски с заглавной буквы: «Четверг, 1 октября»
    d=$(LC_ALL=ru_RU.UTF-8 date '+%A, %-d %B')
    LC_ALL=ru_RU.UTF-8 printf '%s\n' "${d^}"
    ;;
  battery)
    # Глиф Nerd Font + процент; при зарядке — глиф зарядки
    b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)
    [ -z "$b" ] && exit 0
    c=$(cat "$b/capacity"); s=$(cat "$b/status")
    icons=(f007a f007b f007c f007d f007e f007f f0080 f0081 f0082 f0079)
    i=$(( c / 10 )); [ "$i" -gt 9 ] && i=9
    code=${icons[$i]}
    case "$s" in Charging) code=f0084 ;; esac
    printf "\U000$code %s%%\n" "$c"
    ;;
  name)
    n=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)
    printf '%s\n' "${n:-$USER}"
    ;;
esac
