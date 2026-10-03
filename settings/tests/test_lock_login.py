"""Экран блокировки (hyprlock) и окно входа (SDDM): акцент и шрифты приходят из настроек, дефолты ничего не меняют."""
import os
import re
import unittest

from zsettings import testkit as tk
from tests.test_hypr import REAL_ROOT

KIT = tk.Kit(root=REAL_ROOT)


def target(tid):
    return next(t for t in KIT.targets if t["id"] == tid)


def render(tid, overrides=None):
    return tk.render_target(KIT, target(tid), overrides).decode("utf-8")


def conf_pairs(text):
    out = {}
    for ln in text.splitlines():
        m = re.match(r"^([A-Za-z]+)=(.*)$", ln)
        if m:
            out[m.group(1)] = m.group(2)
    return out


class SddmTests(unittest.TestCase):
    def test_defaults_equal_theme_conf_values(self):
        """Файл-перекрытие при дефолтных настройках не меняет вид: значения совпадают с theme.conf темы."""
        with open(os.path.join(REAL_ROOT, "sddm", "zephyrine", "theme.conf"), encoding="utf-8") as f:
            base = conf_pairs(f.read())
        over = conf_pairs(render("sddm"))
        self.assertGreater(len(over), 10)
        for k, v in over.items():
            self.assertEqual(base.get(k), v, k)

    def test_accent_and_font(self):
        a = conf_pairs(render("sddm", {"appearance.accent": "#e0af68"}))
        self.assertEqual(a["primary"], "e0af68")
        self.assertNotEqual(a["primaryContainer"], "4b3161")
        f = conf_pairs(render("sddm", {"appearance.fonts.login.family": "Inter"}))
        self.assertEqual(f["fontFamily"], "Inter")
        self.assertEqual(f["primary"], "bb9af7")


class HyprlockTests(unittest.TestCase):
    def test_accent_changes_primary_everywhere(self):
        base, new = render("hyprlock"), render("hyprlock", {"appearance.accent": "#e0af68"})
        self.assertIn("rgba(187, 154, 247, 1.0)", base)
        self.assertNotIn("rgba(187, 154, 247", new)
        self.assertIn("rgba(224, 175, 104, 1.0)", new)

    def test_lock_font_replaces_all_families(self):
        base, new = render("hyprlock"), render("hyprlock", {"appearance.fonts.lock.family": "Inter"})
        self.assertEqual(base.count("JetBrainsMono Nerd Font"), base.count("font_family = JetBrainsMono Nerd Font"))
        self.assertNotIn("JetBrainsMono", new)
        self.assertIn("font_family = Inter Bold", new)
        self.assertIn("font_family = Inter\n", new)


if __name__ == "__main__":
    unittest.main()
