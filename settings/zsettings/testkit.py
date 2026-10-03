"""Тестовый стенд шаблонов тем (DESIGN §3.6, §8, задача S1.7).

Только stdlib. Три проверки + фикстуры изолированного HOME:

  golden   рендер каждой цели с дефолтами и побайтное сравнение с рукописным файлом
  perturb  подмена одного входа (primary / glass / radius / любой ключ схемы) -> читаемый
           отчёт «какие строки изменились» (+ строки, где осталось СТАРОЕ значение);
           снимки tests/snapshots/perturb/<KEY>.txt (--check / --update)
  lint     неизвестный ключ/фильтр, литеральный цвет вне белого списка, ключи цели,
           которые шаблон не использует (и наоборот)
  home     фикстура изолированного HOME (Zen/Thunderbird/Obsidian, пути с пробелами/скобками)

Подключение к CLI (S1.2):  `from zsettings import testkit; testkit.register(subparsers)`
добавит подкоманду `test` с `golden|perturb|lint|home`; каждая подкоманда имеет
`args.func(args) -> int` (код возврата процесса).  Отдельно работает `bin/zs-test`.

Коды возврата: 0 — всё хорошо (SKIP — не ошибка); 1 — различия/замечания; 2 — ошибка
рендера/нет файла/неверные аргументы; 3 — нет одобренного снимка (perturb --check).

Контекст рендера собирает palette.py (тот же код, что у `targets.apply`); `context_fn` по умолчанию -
`build_context` (обёртка над palette.kit_context, ошибки палитры -> KitError).
"""
import argparse
import difflib
import json
import os
import re
import sys
from pathlib import Path

from . import color, palette
from .render import RenderError, TemplateRenderer

PLACEHOLDER_RE = re.compile(r"\{\{([^}]+)\}\}")
LINT_IGNORE = "zs-lint: ignore"  # маркер в строке шаблона — подавляет lint-замечания по строке

# Маркеры для perturb: алиас -> (ключ схемы, значение-маркер)
PERTURB_ALIASES = {
    "primary": ("appearance.accent", "#ff00ff"),
    "accent": ("appearance.accent", "#ff00ff"),
    "glass": ("appearance.glassAlpha", 0.5),
    "surface": ("appearance.surfaceAlpha", 0.8),
    "radius": ("appearance.radius", 20),
}


class KitError(Exception):
    pass


# --------------------------------------------------------------------------- kit

def _load_json(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


class Kit:
    """Пути и загруженные данные. Все пути переопределяются (тесты работают во временном каталоге)."""

    def __init__(self, root=None, settings_dir=None, scheme=None, targets=None,
                 roles=None, schema=None, snapshots=None):
        here = Path(__file__).resolve().parent.parent  # .../settings
        self.settings_dir = Path(settings_dir) if settings_dir else here
        env_root = os.environ.get("ZEPHYRINE_ROOT")
        self.root = Path(root or env_root or self.settings_dir.parent)
        self.scheme_path = Path(scheme) if scheme else self.root / "quickshell" / "scheme.json"
        self.targets_path = Path(targets) if targets else self.settings_dir / "targets.json"
        self.roles_path = Path(roles) if roles else self.settings_dir / "palette-roles.json"
        self.schema_path = Path(schema) if schema else self.settings_dir / "schema.json"
        self.snapshots = (Path(snapshots) if snapshots
                          else self.settings_dir / "tests" / "snapshots" / "perturb")
        self.targets = _load_json(self.targets_path)["targets"]
        self.roles = _load_json(self.roles_path)
        self.schema = _load_json(self.schema_path)
        self.scheme = _load_json(self.scheme_path)

    def expand(self, p):
        p = os.path.expanduser(p)
        return Path(p) if os.path.isabs(p) else self.root / p

    def template_path(self, target):
        """Шаблон ищется относительно settings/ (DESIGN §2.2), затем относительно корня репо."""
        t = target.get("template")
        if not t:
            return None
        for base in (self.settings_dir, self.root):
            if (base / t).is_file():
                return base / t
        return None

    def golden_path(self, target):
        g = target.get("golden")
        if isinstance(g, str):
            # замороженный golden лежит относительно settings/ (tests/golden/<id>/…)
            p = self.settings_dir / g
            return p if p.is_file() else self.expand(g)
        src = target.get("output")
        return self.expand(src) if src else None

    def select(self, ids=None):
        ts = self.targets
        if ids:
            known = {t["id"] for t in ts}
            bad = [i for i in ids if i not in known]
            if bad:
                raise KitError("неизвестные цели: %s (есть: %s)" % (", ".join(bad), ", ".join(sorted(known))))
            ts = [t for t in ts if t["id"] in ids]
        return ts


# --------------------------------------------------------------------------- контекст

# Контекст рендера собирается в palette.py (единый для стенда и `apply`); здесь только обёртки.
schema_defaults = palette.schema_defaults


def effective_values(kit, overrides=None):
    vals = schema_defaults(kit.schema)
    vals.update(overrides or {})
    return vals


def build_context(kit, overrides=None):
    """Контекст рендера {c,s,a,r,d,f,hypr,idle,meta} по дефолтам схемы + overrides (palette.kit_context).
    Недопустимый акцент -> KitError."""
    try:
        return palette.kit_context(kit, overrides)
    except palette.PaletteError as e:
        raise KitError(str(e))


def render_target(kit, target, overrides=None, context_fn=None):
    """-> bytes вывода шаблона цели. KitError, если нет шаблона; RenderError при ошибке рендера."""
    tp = kit.template_path(target)
    if tp is None:
        raise KitError("нет файла шаблона %s" % target.get("template"))
    text = tp.read_bytes().decode("utf-8")
    ctx = (context_fn or build_context)(kit, overrides)
    return TemplateRenderer(ctx).render(text).encode("utf-8")


def skip_reason(kit, target):
    """Причина, по которой цель не участвует в golden/perturb, либо None."""
    if not target.get("golden"):
        return "golden=false (kind=%s)" % target.get("kind")
    if target.get("kind") != "template":
        return "нет шаблона (kind=%s, выход строится кодом)" % target.get("kind")
    if not target.get("template"):
        return "в targets.json не задан template"
    if kit.template_path(target) is None:
        return "шаблон ещё не написан (%s)" % target["template"]
    return None


# --------------------------------------------------------------------------- golden

def _first_byte_diff(a, b):
    n = min(len(a), len(b))
    i = next((k for k in range(n) if a[k] != b[k]), n)
    lo = max(0, i - 20)
    return "первое различие на байте %d: golden=%r  render=%r (длины %d / %d)" % (
        i, a[lo:i + 20], b[lo:i + 20], len(a), len(b))


def diff_text(want, got, want_name, got_name, limit=80, context=2):
    """Unified diff двух bytes; если текстовый diff пуст (разные байты) — позиция первого различия."""
    wl = want.decode("utf-8", "replace").splitlines(keepends=True)
    gl = got.decode("utf-8", "replace").splitlines(keepends=True)
    lines = list(difflib.unified_diff(wl, gl, want_name, got_name, n=context))
    if not lines:
        return _first_byte_diff(want, got)
    out = []
    for ln in lines[:limit]:
        out.append(ln.replace("\r", "\\r").rstrip("\n"))
        if not ln.endswith("\n"):
            out.append("\\ без перевода строки в конце файла")
    if len(lines) > limit:
        out.append("... ещё %d строк diff (--limit N)" % (len(lines) - limit))
    return "\n".join(out)


def run_golden(kit, ids=None, limit=80, context_fn=None):
    """-> список результатов {id,status(OK|DIFF|SKIP|ERROR),detail}."""
    res = []
    for t in kit.select(ids):
        r = {"id": t["id"], "status": "OK", "detail": ""}
        reason = skip_reason(kit, t)
        if reason:
            r.update(status="SKIP", detail=reason)
            res.append(r)
            continue
        gp = kit.golden_path(t)
        if gp is None or not gp.is_file():
            r.update(status="ERROR", detail="нет golden-файла: %s" % gp)
            res.append(r)
            continue
        try:
            got = render_target(kit, t, None, context_fn)
        except (RenderError, KitError) as e:
            r.update(status="ERROR", detail="ошибка рендера: %s" % e)
            res.append(r)
            continue
        want = gp.read_bytes()
        if want != got:
            r.update(status="DIFF", detail=diff_text(want, got, str(gp), "render:%s" % t["id"], limit))
        res.append(r)
    return res


def format_golden(results):
    lines = []
    for r in results:
        lines.append("%-6s %s%s" % (r["status"], r["id"], ("  — " + r["detail"]) if r["status"] in ("SKIP", "ERROR") else ""))
        if r["status"] == "DIFF":
            lines.append(r["detail"])
    c = {k: sum(1 for r in results if r["status"] == k) for k in ("OK", "DIFF", "SKIP", "ERROR")}
    lines.append("итого: OK=%(OK)d DIFF=%(DIFF)d ERROR=%(ERROR)d SKIP=%(SKIP)d" % c)
    return "\n".join(lines)


def golden_exit_code(results):
    if any(r["status"] == "ERROR" for r in results):
        return 2
    return 1 if any(r["status"] == "DIFF" for r in results) else 0


# --------------------------------------------------------------------------- perturb

def resolve_perturb(kit, key, value=None):
    """-> (settings_key, value, snapshot_name). Алиасы primary/glass/radius; иначе — ключ схемы."""
    if key in PERTURB_ALIASES:
        k, default = PERTURB_ALIASES[key]
        return k, (default if value is None else _coerce(kit, k, value)), key
    if key not in kit.schema.get("keys", {}):
        raise KitError("неизвестный ключ %r (алиасы: %s; либо ключ из schema.json)" % (key, ", ".join(PERTURB_ALIASES)))
    if value is None:
        raise KitError("для ключа %s нужен --value" % key)
    return key, _coerce(kit, key, value), key


def _coerce(kit, key, value):
    if not isinstance(value, str):
        return value
    typ = kit.schema.get("keys", {}).get(key, {}).get("type")
    try:
        if typ == "integer":
            return int(value)
        if typ == "number":
            return float(value)
        if typ == "boolean":
            return value.lower() in ("1", "true", "yes")
        if typ in ("array", "object"):
            return json.loads(value)
    except ValueError:
        raise KitError("значение %r не подходит к типу %s ключа %s" % (value, typ, key))
    return value


def _old_tokens(kit, key, old_ctx):
    """Регэкспы «старого» значения, которые не должны остаться в выводе после подмены (для отчёта)."""
    toks = []
    if key == "appearance.accent":
        hx = old_ctx["c"].get("primary")
        if hx:
            toks.append(("hex %s" % hx, re.compile(re.escape(hx), re.I)))
            toks.append(("rgb %s" % ", ".join(map(str, color.hex_to_rgb(hx))),
                         re.compile(r"(?<!\d)%s(?!\d)" % re.escape(", ".join(map(str, color.hex_to_rgb(hx)))))))
        hs = old_ctx["s"].get("primaryHsl")
        if hs:
            toks.append(("hsl %s" % hs, re.compile(re.escape(hs))))
    elif key in ("appearance.glassAlpha", "appearance.surfaceAlpha"):
        v = old_ctx["a"]["glass" if key.endswith("glassAlpha") else "surface"]
        toks.append(("alpha %s" % v, re.compile(r"(?<![\d.])%s(?!\d)" % re.escape(str(v)))))
    elif key == "appearance.radius":
        v = old_ctx["r"]["md"]
        toks.append(("radius %dpx" % v, re.compile(r"(?<!\d)%dpx" % v)))
    return toks


def _changed_lines(old, new):
    """[(старый_номер|None, старая_строка|None, новый_номер|None, новая_строка|None)] по SequenceMatcher."""
    a, b = old.splitlines(), new.splitlines()
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        n = max(i2 - i1, j2 - j1)
        for k in range(n):
            ia, ib = i1 + k, j1 + k
            out.append((ia + 1 if ia < i2 else None, a[ia] if ia < i2 else None,
                        ib + 1 if ib < j2 else None, b[ib] if ib < j2 else None))
    return out


def _clip(s, n=110):
    return s if len(s) <= n else s[:n - 1] + "…"


def run_perturb(kit, key, value=None, ids=None, context_fn=None):
    """-> (текст отчёта, число изменённых целей). Отчёт детерминирован (годится как снимок)."""
    skey, val, _ = resolve_perturb(kit, key, value)
    cfn = context_fn or build_context
    old_ctx = cfn(kit, None)
    out = ["perturb %s = %r" % (skey, val), ""]
    changed_ids, same_ids, rendered = [], [], 0
    for t in kit.select(ids):
        if kit.template_path(t) is None or t.get("kind") != "template":
            continue
        rendered += 1
        try:
            old = render_target(kit, t, None, cfn).decode("utf-8")
            new = render_target(kit, t, {skey: val}, cfn).decode("utf-8")
        except RenderError as e:
            out.append("== %s: ОШИБКА рендера: %s" % (t["id"], e))
            continue
        ch = _changed_lines(old, new)
        if not ch:
            same_ids.append(t["id"])
            out.append("== %s: без изменений" % t["id"])
            continue
        changed_ids.append(t["id"])
        nlines = len({c[2] for c in ch if c[2]} | {c[0] for c in ch if c[0]})
        out.append("== %s (%s): изменено строк: %d" % (t["id"], t["output"], nlines))
        for ia, la, ib, lb in ch:
            if la is not None:
                out.append("  -%4d | %s" % (ia, _clip(la)))
            if lb is not None:
                out.append("  +%4d | %s" % (ib, _clip(lb)))
        toks = _old_tokens(kit, skey, old_ctx)
        stay = []
        for i, line in enumerate(new.splitlines(), 1):
            for label, rx in toks:
                if rx.search(line):
                    stay.append("   %4d | %s   [%s]" % (i, _clip(line.strip(), 90), label))
                    break
        if stay:
            out.append("  старое значение осталось (допустимо только для намеренных констант: ANSI/синтаксис/нейтрали):")
            out.extend(stay)
        out.append("")
    if rendered == 0:
        out.append("нет ни одной цели с готовым шаблоном — SKIP")
    declared = set(kit.schema["keys"].get(skey, {}).get("targets", []))
    have = {t["id"] for t in kit.select(ids) if kit.template_path(t) and t.get("kind") == "template"}
    for tid in sorted((declared & have) - set(changed_ids)):
        out.append("ЗАМЕЧАНИЕ: schema заявляет %s для цели %s, но вывод не изменился" % (skey, tid))
    for tid in sorted(set(changed_ids) - declared):
        out.append("ЗАМЕЧАНИЕ: вывод цели %s изменился, но schema не заявляет %s для неё (targets)" % (tid, skey))
    return "\n".join(out).rstrip("\n") + "\n", len(changed_ids)


def snapshot_path(kit, name):
    return kit.snapshots / (name.replace("/", "_") + ".txt")


# --------------------------------------------------------------------------- lint

class Issue:
    def __init__(self, target, line, severity, code, msg):
        self.target, self.line, self.severity, self.code, self.msg = target, line, severity, code, msg

    def __str__(self):
        loc = "%s:%s" % (self.target, self.line) if self.line else self.target
        return "%-5s %-14s %s  %s" % (self.severity.upper(), self.code, loc, self.msg)

    def as_dict(self):
        return dict(target=self.target, line=self.line, severity=self.severity, code=self.code, msg=self.msg)


_HEX_RE = re.compile(r"#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![\w-])")
_HYPR_RGBA_RE = re.compile(r"rgba?\(([0-9a-fA-F]{6,8})\)")
_FUNC_RE = re.compile(r"\b(rgba?|hsla?)\(\s*[\d.]")
_BARE_RE = re.compile(r"(?<![0-9a-zA-Z_#.-])([0-9a-fA-F]{6})(?![0-9a-zA-Z_-])")
_REF_RE = re.compile(r"^[a-z]+(?:\.\w+)+$")


def template_refs(text):
    """Множество путей контекста, на которые ссылается шаблон (в т.ч. a.glass в аргументах фильтров)."""
    refs = set()
    for m in PLACEHOLDER_RE.finditer(text):
        parts = m.group(1).split("|")
        refs.add(parts[0].strip())
        for f in parts[1:]:
            if ":" in f:
                arg = f.split(":", 1)[1].strip()
                if _REF_RE.match(arg):
                    refs.add(arg)
    return refs


def _strip_placeholders(text):
    return PLACEHOLDER_RE.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)  # номера строк сохраняются


def _palette_hexes(kit):
    s = set()
    for v in kit.scheme.get("colours", {}).values():
        try:
            s.add(color.normalize_hex(v))
        except ValueError:
            pass
    for h in kit.roles.get("externalColors", {}).get("map", {}):
        s.add(h.lower())
    return s


def _nonpalette_hexes(kit):
    return {str(x["hex"]).lower().lstrip("#") for x in kit.roles.get("nonPalette", [])}


def _whitelisted_func(line_span, text):
    """rgba(0, 0, 0, x) — намеренная чёрная тень."""
    return re.match(r"rgba\(\s*0\s*,\s*0\s*,\s*0\s*,", text[line_span:]) is not None


def covers(kit, key, ref):
    """True/False: ключ настроек `key` управляет путём контекста `ref`; None — не умеем судить."""
    ns, _, rest = ref.partition(".")
    derived = kit.roles.get("derived", {})
    strings = kit.roles.get("strings", {})
    if key == "appearance.accent":
        if ns == "c":
            return rest == "primary" or derived.get(rest, {}).get("anchor") == "primary"
        if ns == "s":
            return strings.get(rest, {}).get("anchor") == "primary"
        return False
    if key == "appearance.glassAlpha":
        return ref == "a.glass"
    if key == "appearance.surfaceAlpha":
        return ref == "a.surface"
    if key == "appearance.radius":
        return ns == "r"
    if key == "appearance.windowRounding":
        return ref == "hypr.rounding"
    if key.startswith("appearance.fonts."):
        return ref == "f." + key[len("appearance.fonts."):] or ref.startswith("f." + key[len("appearance.fonts."):].split(".")[0] + ".")
    if key.startswith("power.idle."):
        tail = key[len("power.idle."):]
        if ref == "idle." + tail or ref.startswith("idle." + tail):
            return True
        if tail.startswith("dim") and ref == "idle.dimBlock":
            return True
        if tail.startswith("lock") and ref == "idle.lockBlock":
            return True
        if tail.startswith("dpms") and ref == "idle.dpmsBlock":
            return True
        if tail.startswith("suspend") and ref == "idle.suspendBlock":
            return True
        return False
    if key.startswith("hypr."):
        return ref == key or ref.startswith(key + ".")
    return None


def lint_target(kit, target, ctx):
    tid = target["id"]
    tp = kit.template_path(target)
    text = tp.read_bytes().decode("utf-8")
    issues = []
    lines = text.splitlines()
    ignored = {i for i, l in enumerate(lines, 1) if LINT_IGNORE in l}

    def add(line, sev, code, msg):
        if line not in ignored:
            issues.append(Issue(tid, line, sev, code, msg))

    renderer = TemplateRenderer(ctx)
    for m in PLACEHOLDER_RE.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        try:
            renderer._process_placeholder(m.group(1).strip())
        except (RenderError, ValueError, TypeError) as e:
            add(line, "error", "unknown-key", "{{%s}}: %s" % (m.group(1), e))
    bare = _strip_placeholders(text)
    for i, l in enumerate(bare.splitlines(), 1):
        if "{{" in l:
            add(i, "error", "bad-placeholder", "незакрытый/битый '{{' (в выводе останется)")
    allow_np = _nonpalette_hexes(kit)
    pal = _palette_hexes(kit)
    lits = set(kit.roles.get("lintWhitelist", {}).get("literals", []))
    for i, l in enumerate(bare.splitlines(), 1):
        for m in _HEX_RE.finditer(l):
            lit = m.group(0)
            hx = lit[1:].lower()
            if lit.lower() == "#00000000" and "#00000000" in {x.lower() for x in lits}:
                continue
            if hx[:6] in allow_np and len(hx) in (6, 8):
                continue
            add(i, "error", "literal-hex", "литеральный цвет %s вне белого списка — нужен {{ c.… | hex }}" % lit)
        for m in _HYPR_RGBA_RE.finditer(l):
            hx = m.group(1).lower()
            if hx[:6] in allow_np:
                continue
            add(i, "error", "literal-hex", "литеральный %s вне белого списка (nonPalette)" % m.group(0))
        for m in _FUNC_RE.finditer(l):
            if _whitelisted_func(m.start(), l):
                continue
            if _HYPR_RGBA_RE.match(l, m.start()):
                continue
            add(i, "error", "literal-func", "литеральный %s…) вне белого списка (допустимо rgba(0, 0, 0, α))" % m.group(1))
        for m in _BARE_RE.finditer(l):
            hx = m.group(1).lower()
            if hx in pal and hx not in allow_np and not _HYPR_RGBA_RE.search(l):
                add(i, "warn", "bare-hex", "«%s» без # совпадает с цветом палитры — вероятно сырой цвет" % hx)
    refs = template_refs(text)
    keys = list(target.get("keys", []))
    for k in keys:
        if covers(kit, k, "x.x") is None:
            continue  # ключ, о связи которого с путями контекста стенд ничего не знает
        if not any(covers(kit, k, r) for r in refs):
            add(0, "warn", "unused-key", "ключ цели %s не влияет на вывод — шаблон не ссылается на связанные пути" % k)
    if all(covers(kit, k, "x.x") is not None for k in keys):
        for r in sorted(refs):
            ns = r.split(".")[0]
            if ns in ("c", "s") and not covers(kit, "appearance.accent", r):
                continue  # константы палитры ключами не управляются
            if not any(covers(kit, k, r) for k in keys):
                add(0, "warn", "undeclared-ref",
                    "шаблон использует %s, но ни один ключ в keys цели не управляет им (set не перегенерирует цель)" % r)
    return issues, refs


def run_lint(kit, ids=None, context_fn=None):
    """-> (issues, число проверенных шаблонов, пропущенные [(id, причина)])."""
    ctx = (context_fn or build_context)(kit, None)
    issues, checked, skipped, all_refs = [], 0, [], set()
    for t in kit.select(ids):
        if t.get("kind") != "template" or not t.get("template"):
            skipped.append((t["id"], "kind=%s" % t.get("kind")))
            continue
        if kit.template_path(t) is None:
            skipped.append((t["id"], "шаблон ещё не написан"))
            continue
        iss, refs = lint_target(kit, t, ctx)
        issues += iss
        all_refs |= refs
        checked += 1
    if checked and not ids:
        ext = [v for vs in kit.roles.get("externalColors", {}).get("map", {}).values() if vs for v in vs]
        used = {r.split(".", 1)[1] for r in all_refs if r.startswith("c.")}
        for k in sorted(set(ext) - used):
            issues.append(Issue("(палитра)", 0, "info", "unused-ext", "ext-ключ %s не используется ни одним шаблоном" % k))
    return issues, checked, skipped


# --------------------------------------------------------------------------- фикстура HOME

class FakeHome:
    def __init__(self, home, **paths):
        self.home = Path(home)
        self.__dict__.update(paths)

    @property
    def env(self):
        return {"HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config),
                "XDG_STATE_HOME": str(self.home / ".local" / "state")}


def make_isolated_home(base):
    """Создаёт в `base` изолированный HOME как в DESIGN §8: профили Zen/Thunderbird
    (installs.ini, пути с пробелами и скобками), vault'ы Obsidian (obsidian.json, пути с пробелами/
    скобками, один «не смонтирован»). Ничего вне `base` не трогает."""
    base = Path(base)
    home = base / "home"
    cfg = home / ".config"
    zen = cfg / "zen"
    zen_prof = zen / "smhkr7xv.Default (release)"
    tb = cfg / "thunderbird"
    tb_prof = tb / "0jbgc9os.default-release"
    for d in (zen_prof, tb_prof, cfg / "obsidian", cfg / "gtk-3.0", cfg / "gtk-4.0", cfg / "qt6ct" / "colors",
              cfg / "kitty", cfg / "zathura", cfg / "hypr", cfg / "zed" / "themes"):
        d.mkdir(parents=True, exist_ok=True)
    (zen / "installs.ini").write_text("[15B76BAA26BA15E7]\nDefault=smhkr7xv.Default (release)\nLocked=1\n", encoding="utf-8")
    (tb / "installs.ini").write_text("[FDC34C9F024745EB]\nDefault=0jbgc9os.default-release\nLocked=1\n", encoding="utf-8")
    (zen_prof / "prefs.js").write_text("// fake\n", encoding="utf-8")
    (tb_prof / "prefs.js").write_text("// fake\n", encoding="utf-8")
    data = base / "mnt" / "data"
    vaults = [data / "Obsidian Vault (main)", data / "AI" / "cosinus [work]"]
    for v in vaults:
        (v / ".obsidian").mkdir(parents=True, exist_ok=True)
        (v / ".obsidian" / "appearance.json").write_text(
            json.dumps({"theme": "moonstone", "enabledCssSnippets": ["transparent"]}), encoding="utf-8")
    gone = base / "mnt" / "gone" / "Vault (not mounted)"  # не создаётся: «/mnt/data не смонтирован»
    reg = {"vaults": {"%016x" % (i + 1): {"path": str(p), "ts": 1700000000000 + i}
                      for i, p in enumerate(vaults + [gone])}}
    (cfg / "obsidian" / "obsidian.json").write_text(json.dumps(reg, ensure_ascii=False, indent=2), encoding="utf-8")
    state = home / ".local" / "state" / "zephyrine"
    state.mkdir(parents=True, exist_ok=True)
    os.chmod(state, 0o700)
    return FakeHome(home, config=cfg, zen_profile=zen_prof, tb_profile=tb_prof, vaults=vaults,
                    unmounted_vault=gone, state=state)


# --------------------------------------------------------------------------- CLI

def _kit_from(args):
    return Kit(root=getattr(args, "root", None), settings_dir=getattr(args, "settings_dir", None))


def _cmd_golden(args):
    try:
        res = run_golden(_kit_from(args), args.target, args.limit)
    except KitError as e:
        print("ошибка: %s" % e, file=sys.stderr)
        return 2
    print(json.dumps(res, ensure_ascii=False, indent=1) if args.json else format_golden(res))
    return golden_exit_code(res)


def _cmd_perturb(args):
    try:
        kit = _kit_from(args)
        report, _ = run_perturb(kit, args.key, args.value, args.target)
    except KitError as e:
        print("ошибка: %s" % e, file=sys.stderr)
        return 2
    if args.update or args.check:
        sp = snapshot_path(kit, args.key)
        if args.value is not None:
            print("ошибка: снимки — только для значения-маркера по умолчанию (без --value)", file=sys.stderr)
            return 2
        if args.update:
            sp.parent.mkdir(parents=True, exist_ok=True)
            sp.write_text(report, encoding="utf-8")
            print("снимок записан: %s" % sp)
            return 0
        if not sp.is_file():
            print("нет одобренного снимка %s (создать: perturb %s --update после ревью)" % (sp, args.key), file=sys.stderr)
            return 3
        want = sp.read_text(encoding="utf-8")
        if want == report:
            print("снимок %s: совпадает" % sp.name)
            return 0
        print(diff_text(want.encode(), report.encode(), str(sp), "текущий отчёт", args.limit))
        return 1
    print(report, end="")
    return 0


def _cmd_lint(args):
    try:
        issues, checked, skipped = run_lint(_kit_from(args), args.target)
    except KitError as e:
        print("ошибка: %s" % e, file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps({"checked": checked, "skipped": skipped, "issues": [i.as_dict() for i in issues]},
                         ensure_ascii=False, indent=1))
    else:
        for i in issues:
            print(i)
        for tid, why in skipped:
            print("SKIP  %s — %s" % (tid, why))
        print("проверено шаблонов: %d; замечаний: %d error, %d warn, %d info" % (
            checked, *(sum(1 for i in issues if i.severity == s) for s in ("error", "warn", "info"))))
    bad = {"error", "warn"} if args.strict else {"error"}
    return 1 if any(i.severity in bad for i in issues) else 0


def _cmd_home(args):
    h = make_isolated_home(args.dir)
    print("export HOME=%s" % json.dumps(str(h.home)))
    print("export XDG_CONFIG_HOME=%s" % json.dumps(str(h.config)))
    return 0


def register(subparsers, name="test"):
    """Регистрирует подкоманду `test` в argparse-подпарсерах CLI (S1.2). Возвращает парсер `test`."""
    p = subparsers.add_parser(name, help="тестовый стенд шаблонов тем (golden|perturb|lint|home)")
    sub = p.add_subparsers(dest="test_cmd", required=True)

    def common(sp):
        sp.add_argument("--target", "-t", action="append", help="id цели (можно несколько); по умолчанию все")
        sp.add_argument("--root", help="корень репо (по умолчанию $ZEPHYRINE_ROOT или родитель settings/)")

    g = sub.add_parser("golden", help="рендер дефолтов и побайтное сравнение с рукописными файлами")
    common(g)
    g.add_argument("--limit", type=int, default=80, help="макс. строк diff на цель")
    g.add_argument("--json", action="store_true")
    g.set_defaults(func=_cmd_golden)
    q = sub.add_parser("perturb", help="подмена входа и отчёт об изменившихся строках")
    q.add_argument("key", help="primary|glass|surface|radius или ключ из schema.json (тогда нужен --value)")
    q.add_argument("--value")
    common(q)
    q.add_argument("--check", action="store_true", help="сравнить с одобренным снимком tests/snapshots/perturb/")
    q.add_argument("--update", action="store_true", help="записать/обновить снимок (после ревью!)")
    q.add_argument("--limit", type=int, default=80)
    q.set_defaults(func=_cmd_perturb)
    l = sub.add_parser("lint", help="проверка шаблонов: ключи, сырые цвета, неиспользуемые ключи цели")
    common(l)
    l.add_argument("--strict", action="store_true", help="warn тоже даёт код 1")
    l.add_argument("--json", action="store_true")
    l.set_defaults(func=_cmd_lint)
    h = sub.add_parser("home", help="создать изолированный HOME (фикстура) и напечатать export-ы")
    h.add_argument("dir", help="каталог, где создать (должен быть вне живого HOME)")
    h.set_defaults(func=_cmd_home)
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(prog="zs-test", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    register(sub, name="test")
    # `zs-test golden` == `zephyrine-settings test golden`: подкоманды поднимаем на верхний уровень
    args = ap.parse_args(["test"] + list(sys.argv[1:] if argv is None else argv))
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
