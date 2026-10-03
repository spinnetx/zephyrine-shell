"""Тесты A3: ползунки appearance.kittyOpacity (patch kitty.conf) и hypr.glassOpacity (эмиттер hypr.py).

Дефолты ничего не меняют (kitty.conf репо и DEFAULT_TEXT), недефолтные значения правят ровно одну строку,
диапазоны проверяются и в схеме, и в CLI. Всё в изолированном HOME (FontCase); живой settings.json не читается.
"""
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SETTINGS_DIR)
sys.path.insert(0, HERE)

try:
    from .test_patch import FontCase, PATCH_IDS
    from . import test_hypr
except ImportError:
    from test_patch import FontCase, PATCH_IDS
    import test_hypr

from zsettings import hypr, patch  # noqa: E402

REAL_ROOT = os.path.dirname(SETTINGS_DIR)
KITTY = os.path.join(REAL_ROOT, ".config", "kitty", "kitty.conf")


def schema_keys():
    with open(os.path.join(SETTINGS_DIR, "schema.json"), encoding="utf-8") as f:
        return json.load(f)["keys"]


def kitty_specs():
    with open(os.path.join(SETTINGS_DIR, "targets.json"), encoding="utf-8") as f:
        return next(t for t in json.load(f)["targets"] if t["id"] == "kitty-conf")["patches"]


def kitty_eff(**over):
    d = {k: v["default"] for k, v in schema_keys().items() if k.startswith("appearance.fonts.mono")
         or k == "appearance.kittyOpacity"}
    d.update(over)
    return d


class SchemaTests(unittest.TestCase):
    def test_ranges_defaults_and_no_stub(self):
        keys = schema_keys()
        for key, lo, hi, dflt, tgt in (("appearance.kittyOpacity", 0.5, 1.0, 0.74, "kitty-conf"),
                                       ("hypr.glassOpacity", 0.3, 1.0, 0.7, "hypr")):
            with self.subTest(key=key):
                k = keys[key]
                self.assertEqual((k["type"], k["min"], k["max"], k["default"]), ("number", lo, hi, dflt))
                self.assertEqual(k["targets"], [tgt])
                self.assertNotIn("stub", k)
                self.assertFalse(k["live"])

    def test_defaults_match_emitter_and_live_files(self):
        self.assertEqual(hypr.DEFAULTS["hypr.glassOpacity"], schema_keys()["hypr.glassOpacity"]["default"])
        with open(KITTY, encoding="utf-8") as f:
            self.assertIn("\nbackground_opacity 0.74\n", f.read())

    def test_glass_key_listed_in_hypr_target(self):
        with open(os.path.join(SETTINGS_DIR, "targets.json"), encoding="utf-8") as f:
            t = next(t for t in json.load(f)["targets"] if t["id"] == "hypr")
        self.assertIn("hypr.glassOpacity", t["keys"])
        self.assertNotIn("hypr.glassOpacity", t.get("keysLater", []))


class KittyPatchTests(unittest.TestCase):
    def run_patch(self, text, **over):
        return patch.patch_text(text, kitty_specs(), kitty_eff(**over), "/h")

    def test_default_leaves_real_kitty_conf_byte_identical(self):
        with open(KITTY, encoding="utf-8") as f:
            text = f.read()
        out, _ = self.run_patch(text)
        self.assertEqual(out, text)

    def test_non_default_changes_only_that_line(self):
        with open(KITTY, encoding="utf-8") as f:
            text = f.read()
        for v, s in ((0.5, "0.50"), (0.55, "0.55"), (1.0, "1.00")):
            with self.subTest(v=v):
                out, _ = self.run_patch(text, **{"appearance.kittyOpacity": v})
                a, b = text.splitlines(), out.splitlines()
                self.assertEqual(len(a), len(b))
                diff = [(x, y) for x, y in zip(a, b) if x != y]
                self.assertEqual(diff, [("background_opacity 0.74", "background_opacity " + s)])
                self.assertIn("background_blur 1", b)


class KittyCliTests(FontCase):
    def test_range_enforced(self):
        for bad in ("0.49", "1.01", "0", "-1", "abc"):
            with self.subTest(bad=bad):
                code, r = self.run_cli("set", "appearance.kittyOpacity=" + bad, "--no-apply")
                self.assertEqual(code, 2)
                self.assertFalse(r["ok"])
        for ok in ("0.5", "1", "0.7"):
            with self.subTest(ok=ok):
                code, r = self.run_cli("set", "appearance.kittyOpacity=" + ok, "--no-apply")
                self.assertEqual((code, r["errors"]), (0, []))

    def test_glass_range_enforced(self):
        for bad in ("0.29", "1.01", "0", "abc"):
            with self.subTest(bad=bad):
                code, r = self.run_cli("set", "hypr.glassOpacity=" + bad, "--no-apply")
                self.assertEqual(code, 2)
        for ok in ("0.3", "1", "0.7"):
            with self.subTest(ok=ok):
                code, r = self.run_cli("set", "hypr.glassOpacity=" + ok, "--no-apply")
                self.assertEqual((code, r["errors"]), (0, []))

    def test_dry_run_writes_nothing_and_reset_returns_to_default(self):
        before = self.snapshot()
        code, r = self.run_cli("set", "appearance.kittyOpacity=0.9", "--dry-run")
        self.assertEqual(code, 0)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.calls() and [c for c in self.calls() if "USR1" in c], [])
        code, r = self.run_cli("set", "appearance.kittyOpacity=0.9")
        self.assertIn("kitty-conf", r["changed"])
        self.assertIn("background_opacity 0.90\n", self.read(self.repo(".config/kitty/kitty.conf")).decode())
        code, r = self.run_cli("reset", "appearance.kittyOpacity")
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertIn("background_opacity 0.74\n", self.read(self.repo(".config/kitty/kitty.conf")).decode())
        with open(self.settings_file, encoding="utf-8") as f:
            self.assertNotIn("kittyOpacity", f.read())

    def test_default_apply_is_noop(self):
        before = self.snapshot()
        code, r = self.apply_fonts()
        self.assertEqual((code, r["errors"], r["changed"]), (0, [], []))
        self.assertEqual(self.snapshot(), before)


class GlassEmitTests(unittest.TestCase):
    def test_default_equals_golden_text(self):
        self.assertEqual(test_hypr.gen(), test_hypr.DEFAULT_TEXT)
        self.assertEqual(test_hypr.gen({"hypr.glassOpacity": 0.7}), test_hypr.DEFAULT_TEXT)

    def test_non_default_changes_only_glass_line(self):
        base = test_hypr.gen().splitlines()
        for v, s in ((0.3, "0.3"), (0.45, "0.45"), (1, "1.0")):
            with self.subTest(v=v):
                new = test_hypr.gen({"hypr.glassOpacity": v}).splitlines()
                self.assertEqual(len(base), len(new))
                diff = [i for i, (x, y) in enumerate(zip(base, new)) if x != y]
                self.assertEqual(diff, [6])   # строка glass_opacity (дальше блок автозапуска)
                self.assertIn("glass_opacity = %s })" % s, new[6])

    def test_range_boundaries(self):
        for bad in (0.29, 1.01, 0, -0.5, float("nan"), None, True, "0.7"):
            with self.subTest(bad=bad):
                with self.assertRaises(hypr.HyprError):
                    test_hypr.gen({"hypr.glassOpacity": bad})
