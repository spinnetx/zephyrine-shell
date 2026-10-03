import json
import os
import unittest

from zsettings import barlayout, model
from zsettings.util import Paths
from tests.test_hypr import REAL_ROOT


def schema():
    p = Paths.from_env({"HOME": "/nonexistent-home", "ZEPHYRINE_ROOT": REAL_ROOT})
    return model.Schema.load(p.schema_file, p.targets_file)


class LayoutTests(unittest.TestCase):
    def setUp(self):
        self.s = schema()

    def check(self, **flat):
        return barlayout.check_values(self.s, flat, list(flat))

    def test_defaults_valid_and_cover_all_items(self):
        flat = {z: self.s.default(z) for z in barlayout.ZONES}
        self.assertEqual(barlayout.check_values(self.s, flat, list(flat)), [])
        # в зонах по умолчанию - всё, кроме DEFAULT_HIDDEN (новые виджеты добавляются пользователем через редактор)
        self.assertEqual(sorted(i for z in flat.values() for i in z),
                         sorted(i for i in barlayout.IDS if i not in barlayout.DEFAULT_HIDDEN))
        self.assertEqual(self.s.default("bar.position"), "top")

    def test_errors(self):
        self.assertIn("unknown bar item", self.check(**{"bar.left": ["nope"]})[0]["error"])
        e = self.check(**{"bar.left": ["workspaces", "clock"]})   # clock уже в bar.right
        self.assertIn("two zones", e[0]["error"])
        self.assertEqual(self.check(**{"bar.left": ["workspaces"], "bar.right": ["clock"]}), [])
        self.assertEqual(barlayout.check_values(self.s, {}, ["appearance.radius"]), [])

    def test_new_widgets_known_and_city(self):
        for i in ("temp", "battery", "kbd", "timer", "weather", "volume", "wifi", "bluetooth", "apps"):
            self.assertIn(i, barlayout.IDS)
        self.assertEqual(self.check(**{"bar.right": ["clock", "timer", "weather"]}), [])
        self.assertEqual(self.check(**{"weather.city": "Kraków"}), [])
        self.assertEqual(self.check(**{"weather.city": "Санкт-Петербург"}), [])
        for bad in ("a/b", "x?y", "q&r", "a%20b", "a\nb", "x" * 61):
            self.assertIn("invalid city", self.check(**{"weather.city": bad})[0]["error"], bad)

    def test_position_enum_validated(self):
        self.assertEqual(self.s.validate("bar.position", "left"), "left")
        with self.assertRaises(model.ValidationError):
            self.s.validate("bar.position", "middle")

    def test_catalog_matches_bar_qml(self):
        qml = open(os.path.join(REAL_ROOT, "quickshell", "Bar.qml"), encoding="utf-8").read()
        if "registry" not in qml:
            self.skipTest("реестр в Bar.qml ещё не добавлен")
        for i in barlayout.IDS:
            self.assertIn(i + ":", qml, i)


if __name__ == "__main__":
    unittest.main()
