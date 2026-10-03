"""Раскладки и опции xkb для раздела «Клавиатура» (DESIGN §4.4, Y1).

Источник - /usr/share/X11/xkb/rules/base.lst (секции `! layout`, `! variant`, `! option`). Если файла нет, проверять
нечем: допустимыми считаются значения нормального вида (см. *_RE), чтобы settings.lua всё равно оставался безопасным.
Ключи: input.layouts [{layout, variant}], input.switchOption (grp:*), input.extraOptions [строки]. Эмиттер - hypr.py.
"""
import re

BASE_LST = "/usr/share/X11/xkb/rules/base.lst"
LAYOUT_RE = re.compile(r"^[a-z][a-z0-9_]*$")
VARIANT_RE = re.compile(r"^[A-Za-z0-9_\-]*$")
OPTION_RE = re.compile(r"^[a-z0-9_]+:[A-Za-z0-9_\-.]+$")
KEYS = ("input.layouts", "input.switchOption", "input.extraOptions")


def parse(text):
    """-> {"layouts": [{id, desc}], "variants": {layout: [{id, desc}]}, "options": [{id, desc}]}."""
    out = {"layouts": [], "variants": {}, "options": []}
    section = None
    for ln in (text or "").splitlines():
        if ln.startswith("!"):
            section = ln[1:].strip()
            continue
        if not ln.strip() or section is None:
            continue
        if section == "layout":
            m = re.match(r"^\s+(\S+)\s+(.*)$", ln)
            if m:
                out["layouts"].append({"id": m.group(1), "desc": m.group(2).strip()})
        elif section == "variant":
            m = re.match(r"^\s+(\S+)\s+(\S+):\s*(.*)$", ln)
            if m:
                out["variants"].setdefault(m.group(2), []).append({"id": m.group(1), "desc": m.group(3).strip()})
        elif section == "option":
            m = re.match(r"^\s+(\S+)\s+(.*)$", ln)
            if m and ":" in m.group(1):   # заголовки групп (`grp`, `caps`) без двоеточия пропускаем
                out["options"].append({"id": m.group(1), "desc": m.group(2).strip()})
    return out


def load(path=BASE_LST):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return parse(f.read())
    except OSError:
        return None


def catalog(path=BASE_LST):
    """Для UI: списки + разделение опций на переключатели (grp:*) и прочие."""
    data = load(path)
    if data is None:
        return None
    opts = data["options"]
    return {"layouts": data["layouts"], "variants": data["variants"],
            "switchOptions": [o for o in opts if o["id"].startswith("grp:")],
            "options": [o for o in opts if not o["id"].startswith("grp:")]}


def kb_strings(layouts, switch, extra):
    """-> (kb_layout, kb_variant, kb_options) для Hyprland."""
    lay = ",".join(l["layout"] for l in layouts)
    var = ",".join(l.get("variant", "") for l in layouts)
    if not any(l.get("variant") for l in layouts):
        var = ""
    opts = ([switch] if switch else []) + list(extra)
    return lay, var, ",".join(opts)


def check_values(schema, flat, changed, path=BASE_LST):
    """Семантическая проверка перед записью settings.json -> [{"key", "error"}] (значения вне схемы типов)."""
    if not any(k in changed for k in KEYS):
        return []
    get = lambda k: flat[k] if k in flat else schema.default(k)  # noqa: E731
    layouts, switch, extra = get("input.layouts"), get("input.switchOption"), get("input.extraOptions")
    data = load(path)
    errors = []
    ids = {x["id"] for x in data["layouts"]} if data else None
    seen = set()
    for i, l in enumerate(layouts):
        name, var = l["layout"], l.get("variant", "")
        key = "input.layouts"
        if not LAYOUT_RE.match(name) or (ids is not None and name not in ids):
            errors.append({"key": key, "error": "unknown layout: %s" % name})
        elif not VARIANT_RE.match(var) or (var and data is not None
                                           and var not in {v["id"] for v in data["variants"].get(name, [])}):
            errors.append({"key": key, "error": "unknown variant %r for layout %s" % (var, name)})
        if (name, var) in seen:
            errors.append({"key": key, "error": "duplicate layout: %s" % name})
        seen.add((name, var))
    opt_ids = {o["id"] for o in data["options"]} if data else None
    if switch and (not switch.startswith("grp:") or (opt_ids is not None and switch not in opt_ids)):
        errors.append({"key": "input.switchOption", "error": "unknown layout switch option: %s" % switch})
    if len(layouts) >= 2 and not switch:
        errors.append({"key": "input.switchOption", "error": "a switch option is required with 2+ layouts"})
    for o in extra:
        if not OPTION_RE.match(o) or o.startswith("grp:") or (opt_ids is not None and o not in opt_ids):
            errors.append({"key": "input.extraOptions", "error": "unknown option: %s" % o})
    return errors
