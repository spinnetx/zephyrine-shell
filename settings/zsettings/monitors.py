"""Управление мониторами (DESIGN §4.3, §7.2, §9.4 D4).

CLI команды:
- `monitors snapshot`: снимок фактических параметров мониторов (hyprctl monitors all -j)
- `monitors try <spec>`: применение параметров через `hl.monitor` с запуском сторожа отката `hl.timer` в компоситоре
- `monitors confirm <token>`: подтверждение параметров и сохранение в settings.json / settings.lua
- `monitors revert [token]`: откат к предыдущим параметрам
"""

import json
import os
import subprocess
import time
import uuid

from . import hypr, model
from .util import ensure_private_dir

PENDING_FILE = "monitor-pending.json"


class MonitorError(Exception):
    pass


def _pending_path(paths):
    return os.path.join(paths.state, PENDING_FILE)


def snapshot(paths=None, runner=None, no_exec=False):
    """Снимок параметров всех подключенных мониторов."""
    if runner is None:
        def default_runner(cmd):
            return subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        runner = default_runner

    if no_exec:
        return []

    try:
        r = runner(["hyprctl", "monitors", "all", "-j"])
        if r.returncode != 0:
            return []
        raw = json.loads(r.stdout)
    except Exception:
        return []

    out = []
    for m in raw:
        desc = m.get("description", "")
        match = ("desc:" + desc) if desc else m["name"]
        out.append({
            "id": m["id"],
            "name": m["name"],
            "description": desc,
            "make": m.get("make", ""),
            "model": m.get("model", ""),
            "width": m["width"],
            "height": m["height"],
            "refreshRate": m.get("refreshRate", 60.0),
            "x": m.get("x", 0),
            "y": m.get("y", 0),
            "scale": m.get("scale", 1.0),
            "transform": m.get("transform", 0),
            "disabled": m.get("disabled", False),
            "mirrorOf": m.get("mirrorOf", "none"),
            "availableModes": m.get("availableModes", []),
            "focused": m.get("focused", False),
            "match": match,
        })
    return out


def _spec_to_lua(m):
    """Преобразование спецификации монитора в строку таблицы Lua для hl.monitor."""
    match = m.get("match") or m.get("name") or "eDP-1"
    parts = ["output = " + hypr.lua_str(match)]
    if m.get("disabled"):
        parts.append("disabled = true")
    else:
        if m.get("mode"):
            parts.append("mode = " + hypr.lua_str(m["mode"]))
        if m.get("position"):
            parts.append("position = " + hypr.lua_str(m["position"]))
        if m.get("scale") is not None:
            parts.append("scale = " + hypr.lua_num(m["scale"], 0.25, 4.0, "scale"))
        if m.get("transform") is not None:
            parts.append("transform = %d" % int(m["transform"]))
        if m.get("mirror") and m["mirror"] != "none":
            parts.append("mirror = " + hypr.lua_str(m["mirror"]))
    return "{ %s }" % ", ".join(parts)


def validate_spec(current_monitors, new_specs):
    """Проверка безопасности: нельзя выключить все экраны, минимальный логический размер."""
    if not current_monitors:
        return
    # Словарь новых спецификаций по имени/match
    spec_by_match = {}
    for s in new_specs:
        key = s.get("match") or s.get("name")
        spec_by_match[key] = s
        if s.get("name"):
            spec_by_match[s["name"]] = s

    any_enabled = False
    for m in current_monitors:
        s = spec_by_match.get(m["match"]) or spec_by_match.get(m["name"])
        is_disabled = s.get("disabled", False) if s else m.get("disabled", False)
        if not is_disabled:
            any_enabled = True

        if s and not is_disabled:
            scale = float(s.get("scale", m.get("scale", 1.0)))
            width = float(m["width"])
            height = float(m["height"])
            log_w = width / scale
            log_h = height / scale
            min_dim = min(log_w, log_h)
            max_dim = max(log_w, log_h)
            if min_dim < 600 or max_dim < 1024:
                raise MonitorError("Слишком мелкий масштаб: логический размер %.0fx%.0f меньше 1024x600" % (log_w, log_h))

    if not any_enabled:
        raise MonitorError("Нельзя отключить все мониторы")


def try_config(paths, spec, timeout_sec=15, runner=None, no_exec=False):
    """Применение временной конфигурации мониторов со сторожем отката в Hyprland."""
    if runner is None:
        def default_runner(cmd):
            return subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        runner = default_runner

    current = snapshot(paths, runner, no_exec)
    if current:
        validate_spec(current, spec)

    token = uuid.uuid4().hex[:12]

    # Строим предыдущие спецификации
    prev_specs = []
    for m in current:
        prev_specs.append({
            "match": m["match"],
            "disabled": m.get("disabled", False),
            "mode": "%dx%d@%.2f" % (m["width"], m["height"], m["refreshRate"]),
            "position": "%dx%d" % (m["x"], m["y"]),
            "scale": m["scale"],
            "transform": m.get("transform", 0),
            "mirror": m.get("mirrorOf", "none")
        })

    prev_lua = ", ".join(_spec_to_lua(p) for p in prev_specs)
    new_lua = ", ".join(_spec_to_lua(s) for s in spec)
    timeout_ms = int(timeout_sec * 1000)

    lua_code = (
        '_G.zp_mon = { token = "%s", confirmed = false, prev = { %s } }; '
        'for _, s in ipairs({ %s }) do hl.monitor(s) end; '
        '_G.zp_mon.timer = hl.timer(function() '
        'if not _G.zp_mon.confirmed then '
        'for _, p in ipairs(_G.zp_mon.prev) do hl.monitor(p) end; '
        'hl.notification.create({ text = "Zephyrine: настройки экрана возвращены (таймаут)", timeout = 5000 }) '
        'end end, { timeout = %d, type = "oneshot" })' % (
            token, prev_lua, new_lua, timeout_ms
        )
    )

    if not no_exec:
        r = runner(["hyprctl", "eval", lua_code])
        if r.returncode != 0:
            raise MonitorError("Ошибка вызова hyprctl eval: %s" % (r.stderr or r.stdout).strip())

    # Записываем файл ожидания
    ensure_private_dir(paths.state)
    pending_data = {
        "token": token,
        "spec": spec,
        "ts": time.time(),
        "timeoutSec": timeout_sec
    }
    with open(_pending_path(paths), "w", encoding="utf-8") as f:
        json.dump(pending_data, f, indent=2)

    return {"ok": True, "token": token, "timeoutSec": timeout_sec}


def confirm(paths, token, runner=None, no_exec=False):
    """Подтверждение настроек мониторов: отмена таймера отката и сохранение в settings.json."""
    if runner is None:
        def default_runner(cmd):
            return subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        runner = default_runner

    ppath = _pending_path(paths)
    if not os.path.exists(ppath):
        raise MonitorError("Нет активного запроса на смену настроек экрана")

    with open(ppath, encoding="utf-8") as f:
        pending = json.load(f)

    if pending.get("token") != token:
        raise MonitorError("Неверный токен подтверждения экрана")

    if not no_exec:
        runner(["hyprctl", "eval", "_G.zp_mon.confirmed = true"])

    # Сохраняем в settings.json
    schema = model.Schema.load(paths.schema_file, paths.targets_file)
    store = model.Store(paths, schema)
    flat = store.read_flat()
    flat["display.monitors"] = pending["spec"]
    store.write(flat)

    # Обновляем settings.lua
    eff_values, _ = model.effective(schema, flat)
    from . import palette
    scheme, roles = palette.load_inputs(paths)
    ctx = palette.build_context(scheme, roles, eff_values)
    lua_out = hypr.emit(eff_values, ctx, paths)

    target_path = os.path.join(paths.root, ".config", "hypr", "settings.lua")
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    with open(target_path, "w", encoding="utf-8") as f:
        f.write(lua_out)

    try:
        os.remove(ppath)
    except OSError:
        pass

    return {"ok": True, "confirmed": True}


def revert(paths, token=None, runner=None, no_exec=False):
    """Откат к предыдущим настройкам экрана."""
    if runner is None:
        def default_runner(cmd):
            return subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        runner = default_runner

    lua_code = (
        'if _G.zp_mon and _G.zp_mon.prev then '
        'for _, p in ipairs(_G.zp_mon.prev) do hl.monitor(p) end; '
        '_G.zp_mon.confirmed = true '
        'end'
    )
    if not no_exec:
        runner(["hyprctl", "eval", lua_code])

    ppath = _pending_path(paths)
    try:
        if os.path.exists(ppath):
            os.remove(ppath)
    except OSError:
        pass

    return {"ok": True, "reverted": True}
