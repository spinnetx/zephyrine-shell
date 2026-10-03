"""doctor: доступность бэкендов и окружения (DESIGN §4, §2.4). Хук CLI: run(paths) -> dict.

Только чтение: ничего не запускает (кроме поиска команд в PATH), ничего не пишет.
"""
import json
import os
import shutil
import sys

from . import backup, palette, targets

# команда -> зачем нужна (для UI и тестов)
COMMANDS = {
    "hyprctl": "reload конфига Hyprland, мониторы, биндинги",
    "luac": "проверка settings.lua перед установкой",
    "pkill": "SIGUSR1 для kitty (перечитать конфиг)",
    "kitty": "цель kitty",
    "qt6ct": "цель qt6ct",
    "zeditor": "цель zed",
    "zathura": "цель zathura",
    "qs": "Quickshell: IPC, открытие окна настроек",
    "gsettings": "шрифты GTK (v1.1)",
    "fc-list": "список шрифтов (v1.1)",
    "mpvpaper": "обои (v1.1)",
    "ffmpeg": "превью обоев (v1.1)",
    "hypridle": "простой (этап 3)",
    "hyprlock": "блокировка (опц.)",
    "gio": "приложения по умолчанию (этап 4)",
    "nmcli": "Wi-Fi (этап 2)",
    "bluetoothctl": "Bluetooth (этап 2)",
    "wpctl": "звук (этап 3)",
    "brightnessctl": "яркость (этап 3)",
    "powerprofilesctl": "профиль питания (этап 3)",
    "hyprpicker": "пипетка цвета (опц.)",
    "wl-copy": "буфер обмена (опц.)",
}


def _json_ok(path):
    try:
        with open(path, encoding="utf-8") as f:
            json.load(f)
        return True, None
    except FileNotFoundError:
        return False, "not-found"
    except (OSError, ValueError) as e:
        return False, "invalid: %s" % e


def _writable_dir(path):
    p = path
    while p and not os.path.exists(p):
        parent = os.path.dirname(p)
        if parent == p:
            break
        p = parent
    return os.path.isdir(p) and os.access(p, os.W_OK | os.X_OK)


def run(paths):
    warnings = []
    blocking = []

    files = {}
    for name, p in (("scheme", palette.scheme_path(paths)), ("roles", palette.roles_path(paths)),
                    ("schema", paths.schema_file), ("targets", paths.targets_file)):
        ok, why = _json_ok(p)
        files[name] = {"path": p, "ok": ok, "error": why}
        if not ok:
            blocking.append("%s: %s (%s)" % (name, p, why))
    ok, why = _json_ok(paths.settings_file)
    files["settings"] = {"path": paths.settings_file, "ok": ok or why == "not-found", "error": None if ok else why}
    if not ok and why != "not-found":
        blocking.append("settings.json: %s" % why)

    commands = {}
    for name, purpose in COMMANDS.items():
        path = shutil.which(name)
        commands[name] = {"available": path is not None, "path": path, "purpose": purpose}

    profiles = {}
    for app in ("zen", "thunderbird"):
        root = os.path.join(paths.home, ".config", app)
        prof, reason = targets.find_profile(root)
        profiles[app] = {"found": prof is not None, "path": prof, "reason": reason, "root": root}
    reg = os.path.join(paths.home, ".config", "obsidian", "obsidian.json")
    vaults = []
    for v in targets.obsidian_vaults(reg):
        vaults.append({"path": v, "mounted": os.path.isdir(v),
                       "obsidian": os.path.isdir(os.path.join(v, ".obsidian"))})
    obsidian = {"registry": reg, "found": os.path.isfile(reg), "vaults": vaults}
    for v in vaults:
        if not v["mounted"]:
            warnings.append("vault не смонтирован: %s" % v["path"])

    tlist = []
    manifest = []
    if files["targets"]["ok"]:
        with open(paths.targets_file, encoding="utf-8") as f:
            manifest = json.load(f)["targets"]
    for t in manifest:
        tpl = t.get("template")
        has_tpl = None
        if tpl:
            has_tpl = any(os.path.isfile(os.path.join(b, tpl)) for b in (paths.settings_dir, paths.root))
        d = t.get("detect") or {}
        if d.get("type") == "command":
            installed = shutil.which(d["name"]) is not None
        elif d.get("type") == "file":
            installed = os.path.exists(targets.expand(paths, d["path"]))
        else:
            installed = True
        tlist.append({"id": t["id"], "stage": t.get("stage"), "kind": t["kind"], "installed": installed,
                      "template": has_tpl})
        if t.get("stage") == "v1" and t["kind"] == "template" and not has_tpl:
            warnings.append("нет шаблона цели %s (%s)" % (t["id"], tpl))

    st_dir = paths.state
    state = {"dir": st_dir, "exists": os.path.isdir(st_dir), "writable": _writable_dir(st_dir),
             "generated": os.path.isfile(targets.state_path(paths)),
             "backups": len(backup.list_backups(paths)), "history": len(backup.list_history(paths))}
    if not state["writable"]:
        blocking.append("каталог состояния недоступен для записи: %s" % st_dir)

    procfs = os.path.isfile(os.path.join(targets.PROC_ROOT, "stat"))
    restart = {"procfs": procfs,
               "running": {app: bool(procfs and targets.process_starts(names)) for app, names in targets.PROC_NAMES.items()},
               "ackOnly": sorted({targets.APP_OF.get(t["id"], t["id"]) for t in manifest
                                  if targets.needs_restart(t)} - set(targets.PROC_NAMES))}
    hypr = {"running": bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")),
            "hyprctl": commands["hyprctl"]["available"]}
    qs_shell = os.environ.get("ZEPHYRINE_QS_PATH") or os.path.join(paths.home, ".config", "quickshell", "zephyrine")
    return {
        "ok": not blocking,
        "blocking": blocking,
        "warnings": warnings,
        "python": "%d.%d.%d" % sys.version_info[:3],
        "home": paths.home, "root": paths.root,
        "files": files, "commands": commands, "profiles": profiles, "obsidian": obsidian,
        "targets": tlist, "state": state, "restart": restart, "hyprland": hypr,
        "quickshell": {"path": qs_shell, "exists": os.path.exists(qs_shell)},
    }
