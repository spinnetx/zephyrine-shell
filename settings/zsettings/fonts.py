"""Список установленных шрифтов (fc-list) и проверка значений `appearance.fonts.*` (DESIGN §3.7, A1).

Фильтры (поле `fontFilter` в schema.json):
  any   - любое семейство;
  mono  - только моноширинные (`fc-list :spacing=mono`);
  nerd  - только семейства с «Nerd Font» в имени (иначе пропадут иконки бара); тот же критерий в
          quickshell/Prefs.qml (`nerdfont`).
Каноническое имя - первое в списке `family` fontconfig (`JetBrainsMono Nerd Font,JetBrainsMono NF,...`);
для проверки «установлен ли шрифт» принимаются и остальные имена.
"""
import shutil
import subprocess

FC_TIMEOUT = 15
NERD_MARK = "Nerd Font"
KINDS = ("any", "mono", "nerd")


class FontsError(Exception):
    """fc-list недоступен или завершился с ошибкой."""


def _run(pattern):
    exe = shutil.which("fc-list")
    if exe is None:
        raise FontsError("fc-list not found")
    cmd = [exe] + ([pattern] if pattern else []) + ["--format", "%{family}\\n"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=FC_TIMEOUT, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FontsError("fc-list failed: %s" % e)
    if r.returncode != 0:
        raise FontsError("fc-list exit %d: %s" % (r.returncode, r.stderr.strip()))
    return r.stdout.splitlines()


def scan(kind="any"):
    """-> [(каноническое имя, [все имена])] без повторов, по алфавиту (без учёта регистра)."""
    if kind not in KINDS:
        raise FontsError("unknown kind %r" % kind)
    lines = _run(":spacing=mono" if kind == "mono" else None)
    seen = {}
    for ln in lines:
        names = [n.strip() for n in ln.split(",") if n.strip()]
        if not names:
            continue
        canon = names[0]
        if kind == "nerd" and NERD_MARK not in canon:
            continue
        seen.setdefault(canon, set()).update(names)
    return sorted(((c, sorted(n)) for c, n in seen.items()), key=lambda x: x[0].casefold())


def families(kind="any"):
    return [c for c, _ in scan(kind)]


def is_nerd(name):
    return NERD_MARK in name


def check_values(schema, flat):
    """Семантическая проверка шрифтов перед записью settings.json -> [{"key", "error"}].

    Проверяются только значения, отличные от дефолта (reset/undo всегда допустимы). Если fc-list
    недоступен - проверять нечем, ошибок нет. Семейство должно быть установлено; `fontFilter`
    nerd - ещё и содержать «Nerd Font» (проверяется и без fc-list); mono - моноширинное.
    """
    errors = []
    cache = {}
    for key, spec in schema.concrete.items():
        if spec.get("type") != "font" or key not in flat:
            continue
        v = flat[key]
        if v == spec.get("default"):
            continue
        flt = spec.get("fontFilter", "any")
        if flt == "nerd" and not is_nerd(v):
            errors.append({"key": key, "error": "not a Nerd Font (the bar icons would disappear): %s" % v})
            continue
        if flt not in cache:
            try:
                cache[flt] = scan("mono" if flt == "mono" else "any")
            except FontsError:
                cache[flt] = None
        found = cache[flt]
        if found is None:
            continue
        want = v.casefold()
        if not any(want == n.casefold() for _, names in found for n in names):
            errors.append({"key": key, "error": "font not installed%s: %s" % (
                " (or not monospace)" if flt == "mono" else "", v)})
    return errors
