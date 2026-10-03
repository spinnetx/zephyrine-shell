import os
import tempfile
import unittest

from zsettings import hypr, xkb
from tests.test_hypr import DEFAULTS, PATHS, ctx_for, eff

LST = """! model
  pc105           Generic 105-key PC

! layout
  pl              Polish
  ru              Russian
  us              English (US)

! variant
  phonetic        ru: Russian (phonetic)
  dvorak          us: English (Dvorak)

! option
  grp             Switching to another layout
  grp:alt_shift_toggle Alt+Shift
  grp:win_space_toggle Win+Space
  caps            Caps Lock behavior
  caps:escape     Caps Lock as Escape
"""


class FakeSchema:
    def default(self, key):
        return DEFAULTS[key]


class ParseTests(unittest.TestCase):
    def test_parse_and_catalog(self):
        d = xkb.parse(LST)
        self.assertEqual([x["id"] for x in d["layouts"]], ["pl", "ru", "us"])
        self.assertEqual(d["variants"]["ru"][0]["id"], "phonetic")
        self.assertEqual([o["id"] for o in d["options"]], ["grp:alt_shift_toggle", "grp:win_space_toggle", "caps:escape"])

    def test_kb_strings(self):
        L = [{"layout": "pl", "variant": ""}, {"layout": "ru", "variant": "phonetic"}]
        self.assertEqual(xkb.kb_strings(L, "grp:alt_shift_toggle", ["caps:escape"]),
                         ("pl,ru", ",phonetic", "grp:alt_shift_toggle,caps:escape"))
        self.assertEqual(xkb.kb_strings(L[:1], "", []), ("pl", "", ""))


class CheckTests(unittest.TestCase):
    def setUp(self):
        d = tempfile.mkdtemp()
        self.path = os.path.join(d, "base.lst")
        with open(self.path, "w", encoding="utf-8") as f:
            f.write(LST)

    def check(self, **flat):
        return xkb.check_values(FakeSchema(), flat, list(flat), self.path)

    def test_ok_and_untouched(self):
        self.assertEqual(self.check(**{"input.layouts": [{"layout": "us", "variant": "dvorak"}],
                                       "input.switchOption": ""}), [])
        self.assertEqual(xkb.check_values(FakeSchema(), {}, ["appearance.radius"], self.path), [])

    def test_errors(self):
        e = self.check(**{"input.layouts": [{"layout": "xx", "variant": ""}], "input.switchOption": ""})
        self.assertIn("unknown layout", e[0]["error"])
        e = self.check(**{"input.layouts": [{"layout": "pl", "variant": "phonetic"}], "input.switchOption": ""})
        self.assertIn("unknown variant", e[0]["error"])
        e = self.check(**{"input.switchOption": ""})   # 2 раскладки по умолчанию без переключателя
        self.assertIn("required", e[0]["error"])
        e = self.check(**{"input.switchOption": "caps:escape"})
        self.assertIn("switch option", e[0]["error"])
        e = self.check(**{"input.extraOptions": ["grp:win_space_toggle"]})
        self.assertIn("unknown option", e[0]["error"])
        e = self.check(**{"input.layouts": [{"layout": "pl", "variant": ""}, {"layout": "pl", "variant": ""}]})
        self.assertIn("duplicate", e[0]["error"])


class EmitTests(unittest.TestCase):
    def gen(self, over=None):
        v = eff(over)
        return hypr.emit(v, ctx_for(v), PATHS)

    def test_defaults_emit_no_input_block(self):
        self.assertNotIn("input", self.gen())

    def test_input_block(self):
        t = self.gen({"input.layouts": [{"layout": "us", "variant": "dvorak"}, {"layout": "ru", "variant": ""}],
                      "input.extraOptions": ["caps:escape"], "input.repeatRate": 40, "input.repeatDelay": 300})
        self.assertIn('kb_layout = "us,ru", kb_variant = "dvorak,", kb_options = "grp:alt_shift_toggle,caps:escape", '
                      'repeat_rate = 40, repeat_delay = 300', t)

    def test_touchpad_block(self):
        self.assertNotIn("touchpad", self.gen())
        t = self.gen({"input.touchpad.tapToClick": False, "input.touchpad.scrollFactor": 1.5, "input.sensitivity": 0.2})
        self.assertIn('sensitivity = 0.2, touchpad = { natural_scroll = true, tap_to_click = false, ', t)
        self.assertIn("middle_button_emulation = false, scroll_factor = 1.5 } } })", t)
        with self.assertRaises(hypr.HyprError):
            self.gen({"input.sensitivity": 3})
        with self.assertRaises(hypr.HyprError):
            self.gen({"input.touchpad.naturalScroll": "yes"})

    def test_rate_only_and_rejects(self):
        self.assertIn('repeat_rate = 30', self.gen({"input.repeatRate": 30}))
        with self.assertRaises(hypr.HyprError):
            self.gen({"input.repeatRate": 500})
        with self.assertRaises(hypr.HyprError):
            self.gen({"input.extraOptions": ['x"]'], "input.repeatRate": 30})


if __name__ == "__main__":
    unittest.main()
