"""История settings.json (для undo) и резервные копии файлов (backup list/restore)."""
import json
import os
import re
import shutil
import time

from .util import atomic_write, ensure_private_dir, sha256_bytes, timestamp

HISTORY_KEEP = 50
BACKUPS_KEEP = 20
_ID_RE = re.compile(r"^[0-9]{8}-[0-9]{6}-[a-z0-9_-]+(?:~[0-9]+)?$")


class BackupError(Exception):
    pass


# ---- история settings.json

def list_history(paths):
    try:
        return sorted(n for n in os.listdir(paths.history_dir) if n.endswith(".json"))
    except FileNotFoundError:
        return []


def push_history(paths, data):
    ensure_private_dir(paths.history_dir)
    existing = list_history(paths)
    ns = time.time_ns()
    name = timestamp(ns) + ".json"
    while existing and name <= existing[-1]:
        ns += 1
        name = timestamp(ns) + ".json"
    atomic_write(os.path.join(paths.history_dir, name), data, mode=0o600)
    for old in list_history(paths)[:-HISTORY_KEEP]:
        try:
            os.unlink(os.path.join(paths.history_dir, old))
        except OSError:
            pass
    return name


def peek_history(paths):
    """(имя, байты) последней записи или None."""
    names = list_history(paths)
    if not names:
        return None
    with open(os.path.join(paths.history_dir, names[-1]), "rb") as f:
        return names[-1], f.read()


def drop_history(paths, name):
    os.unlink(os.path.join(paths.history_dir, name))


# ---- резервные копии

def _safe_reason(reason):
    return re.sub(r"[^a-z0-9_-]+", "-", (reason or "backup").lower()).strip("-") or "backup"


def create(paths, files, reason):
    """Копирует существующие файлы в backups/<ts>-<причина>/ + manifest.json. -> id или None."""
    present = [f for f in files if os.path.isfile(f)]
    if not present:
        return None
    ensure_private_dir(paths.backups_dir)
    base = "%s-%s" % (timestamp(), _safe_reason(reason))
    bid, n = base, 1
    while os.path.exists(os.path.join(paths.backups_dir, bid)):
        n += 1
        bid = "%s~%d" % (base, n)
    d = os.path.join(paths.backups_dir, bid)
    ensure_private_dir(d)
    entries = []
    for i, f in enumerate(present):
        real = os.path.realpath(f)
        with open(real, "rb") as fh:
            data = fh.read()
        stored = "f%d-%s" % (i, os.path.basename(real))
        atomic_write(os.path.join(d, stored), data, mode=0o600)
        entries.append({"path": real, "stored": stored, "sha256": sha256_bytes(data),
                        "size": len(data), "mode": os.stat(real).st_mode & 0o777})
    manifest = {"id": bid, "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "reason": reason, "files": entries}
    atomic_write(os.path.join(d, "manifest.json"),
                 json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", mode=0o600)
    for old in _ids(paths)[:-BACKUPS_KEEP]:
        shutil.rmtree(os.path.join(paths.backups_dir, old), ignore_errors=True)
    return bid


def _ids(paths):
    try:
        return sorted(n for n in os.listdir(paths.backups_dir)
                      if os.path.isfile(os.path.join(paths.backups_dir, n, "manifest.json")))
    except FileNotFoundError:
        return []


def list_backups(paths):
    """Новые первыми: [{id, created, reason, files: [path...]}]."""
    out = []
    for bid in reversed(_ids(paths)):
        try:
            with open(os.path.join(paths.backups_dir, bid, "manifest.json"), encoding="utf-8") as f:
                m = json.load(f)
        except (OSError, ValueError):
            continue
        out.append({"id": bid, "created": m.get("created"), "reason": m.get("reason"),
                    "files": [e["path"] for e in m.get("files", [])]})
    return out


def restore(paths, bid):
    """Возвращает файлы из копии на исходные места (в realpath). Перед этим - копия текущих
    состояний (причина pre-restore). -> (список путей, id страховочной копии)."""
    if not _ID_RE.match(bid or ""):
        raise BackupError("invalid backup id")
    d = os.path.join(paths.backups_dir, bid)
    try:
        with open(os.path.join(d, "manifest.json"), encoding="utf-8") as f:
            m = json.load(f)
    except (OSError, ValueError):
        raise BackupError("backup %s not found" % bid)
    blobs = []
    for e in m["files"]:
        with open(os.path.join(d, e["stored"]), "rb") as fh:
            data = fh.read()
        if sha256_bytes(data) != e["sha256"]:
            raise BackupError("backup %s is corrupted (%s)" % (bid, e["stored"]))
        blobs.append((e, data))
    safety = create(paths, [e["path"] for e, _ in blobs], "pre-restore")
    for e, data in blobs:
        atomic_write(e["path"], data, mode=e.get("mode", 0o644))
    return [e["path"] for e, _ in blobs], safety
