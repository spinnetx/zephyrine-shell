"""Автозапуск (DESIGN §4.4, §10 вопрос 2, модель A, Y4).

Управляемый список `autostart` [{id, name, cmd, enabled, delaySec}] из settings.json эмитится в settings.lua как
`hl.on("hyprland.start", …)` (hypr.py). Инфраструктурные строки hyprland.lua (hyprglass, polkit, keyring, порталы,
hypridle, qs, обои, ssh-add, gsettings) в список не входят: `system_entries` только показывает их (read-only).
"""
import os
import re

ID_RE = re.compile(r"^[a-z0-9][a-z0-9_\-]{0,39}$")
MAX_DELAY = 600


def lua_lines(entries, lua_str):
    """Строки Lua для включённых записей (пусто, если включённых нет)."""
    cmds = []
    for e in entries:
        if not e.get("enabled"):
            continue
        cmd = e["cmd"].strip()
        d = int(e.get("delaySec") or 0)
        cmds.append("sleep %d && %s" % (d, cmd) if d > 0 else cmd)
    if not cmds:
        return []
    return (["-- Автозапуск (autostart): управляемый список центра настроек"]
            + ['hl.on("hyprland.start", function()']
            + ["    hl.exec_cmd(%s)" % lua_str(c) for c in cmds]
            + ["end)"])


def check_values(schema, flat, changed):
    """-> [{"key", "error"}]: уникальные id, непустые name/cmd без переводов строк, задержка 0..600 с."""
    if "autostart" not in changed:
        return []
    entries = flat["autostart"] if "autostart" in flat else schema.default("autostart")
    errors, seen = [], set()
    for i, e in enumerate(entries):
        w = "autostart[%d]" % i
        if not ID_RE.match(e["id"]):
            errors.append({"key": "autostart", "error": "%s: invalid id %r" % (w, e["id"])})
        if e["id"] in seen:
            errors.append({"key": "autostart", "error": "%s: duplicate id %r" % (w, e["id"])})
        seen.add(e["id"])
        for f, lim in (("name", 60), ("cmd", 500)):
            v = e[f]
            if not v.strip() or len(v) > lim or any(ord(c) < 32 for c in v):
                errors.append({"key": "autostart", "error": "%s: invalid %s" % (w, f)})
        if not 0 <= e["delaySec"] <= MAX_DELAY:
            errors.append({"key": "autostart", "error": "%s: delaySec must be 0..%d" % (w, MAX_DELAY)})
    return errors


_EXEC_RE = re.compile(r'^\s*hl\.exec_cmd\("((?:[^"\\]|\\.)*)"\)\s*$')


def parse_system(text):
    """Незакомментированные hl.exec_cmd("…") внутри hl.on("hyprland.start", …) -> список команд."""
    out, inside = [], False
    for ln in (text or "").splitlines():
        if 'hl.on("hyprland.start"' in ln:
            inside = True
            continue
        if inside and ln.startswith("end)"):
            break
        if inside:
            m = _EXEC_RE.match(ln)
            if m:
                out.append(m.group(1).replace('\\"', '"').replace("\\\\", "\\"))
    return out


def system_entries(paths):
    for p in (os.path.join(paths.home, ".config", "hypr", "hyprland.lua"),
              os.path.join(paths.root, ".config", "hypr", "hyprland.lua")):
        try:
            with open(p, encoding="utf-8") as f:
                return parse_system(f.read())
        except OSError:
            continue
    return []
