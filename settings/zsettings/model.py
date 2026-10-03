"""Схема настроек, валидация, разреженный merge, чтение/запись settings.json.

Файл настроек вложенный (`{"appearance": {"glassAlpha": 0.8}}`), схема плоская
(ключ с точками -> описание). Внутри модуля значения живут «плоско»:
`{"appearance.glassAlpha": 0.8}`. В файле хранятся только отличия от дефолтов.

Шаблонные ключи схемы (`appearance.targets.*`, `binds.*`): поле `pattern` у них
описывает ИМЯ ключа (документация), а не значение - как regex оно не применяется.
"""
import copy
import json
import math
import os
import re

from . import backup
from .util import atomic_write, dumps_file

FORMAT_VERSION = 1
_COLOR_RE = r"^#[0-9a-fA-F]{6}$"
_ACTION_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
_SCALAR_TYPES = {"number", "integer", "boolean", "string", "color", "enum", "font", "path",
                 "array", "object"}


class ValidationError(Exception):
    def __init__(self, key, message):
        super().__init__("%s: %s" % (key, message))
        self.key = key
        self.message = message


class StoreError(Exception):
    """settings.json повреждён / неподдерживаемой версии."""


def strict_equal(a, b):
    """Равенство с учётом типов (True != 1, 1 != 1.0 как литералы JSON не важны)."""
    return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


# --------------------------------------------------------------------------- схема

class Schema:
    def __init__(self, keys, target_ids=None):
        self.concrete = {}
        self.templates = {}  # префикс "appearance.targets." -> spec
        for k, spec in keys.items():
            if k.endswith(".*"):
                s = {a: b for a, b in spec.items() if a != "pattern"}
                self.templates[k[:-1]] = s
            else:
                self.concrete[k] = spec
        self.target_ids = None if target_ids is None else list(target_ids)

    @classmethod
    def load(cls, schema_path, targets_path=None):
        with open(schema_path, encoding="utf-8") as f:
            keys = json.load(f)["keys"]
        ids = None
        if targets_path and os.path.exists(targets_path):
            with open(targets_path, encoding="utf-8") as f:
                ids = [t["id"] for t in json.load(f)["targets"]]
        return cls(keys, ids)

    def _template_for(self, key):
        for prefix, spec in self.templates.items():
            if key.startswith(prefix):
                rest = key[len(prefix):]
                if rest and "." not in rest:
                    return prefix, rest, spec
        return None

    def has_key(self, key):
        return key in self.concrete or self._template_for(key) is not None

    def lookup(self, key):
        """Описание ключа или ValidationError (неизвестный ключ / плохой параметр шаблона)."""
        if key in self.concrete:
            return self.concrete[key]
        t = self._template_for(key)
        if t is None:
            raise ValidationError(key, "unknown key")
        prefix, param, spec = t
        if prefix == "appearance.targets.":
            if self.target_ids is not None and param not in self.target_ids:
                raise ValidationError(key, "unknown target id %r" % param)
        elif not _ACTION_RE.match(param):
            raise ValidationError(key, "invalid name %r" % param)
        return spec

    def is_prefix(self, key):
        p = key + "."
        return (any(k.startswith(p) for k in self.concrete)
                or any(t.startswith(p) or t == p for t in self.templates))

    def default(self, key):
        return copy.deepcopy(self.lookup(key).get("default"))

    def defaults_flat(self):
        out = {k: copy.deepcopy(s.get("default")) for k, s in self.concrete.items()}
        if self.target_ids is not None:
            spec = self.templates.get("appearance.targets.")
            if spec is not None:
                for i in self.target_ids:
                    out["appearance.targets." + i] = copy.deepcopy(spec.get("default"))
        return out

    # ---- валидация
    def validate(self, key, value):
        spec = self.lookup(key)
        if spec.get("default") is None and not spec.get("nullable"):
            spec = dict(spec, nullable=True)
        return _check(spec, value, key)

    def affected_targets(self, keys):
        """id целей, которые надо перегенерировать при изменении keys (порядок стабильный)."""
        out = []
        for k in keys:
            try:
                spec = self.lookup(k)
            except ValidationError:
                continue
            for t in spec.get("targets", []):
                if t not in out:
                    out.append(t)
        return out


def _fail(where, msg):
    raise ValidationError(where, msg)


def _field_spec(s):
    return {"type": s} if isinstance(s, str) else s


def _check(spec, v, where):
    t = spec.get("type")
    if v is None:
        if spec.get("nullable"):
            return None
        _fail(where, "null is not allowed")
    if t == "boolean":
        if not isinstance(v, bool):
            _fail(where, "expected boolean")
        return v
    if t in ("integer", "number"):
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            _fail(where, "expected %s" % t)
        if isinstance(v, float) and not math.isfinite(v):
            _fail(where, "not a finite number")
        if t == "integer":
            if isinstance(v, float):
                if not v.is_integer():
                    _fail(where, "expected integer")
                v = int(v)
        else:
            v = float(v)
        if "min" in spec and v < spec["min"]:
            _fail(where, "must be >= %s" % spec["min"])
        if "max" in spec and v > spec["max"]:
            _fail(where, "must be <= %s" % spec["max"])
        return v
    if t in ("string", "color", "enum", "font", "path"):
        if not isinstance(v, str):
            _fail(where, "expected string")
        if "\x00" in v:
            _fail(where, "NUL in string")
        if t in ("font", "path") and not v.strip():
            _fail(where, "must not be empty")
        if t == "font":
            # имя попадает в ini/conf/CSS/gsettings: переводы строк, кавычки и "\" ломают разбор файлов
            if len(v) > 120 or any(ord(c) < 32 or c in '"\\' for c in v):
                _fail(where, "invalid font family name")
        if t == "color":
            if not re.match(spec.get("pattern") or _COLOR_RE, v):
                _fail(where, "expected color #rrggbb")
            return v.lower()
        if t == "enum" and "enum" in spec and v not in spec["enum"]:
            _fail(where, "must be one of: %s" % ", ".join(map(str, spec["enum"])))
        if t == "string" and spec.get("pattern") and not re.search(spec["pattern"], v):
            _fail(where, "does not match %s" % spec["pattern"])
        return v
    if t == "array":
        if not isinstance(v, list):
            _fail(where, "expected array")
        if "minItems" in spec and len(v) < spec["minItems"]:
            _fail(where, "needs at least %d item(s)" % spec["minItems"])
        if "maxItems" in spec and len(v) > spec["maxItems"]:
            _fail(where, "at most %d item(s)" % spec["maxItems"])
        items = spec.get("items")
        if not items:
            return v
        out = []
        for i, el in enumerate(v):
            w = "%s[%d]" % (where, i)
            if isinstance(items.get("type"), str) and items["type"] in _SCALAR_TYPES:
                out.append(_check(items, el, w))
            else:
                out.append(_check_fields(items, el, w))
        return out
    if t == "object":
        return _check_fields(spec.get("items") or {}, v, where)
    _fail(where, "schema has unsupported type %r" % t)


def _check_fields(fields, v, where):
    if not isinstance(v, dict):
        _fail(where, "expected object")
    for k in v:
        if k not in fields:
            _fail("%s.%s" % (where, k), "unknown field")
    out = {}
    for name, fs in fields.items():
        fs = _field_spec(fs)
        w = "%s.%s" % (where, name)
        if name not in v:
            if fs.get("nullable"):
                out[name] = None
                continue
            _fail(w, "missing field")
        out[name] = _check(fs, v[name], w)
    return out


# --------------------------------------------------------------------------- плоское <-> вложенное

def flatten(raw, schema):
    """Вложенный файл -> плоский словарь. `version` пропускается; неизвестные листья сохраняются."""
    flat = {}

    def walk(prefix, d):
        for k, v in d.items():
            p = prefix + "." + k if prefix else k
            if not prefix and k == "version":
                continue
            if schema.has_key(p) or not isinstance(v, dict):
                flat[p] = v
            else:
                walk(p, v)

    walk("", raw)
    return flat


def nest(flat):
    out = {}
    for key in sorted(flat):
        parts = key.split(".")
        d = out
        ok = True
        for p in parts[:-1]:
            nxt = d.setdefault(p, {})
            if not isinstance(nxt, dict):
                ok = False
                break
            d = nxt
        if ok and not isinstance(d.get(parts[-1]), dict):
            d[parts[-1]] = flat[key]
    return out


def effective(schema, flat):
    """(плоские эффективные значения, предупреждения): дефолты + валидные значения из файла."""
    eff = schema.defaults_flat()
    warnings = []
    for k, v in flat.items():
        try:
            eff[k] = schema.validate(k, v)
        except ValidationError as e:
            warnings.append("%s (ignored, default used)" % e)
    return eff, warnings


def apply_updates(schema, flat, updates):
    """updates: [(key, raw_value)] -> (новый flat, изменённые ключи, ошибки).

    Значение, равное дефолту, удаляется из файла (разреженность).
    """
    new = dict(flat)
    changed, errors = [], []
    for key, raw in updates:
        try:
            v = schema.validate(key, raw)
        except ValidationError as e:
            errors.append({"key": e.key, "error": e.message})
            continue
        default = schema.default(key)
        old = flat.get(key, default)
        if strict_equal(v, default):
            new.pop(key, None)
        else:
            new[key] = v
        if not strict_equal(v, old) and key not in changed:
            changed.append(key)
    return new, changed, errors


def remove_keys(schema, flat, keys):
    """reset: удалить ключи (или целые префиксы) из файла. -> (новый flat, изменённые, ошибки)."""
    new = dict(flat)
    changed, errors = [], []
    for key in keys:
        if schema.is_prefix(key):
            hit = [k for k in flat if k.startswith(key + ".")]
        else:
            try:
                schema.lookup(key)
            except ValidationError as e:
                errors.append({"key": e.key, "error": e.message})
                continue
            hit = [key] if key in flat else []
        for k in hit:
            new.pop(k, None)
            if k not in changed:
                changed.append(k)
    return new, changed, errors


def diff_keys(a, b):
    return sorted(k for k in set(a) | set(b) if k not in a or k not in b or not strict_equal(a[k], b[k]))


# --------------------------------------------------------------------------- файл

class Store:
    def __init__(self, paths, schema):
        self.paths = paths
        self.schema = schema

    def read_bytes(self):
        try:
            with open(self.paths.settings_file, "rb") as f:
                return f.read()
        except FileNotFoundError:
            default_path = os.path.join(self.paths.settings_dir, "settings.json")
            if default_path != self.paths.settings_file and os.path.isfile(default_path):
                try:
                    with open(default_path, "rb") as f:
                        return f.read()
                except OSError:
                    pass
            return None

    def parse(self, data):
        if data is None:
            return {}
        try:
            raw = json.loads(data.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as e:
            raise StoreError("settings.json is not valid JSON: %s" % e)
        if not isinstance(raw, dict):
            raise StoreError("settings.json must contain an object")
        ver = raw.get("version", FORMAT_VERSION)
        if ver != FORMAT_VERSION:
            raise StoreError("unsupported settings.json version %r" % (ver,))
        return raw

    def read_flat(self):
        return flatten(self.parse(self.read_bytes()), self.schema)

    def dumps(self, flat):
        d = {"version": FORMAT_VERSION}
        d.update(nest(flat))
        return dumps_file(d)

    def write(self, flat):
        """Пишет settings.json; предыдущая версия уходит в историю. Вызывать под flock."""
        prev = self.read_bytes()
        if prev is None:
            prev = dumps_file({"version": FORMAT_VERSION}).encode()
        data = self.dumps(flat).encode("utf-8")
        if data == prev:
            return False
        backup.push_history(self.paths, prev)
        atomic_write(self.paths.settings_file, data)
        return True
