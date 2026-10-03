"""Эмиттер `.config/hypr/settings.lua` (DESIGN §3.9, задача S1.8).

Контракт emit-цели (targets.py): `emit(values, ctx, paths) -> str`, где
  values - плоские эффективные настройки ("appearance.windowRounding" -> 10, ...),
  ctx    - контекст палитры (palette.build_context; здесь нужен только ctx["c"]),
  paths  - util.Paths (не используется).

Файл детерминирован (никаких дат/путей), все строки идут через `lua_str`. Владеет ключами
`decoration.rounding`, `general.border_size`, `general.col.*`, `plugin.hyprglass.glass_opacity`.
При дефолтных настройках значения совпадают с запасными в hyprland.lua, то есть живой
компоситор не меняется (проверяется tests/test_hypr.py и сравнением `hl.get_config`).
"""
import re

from . import autostart, binds, xkb

HEADER = "-- СГЕНЕРИРОВАНО zephyrine-settings из settings/settings.json. Не править вручную."
RGBA_RE = re.compile(r"^rgba\([0-9a-fA-F]{8}\)$")
HEX_RE = re.compile(r"^[0-9a-fA-F]{6}$")

# Запасные значения - ровно текущие в hyprland.lua; нужны, только если ключа нет в values.
DEFAULTS = {
    "appearance.windowRounding": 10,
    "hypr.borders.style": "legacy",
    "hypr.borders.size": 2,
    "hypr.glassOpacity": 0.7,
    "input.layouts": [{"layout": "pl", "variant": ""}, {"layout": "ru", "variant": ""}],
    "input.switchOption": "grp:alt_shift_toggle",
    "input.extraOptions": [],
    "input.repeatRate": 25,
    "input.repeatDelay": 600,
    "autostart": [
        {"id": "telegram", "name": "Telegram", "cmd": "Telegram", "enabled": True, "delaySec": 0},
        {"id": "zen", "name": "Zen Browser", "cmd": "zen-browser", "enabled": True, "delaySec": 0},
        {"id": "viber", "name": "Viber", "cmd": "QT_QPA_PLATFORM=wayland viber", "enabled": True, "delaySec": 5},
    ],
    "appearance.cursor.theme": "Qogir",
    "appearance.cursor.size": 24,
    "apps.terminal": "kitty",
    "apps.fileManager": "thunar",
    "input.sensitivity": 0.0,
    "input.touchpad.naturalScroll": True,
    "input.touchpad.tapToClick": True,
    "input.touchpad.tapAndDrag": True,
    "input.touchpad.disableWhileTyping": True,
    "input.touchpad.clickfinger": True,
    "input.touchpad.middleButtonEmulation": False,
    "input.touchpad.scrollFactor": 1.0,
    "hypr.borders.custom": {
        "active": ["rgba(33ccffee)", "rgba(00ff99ee)"],
        "angle": 45,
        "inactive": "rgba(595959aa)",
    },
}


class HyprError(ValueError):
    """Недопустимое значение настройки (схема должна была его отсечь раньше)."""


def lua_str(value):
    """Строка Lua в двойных кавычках (тот же набор экранирования, что у фильтра `lua_str`, плюс \\n/\\r/\\0)."""
    s = str(value)
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\0", "\\0")
    return '"%s"' % s


def lua_int(value, lo, hi, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
        raise HyprError("%s: нужно целое число, получено %r" % (name, value))
    v = int(value)
    if not lo <= v <= hi:
        raise HyprError("%s: %d вне диапазона %d..%d" % (name, v, lo, hi))
    return "%d" % v


def lua_num(value, lo, hi, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise HyprError("%s: нужно число, получено %r" % (name, value))
    v = float(value)
    if not lo <= v <= hi:
        raise HyprError("%s: %s вне диапазона %s..%s" % (name, v, lo, hi))
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return s if "." in s else s + ".0"


def _rgba(value, name):
    if not isinstance(value, str) or not RGBA_RE.match(value):
        raise HyprError("%s: нужен цвет rgba(rrggbbaa), получено %r" % (name, value))
    return value.lower()


def _hex6(ctx, key):
    v = (ctx.get("c") or {}).get(key)
    if not isinstance(v, str) or not HEX_RE.match(v.lstrip("#")):
        raise HyprError("палитра: нет цвета %s" % key)
    return v.lstrip("#").lower()


def borders(values, ctx):
    """-> (список активных цветов, угол, неактивный цвет) по hypr.borders.style."""
    style = values.get("hypr.borders.style", DEFAULTS["hypr.borders.style"])
    if style == "legacy":
        return ["rgba(33ccffee)", "rgba(00ff99ee)"], 45, "rgba(595959aa)"
    if style == "accent":
        return (["rgba(%see)" % _hex6(ctx, "primary"), "rgba(%see)" % _hex6(ctx, "secondary")], 45,
                "rgba(%saa)" % _hex6(ctx, "outlineVariant"))
    if style == "custom":
        cu = values.get("hypr.borders.custom") or DEFAULTS["hypr.borders.custom"]
        active = cu.get("active")
        if not isinstance(active, list) or not active:
            raise HyprError("hypr.borders.custom.active: нужен непустой список")
        angle = int(lua_int(cu.get("angle", 45), 0, 360, "hypr.borders.custom.angle"))
        return ([_rgba(c, "hypr.borders.custom.active") for c in active], angle,
                _rgba(cu.get("inactive"), "hypr.borders.custom.inactive"))
    raise HyprError("hypr.borders.style: неизвестный стиль %r" % (style,))


def _input_lines(values):
    """Блок `input` - только если клавиатурные настройки отличаются от прописанных в hyprland.lua (pl,ru; Alt+Shift;
    повтор по умолчанию Hyprland 25/600): при дефолтах settings.lua остаётся прежним."""
    keys = ("input.layouts", "input.switchOption", "input.extraOptions", "input.repeatRate", "input.repeatDelay")
    v = {k: values.get(k, DEFAULTS[k]) for k in keys}
    if all(v[k] == DEFAULTS[k] for k in keys):
        return []
    layouts = v["input.layouts"]
    if not isinstance(layouts, list) or not layouts:
        raise HyprError("input.layouts: нужен непустой список")
    for l in layouts:
        if not xkb.LAYOUT_RE.match(str(l.get("layout"))) or not xkb.VARIANT_RE.match(str(l.get("variant", ""))):
            raise HyprError("input.layouts: недопустимая раскладка %r" % (l,))
    switch = v["input.switchOption"]
    extra = v["input.extraOptions"]
    for o in ([switch] if switch else []) + list(extra):
        if not xkb.OPTION_RE.match(str(o)):
            raise HyprError("input: недопустимая xkb-опция %r" % (o,))
    lay, var, opts = xkb.kb_strings(layouts, switch, extra)
    rate = lua_int(v["input.repeatRate"], 1, 100, "input.repeatRate")
    delay = lua_int(v["input.repeatDelay"], 100, 2000, "input.repeatDelay")
    return ["-- Клавиатура (input.*)",
            "hl.config({ input = { kb_layout = %s, kb_variant = %s, kb_options = %s, repeat_rate = %s, repeat_delay = %s } })"
            % (lua_str(lay), lua_str(var), lua_str(opts), rate, delay)]


THEME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+ -]{0,63}$")


def _cursor_lines(values):
    """Переменные курсора - только при отличии от прописанных в hyprland.lua (Qogir, 24): при дефолтах settings.lua прежний.
    Окружение читают программы, запущенные после перезагрузки конфига/входа; Hyprland «на лету» переключает цель `cursor`."""
    theme = values.get("appearance.cursor.theme", DEFAULTS["appearance.cursor.theme"])
    size = values.get("appearance.cursor.size", DEFAULTS["appearance.cursor.size"])
    if theme == DEFAULTS["appearance.cursor.theme"] and size == DEFAULTS["appearance.cursor.size"]:
        return []
    if not isinstance(theme, str) or not THEME_RE.match(theme):
        raise HyprError("appearance.cursor.theme: недопустимое имя темы %r" % (theme,))
    n = lua_int(size, 16, 64, "appearance.cursor.size")
    return ["-- Курсор мыши (appearance.cursor.*)"] + [
        "hl.env(%s, %s)" % (lua_str(k), v)
        for k, v in (("XCURSOR_THEME", lua_str(theme)), ("HYPRCURSOR_THEME", lua_str(theme)),
                     ("XCURSOR_SIZE", lua_str(n)), ("HYPRCURSOR_SIZE", lua_str(n)))]


# ключ настроек -> ключ Hyprland (input.touchpad.*)
TOUCHPAD_KEYS = (
    ("naturalScroll", "natural_scroll"), ("tapToClick", "tap_to_click"), ("tapAndDrag", "tap_and_drag"),
    ("disableWhileTyping", "disable_while_typing"), ("clickfinger", "clickfinger_behavior"),
    ("middleButtonEmulation", "middle_button_emulation"),
)


def _pointer_lines(values):
    """Чувствительность указателя и тачпад - только при отличии от дефолтов (иначе действует hyprland.lua)."""
    keys = ["input.sensitivity", "input.touchpad.scrollFactor"] + ["input.touchpad." + a for a, _ in TOUCHPAD_KEYS]
    v = {k: values.get(k, DEFAULTS[k]) for k in keys}
    if all(v[k] == DEFAULTS[k] for k in keys):
        return []
    for a, _ in TOUCHPAD_KEYS:
        if not isinstance(v["input.touchpad." + a], bool):
            raise HyprError("input.touchpad.%s: нужно true/false" % a)
    tp = ["%s = %s" % (b, "true" if v["input.touchpad." + a] else "false") for a, b in TOUCHPAD_KEYS]
    tp.append("scroll_factor = " + lua_num(v["input.touchpad.scrollFactor"], 0.1, 5.0, "input.touchpad.scrollFactor"))
    return ["-- Указатель и тачпад (input.sensitivity, input.touchpad.*)",
            "hl.config({ input = { sensitivity = %s, touchpad = { %s } } })"
            % (lua_num(v["input.sensitivity"], -1.0, 1.0, "input.sensitivity"), ", ".join(tp))]


def emit(values, ctx, paths=None):
    get = lambda k: values.get(k, DEFAULTS[k])  # noqa: E731
    rounding = lua_int(get("appearance.windowRounding"), 0, 20, "appearance.windowRounding")
    size = lua_int(get("hypr.borders.size"), 0, 4, "hypr.borders.size")
    glass = lua_num(get("hypr.glassOpacity"), 0.3, 1.0, "hypr.glassOpacity")
    active, angle, inactive = borders(values, ctx)
    colors = ", ".join(lua_str(c) for c in active)
    lines = [
        HEADER,
        "hl.config({ decoration = { rounding = %s } })" % rounding,
        "hl.config({ general = { border_size = %s, col = {" % size,
        "    active_border = { colors = { %s }, angle = %d }," % (colors, angle),
        "    inactive_border = %s } } })" % lua_str(inactive),
        "-- hyprglass: ключи плагина есть только после его загрузки",
        "if hl.plugin and hl.plugin.hyprglass then hl.plugin.hyprglass.config({ glass_opacity = %s }) end" % glass,
    ]
    lines.extend(_input_lines(values))
    lines.extend(_pointer_lines(values))
    lines.extend(_cursor_lines(values))
    lines.extend(binds.lua_lines(values, lua_str))
    lines.extend(autostart.lua_lines(values.get("autostart", DEFAULTS["autostart"]), lua_str))
    monitors_list = values.get("display.monitors") or []
    if monitors_list:
        lines.append("-- Мониторы (display.monitors)")
        for m in monitors_list:
            match = m.get("match") or m.get("name") or "eDP-1"
            parts = ["output = " + lua_str(match)]
            if m.get("disabled"):
                parts.append("disabled = true")
            else:
                if m.get("mode"):
                    parts.append("mode = " + lua_str(m["mode"]))
                if m.get("position"):
                    parts.append("position = " + lua_str(m["position"]))
                if m.get("scale") is not None:
                    parts.append("scale = " + lua_num(m["scale"], 0.25, 4.0, "scale"))
                if m.get("transform") is not None:
                    parts.append("transform = %d" % int(m["transform"]))
                if m.get("mirror"):
                    parts.append("mirror = " + lua_str(m["mirror"]))
            lines.append("hl.monitor({ %s })" % ", ".join(parts))
    lines.append("")
    return "\n".join(lines)
