"""CLI zephyrine-settings (контракт DESIGN §2.4).

stdout - ровно одна строка JSON; логи/трейсбеки - stderr.
Коды выхода: 0 ок; 1 частичный сбой; 2 ошибка валидации/аргументов; 3 занято (flock);
4 drift (без --force); 5 внутренняя ошибка (в т.ч. "not implemented").

Подкоманда `test` (golden|perturb|lint|home) - testkit.register: печатает обычный текст, не JSON;
код выхода - код стенда.

Хуки S1.6 (подключаются автоматически, если модуль существует; иначе - "not implemented"):
  zsettings.targets.apply(paths, targets, *, dry_run, force, no_exec) -> dict
      (ключи changed/actions/restart/skipped/errors/backup; необязательные "ok", "exit")
  zsettings.targets.status(paths) -> dict
  zsettings.doctor.run(paths) -> dict
  zsettings.targets.ack_restart(paths, apps) -> dict;  zsettings.targets.diff(paths, target) -> dict | None
`targets` - список id целей (None = все). Вызываются под flock команд set/reset/undo/apply.
"""
import argparse
import importlib
import json
import os
import subprocess
import sys
import traceback

from . import autostart, backup, barlayout, binds, fonts, mime, model, palette, testkit, themes, wallpaper, xkb
from .util import FileLock, LockTimeout, Paths, dumps_line

SECTIONS = {
    "appearance", "network", "devices", "system",
    "appearance/colors", "appearance/style", "appearance/bar", "appearance/fonts", "appearance/icons", "appearance/wallpaper", "appearance/apps",
    "network/wifi", "network/bluetooth", "devices/audio",
    "devices/display", "devices/power", "system/keyboard", "system/touchpad", "system/binds", "system/apps",
    "system/autostart", "system/notifications", "system/about",
}


class UsageError(Exception):
    pass


class JsonParser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError(message)


def envelope(ok=True, **extra):
    out = {"ok": ok, "changed": [], "actions": [], "restart": [], "skipped": [],
           "errors": [], "backup": None}
    out.update(extra)
    return out


def _import_hook(module, func):
    """Функция из zsettings.<module> или None, если модуля ещё нет (S1.6)."""
    name = "zsettings." + module
    try:
        mod = importlib.import_module(name)
    except ModuleNotFoundError as e:
        if e.name == name:
            return None
        raise
    return getattr(mod, func, None)


def _not_implemented(what):
    return 5, envelope(False, errors=[{"error": "not implemented: %s" % what}])


def _parse_value(text):
    def bad(_):
        raise ValueError
    try:
        return json.loads(text, parse_constant=bad)
    except ValueError:
        return text


def _load_schema(paths):
    return model.Schema.load(paths.schema_file, paths.targets_file)


def _exit_code(out):
    if "exit" in out:
        return out.pop("exit")
    return 0 if out.get("ok", True) and not out.get("errors") else 1


def _affected(schema, eff, keys, paths=None):
    """Цели для перегенерации по изменённым ключам: `targets` из схемы + `keys` из targets.json
    (DESIGN §3.2) + включённые appearance.targets.<id>."""
    t = schema.affected_targets(keys)
    if paths is not None:
        try:
            with open(paths.targets_file, encoding="utf-8") as f:
                manifest = json.load(f)["targets"]
        except (OSError, ValueError, KeyError):
            manifest = []
        for m in manifest:
            if m["id"] not in t and any(k in m.get("keys", []) for k in keys):
                t.append(m["id"])
    for k in keys:
        if k.startswith("appearance.targets.") and eff.get(k) is True:
            tid = k[len("appearance.targets."):]
            if tid not in t:
                t.append(tid)
    return t


def _do_apply(paths, args, targets, force=False):
    """Вызов apply-хука. -> (code, dict envelope)."""
    fn = _import_hook("targets", "apply")
    if fn is None:
        return 1, {"ok": False, "errors": [{"target": "*", "error": "not implemented: apply (S1.6)"}]}
    out = fn(paths, targets, dry_run=getattr(args, "dry_run", False),
             force=force or getattr(args, "force", False), no_exec=getattr(args, "no_exec", False))
    out = dict(out)
    out.setdefault("ok", not out.get("errors"))
    return _exit_code(out), out


def _finish_write(paths, schema, args, flat_new, keys, out):
    """Общая часть set/reset/undo после записи: цели + apply (если не --no-apply)."""
    eff, _ = model.effective(schema, flat_new)
    targets = _affected(schema, eff, keys, paths)
    out["keys"] = keys
    out["targets"] = targets
    if getattr(args, "no_apply", False) or not targets or getattr(args, "dry_run", False):
        return 0, out
    # Смена режима темы перекрашивает ВСЕ цели: просьба явная, поэтому незнакомые (drift) файлы тоже перезаписываются,
    # а прежнее содержимое уходит в бэкап (отмена — «Отменить» / `undo`). Иначе первая же ручная правка одного файла
    # блокировала бы смену темы у половины приложений.
    code, res = _do_apply(paths, args, targets, force="appearance.mode" in keys)
    for k, v in res.items():
        if k == "skipped":  # цели будущих этапов в отчёте о set/undo - шум
            out[k] = list(out.get(k, [])) + [x for x in v if x.get("reason") != "stage-not-implemented"]
        elif k in ("errors", "actions", "restart"):
            out[k] = list(out.get(k, [])) + list(v)
        elif k != "ok":
            out[k] = v
    out["ok"] = res.get("ok", True) and not out["errors"]
    return code, out


# --------------------------------------------------------------------------- команды

def cmd_get(args, paths):
    schema = _load_schema(paths)
    store = model.Store(paths, schema)
    flat = store.read_flat()
    eff, warnings = model.effective(schema, flat)
    out = {"ok": True}
    key = args.key
    if key is None:
        out["values"] = model.nest(eff)
    elif schema.has_key(key):
        d = schema.default(key)
        v = eff.get(key, d)
        out.update(key=key, value=v, default=d, isDefault=model.strict_equal(v, d))
    elif schema.is_prefix(key):
        sub = {k[len(key) + 1:]: v for k, v in eff.items() if k.startswith(key + ".")}
        out.update(key=key, values=model.nest(sub))
    else:
        return 2, envelope(False, errors=[{"key": key, "error": "unknown key"}])
    if warnings:
        out["warnings"] = warnings
    return 0, out


def cmd_set(args, paths):
    schema = _load_schema(paths)
    updates, errors = [], []
    for pair in args.pairs:
        if "=" not in pair:
            errors.append({"key": pair, "error": "expected KEY=VALUE"})
            continue
        k, v = pair.split("=", 1)
        updates.append((k, _parse_value(v)))
    if errors:
        return 2, envelope(False, errors=errors)
    store = model.Store(paths, schema)
    with FileLock(paths):
        flat = store.read_flat()
        new, changed, errors = model.apply_updates(schema, flat, updates)
        if errors:
            return 2, envelope(False, errors=errors)
        # семантика, которую схема не проверяет (акцент -> допустимая палитра), - до записи файла
        errors = palette.check_values(paths, schema, new) if changed else []
        if not errors and changed:  # шрифт должен быть установлен; для шелла - Nerd Font (fc-list)
            errors = fonts.check_values(schema, {k: new[k] for k in changed if k in new})
        if changed and not errors:  # тема иконок/курсора должна быть установлена (themes.py)
            errors = themes.check_values(paths, schema, new, changed)
        if changed and not errors:  # раскладки/опции xkb должны существовать (xkb.py)
            errors = xkb.check_values(schema, new, changed)
        if changed and not errors:  # сочетания клавиш, команды приложений, автозапуск
            errors = (binds.check_values(schema, new, changed) or autostart.check_values(schema, new, changed)
                      or barlayout.check_values(schema, new, changed))
        if changed and not errors:  # файл обоев должен существовать (wallpaper.py)
            errors = wallpaper.check_values(paths, schema, new, changed)
        if errors:
            return 2, envelope(False, errors=errors)
        if changed and not args.dry_run:
            store.write(new)
        return _finish_write(paths, schema, args, new, changed, envelope())


def cmd_reset(args, paths):
    schema = _load_schema(paths)
    store = model.Store(paths, schema)
    with FileLock(paths):
        flat = store.read_flat()
        new, changed, errors = model.remove_keys(schema, flat, args.keys)
        if errors:
            return 2, envelope(False, errors=errors)
        if changed and not args.dry_run:
            store.write(new)
        return _finish_write(paths, schema, args, new, changed, envelope())


def cmd_undo(args, paths):
    schema = _load_schema(paths)
    store = model.Store(paths, schema)
    with FileLock(paths):
        last = backup.peek_history(paths)
        if last is None:
            return 2, envelope(False, errors=[{"error": "nothing to undo"}])
        name, data = last
        old = store.read_flat()
        new = store.parse(data)  # проверка версии/JSON до записи
        new = model.flatten(new, schema)
        changed = model.diff_keys(old, new)
        if not args.dry_run:
            from .util import atomic_write
            atomic_write(paths.settings_file, data)
            backup.drop_history(paths, name)
        out = envelope(restored=name)
        return _finish_write(paths, schema, args, new, changed, out)


def cmd_backup(args, paths):
    if args.action == "list":
        return 0, {"ok": True, "backups": backup.list_backups(paths)}
    if not args.id:
        return 2, envelope(False, errors=[{"error": "backup restore needs ID"}])
    with FileLock(paths):
        try:
            files, safety = backup.restore(paths, args.id)
        except backup.BackupError as e:
            return 2, envelope(False, errors=[{"error": str(e)}])
    return 0, envelope(restored=files, backup=safety)


def cmd_open(args, paths):
    section = args.section
    if section is not None and section not in SECTIONS:
        return 2, envelope(False, errors=[{"key": "section", "error": "unknown section %r" % section}])
    qs = os.environ.get("ZEPHYRINE_QS", "qs")
    shell = os.environ.get("ZEPHYRINE_QS_PATH") or os.path.join(paths.home, ".config", "quickshell", "zephyrine")
    cmd = [qs, "-p", shell, "ipc", "call", "settings"] + (["openAt", section] if section else ["open"])
    if args.no_exec:
        return 0, envelope(command=cmd, executed=False)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    except FileNotFoundError:
        return 1, envelope(False, command=cmd, errors=[{"error": "qs not found: %s" % qs}])
    except subprocess.TimeoutExpired:
        return 1, envelope(False, command=cmd, errors=[{"error": "qs ipc timed out"}])
    # IPC Quickshell возвращает 0 даже при ошибке; успешный void-вызов ничего не печатает.
    text = ((r.stdout or "") + (r.stderr or "")).strip()
    if r.returncode != 0 or text:
        return 1, envelope(False, command=cmd, errors=[{"error": text or "qs exited %d" % r.returncode}])
    return 0, envelope(command=cmd, executed=True)


def cmd_apply(args, paths):
    if _import_hook("targets", "apply") is None:
        return _not_implemented("apply (S1.6)")
    targets = args.targets.split(",") if args.targets else None
    with FileLock(paths):
        return _do_apply(paths, args, targets)


def cmd_status(args, paths):
    fn = _import_hook("targets", "status")
    if fn is None:
        return _not_implemented("status (S1.6)")
    out = dict(fn(paths))
    out.setdefault("ok", True)
    return _exit_code(out), out


def cmd_ack_restart(args, paths):
    fn = _import_hook("targets", "ack_restart")
    if fn is None:
        return _not_implemented("ack-restart")
    out = dict(fn(paths, args.apps))
    if out.get("unknown"):
        out["errors"] = [{"app": a, "error": "unknown app"} for a in out["unknown"]]
        return 2, envelope(**out)
    return 0, envelope(**out)


def cmd_diff(args, paths):
    fn = _import_hook("targets", "diff")
    if fn is None:
        return _not_implemented("diff")
    out = fn(paths, args.target)
    if out is None:
        return 2, envelope(False, errors=[{"target": args.target, "error": "unknown target"}])
    return 0, envelope(**out)


def cmd_wallpaper(args, paths):
    """`wallpaper list [--no-thumbs]` - каталог обоев с превью (ffmpeg) и выбором; `wallpaper restart
    [--no-exec]` - перезапуск mpvpaper рабочего стола на выбранный файл (только он; lock-экземпляр не трогается)."""
    schema = _load_schema(paths)
    eff, _ = model.effective(schema, model.Store(paths, schema).read_flat())
    if args.action == "list":
        return 0, wallpaper.list_wallpapers(paths, eff, thumbs=not args.no_thumbs)
    want_d, _ = wallpaper.desired(paths, eff)
    err = wallpaper.check_file(want_d)
    if err:
        return 2, envelope(False, errors=[{"key": wallpaper.KEY_DESKTOP, "error": err}])
    with FileLock(paths):
        r = wallpaper.restart_desktop(paths, want_d, no_exec=args.no_exec)
    if not r["ok"]:
        return 1, envelope(False, errors=[{"target": "wallpaper", "error": r["error"]}], **{
            k: v for k, v in r.items() if k not in ("ok", "error")})
    out = envelope(actions=[] if args.no_exec else ["wallpaper:restart"],
                   actionsSkipped=["wallpaper:restart"] if args.no_exec else [])
    out.update({k: v for k, v in r.items() if k != "ok"})
    return 0, out


def cmd_fonts(args, paths):
    """Список установленных семейств для выбора шрифта: any | mono | nerd (zsettings/fonts.py)."""
    try:
        fams = fonts.families(args.kind)
    except fonts.FontsError as e:
        return 1, envelope(False, errors=[{"error": str(e)}])
    return 0, envelope(kind=args.kind, families=fams, count=len(fams))


def cmd_themes(args, paths):
    """Установленные темы иконок или курсора с файлами-превью: `themes --kind icons|cursors [--no-thumbs]`."""
    try:
        items = themes.listing(args.kind, paths, thumbs=not args.no_thumbs)
    except themes.ThemesError as e:
        return 1, envelope(False, errors=[{"error": str(e)}])
    return 0, envelope(kind=args.kind, themes=items, count=len(items))


def cmd_doctor(args, paths):
    fn = _import_hook("doctor", "run")
    if fn is None:
        return _not_implemented("doctor (S1.6)")
    out = dict(fn(paths))
    out.setdefault("ok", True)
    return _exit_code(out), out


def cmd_monitors(args, paths):
    from . import monitors
    try:
        if args.action == "snapshot":
            res = monitors.snapshot(paths, no_exec=args.no_exec)
            return 0, envelope(True, monitors=res)
        elif args.action == "try":
            spec = json.loads(args.payload) if args.payload else []
            res = monitors.try_config(paths, spec, timeout_sec=args.timeout, no_exec=args.no_exec)
            return 0, envelope(True, **res)
        elif args.action == "confirm":
            token = args.payload
            res = monitors.confirm(paths, token, no_exec=args.no_exec)
            return 0, envelope(True, **res)
        elif args.action == "revert":
            token = args.payload or None
            res = monitors.revert(paths, token, no_exec=args.no_exec)
            return 0, envelope(True, **res)
    except Exception as e:
        return 1, envelope(False, errors=[{"error": str(e)}])
    return 1, envelope(False, errors=[{"error": "unknown monitors action"}])


def cmd_mime(args, paths):
    try:
        if args.action == "list":
            return 0, envelope(True, mime=mime.listing())
        if not args.category or not args.app:
            return 2, envelope(False, errors=[{"error": "usage: mime set CATEGORY APP.desktop"}])
        cmds = mime.set_default(args.category, args.app, no_exec=args.no_exec)
        return 0, envelope(True, actions=cmds)
    except mime.MimeError as e:
        return 1, envelope(False, errors=[{"error": str(e)}])


def cmd_binds(args, paths):
    schema = _load_schema(paths)
    flat = model.Store(paths, schema).read_flat()
    if args.action == "list":
        return 0, envelope(True, binds=binds.listing(flat))
    if args.action == "check":
        if not binds.COMBO_RE.match(args.arg or ""):
            return 2, envelope(False, errors=[{"error": "invalid combination: %s" % args.arg}])
        return 0, envelope(True, conflicts=binds.conflicts(args.arg, flat, args.ignore))
    if args.action in ("capture", "release"):
        res = binds.capture(args.action == "capture", no_exec=args.no_exec)
        return 0, envelope(True, actions=res["actions"], capture=res)
    return 2, envelope(False, errors=[{"error": "unknown binds action"}])


def cmd_autostart(args, paths):
    return 0, envelope(True, system=autostart.system_entries(paths))


def cmd_xkb(args, paths):
    cat = xkb.catalog()
    if cat is None:
        return 1, envelope(False, errors=[{"error": "xkb base.lst not found"}])
    return 0, envelope(True, xkb=cat)


def cmd_sysinfo(args, paths):
    from . import sysinfo
    return 0, envelope(True, sysinfo=sysinfo.run(paths))


def cmd_test(args, paths):
    """Обёртка: у `test` собственный текстовый вывод (JSON-конверт не печатается, см. main)."""
    return args.func(args), None


def cmd_future(args, paths):
    return _not_implemented("%s (later stage)" % args.cmd)


# --------------------------------------------------------------------------- разбор аргументов

def build_parser():
    p = JsonParser(prog="zephyrine-settings", description="Zephyrine settings CLI")
    sub = p.add_subparsers(dest="cmd", required=True, parser_class=JsonParser)

    s = sub.add_parser("get")
    s.add_argument("key", nargs="?")
    s.set_defaults(fn=cmd_get)

    s = sub.add_parser("set")
    s.add_argument("pairs", nargs="+", metavar="KEY=VALUE")
    s.add_argument("--no-apply", action="store_true")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("--force", action="store_true")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_set)

    s = sub.add_parser("reset")
    s.add_argument("keys", nargs="+", metavar="KEY")
    s.add_argument("--no-apply", action="store_true")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("--force", action="store_true")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_reset)

    s = sub.add_parser("undo")
    s.add_argument("--no-apply", action="store_true")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("--force", action="store_true")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_undo)

    s = sub.add_parser("backup")
    s.add_argument("action", choices=["list", "restore"])
    s.add_argument("id", nargs="?")
    s.set_defaults(fn=cmd_backup)

    s = sub.add_parser("open")
    s.add_argument("section", nargs="?")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_open)

    s = sub.add_parser("apply")
    s.add_argument("--targets")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("--force", action="store_true")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_apply)

    s = sub.add_parser("ack-restart")
    s.add_argument("apps", nargs="*", metavar="APP")
    s.set_defaults(fn=cmd_ack_restart)

    s = sub.add_parser("diff")
    s.add_argument("target")
    s.set_defaults(fn=cmd_diff)

    s = sub.add_parser("wallpaper")
    s.add_argument("action", choices=["list", "restart"])
    s.add_argument("--no-thumbs", action="store_true")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_wallpaper)

    s = sub.add_parser("fonts")
    s.add_argument("--kind", choices=fonts.KINDS, default="any")
    s.set_defaults(fn=cmd_fonts)

    s = sub.add_parser("themes")
    s.add_argument("--kind", choices=themes.KINDS, required=True)
    s.add_argument("--no-thumbs", action="store_true")
    s.set_defaults(fn=cmd_themes)

    s = sub.add_parser("monitors")
    s.add_argument("action", choices=["snapshot", "try", "confirm", "revert"])
    s.add_argument("payload", nargs="?", default="")
    s.add_argument("--timeout", type=int, default=15)
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_monitors)

    sub.add_parser("status").set_defaults(fn=cmd_status)
    sub.add_parser("doctor").set_defaults(fn=cmd_doctor)

    sub.add_parser("sysinfo").set_defaults(fn=cmd_sysinfo)
    sub.add_parser("xkb").set_defaults(fn=cmd_xkb)

    s = sub.add_parser("binds")
    s.add_argument("action", choices=["list", "check", "capture", "release"])
    s.add_argument("arg", nargs="?", default="")
    s.add_argument("--ignore", default=None, help="id действия, чьи комбинации не считать конфликтом")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_binds)

    sub.add_parser("autostart").set_defaults(fn=cmd_autostart)

    s = sub.add_parser("mime")
    s.add_argument("action", choices=["list", "set"])
    s.add_argument("category", nargs="?", default="")
    s.add_argument("app", nargs="?", default="")
    s.add_argument("--no-exec", action="store_true")
    s.set_defaults(fn=cmd_mime)

    for name in ("render",):
        s = sub.add_parser(name, add_help=False)
        s.add_argument("rest", nargs=argparse.REMAINDER)
        s.set_defaults(fn=cmd_future)

    t = testkit.register(sub)  # `test golden|perturb|lint|home`
    t.set_defaults(fn=cmd_test)
    return p


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        args = build_parser().parse_args(argv)
        code, out = args.fn(args, Paths.from_env())
        if out is None:  # test: вывод уже напечатан стендом
            return code
    except UsageError as e:
        code, out = 2, envelope(False, errors=[{"error": "usage: %s" % e}])
    except LockTimeout as e:
        code, out = 3, envelope(False, errors=[{"error": str(e)}])
    except model.StoreError as e:
        code, out = 5, envelope(False, errors=[{"error": str(e)}])
    except Exception as e:  # noqa: BLE001 - контракт: внутренняя ошибка -> код 5
        traceback.print_exc(file=sys.stderr)
        code, out = 5, envelope(False, errors=[{"error": "internal error: %s: %s" % (type(e).__name__, e)}])
    print(dumps_line(out))
    return code
