"""Сочетания клавиш (DESIGN §4.4, Y2): каталог «действий Zephyrine», проверка, эмиссия переопределений, список и захват.

Ключ настроек `binds.<action>` - список комбинаций вида «SUPER + CTRL + 4»; нет ключа - комбинации по умолчанию из
hyprland.lua (там у этих биндов `description = "zp:<id> · <подпись>"`). Переопределение эмитится в settings.lua:
`hl.unbind(<старые>)` + `hl.bind(<новые>, <то же действие>, {description})`. Остальные бинды (≈50) - только просмотр.
"""
import json
import re
import shutil
import subprocess

QS = "qs -p $HOME/.config/quickshell/zephyrine ipc call "
MODS = ("SUPER", "SHIFT", "CTRL", "ALT")
MASK = {1: "SHIFT", 4: "CTRL", 8: "ALT", 64: "SUPER"}
COMBO_RE = re.compile(r"^(?:(?:SUPER|SHIFT|CTRL|ALT) \+ )*[A-Za-z0-9_]+$")
CAPTURE_SUBMAP = "zp_capture"
CAPTURE_TIMEOUT = 20

# id, подпись, комбинации по умолчанию, release-комбинации, действие ("exec"|"raw", строка), ключ приложения или None
ACTIONS = (
    ("launcher", "Лаунчер", ["SUPER + Super_L", "SUPER + space", "SUPER + R"], {"SUPER + Super_L"},
     ("exec", QS + "launcher toggle"), None),
    ("powermenu", "Меню питания", ["SUPER + Escape"], set(), ("exec", QS + "powermenu toggle"), None),
    ("notifs", "Уведомления и календарь", ["SUPER + N"], set(), ("exec", QS + "notifs toggle"), None),
    ("settings", "Центр настроек", ["SUPER + I"], set(), ("exec", QS + "settings toggle"), None),
    ("terminal", "Терминал", ["SUPER + Q"], set(), ("exec", None), "apps.terminal"),
    ("files", "Файловый менеджер", ["SUPER + E"], set(), ("exec", None), "apps.fileManager"),
    ("lock", "Блокировка экрана", ["SUPER + L"], set(),
     ("exec", "zephyrine-lock"), None),
    ("torrents", "Торренты", ["SUPER + T"], set(), ("exec", "kitty --class torrents -e tremc"), None),
    ("shot-area", "Скриншот области", ["SUPER + CTRL + 4"], set(),
     ("exec", 'grim -g "$(slurp)" -t ppm - | satty --filename - --fullscreen'), None),
    ("shot-full", "Скриншот экрана", ["SUPER + CTRL + 3"], set(),
     ("exec", "grim -t ppm - | satty --filename - --fullscreen"), None),
    ("close", "Закрыть окно", ["SUPER + C"], set(), ("raw", "hl.dsp.window.close()"), None),
    ("float", "Плавающее окно", ["SUPER + V"], set(), ("raw", 'hl.dsp.window.float({ action = "toggle" })'), None),
)
BY_ID = {a[0]: a for a in ACTIONS}
APP_DEFAULTS = {"apps.terminal": "zephyrine-launch-default terminal", "apps.fileManager": "zephyrine-launch-default files"}


def norm(combo):
    """Каноническая форма для сравнения: (frozenset модификаторов, ключ в нижнем регистре)."""
    parts = [p.strip() for p in combo.split("+")]
    return frozenset(p.upper() for p in parts[:-1]), parts[-1].lower()


def combo_from_mask(mask, key):
    mods = [name for bit, name in sorted(MASK.items(), key=lambda x: MODS.index(x[1])) if mask & bit]
    return " + ".join(mods + [key])


def effective(values, action_id):
    a = BY_ID[action_id]
    v = values.get("binds." + action_id)
    return list(v) if v else list(a[2])


def app_cmd(values, key):
    return values.get(key, APP_DEFAULTS[key])


def is_default(values, action_id):
    a = BY_ID[action_id]
    if effective(values, action_id) != a[2]:
        return False
    return a[5] is None or app_cmd(values, a[5]) == APP_DEFAULTS[a[5]]


def lua_lines(values, lua_str):
    """Строки Lua для переопределённых действий (пусто, если всё по умолчанию)."""
    out = []
    for aid, label, defaults, release, (kind, expr), appkey in ACTIONS:
        if is_default(values, aid):
            continue
        if appkey:
            expr = app_cmd(values, appkey)
        disp = "hl.dsp.exec_cmd(%s)" % lua_str(expr) if kind == "exec" else expr
        out.append("-- %s (binds.%s)" % (label, aid))
        for c in defaults:
            out.append("pcall(hl.unbind, %s)" % lua_str(c))
        for c in effective(values, aid):
            opts = ["description = %s" % lua_str("zp:%s · %s" % (aid, label))]
            if c in release:
                opts.append("release = true")
            out.append("hl.bind(%s, %s, { %s })" % (lua_str(c), disp, ", ".join(opts)))
    return out


def check_values(schema, flat, changed):
    """binds.<action>: известное действие, формат комбинаций, нет повторов между действиями -> [{"key","error"}]."""
    errors = []
    for k in changed:   # команды терминала/файлового менеджера попадают в Lua-строку и shell
        v = flat.get(k)
        if k in APP_DEFAULTS and v is not None and (not v.strip() or len(v) > 200 or any(ord(c) < 32 for c in v)):
            errors.append({"key": k, "error": "invalid command"})
    keys = [k for k in changed if k.startswith("binds.")]
    if not keys:
        return errors
    values = {k: v for k, v in flat.items() if k.startswith("binds.")}
    for k in keys:
        aid = k[len("binds."):]
        if aid not in BY_ID:
            errors.append({"key": k, "error": "unknown action: %s" % aid})
            continue
        combos = flat.get(k)
        if combos is None:
            continue
        if not combos:
            errors.append({"key": k, "error": "at least one combination is required"})
        for c in combos:
            if not COMBO_RE.match(c) or norm(c)[1] in ("super", "shift", "ctrl", "alt"):
                errors.append({"key": k, "error": "invalid combination: %s" % c})
        if len({norm(c) for c in combos}) != len(combos):
            errors.append({"key": k, "error": "duplicate combination"})
    if errors:
        return errors
    owner = {}
    for aid in BY_ID:
        for c in effective(values, aid):
            n = norm(c)
            if n in owner and owner[n] != aid:
                bad, other = (aid, owner[n]) if "binds." + aid in keys else (owner[n], aid)
                errors.append({"key": "binds." + bad, "error": "combination %s is already used by %s" % (c, other)})
            owner[n] = aid
    return errors


def _run(argv):
    exe = shutil.which(argv[0])
    if exe is None:
        return None
    try:
        r = subprocess.run([exe] + argv[1:], capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def parse_hypr_binds(text):
    """`hyprctl binds -j` -> [{combo, key, description, release}]; zp-бинды пропускаются."""
    try:
        data = json.loads(text)
    except (TypeError, ValueError):
        return []
    out = []
    for b in data if isinstance(data, list) else []:
        desc = str(b.get("description") or "")
        if desc.startswith("zp:"):
            continue
        key = str(b.get("key") or "")
        if not key:
            continue
        out.append({"combo": combo_from_mask(int(b.get("modmask") or 0), key), "description": desc,
                    "dispatcher": str(b.get("dispatcher") or ""), "arg": str(b.get("arg") or ""),
                    "release": bool(b.get("release"))})
    return out


def listing(values, runner=_run):
    acts = [{"id": aid, "label": label, "defaults": defaults, "combos": effective(values, aid),
             "custom": bool(values.get("binds." + aid)), "release": sorted(release)}
            for aid, label, defaults, release, _e, _k in ACTIONS]
    others = parse_hypr_binds(runner(["hyprctl", "binds", "-j"]) or "")
    return {"actions": acts, "others": others}


def conflicts(combo, values, ignore_action=None, runner=_run):
    """Кто уже занимает комбинацию: действия Zephyrine и прочие бинды Hyprland."""
    n = norm(combo)
    out = []
    for aid in BY_ID:
        if aid != ignore_action and any(norm(c) == n for c in effective(values, aid)):
            out.append({"kind": "zephyrine", "id": aid, "label": BY_ID[aid][1]})
    for b in parse_hypr_binds(runner(["hyprctl", "binds", "-j"]) or ""):
        if norm(b["combo"]) == n:
            out.append({"kind": "hyprland", "label": b["description"] or (b["dispatcher"] + " " + b["arg"]).strip()})
    return out


def _run_full(argv):
    """-> (код выхода | None, stdout, stderr); для диагностики захвата."""
    exe = shutil.which(argv[0])
    if exe is None:
        return None, "", "%s not found" % argv[0]
    try:
        r = subprocess.run([exe] + argv[1:], capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "", str(e)
    return r.returncode, r.stdout, r.stderr


def active_submap(runner=_run):
    """Имя активного submap (`hyprctl submap`); пусто/default - обычный режим; None - hyprctl недоступен."""
    out = runner(["hyprctl", "submap"])
    return None if out is None else out.strip()


def capture(start, runner=_run, no_exec=False, spawn=None, full=_run_full):
    """Захват комбинации: на время ввода включаем submap без биндов (иначе Hyprland перехватит SUPER+… раньше окна);
    сторож сбрасывает submap через CAPTURE_TIMEOUT с, если окно упало.

    Возвращает {"active": bool, "submap": str|None, "actions": [...], "diagnostic": str}. Захват считается включённым
    только если `hyprctl submap` подтвердил zp_capture: иначе нажатые сочетания СРАБОТАЛИ бы, и UI не должен
    предлагать нажимать их. Пробуем три формы диспетчера (Lua dsp, hl.dispatch, старый `dispatch submap`); в
    диагностику попадает вывод каждой."""
    target = CAPTURE_SUBMAP if start else "reset"
    attempts = [["hyprctl", "dispatch", 'hl.dsp.submap("%s")' % target],
                ["hyprctl", "dispatch", 'hl.dispatch(hl.dsp.submap("%s"))' % target],
                ["hyprctl", "dispatch", "submap", target]]
    if no_exec:
        return {"active": False, "submap": None, "actions": [" ".join(attempts[0])], "diagnostic": ""}
    done, log, current = [], [], None
    for cmd in attempts:
        rc, out, err = full(cmd)
        done.append(" ".join(cmd))
        log.append("%s → код %s, вывод %r" % (" ".join(cmd[2:]), rc, (out + err).strip()[:160]))
        current = active_submap(runner)
        if current is None or (current == CAPTURE_SUBMAP) == start:
            break
    ok = current is not None and (current == CAPTURE_SUBMAP) == start
    diag = ""
    if start and not ok:
        errs = (runner(["hyprctl", "configerrors"]) or "").strip()
        diag = "submap zp_capture не включился (hyprctl submap: %r). Попытки: %s" % (current, "; ".join(log))
        if errs:
            diag += ". configerrors: " + errs[:300]
        full(["hyprctl", "dispatch", 'hl.dsp.submap("reset")'])
    if start and ok:
        watchdog = ["sh", "-c", "sleep %d; hyprctl dispatch 'hl.dsp.submap(\"reset\")'; hyprctl dispatch submap reset"
                    % CAPTURE_TIMEOUT]
        (spawn or (lambda a: subprocess.Popen(a, start_new_session=True, stdin=subprocess.DEVNULL,
                                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)))(watchdog)
    return {"active": start and ok, "submap": current, "actions": done, "diagnostic": diag}
