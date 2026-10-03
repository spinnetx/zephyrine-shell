"""Применение целей генератора тем: рендер, деплой, drift, reload, статусы (DESIGN §3.2, §3.6, §3.8, §7).

Хуки для cli.py (`_import_hook`):
    apply(paths, targets, *, dry_run=False, force=False, no_exec=False, reason="apply") -> dict
    status(paths) -> dict

Порядок `apply` (§3.8): настройки -> эффективная палитра -> рендер целей -> сравнение с текущим
(без изменений - ничего не пишем: идемпотентность) -> drift-проверка -> ОДИН бэкап всех перезаписываемых
файлов -> запись (всегда в realpath, симлинк остаётся симлинком) -> деплой копий -> reload-действия.

Виды целей: template (шаблон из templates/), data (quickshell: scheme.override.json), emit (модуль
`zsettings.<id цели>` с функцией `emit(values, ctx, paths) -> str`; нет модуля - цель пропускается).
command: модуль `zsettings.<id цели>` с `apply_command(...)`/`status_info(...)` (сейчас `wallpaper`); без модуля
и patch, а также цели не-v1 этапов пока пропускаются (state "later").

Деплой (поле `deploy` в targets.json): none | copy:<путь> | obsidian-vaults | zen-profile | tb-profile |
tb-xpi. Все пути - от HOME из `Paths` (XDG_CONFIG_HOME сознательно игнорируется: изолированный HOME в
тестах не должен достать до реальных ~/.config).

Drift: у каждого пути в `<state>/generated.json` хранится список последних записанных sha256 (`known`).
Файл, содержимое которого неизвестно и не равно новому выводу, - правился руками (drift); исключение -
«приём во владение» (§3.6.5): файл без записи, равный выводу при ДЕФОЛТНЫХ настройках (golden) либо равный
текущему файлу в репо; а также эмитируемый файл с шапкой «СГЕНЕРИРОВАНО zephyrine-settings» (после git pull). Поэтому `backup restore` не создаёт ложного drift: восстановленный файл - один из
ранее записанных.

Состояния цели в status: live | restart | outdated | missing | manual | error | no-template | unmanaged | later.
"""
import copy
import difflib
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path

from . import backup, model, palette, patch
from .render import RenderError, TemplateRenderer
from .util import FileLock, atomic_write, dumps_file, ensure_private_dir, sha256_bytes

SUPPORTED_STAGES = {"v1"}
SUPPORTED_KINDS = {"template", "data", "emit"}
KNOWN_KEEP = 8
RELOAD_TIMEOUT = 10
# Приложение, которое надо перезапустить (для отчёта `restart`); по умолчанию - id цели.
APP_OF = {"gtk3": "gtk", "gtk4": "gtk", "tb-css": "thunderbird", "tb-theme": "thunderbird",
          "zen-chrome": "zen", "zen-content": "zen", "gtk3-settings": "gtk", "gtk4-settings": "gtk",
          "qt6ct-conf": "qt6ct"}
# Имена процессов (/proc/<pid>/comm) приложения для автосброса restartPending. Нет записи - процесса нет
# (gtk, qt6ct: перезапуск сам по себе ничего не доказывает) -> сбрасывается только командой `ack-restart`.
PROC_NAMES = {"thunderbird": ("thunderbird", "thunderbird-bin"),
              "zen": ("zen", "zen-bin", "zen-browser"),
              "zathura": ("zathura",),
              "obsidian": ("obsidian",),
              "zed": ("zed", "zeditor", "zed-editor")}
PROC_ROOT = "/proc"  # подменяется в тестах
DIFF_MAX_BYTES = 256 * 1024


class NoTemplate(Exception):
    pass


class UnsupportedTarget(Exception):
    pass


class _NoDest(Exception):
    """Нет места назначения (профиль/vault) - цель целиком пропускается (skipped)."""


# --------------------------------------------------------------------------- пути и обнаружение

def expand(paths, p):
    """`~` -> HOME из Paths; относительный путь - от корня репо."""
    if p == "~" or p.startswith("~/"):
        return os.path.join(paths.home, p[2:])
    if os.path.isabs(p):
        return p
    return os.path.join(paths.root, p)


def find_profile(root_dir, registry="installs.ini", key="Default"):
    """Как deploy.sh: `grep -m1 '^Default=' installs.ini | cut -d= -f2-` -> каталог профиля.
    -> (путь|None, причина|None). Пробелы и скобки в именах профиля - обычные символы (без shell)."""
    ini = os.path.join(root_dir, registry)
    try:
        with open(ini, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None, "profile-not-found"
    prefix = key + "="
    value = next((ln[len(prefix):] for ln in lines if ln.startswith(prefix)), "")
    if not value:
        return None, "profile-not-found"
    prof = os.path.join(root_dir, value)
    if not os.path.isdir(prof):
        return None, "profile-not-found"
    return prof, None


def obsidian_vaults(registry_file):
    """Пути vault'ов из obsidian.json (`vaults.*.path`), порядок по ключу; нет файла/битый -> []."""
    try:
        with open(registry_file, encoding="utf-8") as f:
            data = json.load(f)
        vs = data.get("vaults") or {}
        return [vs[k]["path"] for k in sorted(vs) if isinstance(vs[k], dict) and isinstance(vs[k].get("path"), str)]
    except (OSError, ValueError, AttributeError):
        return []


def _deploy_rel(t):
    """'<профиль TB>/chrome/userChrome.css' -> 'chrome/userChrome.css'."""
    m = re.match(r"^<[^>]+>/(.+)$", t.get("deployPath", ""))
    return m.group(1) if m else os.path.basename(t["output"])


def build_xpi(manifest_bytes):
    """Детерминированный zip (дата 1980-01-01, права 0644, create_system, единственная запись):
    повторная сборка даёт те же байты - undo байт-в-байт, drift не срабатывает на пересборке."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        zi = zipfile.ZipInfo("manifest.json", date_time=(1980, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = 0o644 << 16
        zi.create_system = 3  # фиксируем (иначе зависит от ОС сборки)
        z.writestr(zi, manifest_bytes)
    return buf.getvalue()


# --------------------------------------------------------------------------- состояние (generated.json)

def state_path(paths):
    return os.path.join(paths.state, "generated.json")


def load_state(paths):
    try:
        with open(state_path(paths), encoding="utf-8") as f:
            st = json.load(f)
        if not isinstance(st, dict) or not isinstance(st.get("targets"), dict):
            raise ValueError
    except (OSError, ValueError):
        st = {}
    st.setdefault("version", 1)
    st.setdefault("meta", {}).setdefault("tbVersion", 0)
    st.setdefault("targets", {})
    return st


def save_state(paths, st):
    ensure_private_dir(paths.state)
    atomic_write(state_path(paths), dumps_file(st), mode=0o600)


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def process_starts(names, proc_root=None):
    """Времена запуска (epoch, с) процессов с comm из `names`: /proc/<pid>/stat поле 22 (тики с загрузки)
    + btime из /proc/stat. Нечитаемые/исчезнувшие процессы пропускаются."""
    root = proc_root or PROC_ROOT
    names = set(names)
    try:
        hz = os.sysconf("SC_CLK_TCK")
        btime = None
        with open(os.path.join(root, "stat"), encoding="utf-8", errors="replace") as f:
            for ln in f:
                if ln.startswith("btime "):
                    btime = int(ln.split()[1])
                    break
        entries = os.listdir(root)
    except (OSError, ValueError):
        return []
    if btime is None:
        return []
    out = []
    for e in entries:
        if not e.isdigit():
            continue
        try:
            with open(os.path.join(root, e, "comm"), encoding="utf-8", errors="replace") as f:
                if f.read().strip() not in names:
                    continue
            with open(os.path.join(root, e, "stat"), encoding="utf-8", errors="replace") as f:
                raw = f.read()
            ticks = int(raw[raw.rindex(")") + 2:].split()[19])  # поле 22; после ")" идут поля с 3-го
        except (OSError, ValueError, IndexError):
            continue
        out.append(btime + ticks / hz)
    return out


def _applied_ts(rec):
    """Время последней записи целей: lastAppliedTs (epoch) либо разбор lastApplied."""
    ts = rec.get("lastAppliedTs")
    if isinstance(ts, (int, float)):
        return float(ts)
    try:
        import datetime
        return datetime.datetime.strptime(rec["lastApplied"], "%Y-%m-%dT%H:%M:%S%z").timestamp()
    except (KeyError, ValueError, TypeError):
        return None


# --------------------------------------------------------------------------- план

class Dest:
    """Один файл назначения. data - байты на запись; cmp - то, что сравнивается (для xpi - manifest)."""

    def __init__(self, path, kind, data, cmp=None):
        self.path = path
        self.real = os.path.realpath(path)
        self.kind = kind          # repo | copy | static | xpi
        self.data = data
        self.cmp = data if cmp is None else cmp
        self.current = None       # содержимое сейчас (None - файла нет)
        self.action = "same"      # same | create | update | drift


GENERATED_MARK = "-- СГЕНЕРИРОВАНО zephyrine-settings".encode("utf-8")
GENERATED_WORD = "СГЕНЕРИРОВАН".encode("utf-8")
GENERATED_TOOL = b"zephyrine-settings"


class Plan:
    def __init__(self, engine, target):
        self.engine = engine
        self.t = target
        self.id = target["id"]
        self.state = None         # не None - цель не применяется: later|unmanaged|missing|no-template|error
        self.reason = None
        self.message = None
        self.installed = True
        self.dests = []
        self.skipped = []         # пропущенные назначения: [{"reason", "path"}]
        self.default_cmp = None
        self._default_done = False

    def na(self, state, reason, message=None, installed=True):
        self.state, self.reason, self.message, self.installed = state, reason, message, installed
        return self

    def default_content(self):
        """Вывод при дефолтных настройках (golden) - для приёма файла во владение."""
        if not self._default_done:
            self._default_done = True
            try:
                self.default_cmp = self.engine.render(self.t, default=True)
            except (RenderError, palette.PaletteError, NoTemplate, UnsupportedTarget, OSError, ValueError, KeyError):
                self.default_cmp = None
        return self.default_cmp

    @property
    def drifted(self):
        return [d for d in self.dests if d.action == "drift"]

    @property
    def writes(self):
        return [d for d in self.dests if d.action in ("create", "update")]


def needs_restart(t):
    if "live" in t:
        return not t["live"]
    return not t.get("restart", "").startswith("вживую")


def _read_current(d):
    try:
        with open(d.path, "rb") as f:
            raw = f.read()
    except FileNotFoundError:
        return None
    if d.kind == "xpi":
        try:
            with zipfile.ZipFile(io.BytesIO(raw)) as z:
                return z.read("manifest.json")
        except (zipfile.BadZipFile, KeyError):
            return raw  # не наш xpi: заведомо неизвестное содержимое
    return raw


class Engine:
    def __init__(self, paths):
        self.paths = paths
        self.schema = model.Schema.load(paths.schema_file, paths.targets_file)
        flat = model.Store(paths, self.schema).read_flat()
        self.eff, self.warnings = model.effective(self.schema, flat)
        self.defaults = self.schema.defaults_flat()
        with open(paths.targets_file, encoding="utf-8") as f:
            self.manifest = json.load(f)["targets"]
        self.state = load_state(paths)
        self._inputs = None
        self._ctx = {}
        self._starts = {}

    # ---- перезапуск
    def app_starts(self, app):
        if app not in self._starts:
            self._starts[app] = process_starts(PROC_NAMES[app]) if app in PROC_NAMES else None
        return self._starts[app]

    def restart_state(self, t):
        """-> (pending, running). pending - реально нужен перезапуск: записано, не подтверждено (ack) и
        (если у приложения есть процесс) оно запущено и старше последней записи целей. running: None - у
        приложения нет процесса (только ack), иначе bool."""
        rec = self.state["targets"].get(t["id"], {})
        starts = self.app_starts(APP_OF.get(t["id"], t["id"]))
        running = None if starts is None else bool(starts)
        if not (rec.get("restartPending") and needs_restart(t)):
            return False, running
        if starts is None:
            return True, None
        if not starts:
            return False, False  # не запущено: подхватит при старте
        ts = _applied_ts(rec)
        return (ts is None or min(starts) <= ts), True

    def pending_apps(self):
        return _dedupe(APP_OF.get(t["id"], t["id"]) for t in self.manifest if self.restart_state(t)[0])

    def known_apps(self):
        return sorted({APP_OF.get(t["id"], t["id"]) for t in self.manifest if needs_restart(t)})

    def ack_restart(self, apps):
        """Сбрасывает restartPending целей приложений `apps` (None - всех). -> (acked_targets, unknown_apps)."""
        known = self.known_apps()
        want = None if not apps else list(apps)
        unknown = [a for a in (want or []) if a not in known and a not in {t["id"] for t in self.manifest}]
        acked = []
        for t in self.manifest:
            app = APP_OF.get(t["id"], t["id"])
            if want is not None and app not in want and t["id"] not in want:
                continue
            rec = self.state["targets"].get(t["id"])
            if rec and rec.get("restartPending"):
                rec["restartPending"] = False
                rec["restartAckedAt"] = _now()
                acked.append(t["id"])
        return acked, unknown

    # ---- контекст
    def inputs(self):
        if self._inputs is None:
            self._inputs = palette.load_inputs(self.paths)
        return self._inputs

    def tb_version(self):
        n = self.state["meta"].get("tbVersion", 0)
        return "1.0" if not n else "1.0.%d" % n

    def ctx(self, default=False):
        if default not in self._ctx:
            scheme, roles = self.inputs()
            if default == "alt":
                # те же настройки, но ПРОТИВОПОЛОЖНЫЙ режим темы (для приёма файла, записанного в другом режиме)
                vals = dict(self.eff)
                vals[palette.MODE_KEY] = "dark" if palette.mode_of(self.eff) == "light" else "light"
                self._ctx[default] = palette.build_context(scheme, roles, vals, self.defaults,
                                                           {"tbVersion": self.tb_version()})
            elif default:
                self._ctx[default] = palette.build_context(scheme, roles, self.defaults, self.defaults)
            else:
                self._ctx[default] = palette.build_context(scheme, roles, self.eff, self.defaults,
                                                           {"tbVersion": self.tb_version()})
        return self._ctx[default]

    # ---- рендер
    def template_path(self, t):
        rel = t.get("template")
        if not rel:
            return None
        for base in (self.paths.settings_dir, self.paths.root):
            p = os.path.join(base, rel)
            if os.path.isfile(p):
                return p
        return None

    def render(self, t, default=False):
        """-> bytes вывода цели. NoTemplate / UnsupportedTarget / RenderError / PaletteError."""
        kind, tid = t["kind"], t["id"]
        if kind == "template":
            tp = self.template_path(t)
            if tp is None:
                raise NoTemplate(t.get("template"))
            with open(tp, "rb") as f:
                text = f.read().decode("utf-8")
            return TemplateRenderer(self.ctx(default)).render(text).encode("utf-8")
        if kind == "data" and tid == "quickshell":
            scheme, _ = self.inputs()
            return palette.override_text(scheme, self.ctx(default)["c"]).encode("utf-8")
        if kind == "emit":
            fn = _emitter(tid)
            if fn is None:
                raise NoTemplate("zsettings.%s.emit" % tid.replace("-", "_"))
            values = self.defaults if default else self.eff
            return fn(values, self.ctx(default), self.paths).encode("utf-8")
        raise UnsupportedTarget(kind)

    # ---- обнаружение
    def detect(self, t):
        d = t.get("detect") or {"type": "always"}
        typ = d.get("type", "always")
        if typ == "command":
            return (True, None) if shutil.which(d["name"]) else (False, "not-installed")
        if typ == "file":
            return (True, None) if os.path.exists(expand(self.paths, d["path"])) else (False, _file_reason(t))
        return True, None

    # ---- план
    def plan(self, t):
        p = Plan(self, t)
        tid = t["id"]
        stage = t.get("stage", "v1")
        if not patch.handles(t) and (stage not in SUPPORTED_STAGES or t["kind"] not in SUPPORTED_KINDS):
            return p.na("later", "stage-not-implemented", "stage %s, kind %s" % (stage, t["kind"]))
        if self.eff.get(t.get("manageKey") or "appearance.targets." + tid, True) is False:
            return p.na("unmanaged", "not-managed")
        ok, reason = self.detect(t)
        if not ok:
            return p.na("missing", reason, installed=False)
        if patch.handles(t):  # правка отдельных ключей существующего файла (zsettings/patch.py)
            return patch.plan(self, t, p)
        try:
            data = self.render(t)
        except NoTemplate as e:
            return p.na("no-template", "no-template", str(e))
        except UnsupportedTarget as e:
            return p.na("later", "kind-not-implemented", str(e))
        except (RenderError, palette.PaletteError, OSError, ValueError, KeyError) as e:
            return p.na("error", "render-error", "%s: %s" % (type(e).__name__, e))
        is_writable_root = os.access(self.paths.root, os.W_OK) and not self.paths.root.startswith("/usr")
        if is_writable_root:
            p.dests.append(Dest(os.path.join(self.paths.root, t["output"]), "repo", data))
        else:
            deploy = t.get("deploy", "none")
            if deploy == "none":
                out = t.get("output", "")
                if out.startswith(".config/"):
                    self._add(p, Dest(os.path.join(self.paths.home, out), "copy", data))
                elif t.get("id") == "quickshell":
                    self._add(p, Dest(os.path.join(self.paths.state, "scheme.override.json"), "copy", data))
                elif t.get("id") == "sddm":
                    self._add(p, Dest(os.path.join(self.paths.state, "sddm-theme.conf.user"), "copy", data))
        try:
            self._deploy(t, p, data)
            self._evaluate(p)
        except _NoDest as e:
            p.dests = []
            return p.na("missing", e.args[0], installed=False)
        except OSError as e:
            p.dests = []
            return p.na("error", "io-error", str(e))
        return p

    def _add(self, p, dest):
        if all(d.real != dest.real for d in p.dests):
            p.dests.append(dest)

    def _deploy(self, t, p, data):
        deploy = t.get("deploy", "none")
        if deploy == "none":
            return
        if deploy.startswith("copy:"):
            self._add(p, Dest(expand(self.paths, deploy[5:]), "copy", data))
            return
        rel = _deploy_rel(t)
        if deploy == "obsidian-vaults":
            reg = expand(self.paths, t.get("registry", "~/.config/obsidian/obsidian.json"))
            static = _static_siblings(self.paths, t)
            usable = 0
            for v in obsidian_vaults(reg):
                if not os.path.isdir(v):
                    p.skipped.append({"reason": "vault-not-mounted", "path": v})
                elif not os.path.isdir(os.path.join(v, ".obsidian")):
                    p.skipped.append({"reason": "no-obsidian-dir", "path": v})
                else:
                    usable += 1
                    self._add(p, Dest(os.path.join(v, rel), "copy", data))
                    for name, sdata in static:
                        self._add(p, Dest(os.path.join(v, os.path.dirname(rel), name), "static", sdata))
            if not usable:
                raise _NoDest("no-vaults")
        elif deploy in ("zen-profile", "tb-profile", "tb-xpi"):
            prof_spec = t.get("profile") or {}
            root = expand(self.paths, prof_spec.get("root", "~/.config/" + ("zen" if deploy == "zen-profile" else "thunderbird")))
            prof, reason = find_profile(root, prof_spec.get("registry", "installs.ini"), prof_spec.get("key", "Default"))
            if prof is None:
                raise _NoDest(reason)
            if deploy == "tb-xpi":
                self._add(p, Dest(os.path.join(prof, rel), "xpi", build_xpi(data), cmp=data))
            else:
                self._add(p, Dest(os.path.join(prof, rel), "copy", data))
        else:
            raise ValueError("unknown deploy %r" % deploy)

    def _evaluate(self, p):
        rec = self.state["targets"].get(p.id, {}).get("paths", {})
        repo = p.dests[0]
        for d in p.dests:
            d.current = _read_current(d)
        for d in p.dests:
            if d.current is None:
                d.action = "create"
            elif d.current == d.cmp:
                d.action = "same"
            elif d.kind == "static" or sha256_bytes(d.current) in rec.get(d.real, {}).get("known", []):
                d.action = "update"
            elif self._adoptable(p, d, repo):
                d.action = "update"
            else:
                d.action = "drift"

    def _adoptable(self, p, d, repo):
        """Приём во владение: файл без записи, равный golden (дефолтный вывод) или текущему файлу в репо."""
        if d.current == p.default_content():
            return True
        # Файл с нетронутой шапкой «СГЕНЕРИРОВАНО… zephyrine-settings» (settings.lua, hyprlock.conf, theme.conf.user): его принёс
        # git pull или другая сборка, руками его не правят (в шапке так и сказано). Приём во владение; прежнее содержимое
        # уйдёт в бэкап при записи.
        if d.current is not None and (d.current.startswith(GENERATED_MARK)
                                      or (GENERATED_WORD in d.current[:2048] and GENERATED_TOOL in d.current[:2048])):
            return True
        # Вывод в ДРУГОМ режиме темы при тех же настройках (файл в репо пришёл из git, а state помнит старое содержимое):
        # переключение тёмная <-> светлая не должно упираться в drift.
        if p.t.get("kind") in ("template", "data") and d.current is not None:
            try:
                if d.current == self.render(p.t, default="alt"):
                    return True
            except Exception:  # noqa: BLE001 - другой режим может быть недопустим (акцент) - тогда не принимаем
                pass
        return d is not repo and repo.current is not None and d.current == repo.current

    # ---- apply
    def apply(self, targets, dry_run, force, no_exec, reason):
        explicit = bool(targets)
        by_id = {t["id"]: t for t in self.manifest}
        ids = list(targets) if explicit else [t["id"] for t in self.manifest]
        out = {"ok": True, "changed": [], "actions": [], "actionsSkipped": [], "restart": [],
               "restartTargets": [], "skipped": [], "errors": [], "backup": None, "drift": [],
               "unchanged": []}
        if dry_run:
            out["dryRun"] = True
        if self.warnings:
            out["warnings"] = list(self.warnings)
        todo = []
        cmd_changed = []   # цели kind=command (wallpaper): без файлов, свой apply в zsettings/<id>.py
        for tid in ids:
            t = by_id.get(tid)
            if t is None:
                out["errors"].append({"target": tid, "error": "unknown target"})
                continue
            if t["kind"] == "command" and self._command_hook(t) is not None:
                if self._apply_command(t, out, dry_run, no_exec, explicit):
                    cmd_changed.append(tid)
                continue
            p = self.plan(t)
            if p.state:
                self._report_na(p, out, explicit)
                continue
            for s in p.skipped:
                out["skipped"].append({"target": tid, **s})
            if p.drifted and not force:
                out["drift"].append(tid)
                out["errors"].append({"target": tid, "error": "drift",
                                      "paths": [d.path for d in p.drifted]})
                continue
            for d in p.drifted:  # --force: перезаписываем (содержимое уйдёт в бэкап)
                d.action = "update"
            if p.writes:
                todo.append(p)
            else:
                out["unchanged"].append(tid)
                if not dry_run:
                    self._record(p, changed=False)
        if dry_run:
            out["changed"] = [p.id for p in todo] + cmd_changed
            self._finish(out, todo, force)
            return out
        files = []
        for p in todo:
            files += [d.real for d in p.dests if d.action == "update" and os.path.isfile(d.real)]
        if files:
            out["backup"] = backup.create(self.paths, sorted(set(files)), reason)
        for p in todo:
            self._write_target(p, out, no_exec)
        save_state_if_changed(self)
        self._finish(out, todo, force)
        return out

    # ---- цели kind=command: логика в zsettings/<id цели>.py (apply_command / status_info)
    @staticmethod
    def _command_hook(t):
        import importlib
        name = "zsettings." + t["id"].replace("-", "_")
        try:
            mod = importlib.import_module(name)
        except ModuleNotFoundError as e:
            if e.name == name:
                return None
            raise
        return mod if hasattr(mod, "apply_command") else None

    def _apply_command(self, t, out, dry_run, no_exec, explicit):
        mod = self._command_hook(t)
        try:
            return mod.apply_command(self, t, out, dry_run=dry_run, no_exec=no_exec, explicit=explicit)
        except OSError as e:
            out["errors"].append({"target": t["id"], "error": "%s: %s" % (type(e).__name__, e)})
            return False

    def _finish(self, out, todo, force):
        by_id = {t["id"]: t for t in self.manifest}
        out["restart"] = _dedupe(APP_OF.get(i, i) for i in out["restartTargets"] if self.restart_state(by_id[i])[0])
        out["restartPending"] = self.pending_apps()
        out["ok"] = not out["errors"]
        if out["drift"] and not force:
            out["exit"] = 4

    @staticmethod
    def _report_na(p, out, explicit):
        if p.state == "later" and not explicit:
            return
        if p.state == "error":
            out["errors"].append({"target": p.id, "error": p.message or p.reason})
            return
        e = {"target": p.id, "reason": p.reason}
        if p.message:
            e["message"] = p.message
        out["skipped"].append(e)

    def _write_target(self, p, out, no_exec):
        t = p.t
        repo = p.dests[0]
        err = self._precheck(t, repo, no_exec)
        if err:
            out["errors"].append({"target": p.id, "error": err})
            return
        prev_rec = copy.deepcopy(self.state["targets"].get(p.id))
        try:
            for d in p.writes:
                atomic_write(d.path, d.data)
        except OSError as e:
            out["errors"].append({"target": p.id, "error": "write failed: %s" % e})
            return
        self._record(p, changed=True)
        if self._reload(t, p, no_exec, out, prev_rec):
            out["changed"].append(p.id)
            if needs_restart(t):
                out["restartTargets"].append(p.id)

    def _record(self, p, changed):
        rec = self.state["targets"].setdefault(p.id, {})
        paths_rec = rec.setdefault("paths", {})
        for d in p.dests:
            sha = sha256_bytes(d.cmp)
            e = paths_rec.setdefault(d.real, {})
            known = [s for s in e.get("known", []) if s != sha] + [sha]
            e["known"] = known[-KNOWN_KEEP:]
            e["sha256"] = sha
        rec["sha256"] = sha256_bytes(p.dests[0].cmp)
        if changed:
            rec["lastApplied"] = _now()
            rec["lastAppliedTs"] = round(time.time(), 3)
            rec["restartPending"] = needs_restart(p.t)
            rec.pop("restartAckedAt", None)

    # ---- reload и проверки
    def _precheck(self, t, repo, no_exec):
        """luac -p перед записью lua-вывода (DESIGN §3.9). -> текст ошибки | None."""
        if no_exec or not t["output"].endswith(".lua"):
            return None
        luac = shutil.which("luac")
        if not luac:
            return None
        with tempfile.TemporaryDirectory(prefix="zs-luac-") as td:
            f = os.path.join(td, "check.lua")
            with open(f, "wb") as fh:
                fh.write(repo.data)
            r = subprocess.run([luac, "-p", f], capture_output=True, text=True, timeout=RELOAD_TIMEOUT,
                               stdin=subprocess.DEVNULL)
        if r.returncode != 0:
            return "luac -p: %s" % ((r.stderr or r.stdout).strip() or "syntax error")
        return None

    def _reload(self, t, p, no_exec, out, prev_rec):
        """Выполняет reload-действие цели. -> False, если вывод откатан (ошибка конфига Hyprland)."""
        name = t.get("reload", "none")
        if name == "none":
            return True
        defaults = {"kitty-usr1": ["pkill", "-USR1", "-x", "kitty"],
                    "hypr-reload": ["hyprctl", "reload", "config-only"],
                    "hypridle-restart": ["sh", "-c", "if pgrep -x hypridle >/dev/null; then pkill -x hypridle && setsid hypridle >/dev/null 2>&1 & fi"]}
        cmd = t.get("reloadCmd") or defaults.get(name)
        if cmd is None:
            out["skipped"].append({"target": p.id, "reason": "reload-not-implemented:" + name})
            return True
        label = "%s:%s" % (p.id, name.split("-", 1)[-1])
        if no_exec:
            out["actionsSkipped"].append(label)
            return True
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=RELOAD_TIMEOUT, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired) as e:
            out["errors"].append({"target": p.id, "error": "reload %s failed: %s" % (name, e)})
            return True
        # pkill: 1 = нет процессов kitty / hypridle - не ошибка
        if r.returncode != 0 and not (name in ("kitty-usr1", "hypridle-restart") and r.returncode == 1):
            out["errors"].append({"target": p.id, "error": "reload %s: exit %d %s" % (
                name, r.returncode, (r.stderr or r.stdout).strip())})
            return True
        out["actions"].append(label)
        if name == "hypr-reload":
            return self._hypr_postcheck(t, p, out, prev_rec)
        return True

    def _hypr_postcheck(self, t, p, out, prev_rec):
        """`hyprctl configerrors` пуст, иначе откат прежнего содержимого + повторный reload (§3.9)."""
        try:
            r = subprocess.run(["hyprctl", "configerrors"], capture_output=True, text=True,
                               timeout=RELOAD_TIMEOUT, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            return True
        text = (r.stdout or "").strip()
        if not text:
            return True
        repo = p.dests[0]
        if repo.current is None:
            try:
                os.unlink(repo.real)
            except OSError:
                pass
        else:
            atomic_write(repo.path, repo.current)
        if prev_rec is None:
            self.state["targets"].pop(p.id, None)
        else:
            self.state["targets"][p.id] = prev_rec
        try:
            subprocess.run(["hyprctl", "reload", "config-only"], capture_output=True, text=True,
                           timeout=RELOAD_TIMEOUT, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            pass
        out["errors"].append({"target": p.id, "error": "hyprctl configerrors: %s (вывод откатан)" % text})
        return False

    # ---- status
    def status_of(self, t):
        p = self.plan(t)
        rec = self.state["targets"].get(t["id"], {})
        pending, running = self.restart_state(t)
        cmd_mod = self._command_hook(t) if t["kind"] == "command" else None
        info = {"id": t["id"], "stage": t.get("stage"), "kind": t["kind"], "app": APP_OF.get(t["id"], t["id"]),
                "managed": p.state != "unmanaged", "installed": p.installed,
                "restart": t.get("restart"), "needsRestart": needs_restart(t),
                "restartPending": pending, "appRunning": running,
                "restartAckedAt": rec.get("restartAckedAt"),
                "lastApplied": rec.get("lastApplied"), "drift": False, "reason": p.reason,
                "paths": [], "skippedPaths": p.skipped}
        if cmd_mod is not None:
            return cmd_mod.status_info(self, t, info)
        if p.message:
            info["message"] = p.message
        if p.state:
            info["state"] = p.state
            return info
        info["paths"] = [{"path": d.path, "kind": d.kind, "action": d.action} for d in p.dests]
        actions = {d.action for d in p.dests}
        info["drift"] = "drift" in actions
        if info["drift"]:
            info["state"] = "manual"
        elif "create" in actions:
            info["state"], info["reason"] = "missing", "not-deployed"
        elif "update" in actions:
            info["state"] = "outdated"
        elif info["restartPending"] and info["needsRestart"]:
            info["state"] = "restart"
        else:
            info["state"] = "live"
        return info


def _text(b):
    return b.decode("utf-8", errors="replace").splitlines(keepends=True)


def diff_of(engine, tid):
    """Unified diff «сгенерировано vs на диске» по каждому расходящемуся файлу цели (DESIGN §6.3)."""
    t = next((x for x in engine.manifest if x["id"] == tid), None)
    if t is None:
        return None
    p = engine.plan(t)
    out = {"ok": True, "target": tid, "state": p.state, "reason": p.reason, "drift": False, "files": []}
    if p.message:
        out["message"] = p.message
    for d in p.dests:
        if d.action == "same":
            continue
        cur = d.current
        gen = d.cmp
        binary = b"\0" in gen or (cur is not None and b"\0" in cur)
        ent = {"path": d.path, "kind": d.kind, "action": d.action, "exists": cur is not None,
               "binary": binary, "diff": "", "added": 0, "removed": 0, "truncated": False}
        if d.kind == "xpi":
            ent["note"] = "сравнивается manifest.json внутри xpi"
        if not binary:
            lines = list(difflib.unified_diff(_text(gen), _text(cur or b""), "generated: " + d.path,
                                              "disk: " + d.path))
            ent["added"] = sum(1 for ln in lines if ln.startswith("+") and not ln.startswith("+++"))
            ent["removed"] = sum(1 for ln in lines if ln.startswith("-") and not ln.startswith("---"))
            text = "".join(ln if ln.endswith("\n") else ln + "\n\\ No newline at end of file\n" for ln in lines)
            if len(text.encode("utf-8")) > DIFF_MAX_BYTES:
                text = text.encode("utf-8")[:DIFF_MAX_BYTES].decode("utf-8", errors="ignore")
                ent["truncated"] = True
            ent["diff"] = text
        out["files"].append(ent)
    out["drift"] = bool(p.drifted)
    return out


def _file_reason(t):
    d = t.get("deploy", "")
    if d in ("zen-profile", "tb-profile", "tb-xpi"):
        return "profile-not-found"
    if d == "obsidian-vaults":
        return "registry-not-found"
    return "not-installed"


def _static_siblings(paths, t):
    """Статические файлы рядом с выводом (obsidian/Zephyrine/manifest.json) - копируются как есть."""
    d = os.path.dirname(os.path.join(paths.root, t["output"]))
    own = os.path.basename(t["output"])
    out = []
    try:
        for name in sorted(os.listdir(d)):
            fp = os.path.join(d, name)
            if name != own and os.path.isfile(fp):
                with open(fp, "rb") as f:
                    out.append((name, f.read()))
    except OSError:
        pass
    return out


def _emitter(tid):
    import importlib
    name = "zsettings." + tid.replace("-", "_")
    try:
        mod = importlib.import_module(name)
    except ModuleNotFoundError as e:
        if e.name == name:
            return None
        raise
    return getattr(mod, "emit", None)


def _dedupe(items):
    seen, out = set(), []
    for i in items:
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out


def save_state_if_changed(engine):
    before = None
    try:
        with open(state_path(engine.paths), encoding="utf-8") as f:
            before = json.load(f)
    except (OSError, ValueError):
        pass
    if before != engine.state:
        save_state(engine.paths, engine.state)


# --------------------------------------------------------------------------- хуки CLI

def apply(paths, targets, *, dry_run=False, force=False, no_exec=False, reason="apply"):
    with FileLock(paths):
        return Engine(paths).apply(targets, dry_run, force, no_exec, reason)


def status(paths):
    eng = Engine(paths)
    return {"ok": True, "targets": [eng.status_of(t) for t in eng.manifest],
            "restartPending": eng.pending_apps(),
            "state": state_path(paths), "root": paths.root}


def ack_restart(paths, apps):
    """-> dict: acked (цели), apps (запрошенные), unknown. Под flock; пишет generated.json."""
    with FileLock(paths):
        eng = Engine(paths)
        acked, unknown = eng.ack_restart(apps)
        if not unknown:
            save_state_if_changed(eng)
        return {"ok": not unknown, "acked": acked, "apps": list(apps or []) or eng.known_apps(),
                "unknown": unknown, "restartPending": eng.pending_apps()}


def diff(paths, target):
    return diff_of(Engine(paths), target)
