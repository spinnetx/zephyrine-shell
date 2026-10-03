"""Цель `cursor` (kind=command, DESIGN §3.11): курсор Hyprland вживую - `hyprctl setcursor <тема> <размер>`.

Файлы тут не пишутся: GTK получает тему через settings.ini и gsettings, переменные XCURSOR_*/HYPRCURSOR_* для следующего
входа - цель `hypr` (settings.lua). Эта цель нужна, чтобы курсор менялся сразу, без перезагрузки сессии.
Идемпотентность - по подписи (тема, размер) последнего выполненного вызова в generated.json (`cmdWant`); без записи о
вызове и при значениях по умолчанию (Qogir/24, как в hyprland.lua) ничего не делается. Вне сессии Hyprland
(нет HYPRLAND_INSTANCE_SIGNATURE) цель пропускается: переменные подхватятся при следующем входе.

Хуки targets.py (как у gsettings): `apply_command(...)`, `status_info(...)`.
"""
import hashlib
import os
import shutil
import subprocess
import time

from .gsettings import _target_state

KEY_THEME = "appearance.cursor.theme"
KEY_SIZE = "appearance.cursor.size"
TIMEOUT = 8


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def desired(engine):
    return str(engine.eff[KEY_THEME]), str(engine.eff[KEY_SIZE])


def signature(want):
    return hashlib.sha256("\0".join(want).encode("utf-8")).hexdigest()


def is_default(engine, want):
    return want == (str(engine.schema.default(KEY_THEME)), str(engine.schema.default(KEY_SIZE)))


def in_hyprland():
    return bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def needs_call(engine, t, want):
    rec = engine.state["targets"].get(t["id"], {}).get("cmdWant")
    if rec is None:
        return not is_default(engine, want)
    return rec != signature(want)


def apply_command(engine, t, out, *, dry_run, no_exec, explicit):
    """-> True, если цель изменилась (или изменилась бы при dry_run)."""
    tid = t["id"]
    state, reason = _target_state(engine, t)
    if state:
        if explicit or state != "missing":
            out["skipped"].append({"target": tid, "reason": reason})
        return False
    want = desired(engine)
    if not needs_call(engine, t, want):
        out["unchanged"].append(tid)
        return False
    if dry_run:
        return True
    if no_exec:
        out["actionsSkipped"].append("%s:setcursor" % tid)
        out["changed"].append(tid)
        return True
    if not in_hyprland():
        out["skipped"].append({"target": tid, "reason": "hyprland-not-running"})
        return False
    try:
        r = subprocess.run([shutil.which("hyprctl") or "hyprctl", "setcursor", want[0], want[1]],
                           capture_output=True, text=True, timeout=TIMEOUT, stdin=subprocess.DEVNULL)
        err = None if r.returncode == 0 else "exit %d %s" % (r.returncode, (r.stderr or r.stdout).strip())
        if err is None and (r.stdout or "").strip().lower() not in ("", "ok"):
            err = (r.stdout or "").strip()  # hyprctl печатает ошибки в stdout с кодом 0
    except (OSError, subprocess.TimeoutExpired) as e:
        err = str(e)
    if err:
        out["errors"].append({"target": tid, "error": "hyprctl setcursor: %s" % err})
        return False
    rec = engine.state["targets"].setdefault(tid, {})
    rec.update(cmdWant=signature(want), lastApplied=_now(), lastAppliedTs=round(time.time(), 3), restartPending=False)
    out["actions"].append("%s:setcursor" % tid)
    out["changed"].append(tid)
    return True


def status_info(engine, t, info):
    """Дополняет info статуса (Engine.status_of): state live|outdated|missing|unmanaged."""
    state, reason = _target_state(engine, t)
    if state:
        info.update(state=state, reason=reason, installed=state != "missing", managed=state != "unmanaged")
        return info
    info["reason"] = None
    want = desired(engine)
    todo = needs_call(engine, t, want)
    info["paths"] = [{"path": "hyprctl setcursor %s %s" % want, "kind": "command",
                      "action": "update" if todo else "same"}]
    info["state"] = "outdated" if todo and in_hyprland() else "live"
    return info
