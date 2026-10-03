"""Тесты palette.py: эффективная палитра, scheme.override.json, контекст рендера (включая ключ `d`)."""
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SETTINGS_DIR)

from zsettings import palette, testkit  # noqa: E402
from zsettings.render import TemplateRenderer  # noqa: E402
from zsettings.util import Paths  # noqa: E402


def real_inputs():
    with open(os.path.join(SETTINGS_DIR, "..", "quickshell", "scheme.json"), encoding="utf-8") as f:
        scheme = json.load(f)
    with open(os.path.join(SETTINGS_DIR, "palette-roles.json"), encoding="utf-8") as f:
        roles = json.load(f)
    with open(os.path.join(SETTINGS_DIR, "schema.json"), encoding="utf-8") as f:
        schema = json.load(f)
    return scheme, roles, schema


class PaletteTests(unittest.TestCase):
    def setUp(self):
        self.scheme, self.roles, self.schema = real_inputs()
        self.defaults = palette.schema_defaults(self.schema)

    def ctx(self, **over):
        vals = dict(self.defaults)
        vals.update(over)
        return palette.build_context(self.scheme, self.roles, vals, self.defaults)

    def test_defaults_are_scheme_literals(self):
        ctx = self.ctx()
        base = palette.base_colours(self.scheme)
        self.assertEqual(ctx["c"], base)  # короткое замыкание: ни одного вычисленного цвета
        self.assertEqual(ctx["s"]["primaryHsl"], "267, 85%, 78%")
        self.assertEqual(palette.override_colours(self.scheme, ctx["c"]), {})
        self.assertEqual(palette.override_text(self.scheme, ctx["c"]), '{"colours": {}}\n')

    def test_accent_derives_and_only_changed_keys_in_override(self):
        ctx = self.ctx(**{"appearance.accent": "#7aa2f7"})
        self.assertEqual(ctx["c"]["primary"], "7aa2f7")
        self.assertEqual(ctx["c"]["purple"], "bb9af7")  # оттенки (ANSI/синтаксис) не следуют за акцентом
        ov = palette.override_colours(self.scheme, ctx["c"])
        self.assertEqual(ov["primary"], "7aa2f7")
        self.assertNotIn("purple", ov)
        self.assertNotIn("background", ov)
        self.assertTrue(set(ov) <= set(self.scheme["colours"]))
        text = palette.override_text(self.scheme, ctx["c"])
        self.assertTrue(text.endswith("\n"))
        self.assertEqual(json.loads(text)["colours"], ov)
        self.assertNotEqual(ctx["s"]["primaryHsl"], "267, 85%, 78%")

    def test_bad_accent(self):
        with self.assertRaises(palette.PaletteError):
            self.ctx(**{"appearance.accent": "#101030"})

    def test_d_namespace_is_defaults_and_anchor_filter(self):
        ctx = self.ctx(**{"appearance.glassAlpha": 0.8, "appearance.radius": 5})
        self.assertEqual((ctx["a"]["glass"], ctx["r"]["md"]), (0.8, 5))
        self.assertEqual((ctx["d"]["a"]["glass"], ctx["d"]["a"]["surface"]), (0.88, 0.94))
        self.assertEqual((ctx["d"]["r"]["lg"], ctx["d"]["r"]["md"], ctx["d"]["r"]["sm"], ctx["d"]["r"]["xs"]),
                         (14, 12, 10, 8))
        r = TemplateRenderer(ctx)
        self.assertEqual(r.render("{{ a.glass | anchor:0.72 }}"), "0.64")
        self.assertEqual(TemplateRenderer(self.ctx()).render("{{ a.glass | anchor:0.72 }}"), "0.72")

    def test_meta_and_sections(self):
        ctx = palette.build_context(self.scheme, self.roles, self.defaults, self.defaults, {"tbVersion": "1.0.3"})
        self.assertEqual(ctx["meta"]["tbVersion"], "1.0.3")
        self.assertEqual(self.ctx()["meta"], {"tbVersion": "1.0"})
        self.assertEqual(self.ctx()["hypr"]["rounding"], 10)
        self.assertIn("shell", self.ctx()["f"])

    def test_none_values_ignored(self):
        vals = dict(self.defaults)
        vals["appearance.accent"] = None
        ctx = palette.build_context(self.scheme, self.roles, vals, self.defaults)
        self.assertEqual(ctx["c"]["primary"], "bb9af7")

    def test_testkit_uses_palette_context(self):
        kit = testkit.Kit()
        for over in (None, {"appearance.accent": "#7aa2f7", "appearance.radius": 3, "appearance.glassAlpha": 0.7}):
            self.assertEqual(testkit.build_context(kit, over), palette.kit_context(kit, over))
        self.assertIn("d", testkit.build_context(kit))
        self.assertIs(testkit.schema_defaults, palette.schema_defaults)
        with self.assertRaises(testkit.KitError):
            testkit.build_context(kit, {"appearance.accent": "#101030"})

    def test_check_values(self):
        from zsettings import model
        with tempfile.TemporaryDirectory(prefix="zs-pal-") as td:
            root = os.path.join(td, "root")
            os.makedirs(os.path.join(root, "settings"))
            os.makedirs(os.path.join(root, "quickshell"))
            import shutil
            shutil.copy(os.path.join(SETTINGS_DIR, "schema.json"), os.path.join(root, "settings"))
            shutil.copy(os.path.join(SETTINGS_DIR, "palette-roles.json"), os.path.join(root, "settings"))
            shutil.copy(os.path.join(SETTINGS_DIR, "..", "quickshell", "scheme.json"), os.path.join(root, "quickshell"))
            paths = Paths.from_env({"HOME": td, "ZEPHYRINE_ROOT": root, "ZEPHYRINE_STATE": os.path.join(td, "st")})
            schema = model.Schema.load(paths.schema_file)
            self.assertEqual(palette.check_values(paths, schema, {}), [])
            self.assertEqual(palette.check_values(paths, schema, {"appearance.accent": "#7aa2f7"}), [])
            errs = palette.check_values(paths, schema, {"appearance.accent": "#101030"})
            self.assertEqual(errs[0]["key"], "appearance.accent")
            os.unlink(palette.scheme_path(paths))  # нет scheme.json - проверять нечего, не падаем
            self.assertEqual(palette.check_values(paths, schema, {"appearance.accent": "#101030"}), [])


if __name__ == "__main__":
    unittest.main()
