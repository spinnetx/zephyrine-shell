"""Темы иконок и курсора мыши: сканирование, превью, проверка значений `appearance.icons.theme` /
`appearance.cursor.theme` (DESIGN §3.11).

Темы лежат по спецификации Icon Theme: `$HOME/.icons`, `$XDG_DATA_HOME/icons` (по умолчанию `~/.local/share/icons`),
`<каталог из $XDG_DATA_DIRS>/icons` (по умолчанию `/usr/local/share:/usr/share`). Переменная `ZEPHYRINE_ICON_DIRS`
(список через `:`) заменяет весь этот поиск - для тестов. Имя темы - имя её каталога (его ждут GTK, gsettings, Xcursor).

  иконки  - каталог с `index.theme`, у которого в `[Icon Theme]` есть `Directories` и нет `Hidden=true`
            (`hicolor` - служебный запасной набор, в выбор не попадает);
  курсоры - каталог с подкаталогом `cursors` (или `cursors_scalable`).

Превью: у иконок - до 5 файлов из темы (папка, терминал, браузер, настройки, текст); у курсоров - PNG кадров
`left_ptr` / `pointer` / `text` из Xcursor-файлов (разбор формата здесь, без внешних утилит), кэш
`<state>/cache/cursor-thumbs/`.
"""
import os
import re
import struct
import zlib

KINDS = ("icons", "cursors")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+ -]{0,63}$")
SKIP_ICON_THEMES = {"hicolor"}
ICON_SAMPLES = ("folder", "utilities-terminal", "web-browser", "preferences-system", "text-x-generic")
ICON_EXT = (".svg", ".png", ".xpm")
# кадры курсора для превью: первое найденное имя из группы (в темах стрелка бывает `left_ptr`, `default` и т.д.)
CURSOR_SAMPLES = (("left_ptr", "default", "arrow"), ("pointer", "hand2", "hand1", "pointing_hand"),
                  ("text", "xterm", "ibeam"))
CURSOR_PREVIEW_SIZE = 32


class ThemesError(Exception):
    pass


def search_dirs(home, env=None):
    env = os.environ if env is None else env
    override = env.get("ZEPHYRINE_ICON_DIRS")
    if override is not None:
        return [d for d in override.split(os.pathsep) if d]
    data_home = env.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    data_dirs = (env.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    dirs = [os.path.join(home, ".icons"), os.path.join(data_home, "icons")]
    dirs += [os.path.join(d, "icons") for d in data_dirs if d]
    out = []
    for d in dirs:
        if d not in out:
            out.append(d)
    return out


def _index(path):
    """[Icon Theme] из index.theme -> {ключ: значение} (пустой, если файла/секции нет)."""
    try:
        with open(os.path.join(path, "index.theme"), encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return {}
    cur, out = None, {}
    for ln in lines:
        ln = ln.strip()
        if ln.startswith("[") and ln.endswith("]"):
            cur = ln[1:-1]
        elif cur == "Icon Theme" and "=" in ln and not ln.startswith("#"):
            k, v = ln.split("=", 1)
            out.setdefault(k.strip(), v.strip())
    return out


def _is_icon_theme(path, name):
    if name in SKIP_ICON_THEMES:
        return False
    idx = _index(path)
    if not idx.get("Directories") and not idx.get("ScaledDirectories"):
        return False
    return idx.get("Hidden", "false").lower() != "true"


def _is_cursor_theme(path):
    return any(os.path.isdir(os.path.join(path, d)) for d in ("cursors", "cursors_scalable"))


def scan(kind, home, env=None):
    """-> [{"name", "path"}] без повторов (при совпадении имён побеждает каталог, найденный первым), по алфавиту."""
    if kind not in KINDS:
        raise ThemesError("unknown kind %r" % kind)
    seen = {}
    for base in search_dirs(home, env):
        try:
            names = os.listdir(base)
        except OSError:
            continue
        for name in names:
            path = os.path.join(base, name)
            if name in seen or not NAME_RE.match(name) or not os.path.isdir(path):
                continue
            ok = _is_icon_theme(path, name) if kind == "icons" else _is_cursor_theme(path)
            if ok:
                seen[name] = path
    return [{"name": n, "path": seen[n]} for n in sorted(seen, key=str.casefold)]


def names(kind, home, env=None):
    return [t["name"] for t in scan(kind, home, env)]


# --------------------------------------------------------------------------- превью иконок

def _dir_size(entry):
    """Сортировочный ключ каталога Directories: scalable первым, дальше по размеру (64x64, places/48 …) по убыванию."""
    if "scalable" in entry:
        return 10 ** 6
    nums = [int(n) for n in re.findall(r"\d+", entry)]
    return max(nums) if nums else 0


def icon_samples(path, limit=len(ICON_SAMPLES)):
    """Абсолютные пути файлов-образцов иконок темы (только найденные, без поиска в Inherits)."""
    idx = _index(path)
    entries = [e.strip() for e in (idx.get("Directories", "") + "," + idx.get("ScaledDirectories", "")).split(",")
               if e.strip() and ".." not in e and not e.strip().startswith("/")]
    entries.sort(key=_dir_size, reverse=True)
    entries = [e for e in entries if "symbolic" not in e]
    out = []
    for icon in ICON_SAMPLES:
        for e in entries:
            hit = next((p for p in (os.path.join(path, e, icon + x) for x in ICON_EXT) if os.path.isfile(p)), None)
            if hit:
                out.append(hit)
                break
        if len(out) >= limit:
            break
    return out


# --------------------------------------------------------------------------- превью курсора (Xcursor -> PNG)

_XCUR_MAGIC = b"Xcur"
_XCUR_IMAGE = 0xFFFD0002


def read_xcursor(path, want=CURSOR_PREVIEW_SIZE):
    """Кадр Xcursor-файла с номинальным размером, ближайшим к `want` -> (w, h, xhot, yhot, bytes RGBA) или None."""
    try:
        with open(path, "rb") as fh:
            data = fh.read(4 * 1024 * 1024)
        if data[:4] != _XCUR_MAGIC:
            return None
        _hdr, _ver, ntoc = struct.unpack_from("<III", data, 4)
        best = None
        for i in range(min(ntoc, 256)):
            typ, sub, pos = struct.unpack_from("<III", data, 16 + 12 * i)
            if typ == _XCUR_IMAGE and (best is None or abs(sub - want) < abs(best[0] - want)):
                best = (sub, pos)
        if best is None:
            return None
        _hs, _t, _nominal, _v, w, h, xh, yh, _delay = struct.unpack_from("<IIIIIIIII", data, best[1])
        if not (0 < w <= 256 and 0 < h <= 256):
            return None
        raw = data[best[1] + 36: best[1] + 36 + w * h * 4]
        if len(raw) != w * h * 4:
            return None
        rgba = bytearray(w * h * 4)
        for i in range(w * h):  # ARGB (предумноженный, little-endian BGRA в памяти) -> RGBA без предумножения
            b, g, r, a = raw[4 * i: 4 * i + 4]
            if 0 < a < 255:
                r, g, b = min(255, r * 255 // a), min(255, g * 255 // a), min(255, b * 255 // a)
            rgba[4 * i: 4 * i + 4] = bytes((r, g, b, a))
        return w, h, xh, yh, bytes(rgba)
    except (OSError, struct.error):
        return None


def png_bytes(w, h, rgba):
    def chunk(tag, body):
        c = struct.pack(">I", len(body)) + tag + body
        return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    rows = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))


def _cursor_file(path, names_):
    for sub in ("cursors", "cursors_scalable"):
        for n in names_:
            p = os.path.join(path, sub, n)
            if os.path.isfile(p):  # симлинк на файл (`default -> left_ptr`) тоже подходит
                return p
    return None


def cursor_thumbs(paths, name, path):
    """PNG-превью курсора -> [путь] (кэш по имени/mtime каталога cursors; ошибки превью не фатальны)."""
    import hashlib
    out = []
    try:
        mtime = int(os.stat(os.path.join(path, "cursors" if os.path.isdir(os.path.join(path, "cursors")) else "cursors_scalable")).st_mtime)
    except OSError:
        mtime = 0
    cache = os.path.join(paths.state, "cache", "cursor-thumbs")
    key = hashlib.sha1(("%s|%s|%d|v1" % (name, path, mtime)).encode("utf-8")).hexdigest()[:16]
    for i, group in enumerate(CURSOR_SAMPLES):
        dst = os.path.join(cache, "%s-%d.png" % (key, i))
        if os.path.isfile(dst):
            out.append(dst)
            continue
        src = _cursor_file(path, group)
        img = read_xcursor(src) if src else None
        if img is None:
            continue
        try:
            from .util import atomic_write, ensure_private_dir
            ensure_private_dir(os.path.dirname(cache))
            ensure_private_dir(cache)
            atomic_write(dst, png_bytes(img[0], img[1], img[4]))
            out.append(dst)
        except OSError:
            continue
    return out


def listing(kind, paths, thumbs=True, env=None):
    """Ответ CLI `themes --kind …`: [{"name", "path", "samples": [файлы-превью]}]."""
    items = scan(kind, paths.home, env)
    for t in items:
        if not thumbs:
            t["samples"] = []
        elif kind == "icons":
            t["samples"] = icon_samples(t["path"])
        else:
            t["samples"] = cursor_thumbs(paths, t["name"], t["path"])
    return items


# --------------------------------------------------------------------------- проверка значений

KEYS = {"appearance.icons.theme": "icons", "appearance.cursor.theme": "cursors"}


def check_values(paths, schema, flat, keys, env=None):
    """Тема должна быть установлена. Проверяются только изменяемые сейчас ключи, не равные дефолту (reset/undo всегда
    допустимы); если тем такого вида не нашлось вовсе - проверять нечем, ошибок нет. -> [{"key", "error"}]."""
    errors = []
    for key, kind in KEYS.items():
        if key not in keys or key not in flat:
            continue
        v = flat[key]
        if v is None or v == schema.default(key):
            continue
        have = names(kind, paths.home, env)
        if have and v not in have:
            errors.append({"key": key, "error": "%s theme not installed: %s" % (
                "icon" if kind == "icons" else "cursor", v)})
    return errors
