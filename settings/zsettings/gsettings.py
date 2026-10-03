"""Цель `gsettings` (kind=command, DESIGN §3.2, A1): шрифты интерфейса/моно в dconf (GTK 4 подхватывает вживую).

Описание в targets.json: `commands` - [{"schema", "key", "from", "value"}]; поля подстановки и `sizeFrom` -
как у patch-целей (zsettings/patch.py). Текущее значение читается `gsettings get`, пишется
`gsettings set` (аргументами, без shell) только если отличается: повторный apply ничего не делает.
С `no_exec` gsettings не запускается вообще; идемпотентность тогда - по хэшу последнего выставленного
значения в generated.json (`cmdWant`), который пишет только реальный запуск.

Хуки targets.py (как у wallpaper): `apply_command(...)`, `status_info(...)`.
"""
import ast
import hashlib
import json
import shutil
import subprocess
import time

from . import patch

TIMEOUT = 8


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def _target_state(engine, t):
    """-> (state|None, reason|None): unmanaged / missing (нет gsettings) - цель не применяется."""
    if engine.eff.get(t.get("manageKey") or "appearance.targets." + t["id"], True) is False:
        return "unmanaged", "not-managed"
    ok, reason = engine.detect(t)
    if not ok:
        return "missing", reason
    return None, None


def desired(engine, t):
    """-> [{"schema", "key", "value"}] по эффективным настройкам. patch.PatchError при плохих данных."""
    out = []
    for c in t.get("commands") or []:
        f = patch.fields(engine.eff, c)
        out.append({"schema": c["schema"], "key": c["key"],
                    "value": patch._format(c.get("value", "{v}"), f, "%s %s" % (c["schema"], c["key"]))})
    return out


def signature(wants):
    return hashlib.sha256(json.dumps([[w["schema"], w["key"], w["value"]] for w in wants]).encode()).hexdigest()


def get(schema, key):
    """Текущее значение ключа строкой (число - тоже) или None (нет gsettings/ключа/сессионной шины)."""
    exe = shutil.which("gsettings")
    if exe is None:
        return None
    try:
        r = subprocess.run([exe, "get", schema, key], capture_output=True, text=True, timeout=TIMEOUT,
                           stdin=subprocess.DEVNULL)
        if r.returncode != 0:
            return None
        v = ast.literal_eval(r.stdout.strip())
    except (OSError, subprocess.TimeoutExpired, ValueError, SyntaxError):
        return None
    if isinstance(v, int) and not isinstance(v, bool):  # cursor-size: число сравнивается как строка со значением цели
        return str(v)
    return v if isinstance(v, str) else None


def pending(engine, t, wants, no_exec=False):
    """Какие из wants надо выставить."""
    if no_exec:
        return list(wants) if engine.state["targets"].get(t["id"], {}).get("cmdWant") != signature(wants) else []
    return [w for w in wants if get(w["schema"], w["key"]) != w["value"]]


def apply_command(engine, t, out, *, dry_run, no_exec, explicit):
    """-> True, если цель изменилась (или изменилась бы при dry_run)."""
    from . import targets as T
    tid = t["id"]
    state, reason = _target_state(engine, t)
    if state:
        if explicit or state != "missing":
            out["skipped"].append({"target": tid, "reason": reason})
        return False
    try:
        wants = desired(engine, t)
    except patch.PatchError as e:
        out["errors"].append({"target": tid, "error": str(e)})
        return False
    sig = signature(wants)
    todo = pending(engine, t, wants, no_exec)
    if not todo:
        out["unchanged"].append(tid)
        if not dry_run and not no_exec:
            engine.state["targets"].setdefault(tid, {})["cmdWant"] = sig
        return False
    if dry_run:
        return True
    if no_exec:
        out["actionsSkipped"].append("%s:set" % tid)
        out["changed"].append(tid)
        return True
    exe = shutil.which("gsettings")
    failed = False
    for w in todo:
        try:
            r = subprocess.run([exe, "set", w["schema"], w["key"], w["value"]], capture_output=True, text=True,
                               timeout=TIMEOUT, stdin=subprocess.DEVNULL)
            err = None if r.returncode == 0 else "exit %d %s" % (r.returncode, (r.stderr or r.stdout).strip())
        except (OSError, subprocess.TimeoutExpired) as e:
            err = str(e)
        if err:
            out["errors"].append({"target": tid, "error": "gsettings set %s: %s" % (w["key"], err)})
            failed = True
    if failed:
        return False
    rec = engine.state["targets"].setdefault(tid, {})
    rec.update(cmdWant=sig, lastApplied=_now(), lastAppliedTs=round(time.time(), 3),
               restartPending=T.needs_restart(t))
    rec.pop("restartAckedAt", None)
    out["actions"].append("%s:set" % tid)
    out["changed"].append(tid)
    if T.needs_restart(t):
        out["restartTargets"].append(tid)
    return True


def status_info(engine, t, info):
    """Дополняет info статуса (Engine.status_of): state live|restart|outdated|missing|unmanaged|error."""
    state, reason = _target_state(engine, t)
    if state:
        info.update(state=state, reason=reason, installed=state != "missing", managed=state != "unmanaged")
        return info
    info["reason"] = None  # план цели - «later» (kind=command не из Plan): причина оттуда не нужна
    try:
        wants = desired(engine, t)
    except patch.PatchError as e:
        info.update(state="error", reason="patch-error", message=str(e))
        return info
    todo = pending(engine, t, wants)
    info["paths"] = [{"path": "%s %s" % (w["schema"], w["key"]), "kind": "gsettings",
                      "action": "update" if w in todo else "same"} for w in wants]
    if todo:
        info["state"] = "outdated"
    elif info["restartPending"] and info["needsRestart"]:
        info["state"] = "restart"
    else:
        info["state"] = "live"
    return info
