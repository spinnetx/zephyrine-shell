"""Генерация секций hypridle.conf (DESIGN §3.2, §4.3, §9.4 D3).

Модуль строит блоки слушателей (listener) для hypridle.conf:
- Затемнение экрана (dimSec, dimLevel)
- Автоблокировка (lockSec)
- Гашение экрана через DPMS (dpmsSec)
- Сон / suspend (suspendSec)

При значениях по умолчанию вывод байт-в-байт равен tests/golden/hypridle/hypridle.conf.
"""

GOLDEN_LOCK = (
    "# Автолок по бездействию отключён (2026-09-12) — пользователь хочет\n"
    "# блокировать экран исключительно вручную (SUPER+L). Было: ~5 минут бездействия -> блокировка тем же вызовом.\n"
    "# Раскомментировать, если понадобится обратно:\n"
    "# listener {\n"
    "#     timeout = 300\n"
    "#     on-timeout = loginctl lock-session\n"
    "# }"
)

GOLDEN_SUSPEND = (
    "# Suspend по таймауту отключён по умолчанию: сценарий десктопный (ноутбук\n"
    "# закрыт/используется с внешним монитором DP-6, крышка обычно не закрыта),\n"
    "# и агрессивный auto-suspend там нежелателен. Раскомментируйте и подберите\n"
    "# таймаут сами, если нужно:\n"
    "# listener {\n"
    "#     timeout = 1800\n"
    "#     on-timeout = systemctl suspend\n"
    "# }"
)


def fmt_mins(sec):
    """Форматирование секунд в человекочитаемые минуты на русском."""
    m = sec / 60.0
    if m == int(m):
        m_int = int(m)
        if m_int % 10 == 1 and m_int % 100 != 11:
            word = "минута"
        elif 2 <= m_int % 10 <= 4 and (m_int % 100 < 10 or m_int % 100 >= 20):
            word = "минуты"
        else:
            word = "минут"
        return "%d %s" % (m_int, word)
    else:
        s = ("%.1f" % m).rstrip("0").rstrip(".")
        return "%s минуты" % s


def build_idle_context(values):
    """Построение словаря idle.* для контекста рендера шаблонов."""
    dim_sec = values.get("power.idle.dimSec")
    dim_level = values.get("power.idle.dimLevel", "10%")
    # Допускаем число или строку (например "10" -> "10%")
    if isinstance(dim_level, (int, float)):
        dim_level = "%d%%" % int(dim_level)
    elif str(dim_level).isdigit():
        dim_level = str(dim_level) + "%"

    lock_sec = values.get("power.idle.lockSec")
    dpms_sec = values.get("power.idle.dpmsSec")
    suspend_sec = values.get("power.idle.suspendSec")

    # 1. Dim listener
    if dim_sec and int(dim_sec) > 0:
        mins_str = fmt_mins(int(dim_sec))
        dim_block = (
            "# ~%s бездействия — плавное затемнение подсветки (ноутбучный экран).\n"
            "# Восстанавливаем яркость при любой активности (resume).\n"
            "listener {\n"
            "    timeout = %d\n"
            "    on-timeout = brightnessctl -s set %s\n"
            "    on-resume = brightnessctl -r\n"
            "}" % (mins_str, int(dim_sec), dim_level)
        )
    else:
        dim_block = (
            "# Затемнение подсветки по бездействию отключено:\n"
            "# listener {\n"
            "#     timeout = 150\n"
            "#     on-timeout = brightnessctl -s set 10%\n"
            "#     on-resume = brightnessctl -r\n"
            "# }"
        )

    # 2. Lock listener
    if lock_sec and int(lock_sec) > 0:
        mins_str = fmt_mins(int(lock_sec))
        lock_block = (
            "# Автолок по бездействию через ~%s:\n"
            "listener {\n"
            "    timeout = %d\n"
            "    on-timeout = loginctl lock-session\n"
            "}" % (mins_str, int(lock_sec))
        )
    else:
        lock_block = GOLDEN_LOCK

    # 3. DPMS listener
    if dpms_sec and int(dpms_sec) > 0:
        mins_str = fmt_mins(int(dpms_sec))
        dpms_block = (
            "# ~%s — гасим экран через dpms, включаем обратно при любой активности.\n"
            "listener {\n"
            "    timeout = %d\n"
            "    on-timeout = hyprctl dispatch \"hl.dsp.dpms({action=\\\"off\\\"})\"\n"
            "    on-resume = hyprctl dispatch \"hl.dsp.dpms({action=\\\"on\\\"})\"\n"
            "}" % (mins_str, int(dpms_sec))
        )
    else:
        dpms_block = (
            "# Гашение экрана через dpms отключено:\n"
            "# listener {\n"
            "#     timeout = 330\n"
            "#     on-timeout = hyprctl dispatch \"hl.dsp.dpms({action=\\\"off\\\"})\"\n"
            "#     on-resume = hyprctl dispatch \"hl.dsp.dpms({action=\\\"on\\\"})\"\n"
            "# }"
        )

    # 4. Suspend listener
    if suspend_sec and int(suspend_sec) > 0:
        mins_str = fmt_mins(int(suspend_sec))
        suspend_block = (
            "# Сон (suspend) через ~%s:\n"
            "listener {\n"
            "    timeout = %d\n"
            "    on-timeout = systemctl suspend\n"
            "}" % (mins_str, int(suspend_sec))
        )
    else:
        suspend_block = GOLDEN_SUSPEND

    return {
        "dimSec": dim_sec,
        "dimLevel": dim_level,
        "lockSec": lock_sec,
        "dpmsSec": dpms_sec,
        "suspendSec": suspend_sec,
        "dimBlock": dim_block,
        "lockBlock": lock_block,
        "dpmsBlock": dpms_block,
        "suspendBlock": suspend_block,
    }
