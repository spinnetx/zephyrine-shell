"""Светлая тема (appearance.mode=light): палитра, акцент, контраст, шаблоны, patch/gsettings по режиму."""
import json
import os
import re
import unittest

from zsettings import color, palette, patch, testkit as tk
from tests.test_hypr import REAL_ROOT

KIT = tk.Kit(root=REAL_ROOT)
DARK = KIT.scheme
ROLES = KIT.roles
LIGHT = ROLES["schemes"]["light"]
MODE = {"appearance.mode": "light"}

# (текст, фон, минимальный контраст WCAG)
PAIRS = (("onSurface", "surface", 7), ("onSurface", "surfaceContainerHighest", 7), ("onSurfaceVariant", "surface", 4.5),
         ("primary", "surface", 4.5), ("secondary", "surface", 4.5), ("error", "surface", 4.5),
         ("onPrimary", "primary", 4.5), ("onSecondary", "secondary", 4.5), ("onTertiary", "tertiary", 4.5),
         ("onError", "error", 4.5), ("onSuccess", "success", 4.5), ("onWarning", "warning", 4.5),
         ("onPrimaryContainer", "primaryContainer", 4.5), ("onSecondaryContainer", "secondaryContainer", 4.5),
         ("onTertiaryContainer", "tertiaryContainer", 4.5), ("onErrorContainer", "errorContainer", 4.5),
         ("onSuccessContainer", "successContainer", 4.5), ("outline", "surface", 3))


def eff(over=None):
    v = tk.effective_values(KIT, dict(MODE, **(over or {})))
    return palette.effective_palette(DARK, ROLES, v)


class LightSchemeTests(unittest.TestCase):
    def test_same_keys_as_dark_and_valid_hex(self):
        self.assertEqual(list(LIGHT["colours"]), list(DARK["colours"]))
        for k, v in LIGHT["colours"].items():
            self.assertRegex(v, r"^[0-9a-f]{6}$", k)
        self.assertEqual(LIGHT["mode"], "light")

    def test_light_surface_is_light_and_dark_is_untouched(self):
        self.assertGreater(color.hex_to_oklch(LIGHT["colours"]["background"])[0], 0.95)
        self.assertLess(color.hex_to_oklch(DARK["colours"]["background"])[0], 0.3)
        dark = palette.effective_palette(DARK, ROLES, tk.effective_values(KIT))
        self.assertEqual(dark["background"], DARK["colours"]["background"])

    def test_contrast_of_default_light_palette(self):
        c = eff()
        for fg, bg, need in PAIRS:
            self.assertGreaterEqual(color.contrast(c[fg], c[bg]), need, "%s на %s" % (fg, bg))

    def test_contrast_with_every_preset_accent(self):
        for acc in ("#bb9af7", "#7aa2f7", "#2ac3de", "#9ece6a", "#e0af68", "#ff9e64", "#f7768e", "#f5a3d4"):
            c = eff({"appearance.accent": acc})
            self.assertLessEqual(color.hex_to_oklch(c["primary"])[0], color.LIGHT_MAX_L + 0.01, acc)
            for fg, bg, need in (("primary", "surface", 3), ("onPrimary", "primary", 4.5),
                                 ("onPrimaryContainer", "primaryContainer", 4.5)):
                self.assertGreaterEqual(color.contrast(c[fg], c[bg]), need, "%s: %s на %s" % (acc, fg, bg))

    def test_dark_accent_validation_unchanged(self):
        with self.assertRaises(palette.PaletteError):
            palette.effective_palette(DARK, ROLES, tk.effective_values(KIT, {"appearance.accent": "#101030"}))

    def test_light_accent_is_idempotent_and_keeps_dark_ones(self):
        a = color.light_accent("#bb9af7")
        self.assertEqual(color.light_accent(a), a)
        self.assertEqual(color.light_accent("#303090"), "303090")


class LightRenderTests(unittest.TestCase):
    def render(self, tid, over=None):
        t = next(x for x in KIT.targets if x["id"] == tid)
        return tk.render_target(KIT, t, dict(MODE, **(over or {}))).decode("utf-8")

    def test_every_template_renders_in_light_mode(self):
        n = 0
        for t in KIT.targets:
            if t.get("kind") != "template" or tk.skip_reason(KIT, t):
                continue
            out = self.render(t["id"])
            self.assertNotIn("{{", out, t["id"])
            n += 1
        self.assertGreater(n, 10)

    def test_mode_specific_constants(self):
        self.assertIn("color-scheme: light;", self.render("obsidian"))
        self.assertIn('"appearance": "light"', self.render("zed"))
        self.assertIn('"color_scheme": "light"', self.render("tb-theme"))
        dark = tk.render_target(KIT, next(x for x in KIT.targets if x["id"] == "obsidian"), None).decode("utf-8")
        self.assertIn("color-scheme: dark;", dark)

    def test_quickshell_override_carries_whole_light_palette(self):
        ov = json.loads(palette.override_text(DARK, eff()))["colours"]
        self.assertEqual(ov["background"], LIGHT["colours"]["background"])
        self.assertGreater(len(ov), 60)

    def test_hyprlock_and_sddm_follow_mode(self):
        self.assertIn(LIGHT["colours"]["primary"], self.render("sddm"))
        lock = self.render("hyprlock")
        r, g, b = (int(LIGHT["colours"]["primary"][i:i + 2], 16) for i in (0, 2, 4))
        self.assertIn("rgba(%d, %d, %d, 1.0)" % (r, g, b), lock)


class ModeMapPatchTests(unittest.TestCase):
    def test_map_picks_value_by_mode(self):
        spec = {"from": "appearance.mode", "map": {"dark": "adw-gtk3-dark", "light": "adw-gtk3"}}
        self.assertEqual(patch.fields({"appearance.mode": "light"}, spec), {"v": "adw-gtk3"})
        self.assertEqual(patch.fields({"appearance.mode": "dark"}, spec), {"v": "adw-gtk3-dark"})
        with self.assertRaises(patch.PatchError):
            patch.fields({"appearance.mode": "sepia"}, spec)

    def test_gtk_settings_ini_patch(self):
        t = next(x for x in KIT.targets if x["id"] == "gtk3-settings")
        text = "[Settings]\ngtk-theme-name=adw-gtk3-dark\ngtk-application-prefer-dark-theme=true\ngtk-icon-theme-name=Papirus-Dark\ngtk-font-name=Inter,  10\ngtk-cursor-theme-name=Qogir\ngtk-cursor-theme-size=24\n"
        base = tk.effective_values(KIT)
        out, _ = patch.patch_text(text, t["patches"], dict(base, **MODE), "/h")
        self.assertIn("gtk-theme-name=adw-gtk3\n", out)
        self.assertIn("gtk-application-prefer-dark-theme=false\n", out)
        self.assertIn("gtk-icon-theme-name=Papirus\n", out)
        same, _ = patch.patch_text(text, t["patches"], base, "/h")
        self.assertEqual(same, text)


if __name__ == "__main__":
    unittest.main()


class AdoptOtherModeTests(unittest.TestCase):
    """Файл, записанный в другом режиме темы (пришёл из git), - не drift при переключении режима."""

    class P:
        t = {"kind": "template"}

        def default_content(self):
            return b"default"

    class D:
        def __init__(self, cur):
            self.current = cur

    class E:
        def __init__(self, alt):
            self.alt = alt

        def render(self, t, default=False):
            assert default == "alt"
            if isinstance(self.alt, Exception):
                raise self.alt
            return self.alt

    def adopt(self, current, alt):
        from zsettings import targets
        d = self.D(current)
        return targets.Engine._adoptable(self.E(alt), self.P(), d, d)

    def test_other_mode_output_is_adopted(self):
        self.assertTrue(self.adopt(b"dark render", b"dark render"))

    def test_foreign_edit_is_still_drift(self):
        self.assertFalse(self.adopt(b"hand edited", b"dark render"))

    def test_render_failure_means_not_adopted(self):
        self.assertFalse(self.adopt(b"x", ValueError("accent")))

    def test_generated_header_is_adopted_for_any_kind(self):
        self.assertTrue(self.adopt("; СГЕНЕРИРОВАНО zephyrine-settings из x\n[General]\n".encode(), b"other"))
        self.assertTrue(self.adopt("# Файл СГЕНЕРИРОВАН zephyrine-settings из x\n".encode(), b"other"))
