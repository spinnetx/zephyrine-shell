"""Цель `wallpaper` (kind=command, DESIGN §3.2, §4.1, §9.2 A2): видео/картинка обоев.

Выбор живёт в настройках `appearance.wallpaper.desktop` / `.lock` (путь от корня репо либо абсолютный;
`lock = null` - как рабочий стол). Цель делает три вещи:

1. симлинки в состоянии `<state>/wallpaper-desktop` и `<state>/wallpaper-lock` (ведут на выбранный файл);
   их читают `scripts/wallpaper-desktop.sh` (автозапуск mpvpaper) и `scripts/lock-with-video.sh`
   с фолбэком на прежнее видео, если симлинка нет;
2. перезапуск ТОЛЬКО mpvpaper рабочего стола (экземпляр без `-l overlay` / `input-ipc-server`) - сначала
   стартует новый, потом гасится старый (нет мигания пустым столом; упавший новый не убивает старый);
   экземпляр экрана блокировки не трогается никогда;
3. превью каталога обоев через ffmpeg (кадр в `<state>/cache/wallpaper-thumbs/<sha1>.jpg`).

SDDM здесь не трогается: копия видео лежит в системном каталоге, обновляет её `sudo sddm/install-theme.sh`
(он берёт выбранное видео из того же симлинка). UI показывает подсказку (`sddm_info`).

Хуки targets.py: `apply_command(...)`, `status_info(...)`; CLI: `wallpaper list|restart`.
Реальные процессы запускаются/убиваются только без `no_exec`; в тестах подменяются `_spawn`, `_kill`,
`_alive`, `_sleep`, `PROC_ROOT`, `_which`.
"""
import hashlib
import os
import shutil
import signal
import subprocess
import time

from . import model
from .util import ensure_private_dir

KEY_DESKTOP = "appearance.wallpaper.desktop"
KEY_LOCK = "appearance.wallpaper.lock"
MANAGE_KEY = "appearance.targets.wallpaper"
VIDEO_EXT = {".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".gif"}
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
# Те же параметры, что в scripts/wallpaper-desktop.sh (запасной вариант без скрипта).
MPV_OPTS = "no-audio --loop --panscan=1.0 --image-display-duration=inf"
PROC_ROOT = "/proc"          # подменяется в тестах
NEW_GRACE = 1.0              # сколько ждём, что новый mpvpaper не упал, прежде чем гасить старый
KILL_WAIT = 2.0              # сколько ждём выхода старого после SIGTERM
THUMB_W = 320
THUMB_TIMEOUT = 20
_which = shutil.which
_sleep = time.sleep

def _get_sddm_hint():
    if _which("zephyrine-sddm-theme"):
        return "sudo zephyrine-sddm-theme"
    if os.path.isfile("/usr/lib/zephyrine/sddm/install-theme.sh"):
        return "sudo /usr/lib/zephyrine/sddm/install-theme.sh"
    return "sudo install-theme.sh"

SDDM_HINT = _get_sddm_hint()
SDDM_THEMES = ("zephyrine", "mybar")   # где может лежать установленная копия видео (системный каталог)
SDDM_ROOT = "/usr/share/sddm/themes"   # подменяется в тестах


# --------------------------------------------------------------------------- пути и проверка

def media_kind(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in VIDEO_EXT:
        return "video"
    if ext in IMAGE_EXT:
        return "image"
    return None


def resolve(paths, value):
    """Значение настройки -> абсолютный путь (`~` - HOME из Paths; относительный - от корня репо)."""
    if value == "~" or value.startswith("~/"):
        return os.path.join(paths.home, value[2:])
    if os.path.isabs(value):
        return value
    return os.path.join(paths.root, value)


def to_value(paths, abs_path):
    """Абсолютный путь -> значение для settings.json: внутри репо - относительное (переносимо)."""
    root = paths.root.rstrip("/") + "/"
    return abs_path[len(root):] if abs_path.startswith(root) else abs_path


def link_path(paths, which):
    return os.path.join(paths.state, "wallpaper-" + which)


def desired(paths, eff):
    """-> (desktop_abs, lock_abs); lock = null - как рабочий стол."""
    desktop = resolve(paths, eff[KEY_DESKTOP])
    lock = eff.get(KEY_LOCK)
    return desktop, (resolve(paths, lock) if lock else desktop)


def check_file(path):
    """-> текст ошибки | None: файл существует, обычный, поддерживаемого типа."""
    if not os.path.isfile(path):
        return "file not found: %s" % path
    if media_kind(path) is None:
        return "unsupported file type: %s (expected video/image)" % os.path.basename(path)
    return None


def check_values(paths, schema, flat, keys):
    """Семантика, которую схема не умеет: выбранный файл обоев существует. Проверяются только изменяемые
    сейчас ключи (`keys`) - исчезнувший файл не мешает менять остальные настройки. -> [{"key","error"}]."""
    eff, _ = model.effective(schema, flat)
    errors = []
    for k in (KEY_DESKTOP, KEY_LOCK):
        if k in keys and eff.get(k):
            e = check_file(resolve(paths, eff[k]))
            if e:
                errors.append({"key": k, "error": e})
    return errors


# --------------------------------------------------------------------------- симлинки

def read_links(paths):
    out = {}
    for w in ("desktop", "lock"):
        try:
            out[w] = os.readlink(link_path(paths, w))
        except OSError:
            out[w] = None
    return out


def links_needed(paths, want, default_abs):
    """Какие симлинки надо (пере)создать: отличаются от `want`. Отсутствие симлинка допустимо, пока выбран
    файл по умолчанию: скрипты берут его фолбэком, лишний симлинк не нужен."""
    cur = read_links(paths)
    return [w for w in ("desktop", "lock")
            if cur[w] != want[w] and not (cur[w] is None and _same_path(want[w], default_abs))]


def _same_path(a, b):
    return os.path.normpath(a) == os.path.normpath(b)


def sync_links(paths, want, which=("desktop", "lock")):
    """Переключает симлинки `which` на `want` ({"desktop","lock"}); атомарно (tmp-симлинк + rename).
    -> список изменившихся ("desktop"/"lock")."""
    cur = read_links(paths)
    changed = []
    for w in which:
        if cur[w] == want[w]:
            continue
        ensure_private_dir(paths.state)
        dst = link_path(paths, w)
        tmp = "%s.tmp%d" % (dst, os.getpid())
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        os.symlink(want[w], tmp)
        os.replace(tmp, dst)
        changed.append(w)
    return changed


# --------------------------------------------------------------------------- mpvpaper

def mpvpaper_instances(proc_root=None):
    """Запущенные mpvpaper: [{"pid","args","lock","file"}]. lock - экземпляр экрана блокировки
    (слой overlay `-l`/`--layer` либо `input-ipc-server`); file - последний аргумент (видео)."""
    root = proc_root or PROC_ROOT
    try:
        entries = sorted(os.listdir(root), key=lambda e: int(e) if e.isdigit() else -1)
    except OSError:
        return []
    out = []
    for e in entries:
        if not e.isdigit():
            continue
        try:
            with open(os.path.join(root, e, "comm"), encoding="utf-8", errors="replace") as f:
                if f.read().strip() != "mpvpaper":
                    continue
            with open(os.path.join(root, e, "cmdline"), "rb") as f:
                raw = f.read()
        except OSError:
            continue
        args = [a.decode("utf-8", errors="replace") for a in raw.split(b"\0") if a]
        lock = any(a in ("-l", "--layer") for a in args) or any("input-ipc-server" in a for a in args)
        out.append({"pid": int(e), "args": args, "lock": lock, "file": args[-1] if len(args) > 1 else None})
    return out


def desktop_instances(proc_root=None):
    return [i for i in mpvpaper_instances(proc_root) if not i["lock"]]


def _same_file(a, b):
    return a is not None and os.path.realpath(a) == os.path.realpath(b)


def stale_instances(want_desktop, proc_root=None):
    """Экземпляры рабочего стола, играющие не выбранный файл."""
    return [i for i in desktop_instances(proc_root) if not _same_file(i["file"], want_desktop)]


def start_command(paths, want_desktop):
    script = os.path.join(paths.root, "scripts", "wallpaper-desktop.sh")
    if os.access(script, os.X_OK):
        return [script]
    return ["mpvpaper", "-o", MPV_OPTS, "ALL", want_desktop]


def _spawn(cmd, env):
    return subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True, env=env)


def _kill(pid, sig):
    os.kill(pid, sig)


def _alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    try:  # зомби (дочерний, не прибранный) считаем завершённым
        with open("/proc/%d/stat" % pid, encoding="utf-8", errors="replace") as f:
            raw = f.read()
        return raw[raw.rindex(")") + 2:][:1] != "Z"
    except (OSError, ValueError):
        return True


def restart_desktop(paths, want_desktop, *, no_exec=False):
    """Перезапуск mpvpaper РАБОЧЕГО СТОЛА на `want_desktop`. no_exec - только план (ничего не запускает и не
    убивает). -> {"ok", "executed", "command", "old": [pid], "new": pid|None, "error"?}."""
    old = [i["pid"] for i in desktop_instances()]
    cmd = start_command(paths, want_desktop)
    res = {"ok": True, "executed": False, "command": cmd, "old": old, "new": None}
    if no_exec:
        return res
    env = dict(os.environ, ZEPHYRINE_STATE=paths.state)
    try:
        proc = _spawn(cmd, env)
    except OSError as e:
        res.update(ok=False, error="cannot start %s: %s" % (cmd[0], e))
        return res
    res.update(executed=True, new=proc.pid)
    _sleep(NEW_GRACE)
    rc = proc.poll()
    if rc is not None:  # новый не поднялся: старый оставляем играть
        res.update(ok=False, error="mpvpaper exited with %s right after start (old instance kept)" % rc)
        return res
    for pid in old:
        try:
            _kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except OSError as e:
            res.update(ok=False, error="cannot stop pid %d: %s" % (pid, e))
    waited = 0.0
    while waited < KILL_WAIT and any(_alive(p) for p in old):
        _sleep(0.1)
        waited += 0.1
    for pid in old:
        if _alive(pid):
            try:
                _kill(pid, signal.SIGKILL)
            except OSError:
                pass
    return res


# --------------------------------------------------------------------------- превью (ffmpeg)

def thumb_dir(paths):
    return os.path.join(paths.state, "cache", "wallpaper-thumbs")


def thumb_path(paths, src):
    st = os.stat(src)
    key = "%s\0%d\0%d" % (os.path.realpath(src), st.st_size, int(st.st_mtime))
    return os.path.join(thumb_dir(paths), hashlib.sha1(key.encode("utf-8")).hexdigest() + ".jpg")


def make_thumb(paths, src):
    """-> путь превью (создаёт кадром ffmpeg при отсутствии) | None (нет ffmpeg / не вышло)."""
    try:
        dst = thumb_path(paths, src)
    except OSError:
        return None
    if os.path.isfile(dst) and os.path.getsize(dst) > 0:
        return dst
    ffmpeg = _which("ffmpeg")
    if not ffmpeg:
        return None
    ensure_private_dir(os.path.dirname(thumb_dir(paths)))
    ensure_private_dir(thumb_dir(paths))
    tmp = "%s.tmp%d.jpg" % (dst[:-4], os.getpid())
    seeks = [[]] if media_kind(src) == "image" else [["-ss", "2"], []]   # короткое видео: кадр с начала
    for seek in seeks:
        cmd = [ffmpeg, "-y", "-v", "error", "-nostdin"] + seek + ["-i", src, "-frames:v", "1",
               "-vf", "scale=%d:-2" % THUMB_W, "-q:v", "4", tmp]
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=THUMB_TIMEOUT, stdin=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if r.returncode == 0 and os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
            os.replace(tmp, dst)
            return dst
    try:
        os.unlink(tmp)
    except OSError:
        pass
    return None


# --------------------------------------------------------------------------- каталог и SDDM

def catalog(paths):
    """Файлы обоев из стандартных каталогов (рекурсивно, по имени): [{"path","rel","value","name","kind","size"}]."""
    bases = [
        os.path.join(paths.root, "wallpapers"),
        os.path.join(paths.home, ".local", "share", "zephyrine", "wallpapers"),
        os.path.join(paths.home, "Pictures", "Wallpapers"),
        os.path.join(paths.home, "Pictures", "wallpapers"),
        os.path.join(paths.home, "wallpapers"),
    ]
    items = []
    seen = set()
    for base in bases:
        if not os.path.isdir(base):
            continue
        for dirpath, dirs, files in os.walk(base):
            dirs.sort()
            for fn in sorted(files):
                p = os.path.join(dirpath, fn)
                rp = os.path.realpath(p)
                if rp in seen:
                    continue
                seen.add(rp)
                kind = media_kind(p)
                if kind is None or not os.path.isfile(p):
                    continue
                try:
                    size = os.path.getsize(p)
                except OSError:
                    continue
                if p.startswith(paths.root.rstrip("/") + "/"):
                    rel = os.path.relpath(p, paths.root)
                elif p.startswith(paths.home.rstrip("/") + "/"):
                    rel = "~/" + os.path.relpath(p, paths.home)
                else:
                    rel = p
                items.append({"path": p, "rel": rel, "value": to_value(paths, p),
                              "name": os.path.splitext(fn)[0], "kind": kind, "size": size})
    items.sort(key=lambda i: i["rel"].lower())
    return items


def sddm_info(want_desktop):
    """Подсказка про SDDM: копия видео в системном каталоге обновляется только `sudo install-theme.sh`.
    inSync: True/False - размер установленной копии совпадает/нет с выбранным файлом; None - не определено
    (тема не установлена, выбрана картинка - SDDM берёт только видео)."""
    info = {"hint": SDDM_HINT, "installed": None, "inSync": None}
    for theme in SDDM_THEMES:
        p = os.path.join(SDDM_ROOT, theme, "assets", "background.mp4")
        if os.path.isfile(p):
            info["installed"] = p
            try:
                if media_kind(want_desktop) == "video":
                    info["inSync"] = os.path.getsize(p) == os.path.getsize(want_desktop)
            except OSError:
                pass
            break
    return info


def list_wallpapers(paths, eff, thumbs=True):
    """Ответ `wallpaper list`: каталог + текущий выбор + превью + доступность бэкендов + подсказка SDDM."""
    want_d, want_l = desired(paths, eff)
    items = catalog(paths)
    known = {os.path.realpath(i["path"]) for i in items}
    for p in (want_d, want_l):  # выбранный вручную файл вне каталога тоже показываем
        if os.path.isfile(p) and media_kind(p) and os.path.realpath(p) not in known:
            known.add(os.path.realpath(p))
            items.append({"path": p, "rel": p, "value": to_value(paths, p), "name": os.path.splitext(os.path.basename(p))[0],
                          "kind": media_kind(p), "size": os.path.getsize(p)})
    for i in items:
        i["thumb"] = make_thumb(paths, i["path"]) if thumbs else _cached_thumb(paths, i["path"])
        i["desktop"] = _same_file(i["path"], want_d)
        i["lock"] = _same_file(i["path"], want_l)
    return {"ok": True, "items": items, "desktop": want_d, "lock": want_l,
            "default": resolve(paths, _default(paths)), "ffmpeg": bool(_which("ffmpeg")),
            "mpvpaper": bool(_which("mpvpaper")), "sddm": sddm_info(want_d)}


def _cached_thumb(paths, src):
    try:
        p = thumb_path(paths, src)
    except OSError:
        return None
    return p if os.path.isfile(p) and os.path.getsize(p) > 0 else None


def _default(paths):
    schema = model.Schema.load(paths.schema_file, paths.targets_file)
    return schema.default(KEY_DESKTOP)


# --------------------------------------------------------------------------- хуки targets.py

def _target_state(engine, t):
    """-> (state|None, reason): unmanaged / missing (нет mpvpaper) / None - можно работать."""
    if engine.eff.get(t.get("manageKey") or MANAGE_KEY, True) is False:
        return "unmanaged", "not-managed"
    ok, reason = engine.detect(t)
    if not ok:
        return "missing", reason
    return None, None


def apply_command(engine, t, out, *, dry_run, no_exec, explicit):
    """Применение цели из Engine.apply. Дополняет `out` (changed/actions/actionsSkipped/skipped/errors).
    -> True, если цель изменилась (или изменилась бы при dry_run)."""
    paths = engine.paths
    state, reason = _target_state(engine, t)
    if state:
        if explicit or state != "missing":
            out["skipped"].append({"target": t["id"], "reason": reason})
        return False
    want_d, want_l = desired(paths, engine.eff)
    for which, p in (("desktop", want_d), ("lock", want_l)):
        e = check_file(p)
        if e:
            out["errors"].append({"target": t["id"], "error": "%s: %s" % (which, e)})
            return False
    want = {"desktop": want_d, "lock": want_l}
    links_changed = links_needed(paths, want, resolve(paths, engine.schema.default(KEY_DESKTOP)))
    stale = stale_instances(want_d)
    need_restart = bool(stale)
    if not desktop_instances():
        need_restart = False
        if links_changed:
            out["skipped"].append({"target": t["id"], "reason": "mpvpaper-not-running"})
    if dry_run:
        return bool(links_changed or need_restart)
    if links_changed:
        try:
            sync_links(paths, want, links_changed)
        except OSError as e:
            out["errors"].append({"target": t["id"], "error": "symlink failed: %s" % e})
            return False
    restarted = False
    if need_restart:
        if no_exec:
            out["actionsSkipped"].append("wallpaper:restart")
        else:
            r = restart_desktop(paths, want_d)
            if r["ok"]:
                out["actions"].append("wallpaper:restart")
                restarted = True
            else:
                out["errors"].append({"target": t["id"], "error": r["error"]})
    if links_changed or restarted:
        rec = engine.state["targets"].setdefault(t["id"], {})
        rec.update(desktop=want_d, lock=want_l, lastApplied=_now(), lastAppliedTs=round(time.time(), 3))
        out["changed"].append(t["id"])
        return True
    return False


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def status_info(engine, t, info):
    """Дополняет info статуса цели (Engine.status_of): state live|outdated|missing|unmanaged|error."""
    paths = engine.paths
    info["reason"] = None   # от общего plan() (command-цель для него «later») ничего не оставляем
    state, reason = _target_state(engine, t)
    if state:
        info.update(state=state, reason=reason, installed=state != "missing", managed=state != "unmanaged")
        return info
    want_d, want_l = desired(paths, engine.eff)
    err = check_file(want_d) or check_file(want_l)
    cur = read_links(paths)
    need = links_needed(paths, {"desktop": want_d, "lock": want_l}, resolve(paths, engine.schema.default(KEY_DESKTOP)))
    info["paths"] = [{"path": link_path(paths, w), "kind": "symlink",
                      "action": "same" if w not in need else ("create" if cur[w] is None else "update")}
                     for w in ("desktop", "lock")]
    if err:
        info.update(state="error", reason="file-not-found", message=err)
    elif need or (desktop_instances() and stale_instances(want_d)):
        info.update(state="outdated", reason="not-applied")
    else:
        info["state"] = "live"
    return info


def pick_file(paths):
    """Вызов системного диалога выбора файла (zenity / yad / kdialog). -> (code, envelope)."""
    filter_pattern = "*.mp4 *.mkv *.webm *.mov *.avi *.m4v *.gif *.png *.jpg *.jpeg *.webp *.bmp"
    filter_label = "Обои (видео, изображения)"
    title = "Выберите обои (видео или изображение)"

    if _which("zenity"):
        cmd = [
            _which("zenity"), "--file-selection",
            "--title=" + title,
            f"--file-filter={filter_label} | {filter_pattern}",
            "--file-filter=Все файлы | *"
        ]
    elif _which("yad"):
        cmd = [
            _which("yad"), "--file-selection",
            "--title=" + title,
            f"--file-filter={filter_label} | {filter_pattern}",
            "--file-filter=Все файлы | *"
        ]
    elif _which("kdialog"):
        cmd = [
            _which("kdialog"), "--getopenfilename", paths.home,
            f"{filter_pattern}|{filter_label}\n*|Все файлы",
            "--title", title
        ]
    else:
        return 1, {"ok": False, "error": "file chooser dialog not found (install zenity, yad, or kdialog)"}

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e:
        return 1, {"ok": False, "error": "failed to run file chooser: %s" % e}

    if proc.returncode != 0:
        return 0, {"ok": False, "cancelled": True}

    chosen = proc.stdout.strip()
    if not chosen:
        return 0, {"ok": False, "cancelled": True}

    if "|" in chosen:
        chosen = chosen.split("|")[0].strip()

    err = check_file(chosen)
    if err:
        return 2, {"ok": False, "error": err}

    val = to_value(paths, chosen)
    thumb = make_thumb(paths, chosen)
    return 0, {
        "ok": True,
        "path": chosen,
        "value": val,
        "name": os.path.splitext(os.path.basename(chosen))[0],
        "kind": media_kind(chosen),
        "thumb": thumb
    }

