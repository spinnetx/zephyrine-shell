"""Приложения по умолчанию (DESIGN §4.4, Y3): чтение и запись через `gio mime` / `xdg-settings`.

Состояние живёт в ~/.config/mimeapps.list (его ведёт gio), в settings.json ничего не пишется. Категория - набор
MIME-типов; основной тип (первый) даёт список кандидатов и текущее значение, запись идёт по всем типам категории.
"""
import os
import re
import shutil
import subprocess

TIMEOUT = 10
DESKTOP_RE = re.compile(r"^[A-Za-z0-9._\-]+\.desktop$")

# id -> (подпись, [mime-типы]); первый тип - основной
CATEGORIES = {
    "browser": ("Браузер", ["x-scheme-handler/http", "x-scheme-handler/https", "text/html"]),
    "mail": ("Почта", ["x-scheme-handler/mailto"]),
    "files": ("Файлы", ["inode/directory"]),
    "text": ("Текст", ["text/plain"]),
    "pdf": ("PDF", ["application/pdf"]),
    "images": ("Изображения", ["image/png", "image/jpeg", "image/gif", "image/webp", "image/svg+xml"]),
    "video": ("Видео", ["video/mp4", "video/x-matroska", "video/webm"]),
    "audio": ("Аудио", ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav"]),
    "torrent": ("Торренты", ["application/x-bittorrent", "x-scheme-handler/magnet"]),
}


class MimeError(Exception):
    pass


def _run(argv):
    exe = shutil.which(argv[0])
    if exe is None:
        raise MimeError("%s not found" % argv[0])
    try:
        # разбор вывода gio рассчитан на английские заголовки: при русской локали список приложений получался пустым
        env = dict(os.environ, LC_ALL="C", LANGUAGE="C", LANG="C")
        r = subprocess.run([exe] + argv[1:], capture_output=True, text=True, timeout=TIMEOUT,
                           stdin=subprocess.DEVNULL, env=env)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MimeError("%s failed: %s" % (argv[0], e))
    if r.returncode != 0:
        raise MimeError("%s exit %d: %s" % (argv[0], r.returncode, r.stderr.strip()))
    return r.stdout


def parse_gio_mime(text):
    """-> (default | None, registered[], recommended[])."""
    default, registered, recommended, cur = None, [], [], None
    for ln in (text or "").splitlines():
        s = ln.strip()
        if s.startswith("Default application for"):
            m = re.search(r":\s*(\S+\.desktop)\s*$", s)
            default = m.group(1) if m else None
            cur = None
        elif s.startswith("Registered applications"):
            cur = registered
        elif s.startswith("Recommended applications"):
            cur = recommended
        elif s.startswith("No default") or s.startswith("No registered") or s.startswith("No recommended"):
            cur = None
        elif cur is not None and DESKTOP_RE.match(s):
            cur.append(s)
    return default, registered, recommended


def _data_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")
    dirs = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    return [home] + [d for d in dirs if d]


def app_name(desktop_id, data_dirs=None):
    """Name= из .desktop (локализованное Name[ru] в приоритете), иначе id без суффикса."""
    for d in (data_dirs if data_dirs is not None else _data_dirs()):
        path = os.path.join(d, "applications", desktop_id)
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                name = loc = None
                in_entry = False
                for ln in f:
                    ln = ln.strip()
                    if ln.startswith("["):
                        in_entry = ln == "[Desktop Entry]"
                    elif in_entry and ln.startswith("Name="):
                        name = ln[5:]
                    elif in_entry and ln.startswith("Name[ru]="):
                        loc = ln[9:]
                if loc or name:
                    return loc or name
        except OSError:
            continue
    return desktop_id[:-len(".desktop")]


def scan_desktop(types, data_dirs=None):
    """Запасной список: .desktop-файлы, чей MimeType= содержит один из типов (если gio ничего не выдал)."""
    found = []
    for d in (data_dirs if data_dirs is not None else _data_dirs()):
        adir = os.path.join(d, "applications")
        try:
            names = sorted(os.listdir(adir))
        except OSError:
            continue
        for n in names:
            if not DESKTOP_RE.match(n) or n in found:
                continue
            try:
                with open(os.path.join(adir, n), encoding="utf-8", errors="replace") as f:
                    for ln in f:
                        if ln.startswith("MimeType=") and any(t in ln[9:].split(";") for t in types):
                            found.append(n)
                            break
            except OSError:
                continue
    return found


def query(mimetype, runner=_run):
    return parse_gio_mime(runner(["gio", "mime", mimetype]))


def listing(runner=_run, namer=app_name, scanner=scan_desktop):
    """-> [{id, label, current, apps:[{id,name}]}] по всем категориям."""
    out = []
    for cid, (label, types) in CATEGORIES.items():
        item = {"id": cid, "label": label, "current": None, "apps": [], "error": ""}
        try:
            default, registered, recommended = query(types[0], runner)
            ids = list(dict.fromkeys(recommended + registered))
            if not ids:
                ids = scanner(types)
            if default and default not in ids:
                ids.insert(0, default)
            item["current"] = default
            item["apps"] = [{"id": a, "name": namer(a)} for a in ids]
        except MimeError as e:
            item["error"] = str(e)
        out.append(item)
    return out


def set_default(category, desktop_id, runner=_run, no_exec=False):
    """Назначить приложение на все типы категории -> список выполненных команд."""
    if category not in CATEGORIES:
        raise MimeError("unknown category: %s" % category)
    if not DESKTOP_RE.match(desktop_id or ""):
        raise MimeError("invalid desktop file id: %r" % (desktop_id,))
    cmds = [["gio", "mime", t, desktop_id] for t in CATEGORIES[category][1]]
    if category == "browser":
        cmds.append(["xdg-settings", "set", "default-web-browser", desktop_id])
    if not no_exec:
        for c in cmds:
            try:
                runner(c)
            except MimeError:
                if c[0] == "xdg-settings":   # опционально: без xdg-settings gio-записей достаточно
                    continue
                raise
    return [" ".join(c) for c in cmds]
