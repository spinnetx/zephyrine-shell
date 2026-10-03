#!/usr/bin/env bash
# Лимиты Claude Code / agy (Gemini) для виджета Limits Quickshell-бара:
# quickshell/services/AiUsage.qml вызывает этот скрипт асинхронно.
# Логика парсинга взята из ~/.config/kargos/ai-limits.2m.sh (там она
# рассчитана на Argos/xbar-разметку), здесь переработана под JSON
# ({"text","tooltip","class"}).
#
# Использование: ai-usage-widget.sh claude|agy

target="$1"
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin:$PATH"
export NO_COLOR=1

strip_ansi() { sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g'; }

# Возвращает css-класс по проценту использования (>=85 critical, >=60 warning)
class_for() {
    local val="$1"
    [ -z "$val" ] || [ "$val" = "N/A" ] && return
    if [ "$val" -ge 85 ] 2>/dev/null; then echo "critical"
    elif [ "$val" -ge 60 ] 2>/dev/null; then echo "warning"
    fi
}

# Формат {text, tooltip, class} — то, что напрямую разбирает
# виджет Limits (quickshell/services/AiUsage.qml, JSON на stdout).
emit() {
    jq -nc --arg text "$1" --arg tooltip "$2" --arg class "$3" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

case "$target" in
claude)
    # `claude -p "/usage"` теперь работает headless и отдаёт реальные цифры
    # (перепроверено 2026-09-12 на CLI 2.1.251) — не расходует ни лимит, ни
    # счётчик запросов (3 вызова подряд: тайминг стабильно ~1.9с, счётчик
    # Last 24h/7d requests не менялся, проценты не двигались — похоже на
    # отдельный лёгкий эндпоинт метаданных, а не completion). Раньше это не
    # работало (см. историю в CONTEXT.md), тогда завели обход через кэш-файл
    # от statusLine — тот механизм оставлен только для строки статуса самого
    # CLI (scripts/claude-statusline.sh), виджет от него больше не зависит.
    BIN=$(command -v claude 2>/dev/null)
    if [ -z "$BIN" ]; then
        emit "✳ N/A" "claude CLI не найден в PATH" ""
        exit 0
    fi

    RAW=$(timeout 15s "$BIN" -p "/usage" < /dev/null 2>&1 | strip_ansi)

    # Строки вида:
    # "Current session: 16% used · resets Sep 13, 12:40am (Europe/Warsaw)"
    # "Current week (all models): 19% used · resets Sep 16, 12pm (Europe/Warsaw)"
    FIVE_PCT=$(printf '%s\n' "$RAW" | grep -m1 '^Current session:' | grep -oE '[0-9]+% used' | grep -oE '^[0-9]+')
    FIVE_RESET_RAW=$(printf '%s\n' "$RAW" | grep -m1 '^Current session:' | sed -E 's/^.*resets //')
    WEEK_PCT=$(printf '%s\n' "$RAW" | grep -m1 '^Current week' | grep -oE '[0-9]+% used' | grep -oE '^[0-9]+')
    WEEK_RESET_RAW=$(printf '%s\n' "$RAW" | grep -m1 '^Current week' | sed -E 's/^.*resets //')

    [ -z "$FIVE_PCT" ] && FIVE_PCT="N/A"
    [ -z "$WEEK_PCT" ] && WEEK_PCT="N/A"

    # "Sep 13, 12:40am (Europe/Warsaw)" -> "Sep 13 12:40 am" (без запятой/tz,
    # пробел перед am/pm) — иначе GNU date отказывается это парсить.
    # LC_ALL=C — чтобы английское имя месяца распозналось независимо от локали.
    fmt_reset() {
        local raw="$1" cleaned
        [ -z "$raw" ] && { echo "N/A"; return; }
        cleaned=$(printf '%s' "$raw" | sed -E 's/\s*\([^)]*\)\s*$//; s/,//; s/([0-9])(am|pm)/\1 \2/')
        LC_ALL=C date -d "$cleaned" +"%d.%m %H:%M" 2>/dev/null || echo "N/A"
    }
    FIVE_RESET_FMT=$(fmt_reset "$FIVE_RESET_RAW")
    WEEK_RESET_FMT=$(fmt_reset "$WEEK_RESET_RAW")

    TEXT="✳ ${FIVE_PCT}%"
    TOOLTIP=$(printf 'Claude Code\n5ч сессия: %s%% (сброс: %s)\nНеделя: %s%% (сброс: %s)' \
        "$FIVE_PCT" "$FIVE_RESET_FMT" "$WEEK_PCT" "$WEEK_RESET_FMT")
    emit "$TEXT" "$TOOLTIP" "$(class_for "$FIVE_PCT")"
    ;;

agy)
    BIN=$(command -v agy 2>/dev/null)
    if [ -z "$BIN" ]; then
        emit "✦ N/A" "agy CLI не найден в PATH" ""
        exit 0
    fi

    RAW=$(timeout 15s "$BIN" -p "/usage" < /dev/null 2>&1 | strip_ansi)

    G_5H_REMAIN=$(printf '%s\n' "$RAW" | awk -F'\t' '$1=="Gemini Models" && $2 ~ /Five Hour/ {print $3}' | tr -d '%' | head -n1)
    G_5H_RESET_RAW=$(printf '%s\n' "$RAW" | awk -F'\t' '$1=="Gemini Models" && $2 ~ /Five Hour/ {print $4}' | head -n1)
    G_7D_REMAIN=$(printf '%s\n' "$RAW" | awk -F'\t' '$1=="Gemini Models" && $2 ~ /Weekly/ {print $3}' | tr -d '%' | head -n1)
    G_7D_RESET_RAW=$(printf '%s\n' "$RAW" | awk -F'\t' '$1=="Gemini Models" && $2 ~ /Weekly/ {print $4}' | head -n1)

    if [ -n "$G_5H_REMAIN" ]; then G_5H_PCT=$(( 100 - G_5H_REMAIN )); else G_5H_PCT="N/A"; fi
    if [ -n "$G_7D_REMAIN" ]; then G_7D_PCT=$(( 100 - G_7D_REMAIN )); else G_7D_PCT="N/A"; fi

    fmt_reset() {
        local ts="$1"
        [ -z "$ts" ] && { echo "N/A"; return; }
        timeout 5s date -d "$ts" +"%d.%m %H:%M" 2>/dev/null || echo "N/A"
    }
    G_5H_RESET=$(fmt_reset "$G_5H_RESET_RAW")
    G_7D_RESET=$(fmt_reset "$G_7D_RESET_RAW")

    TEXT="✦ ${G_5H_PCT}%"
    TOOLTIP=$(printf 'Gemini Pro (agy)\n5ч окно: %s%% (сброс: %s)\nНеделя: %s%% (сброс: %s)' \
        "$G_5H_PCT" "$G_5H_RESET" "$G_7D_PCT" "$G_7D_RESET")
    emit "$TEXT" "$TOOLTIP" "$(class_for "$G_5H_PCT")"
    ;;

*)
    emit "?" "usage: ai-usage-widget.sh claude|agy" ""
    ;;
esac
