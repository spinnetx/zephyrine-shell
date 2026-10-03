import glob
import json
import os
import random
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from zsettings import color as C  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))  # ~/my_zephyrine_conf
SCHEME = os.path.join(REPO, "quickshell", "scheme.json")


def scheme_colours():
    with open(SCHEME) as f:
        return json.load(f)["colours"]


def theme_hexes():
    """Все 6/8-значные hex из текущих файлов тем (первые 6 цифр)."""
    pats = [".config/gtk-3.0/*", ".config/gtk-4.0/*", ".config/kitty/*", ".config/qt6ct/colors/*",
            ".config/zathura/*", ".config/zed/themes/*", "obsidian/**/*.css",
            "thunderbird/**/*.css", "thunderbird/**/*.json", "zen/*.css"]
    found = set()
    for p in pats:
        for path in glob.glob(os.path.join(REPO, p), recursive=True):
            if not os.path.isfile(path):
                continue
            try:
                with open(path, encoding="utf-8") as fh:
                    text = fh.read()
            except (UnicodeDecodeError, OSError):
                continue
            for m in re.finditer(r"#([0-9a-fA-F]{8}|[0-9a-fA-F]{6})(?![0-9a-fA-F])", text):
                found.add(m.group(1)[:6].lower())
    return sorted(found)


class RoundTrip(unittest.TestCase):
    def check(self, hx):
        self.assertEqual(C.oklch_to_hex(C.hex_to_oklch(hx)), hx, hx)
        self.assertEqual(C.oklab_to_hex(C.hex_to_oklab(hx)), hx, hx)
        self.assertEqual(C.rgb_to_hex(C.hex_to_rgb(hx)), hx, hx)

    def test_scheme_json(self):
        cols = scheme_colours()
        self.assertGreaterEqual(len(cols), 31)
        for k, v in cols.items():
            with self.subTest(k):
                self.check(v)

    def test_theme_files(self):
        hexes = theme_hexes()
        if not hexes:
            self.skipTest("нет файлов тем")
        for hx in hexes:
            with self.subTest(hx):
                self.check(hx)

    def test_random_and_extremes(self):
        rnd = random.Random(1)
        samples = ["000000", "ffffff", "ff0000", "00ff00", "0000ff", "ff00ff", "00ffff", "ffff00", "808080"]
        samples += ["%06x" % rnd.randrange(1 << 24) for _ in range(20000)]
        for hx in samples:
            self.check(hx)

    def test_normalize(self):
        self.assertEqual(C.normalize_hex("#BB9AF7"), "bb9af7")
        for bad in ("12345", "gggggg", "#1234567", None):
            with self.assertRaises(ValueError):
                C.normalize_hex(bad)


class Gamut(unittest.TestCase):
    def test_clip_in_gamut_and_keeps_hue(self):
        lch = (0.7, 0.4, 150.0)  # заведомо вне sRGB
        L, c, h = C.clip_oklch(lch)
        self.assertLess(c, 0.4)
        self.assertTrue(C.in_gamut(C.oklab_to_linear(C.oklch_to_oklab((L, c, h)))))
        self.assertEqual((L, h), (0.7, 150.0))
        out = C.oklch_to_hex(lch)
        self.assertAlmostEqual(C.hex_to_oklch(out)[2], 150.0, delta=3.0)

    def test_extreme_lightness(self):
        self.assertEqual(C.oklch_to_hex((1.2, 0.3, 10)), "ffffff")
        self.assertEqual(C.oklch_to_hex((-0.1, 0.3, 10)), "000000")


class Wcag(unittest.TestCase):
    def test_known(self):
        self.assertAlmostEqual(C.contrast("000000", "ffffff"), 21.0, places=6)
        self.assertAlmostEqual(C.contrast("ffffff", "ffffff"), 1.0, places=6)
        self.assertAlmostEqual(C.contrast("777777", "ffffff"), 4.48, places=2)

    def test_scheme_pairs(self):
        c = scheme_colours()
        self.assertGreaterEqual(C.contrast(c["primary"], c["background"]), 3.0)
        self.assertGreaterEqual(C.contrast(c["onPrimary"], c["primary"]), 4.5)


class Hsl(unittest.TestCase):
    def test_primary_honest_value(self):
        # честный HSL bb9af7 = 261, 85%, 79%; литерал "267, 85%, 78%" из CSS — не его
        # округление, поэтому при дефолтном акценте он берётся short-circuit-ом, а не считается.
        self.assertEqual(C.hsl_string("bb9af7"), "261, 85%, 79%")

    def test_grey_and_primaries(self):
        self.assertEqual(C.hsl_string("808080"), "0, 0%, 50%")
        self.assertEqual(C.hsl_string("ff0000"), "0, 100%, 50%")
        self.assertEqual(C.hsl_string("0000ff"), "240, 100%, 50%")


class Derive(unittest.TestCase):
    PRIMARY_FAMILY = ("onPrimary", "primaryContainer", "onPrimaryContainer",
                      "inversePrimary", "primaryFixed", "primaryFixedDim",
                      "onPrimaryFixed", "onPrimaryFixedVariant", "surfaceTint")

    def test_short_circuit_returns_literal(self):
        c = scheme_colours()
        base = c["primary"]
        for k in self.PRIMARY_FAMILY + ("primary_paletteKeyColor",):
            self.assertIs(C.derive(c[k], base, base), c[k])
            self.assertIs(C.derive(c[k], base, "#" + base.upper()), c[k])  # формат не важен
        self.assertEqual(C.derive("cdb2f9", "bb9af7", "BB9AF7"), "cdb2f9")

    def test_short_circuit_no_computation(self):
        # даже «неточный» литерал не пересчитывается
        self.assertEqual(C.derive("123456", "bb9af7", "bb9af7"), "123456")

    def test_zero_delta_becomes_accent(self):
        c = scheme_colours()
        new = "ff8800"
        for k in ("surfaceTint", "primaryFixedDim", "primary_paletteKeyColor"):
            self.assertEqual(c[k], c["primary"])
            self.assertEqual(C.derive(c[k], c["primary"], new), new)

    def check_accent(self, new):
        c = scheme_colours()
        base = c["primary"]
        d = {k: C.derive(c[k], base, new) for k in self.PRIMARY_FAMILY}
        newL, newC, newH = C.hex_to_oklch(new)
        # контейнер темнее акцента, on-container светлее контейнера, всё читаемо
        self.assertLess(C.hex_to_oklch(d["primaryContainer"])[0], newL)
        self.assertGreaterEqual(C.contrast(d["onPrimaryContainer"], d["primaryContainer"]), 4.5)
        self.assertGreaterEqual(C.contrast(d["onPrimary"], new), 4.5)
        # оттенок контейнера близок к акценту (при заметной хроме)
        Lc, Cc, Hc = C.hex_to_oklch(d["primaryContainer"])
        if Cc > 0.03 and newC > 0.05:
            dh = abs((Hc - newH + 180) % 360 - 180)
            self.assertLess(dh, 25, (new, d["primaryContainer"]))
        # порядок светлоты сохранён: onPrimaryContainer > primaryContainer; fixed светлее
        self.assertGreater(C.hex_to_oklch(d["onPrimaryContainer"])[0], Lc)
        return d

    def test_marker_accent_magenta(self):
        d = self.check_accent("ff00ff")
        self.assertNotEqual(d["primaryContainer"], "4b3161")

    def test_other_accents(self):
        for new in ("7aa2f7", "9ece6a", "ff9e64", "2ac3de"):
            with self.subTest(new):
                self.check_accent(new)

    def test_gamut_safe_result(self):
        # насыщенный акцент даёт валидный hex и все компоненты в диапазоне
        for new in ("ff0000", "00ffff", "ffff00"):
            for k in ("primaryContainer", "inversePrimary", "onPrimaryContainer"):
                out = C.derive(scheme_colours()[k], "bb9af7", new)
                self.assertEqual(len(C.normalize_hex(out)), 6)

    def test_achromatic_base_anchor(self):
        # C_B ~ 0 -> хрома K не масштабируется
        out = C.derive("336699", "808080", "ff8800")
        self.assertEqual(len(out), 6)

    def test_deterministic(self):
        self.assertEqual(C.derive("4b3161", "bb9af7", "ff00ff"),
                         C.derive("4b3161", "bb9af7", "ff00ff"))


class Accent(unittest.TestCase):
    def test_default_ok(self):
        c = scheme_colours()
        on, cpb, con = C.validate_accent(c["primary"], c["background"], c["onPrimary"])
        self.assertEqual(on, c["onPrimary"])
        self.assertGreaterEqual(cpb, 3.0)
        self.assertGreaterEqual(con, 4.5)

    def test_too_dark_rejected(self):
        with self.assertRaises(C.AccentError):
            C.validate_accent("301060", "141414", "ffffff")

    def test_on_primary_switched(self):
        # светлый акцент + светлый «onPrimary» -> переключаем на тёмный вариант
        on, _, con = C.validate_accent("ffe066", "141414", "ffffff")
        self.assertGreaterEqual(con, 4.5)
        self.assertLess(C.hex_to_oklch(on)[0], 0.5)


if __name__ == "__main__":
    unittest.main()
