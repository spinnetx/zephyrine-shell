"""Тесты тестового стенда (zsettings/testkit.py) на синтетическом мини-шаблоне во временном каталоге."""
import argparse
import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from zsettings import testkit as tk

SCHEME = {"name": "t", "colours": {
    "background": "101010", "primary": "bb9af7", "onPrimary": "1c0f3a",
    "primaryContainer": "5b3fa0", "purple": "bb9af7", "purpleDim": "7c4fa8"}}
ROLES = {
    "derived": {"onPrimary": {"anchor": "primary"}, "primaryContainer": {"anchor": "primary"}},
    "strings": {"primaryHsl": {"anchor": "primary", "mode": "hsl-string", "literal": "267, 85%, 78%"}},
    "nonPalette": [{"hex": "33ccff"}],
    "lintWhitelist": {"literals": ["transparent", "#00000000", "rgba(0, 0, 0, <a>)"]},
    "externalColors": {"map": {"7c4fa8": ["purpleDim"]}},
}
SCHEMA = {"keys": {
    "appearance.accent": {"type": "color", "default": None, "targets": ["mini"]},
    "appearance.glassAlpha": {"type": "number", "default": 0.88, "targets": ["mini"]},
    "appearance.radius": {"type": "integer", "default": 12, "targets": ["mini"]},
}}
TEMPLATE = (
    "accent: {{ c.primary | hex }};\n"
    "container: {{ c.primaryContainer | hex }};\n"
    "purple: {{ c.purple | hex }};\n"
    "glass: {{ c.background | rgba:a.glass }};\n"
    "radius: {{ r.md | px }};\n"
    "hsl: {{ s.primaryHsl }};\n"
)
GOLDEN = (
    "accent: #bb9af7;\ncontainer: #5b3fa0;\npurple: #bb9af7;\n"
    "glass: rgba(16, 16, 16, 0.88);\nradius: 12px;\nhsl: 267, 85%, 78%;\n"
)


def mk_kit(tmp, template=TEMPLATE, golden=GOLDEN, keys=None, extra_targets=()):
    tmp = Path(tmp)
    (tmp / "quickshell").mkdir(parents=True, exist_ok=True)
    (tmp / "settings" / "templates").mkdir(parents=True, exist_ok=True)
    (tmp / "out").mkdir(exist_ok=True)
    (tmp / "quickshell" / "scheme.json").write_text(json.dumps(SCHEME))
    (tmp / "settings" / "templates" / "mini.tmpl").write_text(template, encoding="utf-8", newline="")
    if golden is not None:
        (tmp / "out" / "mini.css").write_text(golden, encoding="utf-8", newline="")
    targets = [{"id": "mini", "kind": "template", "template": "templates/mini.tmpl", "output": "out/mini.css",
                "golden": True,
                "keys": keys if keys is not None else ["appearance.accent", "appearance.glassAlpha", "appearance.radius"]},
               {"id": "later", "kind": "template", "template": "templates/none.tmpl", "output": "out/none.css",
                "golden": True, "keys": []},
               {"id": "emitter", "kind": "emit", "template": None, "output": "out/e.lua", "golden": False, "keys": []}]
    targets += list(extra_targets)
    s = tmp / "settings"
    (s / "targets.json").write_text(json.dumps({"targets": targets}))
    (s / "palette-roles.json").write_text(json.dumps(ROLES))
    (s / "schema.json").write_text(json.dumps(SCHEMA))
    return tk.Kit(root=tmp, settings_dir=s)


class Base(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.tmp = Path(self._td.name)


class TestGolden(Base):
    def status(self, res):
        return {r["id"]: r["status"] for r in res}

    def test_ok_and_skip(self):
        res = tk.run_golden(mk_kit(self.tmp))
        self.assertEqual(self.status(res), {"mini": "OK", "later": "SKIP", "emitter": "SKIP"})
        self.assertEqual(tk.golden_exit_code(res), 0)
        self.assertIn("шаблон ещё не написан", [r for r in res if r["id"] == "later"][0]["detail"])

    def test_single_byte_change_detected(self):
        kit = mk_kit(self.tmp, golden=GOLDEN.replace("bb9af7;\ncontainer", "bb9af8;\ncontainer"))
        res = tk.run_golden(kit)
        self.assertEqual(self.status(res)["mini"], "DIFF")
        self.assertEqual(tk.golden_exit_code(res), 1)
        d = [r for r in res if r["id"] == "mini"][0]["detail"]
        self.assertIn("-accent: #bb9af8;", d)
        self.assertIn("+accent: #bb9af7;", d)

    def test_trailing_newline_only(self):
        res = tk.run_golden(mk_kit(self.tmp, golden=GOLDEN.rstrip("\n")))
        self.assertEqual(self.status(res)["mini"], "DIFF")
        self.assertIn("без перевода строки", [r for r in res if r["id"] == "mini"][0]["detail"])

    def test_crlf_difference_detected(self):
        res = tk.run_golden(mk_kit(self.tmp, golden=GOLDEN.replace("\n", "\r\n")))
        self.assertEqual(self.status(res)["mini"], "DIFF")

    def test_render_error_and_missing_golden(self):
        res = tk.run_golden(mk_kit(self.tmp, template="{{ c.nope | hex }}\n"))
        self.assertEqual(self.status(res)["mini"], "ERROR")
        self.assertEqual(tk.golden_exit_code(res), 2)
        with tempfile.TemporaryDirectory() as t2:
            res = tk.run_golden(mk_kit(t2, golden=None))
            self.assertEqual(self.status(res)["mini"], "ERROR")
            self.assertIn("нет golden-файла", [r for r in res if r["id"] == "mini"][0]["detail"])

    def test_target_filter_and_unknown(self):
        kit = mk_kit(self.tmp)
        self.assertEqual([r["id"] for r in tk.run_golden(kit, ["mini"])], ["mini"])
        with self.assertRaises(tk.KitError):
            tk.run_golden(kit, ["zzz"])

    def test_golden_field_as_path(self):
        (self.tmp / "hand.css").write_text(GOLDEN)
        kit = mk_kit(self.tmp, golden="stale\n")
        kit.targets[0]["golden"] = "hand.css"
        self.assertEqual(self.status(tk.run_golden(kit))["mini"], "OK")


class TestContext(Base):
    def test_defaults_shortcircuit(self):
        c = tk.build_context(mk_kit(self.tmp))
        self.assertEqual(c["c"]["primaryContainer"], "5b3fa0")
        self.assertEqual(c["s"]["primaryHsl"], "267, 85%, 78%")
        self.assertEqual((c["r"]["lg"], c["r"]["md"], c["r"]["sm"], c["r"]["xs"]), (14, 12, 10, 8))

    def test_accent_override_derives(self):
        c = tk.build_context(mk_kit(self.tmp), {"appearance.accent": "#7aa2f7", "appearance.radius": 1})
        self.assertEqual(c["c"]["primary"], "7aa2f7")
        self.assertNotEqual(c["c"]["primaryContainer"], "5b3fa0")
        self.assertEqual(c["c"]["purple"], "bb9af7")  # константа не меняется
        self.assertEqual((c["r"]["sm"], c["r"]["xs"]), (0, 0))

    def test_bad_accent(self):
        with self.assertRaises(tk.KitError):
            tk.build_context(mk_kit(self.tmp), {"appearance.accent": "#101030"})

    def test_real_repo_loads(self):
        kit = tk.Kit()
        ctx = tk.build_context(kit)
        self.assertEqual(ctx["c"]["primary"], "bb9af7")
        self.assertEqual(ctx["s"]["primaryHsl"], "267, 85%, 78%")


class TestPerturb(Base):
    def test_primary_report(self):
        rep, n = tk.run_perturb(mk_kit(self.tmp), "primary")
        self.assertEqual(n, 1)
        self.assertIn("-   1 | accent: #bb9af7;", rep)
        self.assertIn("+   1 | accent: #ff00ff;", rep)
        self.assertIn("container:", rep)
        self.assertNotIn("+   5 |", rep)  # радиус не менялся
        # purple (ANSI-подобная константа) осталась старой — выводится в блоке «осталось»
        self.assertIn("старое значение осталось", rep)
        self.assertIn("purple: #bb9af7;", rep)
        self.assertNotIn("ЗАМЕЧАНИЕ", rep)

    def test_glass_and_radius(self):
        kit = mk_kit(self.tmp)
        rep, _ = tk.run_perturb(kit, "glass")
        self.assertIn("+   4 | glass: rgba(16, 16, 16, 0.5);", rep)
        rep, _ = tk.run_perturb(kit, "radius")
        self.assertIn("+   5 | radius: 20px;", rep)

    def test_declared_but_unchanged_warning(self):
        kit = mk_kit(self.tmp, template="x: {{ c.primary | hex }}\n", golden="x\n")
        rep, _ = tk.run_perturb(kit, "glass")
        self.assertIn("заявляет appearance.glassAlpha для цели mini, но вывод не изменился", rep)

    def test_arbitrary_key_needs_value(self):
        kit = mk_kit(self.tmp)
        with self.assertRaises(tk.KitError):
            tk.run_perturb(kit, "appearance.radius")
        rep, n = tk.run_perturb(kit, "appearance.radius", "3")
        self.assertEqual(n, 1)
        self.assertIn("radius: 3px", rep)
        with self.assertRaises(tk.KitError):
            tk.run_perturb(kit, "no.such")

    def test_deterministic_and_no_templates(self):
        kit = mk_kit(self.tmp)
        self.assertEqual(tk.run_perturb(kit, "primary"), tk.run_perturb(kit, "primary"))
        rep, n = tk.run_perturb(kit, "primary", ids=["later"])
        self.assertEqual(n, 0)
        self.assertIn("SKIP", rep)

    def test_snapshot_cli(self):
        mk_kit(self.tmp)
        base = dict(root=str(self.tmp), settings_dir=str(self.tmp / "settings"), target=None,
                    value=None, limit=80)

        def run(**kw):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                rc = tk._cmd_perturb(argparse.Namespace(**{**base, "key": "primary", "check": False,
                                                           "update": False, **kw}))
            return rc, buf.getvalue()

        self.assertEqual(run(check=True)[0], 3)       # снимка нет
        self.assertEqual(run(update=True)[0], 0)
        self.assertEqual(run(check=True)[0], 0)
        (self.tmp / "settings" / "templates" / "mini.tmpl").write_text(TEMPLATE.replace("c.purple", "c.primary"))
        rc, out = run(check=True)                      # роль purple -> primary: снимок ловит
        self.assertEqual(rc, 1)
        self.assertIn("purple:", out)


class TestLint(Base):
    def lint(self, template, keys=None):
        kit = mk_kit(self.tmp, template=template, keys=keys)
        issues, checked, skipped = tk.run_lint(kit, ["mini"])
        self.assertEqual(checked, 1)
        return issues

    def codes(self, issues):
        return sorted((i.code, i.line) for i in issues)

    def test_clean(self):
        self.assertEqual(self.lint(TEMPLATE), [])

    def test_unknown_key_filter_and_broken(self):
        iss = self.lint("{{ c.nope | hex }}\n{{ c.primary | bogus }}\n{{ c.primary | hex }\n"
                        "{{ r.md | px }}{{ a.glass | num:2 }}\n")
        got = self.codes(iss)
        self.assertIn(("unknown-key", 1), got)
        self.assertIn(("unknown-key", 2), got)
        self.assertIn(("bad-placeholder", 3), got)

    def test_literal_colors(self):
        iss = self.lint(
            "a: #ff00ff;\nb: rgba(1, 2, 3, 0.5);\nc: rgba(0, 0, 0, 0.3);\nd: transparent #00000000;\n"
            "e: rgba(33ccffee);\nf: #33ccff;\ng: rgba(aabbccdd);\nh: #ff00ff; /* zs-lint: ignore */\n"
            "i: rgba({{ c.primary | rgb }}, 0.5);\n"
            "{{ r.md | px }}{{ a.glass | num:2 }}{{ c.primary | hex }}\n")
        got = [(c, l) for c, l in self.codes(iss) if c in ("literal-hex", "literal-func")]
        self.assertEqual(got, [("literal-func", 2), ("literal-hex", 1), ("literal-hex", 7)])

    def test_bare_palette_hex_warns(self):
        iss = self.lint("color5 bb9af7\n{{ r.md | px }}{{ a.glass | num:2 }}{{ c.primary | hex }}\n")
        self.assertIn(("bare-hex", 1), self.codes(iss))

    def test_unused_and_undeclared_keys(self):
        # keys заявляют radius, но шаблон r.* не использует; a.glass используется, но glassAlpha не заявлен
        iss = self.lint("{{ c.primary | hex }}{{ a.glass | num:2 }}\n", keys=["appearance.accent", "appearance.radius"])
        got = {i.code: i.msg for i in iss}
        self.assertIn("unused-key", got)
        self.assertIn("appearance.radius", got["unused-key"])
        self.assertIn("undeclared-ref", got)
        self.assertIn("a.glass", got["undeclared-ref"])

    def test_unused_ext_key_info(self):
        kit = mk_kit(self.tmp)
        issues, _, _ = tk.run_lint(kit)  # все цели -> глобальная проверка ext-ключей
        self.assertIn(("unused-ext", "(палитра)"), [(i.code, i.target) for i in issues])
        self.assertEqual([i for i in issues if i.severity == "error"], [])

    def test_exit_codes(self):
        kit = mk_kit(self.tmp, template="{{ c.nope | hex }}\n")
        args = argparse.Namespace(root=str(self.tmp), settings_dir=str(self.tmp / "settings"),
                                  target=["mini"], strict=False, json=False)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(tk._cmd_lint(args), 1)


class TestFixtures(Base):
    def test_isolated_home(self):
        h = tk.make_isolated_home(self.tmp)
        self.assertTrue(str(h.home).startswith(str(self.tmp)))
        self.assertEqual(h.env["HOME"], str(h.home))
        for p in (h.zen_profile, h.tb_profile, *h.vaults):
            self.assertTrue(p.is_dir(), p)
        self.assertIn(" ", h.zen_profile.name)
        self.assertIn("(", h.zen_profile.name)
        self.assertTrue(any("(" in str(v) and " " in str(v) for v in h.vaults))
        zi = (h.config / "zen" / "installs.ini").read_text()
        self.assertEqual([l.split("=", 1)[1] for l in zi.splitlines() if l.startswith("Default=")],
                         [h.zen_profile.name])
        reg = json.loads((h.config / "obsidian" / "obsidian.json").read_text())
        paths = [v["path"] for v in reg["vaults"].values()]
        self.assertEqual(len(paths), 3)
        self.assertFalse(Path(h.unmounted_vault).exists())
        self.assertEqual(sum(1 for p in paths if (Path(p) / ".obsidian").is_dir()), 2)
        self.assertEqual(os.stat(h.state).st_mode & 0o777, 0o700)

    def test_idempotent(self):
        tk.make_isolated_home(self.tmp)
        tk.make_isolated_home(self.tmp)


if __name__ == "__main__":
    unittest.main()
