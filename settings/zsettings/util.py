"""Общие утилиты: пути, атомарная запись, flock, JSON-вывод (только stdlib).

Все пути берутся из окружения, чтобы тесты работали в изолированном каталоге:
  ZEPHYRINE_ROOT   корень репо (по умолчанию $HOME/my_zephyrine_conf)
  ZEPHYRINE_STATE  каталог состояния (по умолчанию $HOME/.local/state/zephyrine)
  HOME             домашний каталог
  ZEPHYRINE_LOCK_TIMEOUT  секунд ожидания flock (по умолчанию 5)
"""
import errno
import fcntl
import hashlib
import json
import os
import tempfile
import time
from dataclasses import dataclass


class LockTimeout(Exception):
    pass


@dataclass
class Paths:
    home: str
    root: str
    settings_dir: str
    settings_file: str
    schema_file: str
    targets_file: str
    state: str
    lock_file: str
    history_dir: str
    backups_dir: str
    lock_timeout: float = 5.0

    @classmethod
    def from_env(cls, env=None):
        env = os.environ if env is None else env
        home = env.get("HOME") or os.path.expanduser("~")
        root = env.get("ZEPHYRINE_ROOT") or env.get("ZEPHYRINE_DIR")
        if not root:
            if os.path.isdir(os.path.join(home, "my_zephyrine_conf")):
                root = os.path.join(home, "my_zephyrine_conf")
            elif os.path.isdir("/usr/share/zephyrine"):
                root = "/usr/share/zephyrine"
            elif os.path.isdir(os.path.join(home, ".local", "share", "zephyrine")):
                root = os.path.join(home, ".local", "share", "zephyrine")
            else:
                root = os.path.join(home, "my_zephyrine_conf")

        state = env.get("ZEPHYRINE_STATE") or os.path.join(home, ".local", "state", "zephyrine")
        sdir = os.path.join(root, "settings")

        cfg_home = env.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
        user_cfg = os.path.join(cfg_home, "zephyrine", "settings.json")
        repo_cfg = os.path.join(sdir, "settings.json")

        explicit_file = env.get("ZEPHYRINE_SETTINGS_FILE")
        is_system_root = root.startswith(("/usr", "/opt")) or not os.access(sdir if os.path.isdir(sdir) else root, os.W_OK)
        if explicit_file:
            sfile = explicit_file
        elif is_system_root:
            sfile = user_cfg
        elif os.path.exists(user_cfg) and not os.path.exists(repo_cfg):
            sfile = user_cfg
        else:
            sfile = repo_cfg

        try:
            timeout = float(env.get("ZEPHYRINE_LOCK_TIMEOUT", "5"))
        except ValueError:
            timeout = 5.0
        return cls(
            home=home, root=root, settings_dir=sdir,
            settings_file=sfile,
            schema_file=os.path.join(sdir, "schema.json"),
            targets_file=os.path.join(sdir, "targets.json"),
            state=state,
            lock_file=os.path.join(state, "settings.lock"),
            history_dir=os.path.join(state, "settings-history"),
            backups_dir=os.path.join(state, "backups"),
            lock_timeout=timeout,
        )


def ensure_private_dir(path):
    """Создаёт каталог (и родителей) с правами 700 для последнего уровня."""
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass


def atomic_write(path, data, mode=0o644):
    """Атомарная запись: tmp в каталоге realpath -> fsync -> rename.

    Пишет в realpath, поэтому симлинк `path` остаётся симлинком. Права
    существующего файла сохраняются, иначе берётся `mode`.
    """
    if isinstance(data, str):
        data = data.encode("utf-8")
    real = os.path.realpath(path)
    d = os.path.dirname(real)
    os.makedirs(d, exist_ok=True)
    try:
        mode = os.stat(real).st_mode & 0o777
    except FileNotFoundError:
        pass
    fd, tmp = tempfile.mkstemp(dir=d, prefix="." + os.path.basename(real) + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fchmod(f.fileno(), mode)
            os.fsync(f.fileno())
        os.replace(tmp, real)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    try:
        dfd = os.open(d, os.O_RDONLY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except OSError:
        pass
    return real


class FileLock:
    """flock(LOCK_EX) на settings.lock; реентерабелен в пределах процесса."""
    _depth = 0
    _fd = None

    def __init__(self, paths):
        self.paths = paths

    def __enter__(self):
        cls = FileLock
        if cls._depth > 0:
            cls._depth += 1
            return self
        ensure_private_dir(os.path.dirname(self.paths.lock_file))
        fd = os.open(self.paths.lock_file, os.O_RDWR | os.O_CREAT, 0o600)
        deadline = time.monotonic() + self.paths.lock_timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError as e:
                if e.errno not in (errno.EAGAIN, errno.EACCES):
                    os.close(fd)
                    raise
                if time.monotonic() >= deadline:
                    os.close(fd)
                    raise LockTimeout("settings are locked by another process")
                time.sleep(0.02)
        cls._fd = fd
        cls._depth = 1
        return self

    def __exit__(self, *exc):
        cls = FileLock
        cls._depth -= 1
        if cls._depth == 0:
            try:
                fcntl.flock(cls._fd, fcntl.LOCK_UN)
            finally:
                os.close(cls._fd)
                cls._fd = None
        return False


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def dumps_line(obj):
    """Одна строка JSON (для stdout CLI)."""
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def dumps_file(obj):
    """Формат файлов настроек: отступ 2, UTF-8, завершающий перевод строки."""
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def timestamp(ns=None):
    """YYYYmmdd-HHMMSS[-nnnnnnnnn] (локальное время)."""
    if ns is None:
        return time.strftime("%Y%m%d-%H%M%S")
    return time.strftime("%Y%m%d-%H%M%S", time.localtime(ns // 10**9)) + "-%09d" % (ns % 10**9)
