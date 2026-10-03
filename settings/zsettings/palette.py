"""Эффективная палитра и контекст рендера шаблонов (DESIGN §3.3-3.5).

Единственное место, где собирается контекст `{c,s,a,r,d,f,hypr,idle,meta}`: его используют и
`targets.apply`, и тестовый стенд (`testkit.build_context` - тонкая обёртка над `kit_context`),
поэтому стенд и реальное применение не расходятся.

Вход - уже разобранные данные (scheme.json, palette-roles.json, плоские эффективные значения
настроек), файлов модуль почти не читает (только `load_inputs`). Только stdlib.

Контекст:
  c.<ключ>      цвет эффективной палитры (hex без '#', нижний регистр)
  s.<имя>       строковые производные (s.primaryHsl)
  a.glass|surface, r.lg|md|sm|xs   альфы и радиусы
  d.a.*, d.r.*  те же значения при ДЕФОЛТНЫХ настройках (нужны фильтру `anchor`, DESIGN §3.3)
  f.<роль>.family|size, hypr.*, idle.*, meta.*
"""
import copy
import json
import os

from . import color, idle

# Базы, у которых настройка не описана в palette-roles.json (bases.<имя>.settingKey), но известна из DESIGN.
_DEFAULT_BASE_KEYS = {"primary": "appearance.accent"}
DEFAULT_META = {"tbVersion": "1.0"}


class PaletteError(ValueError):
    """Недопустимые входные данные палитры (например, акцент не проходит проверку контраста)."""


# --------------------------------------------------------------------------- файлы

def scheme_path(paths):
    return os.path.join(paths.root, "quickshell", "scheme.json")


def roles_path(paths):
    return os.path.join(paths.settings_dir, "palette-roles.json")


def override_path(paths):
    return os.path.join(paths.root, "quickshell", "scheme.override.json")


def _load_json(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def load_inputs(paths):
    """-> (scheme, roles): разобранные scheme.json и palette-roles.json."""
    return _load_json(scheme_path(paths)), _load_json(roles_path(paths))


# --------------------------------------------------------------------------- значения

def schema_defaults(schema):
    """Плоский словарь дефолтов из разобранного schema.json; шаблонные ключи ('*') и None пропускаются."""
    out = {}
    for k, v in schema.get("keys", {}).items():
        if "*" in k or v.get("default") is None:
            continue
        out[k] = copy.deepcopy(v["default"])
    return out


def _clean(values):
    """Без None (нет значения = ключа нет) - как в schema_defaults."""
    return {k: v for k, v in (values or {}).items() if v is not None}


def _nest(flat, prefix):
    res = {}
    for k, v in flat.items():
        if not k.startswith(prefix):
            continue
        cur = res
        parts = k[len(prefix):].split(".")
        for p in parts[:-1]:
            cur = cur.setdefault(p, {})
        cur[parts[-1]] = v
    return res


def _alpha_radius(vals):
    radius = int(vals.get("appearance.radius", 12))
    return ({"glass": vals.get("appearance.glassAlpha", 0.88),
             "surface": vals.get("appearance.surfaceAlpha", 0.94)},
            {"lg": radius + 2, "md": radius, "sm": max(0, radius - 2), "xs": max(0, radius - 4)})


# --------------------------------------------------------------------------- палитра

def base_colours(scheme):
    """Нормализованные hex-цвета из scheme.json (не-hex значения пропускаются)."""
    base = {}
    for k, v in scheme.get("colours", {}).items():
        try:
            base[k] = color.normalize_hex(v)
        except ValueError:
            pass
    return base


def _anchor_pairs(base, roles, vals):
    """{имя_якоря: (базовое, эффективное)} для всех якорей из roles.derived."""
    bases = roles.get("bases", {})
    pairs = {}
    for spec in roles.get("derived", {}).values():
        name = spec.get("anchor")
        if name in pairs or name not in base:
            continue
        key = bases.get(name, {}).get("settingKey") or _DEFAULT_BASE_KEYS.get(name)
        new = vals.get(key) if key else None
        pairs[name] = (base[name], color.normalize_hex(new) if new else base[name])
    return pairs


MODE_KEY = "appearance.mode"


def mode_of(values):
    """"light" | "dark" по настройке appearance.mode (всё прочее — тёмная)."""
    return "light" if (values or {}).get(MODE_KEY) == "light" else "dark"


def pick_scheme(scheme, roles, values):
    """Базовая схема для режима: тёмная — scheme.json, светлая — roles["schemes"]["light"] (если описана)."""
    if mode_of(values) == "light":
        light = (roles.get("schemes") or {}).get("light")
        if light and light.get("colours"):
            return light
    return scheme


def effective_palette(scheme, roles, values):
    """Эффективная палитра {ключ: hex} = базовая схема режима + деривация от изменённых баз (якорная, §3.5).

    PaletteError, если акцент недопустим (на тёмной: слишком тёмный или контраст к фону < 3:1; на светлой акцент
    сначала приводится к допустимой светлоте, ошибка — только если контраст к фону всё равно < 3:1).
    """
    vals = _clean(values)
    light = mode_of(vals) == "light" and pick_scheme(scheme, roles, vals) is not scheme
    scheme = pick_scheme(scheme, roles, vals)
    akey = roles.get("bases", {}).get("primary", {}).get("settingKey") or _DEFAULT_BASE_KEYS["primary"]
    if light and vals.get(akey):
        vals = dict(vals)
        vals[akey] = color.light_accent(vals[akey])
    base = base_colours(scheme)
    eff = dict(base)
    pairs = _anchor_pairs(base, roles, vals)
    for name, (b, n) in pairs.items():
        if n != b:
            eff[name] = n
    for k, spec in roles.get("derived", {}).items():
        if k not in base:
            continue
        b, n = pairs.get(spec.get("anchor"), (None, None))
        if b is None or b == n:
            continue  # short-circuit: литерал из scheme.json
        eff[k] = color.derive(base[k], b, n)
    accent = vals.get(roles.get("bases", {}).get("primary", {}).get("settingKey")
                      or _DEFAULT_BASE_KEYS["primary"])
    if accent and "background" in eff and "onPrimary" in eff:
        try:
            check = color.validate_accent_light if light else color.validate_accent
            eff["onPrimary"] = check(
                color.normalize_hex(accent), eff["background"], eff["onPrimary"])[0]
        except color.AccentError as e:
            raise PaletteError("акцент %s недопустим: %s" % (accent, e))
    return eff


def override_colours(scheme, eff):
    """Ключи, у которых эффективное значение отличается от базового (порядок как в scheme.json)."""
    base = base_colours(scheme)
    return {k: eff[k] for k in scheme.get("colours", {}) if k in base and eff.get(k, base[k]) != base[k]}


def override_text(scheme, eff):
    """Содержимое quickshell/scheme.override.json (DESIGN D6): только переопределённые ключи."""
    ov = override_colours(scheme, eff)
    if not ov:
        return '{"colours": {}}\n'
    return json.dumps({"colours": ov}, indent=4, ensure_ascii=False) + "\n"


# --------------------------------------------------------------------------- контекст

def build_context(scheme, roles, values, defaults=None, meta=None):
    """Контекст рендера по эффективным значениям `values` (плоский словарь ключей настроек).

    `defaults` - плоские дефолты схемы (для пространства `d`); по умолчанию - сами `values` с
    дефолтными альфами/радиусами, то есть `d` вычисляется из `defaults`, а не из `values`.
    """
    vals = _clean(values)
    dvals = _clean(defaults) if defaults is not None else {}
    eff = effective_palette(scheme, roles, vals)
    base = base_colours(pick_scheme(scheme, roles, vals))
    base_primary, new_primary = base.get("primary"), eff.get("primary")
    s = {}
    for name, spec in roles.get("strings", {}).items():
        if spec.get("mode") == "hsl-string" and spec.get("anchor") == "primary" and new_primary:
            same = new_primary == base_primary
            s[name] = spec["literal"] if same and "literal" in spec and mode_of(vals) != "light" else color.hsl_string(new_primary)
    a, r = _alpha_radius(vals)
    da, dr = _alpha_radius(dvals)
    ctx = {
        "c": eff,
        "s": s,
        "a": a,
        "r": r,
        "d": {"a": da, "r": dr},
        "f": _nest(vals, "appearance.fonts."),
        "hypr": _nest(vals, "hypr."),
        "idle": idle.build_idle_context(vals),
        "meta": dict(DEFAULT_META, **(meta or {})),
        "m": mode_context(vals),
    }
    ctx["hypr"]["rounding"] = vals.get("appearance.windowRounding", 10)
    return ctx


def mode_context(values):
    """Пространство `m` для шаблонов: признаки режима (appearance.mode)."""
    mode = mode_of(values)
    return {"scheme": mode, "cls": "theme-" + mode}


def kit_context(kit, overrides=None):
    """context_fn для testkit: `kit` - testkit.Kit (нужны .scheme, .roles, .schema)."""
    defaults = schema_defaults(kit.schema)
    vals = dict(defaults)
    vals.update(overrides or {})
    return build_context(kit.scheme, kit.roles, vals, defaults)


def check_values(paths, schema, flat):
    """Семантическая проверка набора настроек (то, что схема не умеет): акцент должен давать
    допустимую палитру. -> [{"key", "error"}] (пустой список = всё хорошо).

    Вызывается ДО записи settings.json, чтобы `set appearance.accent=#101030` не оставлял файл с
    значением, которое потом не применить.
    """
    from . import model
    eff, _ = model.effective(schema, flat)
    try:
        scheme, roles = load_inputs(paths)
    except (OSError, ValueError):
        return []  # нет scheme.json - проверять нечего (ошибку покажет apply)
    try:
        effective_palette(scheme, roles, eff)
    except PaletteError as e:
        return [{"key": "appearance.accent", "error": str(e)}]
    return []
