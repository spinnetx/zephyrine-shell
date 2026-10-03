"""Patch-цели (правка отдельных ключей существующего файла) (DESIGN §3.2, A1).

Подключается из targets.py: `handles(t)`, `plan(engine, t, plan)`. Команда gsettings - zsettings/gsettings.py.
Файл целиком не генерируется: меняются только перечисленные строки, остальное
(комментарии, чужие ключи, порядок, переводы строк, права) остаётся как было. Поэтому у patch-целей
нет drift: строки, которыми владеет центр настроек, всегда приводятся к настройкам; идемпотентность -
сравнение результата с файлом. Запись идёт через targets.py (realpath, бэкап, симлинк остаётся
симлинком); здесь только вычисление нового содержимого.

Описание правок - поле `patches` цели в targets.json (список):

  {"type": "ini",  "section": "Settings", "key": "gtk-font-name", "from": "appearance.fonts.ui",
   "value": "{family},  {size}"}
      ключ `key=` в секции `[section]`; сохраняется всё до значения (`key =  `), заменяется значение.
      Нет ключа - добавляется в конец секции, нет секции - секция в конец файла.
  {"type": "line", "pattern": "^font_size\\s+(?P<val>.*)$", "from": "appearance.fonts.mono.size",
   "value": "{v:.1f}", "line": "font_size          {v:.1f}"}
      строки, подходящие под regex; заменяется группа `val` (нет группы - вся строка). Нет таких
      строк и есть `line` - добавляется в конец файла, иначе правка пропускается (note).

  `from`      ключ настроек (поле `v`) либо префикс с `.family`/`.size` (поля `family`, `size`, `v`=family);
  `map`       таблица {значение настройки: строка} — поле `v` берётся из неё (режим темы: dark/light -> имя GTK-темы…);
  `fallback`  {"from": ключ, "map": {...}}: если значение `from` равно null (тема иконок «по режиму»), поле `v`
              берётся из map по значению ключа fallback.from (как `map` выше);
  `sizeFrom`  ключ, из которого берётся `size` вместо `<from>.size`;
  `value`     шаблон str.format (по умолчанию "{v}"); поля from, а также `{HOME}` и `{tail}`;
  `tail`      regex с группой `tail` по СТАРОМУ значению (qt6ct: хвост "-1,5,400,..." шрифта сохраняется),
  `tailDefault` хвост, если старого значения нет/не разобрано;
  `forbid`    символы, недопустимые в `family` (qt6ct: запятая).
Поле `deployPatches` - те же правки, но только для живой копии (qt6ct: подстановка color_scheme_path
под HOME, как делает deploy.sh).
"""
import os
import re

_HEADER = re.compile(r"^\s*\[(?P<name>[^\]]*)\]\s*$")
_BAD = ("\n", "\r", "\x00")


class PatchError(Exception):
    pass


def handles(t):
    return t.get("kind") == "patch"


# --------------------------------------------------------------------------- значения

def fields(eff, spec):
    """Поля подстановки для правки/команды из эффективных настроек `eff`."""
    src = spec.get("from")
    if not src:  # правка без значений из настроек (подстановка пути под HOME)
        return {}
    if "map" in spec:  # значение перечислимой настройки (appearance.mode) -> строка из таблицы map
        key = eff.get(src)
        if key not in spec["map"]:
            raise PatchError("no map entry for %s=%r" % (src, key))
        return {"v": spec["map"][key]}
    if spec.get("fallback") and eff.get(src) is None:  # нет значения/null = «по режиму темы» (иконки)
        fb = spec["fallback"]
        key = eff.get(fb["from"])
        if key not in fb["map"]:
            raise PatchError("no fallback map entry for %s=%r" % (fb["from"], key))
        return {"v": fb["map"][key]}
    if src in eff:
        f = {"v": eff[src]}
    else:
        fam, size = eff.get(src + ".family"), eff.get(src + ".size")
        if fam is None or size is None:
            raise PatchError("unknown source key %s" % src)
        f = {"family": fam, "size": size, "v": fam}
    if spec.get("sizeFrom"):
        if spec["sizeFrom"] not in eff:
            raise PatchError("unknown sizeFrom key %s" % spec["sizeFrom"])
        f["size"] = eff[spec["sizeFrom"]]
    bad = spec.get("forbid", "")
    fam = f.get("family")
    if fam is not None and any(c in fam for c in bad):
        raise PatchError("font family %r contains a character not allowed here (%s)" % (fam, bad))
    return f


def _format(tmpl, f, what):
    try:
        out = tmpl.format_map(f)
    except (KeyError, IndexError, ValueError, AttributeError, TypeError) as e:
        raise PatchError("bad value template for %s: %s: %s" % (what, type(e).__name__, e))
    if any(c in out for c in _BAD):
        raise PatchError("%s: value contains a control character" % what)
    return out


def _value(spec, f, old, home, what):
    d = dict(f)
    d["HOME"] = home
    tmpl = spec.get("value", "{v}")
    if "{tail" in tmpl:
        m = re.search(spec["tail"], old) if spec.get("tail") and old is not None else None
        d["tail"] = (m.groupdict().get("tail") or "") if m else spec.get("tailDefault", "")
    return _format(tmpl, d, what)


# --------------------------------------------------------------------------- правка текста

def _split_eol(body):
    core = body.rstrip("\r")
    return core, body[len(core):]


def _patch_ini(parts, spec, f, home, notes):
    section, key = spec["section"], spec["key"]
    key_rx = re.compile(r"^(?P<head>\s*%s\s*=\s*)(?P<val>.*)$" % re.escape(key))
    cur = None
    found = False
    sec_seen = False
    last_in_sec = None
    for i, raw in enumerate(parts):
        body, eol = _split_eol(raw)
        h = _HEADER.match(body)
        if h:
            cur = h.group("name")
            sec_seen = sec_seen or cur == section
            if cur == section:
                last_in_sec = i
            continue
        if cur != section:
            continue
        if body.strip():
            last_in_sec = i
        m = key_rx.match(body)
        if m:
            found = True
            parts[i] = m.group("head") + _value(spec, f, m.group("val"), home, "%s/%s" % (section, key)) + eol
    if found:
        return
    new = "%s=%s" % (key, _value(spec, f, None, home, "%s/%s" % (section, key)))
    if sec_seen:
        parts.insert(last_in_sec + 1, new)
        notes.append("added %s to [%s]" % (key, section))
        return
    if parts and parts[-1] == "":
        parts.pop()
    if parts and parts[-1].strip():
        parts.append("")
    parts.extend(["[%s]" % section, new, ""])
    notes.append("added section [%s]" % section)


def _patch_line(parts, spec, f, home, notes):
    try:
        rx = re.compile(spec["pattern"])
    except re.error as e:
        raise PatchError("bad pattern %r: %s" % (spec["pattern"], e))
    found = False
    for i, raw in enumerate(parts):
        body, eol = _split_eol(raw)
        m = rx.match(body)
        if not m:
            continue
        found = True
        if "val" in rx.groupindex and m.start("val") >= 0:
            s, e = m.span("val")
            old = m.group("val")
        else:
            s, e = m.span()
            old = m.group(0)
        parts[i] = body[:s] + _value(spec, f, old, home, spec["pattern"]) + body[e:] + eol
    if found:
        return
    if spec.get("line"):
        d = dict(f, HOME=home)
        if "{tail" in spec["line"] or "{tail" in spec.get("value", ""):
            d["tail"] = spec.get("tailDefault", "")
        if parts and parts[-1] == "":
            parts.pop()
        parts.append(_format(spec["line"], d, spec["pattern"]))
        parts.append("")
        notes.append("added line for %s" % spec["pattern"])
    else:
        notes.append("no match for %s" % spec["pattern"])


def patch_text(text, specs, eff, home):
    """-> (новый текст, [заметки]). Чистая функция: файлы не трогает."""
    parts = text.split("\n")
    notes = []
    for spec in specs:
        f = fields(eff, spec)
        typ = spec.get("type", "line" if "pattern" in spec else "ini")
        if typ == "ini":
            _patch_ini(parts, spec, f, home, notes)
        elif typ == "line":
            _patch_line(parts, spec, f, home, notes)
        else:
            raise PatchError("unknown patch type %r" % typ)
    return "\n".join(parts), notes


def _read_text(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        return raw, raw.decode("utf-8")
    except UnicodeDecodeError:
        raise PatchError("%s is not valid UTF-8" % path)


# --------------------------------------------------------------------------- планирование

def plan(engine, t, p):
    """Заполняет план patch-цели (Dest-ы: файл в репо и живая копия). -> тот же p (или p.na(...))."""
    from .targets import Dest, expand
    try:
        paths, eff = engine.paths, engine.eff
        specs = t.get("patches") or []
        deploy = t.get("deploy", "none")
        dpatches = t.get("deployPatches") or []
        is_writable_root = os.access(paths.root, os.W_OK) and not paths.root.startswith("/usr")

        repo_path = os.path.join(paths.root, t["output"])
        live_path = expand(paths, deploy[5:]) if deploy.startswith("copy:") else None

        alt_repo = None
        if not os.path.isfile(repo_path) and t["output"].startswith(".config/"):
            cand = os.path.join(paths.root, "themes", t["output"][8:])
            if os.path.isfile(cand):
                alt_repo = cand

        src_path = repo_path if os.path.isfile(repo_path) else alt_repo
        if src_path is None and live_path and os.path.isfile(live_path):
            src_path = live_path

        if src_path is None:
            return p.na("missing", "file-missing", repo_path)

        raw, text = _read_text(src_path)
        new_text, notes = patch_text(text, specs, eff, paths.home)

        if is_writable_root:
            repo = Dest(repo_path, "repo", new_text.encode("utf-8"))
            repo.current = raw if src_path == repo_path else None
            p.dests.append(repo)
            for n in notes:
                p.skipped.append({"reason": "patch-note", "path": repo_path, "message": n})

        if deploy.startswith("copy:"):
            live = live_path
            if is_writable_root and os.path.realpath(live) == os.path.realpath(repo_path):
                pass
            else:
                try:
                    lraw, ltext = _read_text(live)
                except FileNotFoundError:
                    lraw, ltext = None, new_text
                    specs_live = dpatches
                else:
                    specs_live = list(specs) + list(dpatches)
                lnew, lnotes = patch_text(ltext, specs_live, eff, paths.home)
                d = Dest(live, "copy", lnew.encode("utf-8"))
                d.current = lraw
                p.dests.append(d)
                for n in lnotes:
                    p.skipped.append({"reason": "patch-note", "path": live, "message": n})
        elif not is_writable_root and deploy == "none":
            if t["output"].startswith(".config/"):
                live = os.path.join(paths.home, t["output"])
                try:
                    lraw, ltext = _read_text(live)
                except FileNotFoundError:
                    lraw, ltext = None, new_text
                d = Dest(live, "copy", new_text.encode("utf-8"))
                d.current = lraw
                p.dests.append(d)
        elif deploy != "none":
            raise PatchError("unknown deploy %r" % deploy)

        for d in p.dests:
            d.action = "create" if d.current is None else ("same" if d.current == d.cmp else "update")
        return p
    except PatchError as e:
        p.dests = []
        return p.na("error", "patch-error", str(e))
    except OSError as e:
        p.dests = []
        return p.na("error", "io-error", str(e))
