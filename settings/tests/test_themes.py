"""Тесты иконок и курсора мыши (DESIGN §3.11): сканер тем, Xcursor -> PNG, ключи схемы, patch-цели GTK/Qt, gsettings,
цель `cursor` (hyprctl setcursor), блок курсора в settings.lua.

Всё в изолированном каталоге (FontCase: HOME/корень/PATH внутри tmp, поддельные gsettings/hyprctl). Каталоги тем -
тоже внутри tmp (ZEPHYRINE_ICON_DIRS), настоящий /usr/share/icons не читается.
"""
import json
import os
import struct
import sys
import unittest
import zlib
from unittest import mock

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

from zsettings import hypr, patch, themes  # noqa: E402

IDS = PATCH_IDS + ["cursor"]
INDEX_ICONS = "[Icon Theme]\nName=%s\nDirectories=48x48/places,scalable/places,16x16/places\n"


def xcursor(sizes=(24, 32, 48), color=(10, 20, 30, 255)):
    """Минимальный Xcursor-файл: по одному кадру на размер (ARGB little-endian, предумноженный)."""
    chunks = []
    for s in sizes:
        px = struct.pack("<BBBB", color[2], color[1], color[0], color[3]) * (s * s)
        chunks.append(struct.pack("<IIIIIIIII", 36, 0xFFFD0002, s, 1, s, s, 1, 1, 0) + px)
    toc, pos = b"", 16 + 12 * len(sizes)
    for s, c in zip(sizes, chunks):
        toc += struct.pack("<III", 0xFFFD0002, s, pos)
        pos += len(c)
    return b"Xcur" + struct.pack("<III", 16, 1, len(sizes)) + toc + b"".join(chunks)


def mk_icon_theme(base, name, with_index=True, directories=True, hidden=False):
    d = os.path.join(base, name)
    os.makedirs(os.path.join(d, "48x48", "places"))
    if with_index:
        txt = (INDEX_ICONS % name) if directories else "[Icon Theme]\nName=%s\nInherits=Adwaita\n" % name
        if hidden:
            txt += "Hidden=true\n"
        with open(os.path.join(d, "index.theme"), "w") as f:
            f.write(txt)
    return d


def mk_cursor_theme(base, name, files=("left_ptr",)):
    d = os.path.join(base, name, "cursors")
    os.makedirs(d)
    for f in files:
        with open(os.path.join(d, f), "wb") as fh:
            fh.write(xcursor())
    with open(os.path.join(base, name, "index.theme"), "w") as fh:
        fh.write("[Icon Theme]\nName=%s\n" % name)
    return os.path.join(base, name)


class ThemeDirs(unittest.TestCase):
    def setUp(self):
        import tempfile
        td = tempfile.TemporaryDirectory(prefix="zs-themes-")
        self.addCleanup(td.cleanup)
        self.tmp = td.name
        self.a = os.path.join(self.tmp, "a")
        self.b = os.path.join(self.tmp, "b")
        os.makedirs(self.a)
        os.makedirs(self.b)
        self.env = {"ZEPHYRINE_ICON_DIRS": os.pathsep.join([self.a, self.b])}


class ScanTests(ThemeDirs):
    def test_icon_themes_need_directories_and_skip_hidden_and_hicolor(self):
        mk_icon_theme(self.a, "Papirus")
        mk_icon_theme(self.a, "Zeta")
        mk_icon_theme(self.a, "hicolor")
        mk_icon_theme(self.a, "NoIndex", with_index=False)
        mk_icon_theme(self.a, "Hid", hidden=True)
        mk_icon_theme(self.a, "OnlyInherits", directories=False)
        mk_cursor_theme(self.a, "Qogir")
        self.assertEqual(themes.names("icons", self.tmp, self.env), ["Papirus", "Zeta"])

    def test_cursor_themes_need_cursors_dir(self):
        mk_cursor_theme(self.a, "Qogir")
        mk_cursor_theme(self.b, "Bibata")
        mk_icon_theme(self.a, "Papirus")
        self.assertEqual(themes.names("cursors", self.tmp, self.env), ["Bibata", "Qogir"])

    def test_first_directory_wins_and_names_are_case_insensitive_sorted(self):
        p1 = mk_cursor_theme(self.a, "Same")
        mk_cursor_theme(self.b, "Same")
        mk_cursor_theme(self.b, "alpha")
        found = themes.scan("cursors", self.tmp, self.env)
        self.assertEqual([t["name"] for t in found], ["alpha", "Same"])
        self.assertEqual(found[1]["path"], p1)

    def test_unsafe_names_are_ignored(self):
        mk_cursor_theme(self.a, 'bad"name')
        mk_cursor_theme(self.a, "ok")
        self.assertEqual(themes.names("cursors", self.tmp, self.env), ["ok"])

    def test_default_search_dirs(self):
        env = {"XDG_DATA_HOME": "/xh", "XDG_DATA_DIRS": "/d1:/d2"}
        self.assertEqual(themes.search_dirs("/home/u", env),
                         ["/home/u/.icons", "/xh/icons", "/d1/icons", "/d2/icons"])
        self.assertEqual(themes.search_dirs("/home/u", {})[-2:], ["/usr/local/share/icons", "/usr/share/icons"])

    def test_unknown_kind(self):
        with self.assertRaises(themes.ThemesError):
            themes.scan("fonts", self.tmp, self.env)


class PreviewTests(ThemeDirs):
    def test_icon_samples_pick_largest_existing_file(self):
        d = mk_icon_theme(self.a, "Papirus")
        for rel in ("48x48/places/folder.svg", "scalable/places/folder.svg", "16x16/places/folder.png"):
            os.makedirs(os.path.join(d, os.path.dirname(rel)), exist_ok=True)
            open(os.path.join(d, rel), "w").close()
        s = themes.icon_samples(d)
        self.assertEqual(s, [os.path.join(d, "scalable/places/folder.svg")])

    def test_icon_samples_ignore_path_escape_in_index(self):
        d = mk_icon_theme(self.a, "Evil")
        with open(os.path.join(d, "index.theme"), "w") as f:
            f.write("[Icon Theme]\nDirectories=../../etc,/etc\n")
        self.assertEqual(themes.icon_samples(d), [])

    def test_xcursor_picks_nearest_size_and_unpremultiplies(self):
        p = os.path.join(self.a, "left_ptr")
        with open(p, "wb") as f:
            f.write(xcursor((24, 48), color=(100, 50, 0, 128)))
        w, h, xh, yh, rgba = themes.read_xcursor(p, want=30)
        self.assertEqual((w, h, xh, yh), (24, 24, 1, 1))
        # предумноженный (b=0,g=50,r=100 при a=128) -> без предумножения r≈199, g≈99
        self.assertEqual(rgba[:4], bytes((199, 99, 0, 128)))
        self.assertEqual(themes.read_xcursor(p, want=100)[0], 48)

    def test_xcursor_rejects_garbage(self):
        p = os.path.join(self.a, "junk")
        for blob in (b"", b"Xcur", b"nope" * 20, xcursor()[:40]):
            with open(p, "wb") as f:
                f.write(blob)
            self.assertIsNone(themes.read_xcursor(p))
        self.assertIsNone(themes.read_xcursor(os.path.join(self.a, "missing")))

    def test_png_is_valid(self):
        data = themes.png_bytes(2, 1, bytes((1, 2, 3, 255, 4, 5, 6, 0)))
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        pos, idat = 8, b""
        while pos < len(data):
            n, tag = struct.unpack(">I4s", data[pos:pos + 8])
            body = data[pos + 8:pos + 8 + n]
            self.assertEqual(struct.unpack(">I", data[pos + 8 + n:pos + 12 + n])[0], zlib.crc32(tag + body) & 0xFFFFFFFF)
            if tag == b"IHDR":
                self.assertEqual(struct.unpack(">II", body[:8]), (2, 1))
            if tag == b"IDAT":
                idat += body
            pos += 12 + n
        self.assertEqual(zlib.decompress(idat), b"\x00" + bytes((1, 2, 3, 255, 4, 5, 6, 0)))


class SchemaTests(unittest.TestCase):
    def keys(self):
        with open(os.path.join(SETTINGS_DIR, "schema.json"), encoding="utf-8") as f:
            return json.load(f)["keys"]

    def test_keys_and_defaults_match_live_files(self):
        k = self.keys()
        self.assertIsNone(k["appearance.icons.theme"]["default"])
        self.assertEqual(k["appearance.cursor.theme"]["default"], "Qogir")
        self.assertEqual((k["appearance.cursor.size"]["default"], k["appearance.cursor.size"]["min"],
                          k["appearance.cursor.size"]["max"]), (24, 16, 64))
        self.assertEqual(hypr.DEFAULTS["appearance.cursor.theme"], "Qogir")
        self.assertEqual(hypr.DEFAULTS["appearance.cursor.size"], 24)
        root = os.path.dirname(SETTINGS_DIR)
        for rel in (".config/gtk-3.0/settings.ini", ".config/gtk-4.0/settings.ini"):
            with open(os.path.join(root, rel), encoding="utf-8") as f:
                txt = f.read()
            self.assertIn("gtk-cursor-theme-name=Qogir\n", txt)
            self.assertIn("gtk-cursor-theme-size=24\n", txt)

    def test_theme_name_pattern_rejects_dangerous_names(self):
        import re
        rx = re.compile(self.keys()["appearance.cursor.theme"]["pattern"])
        for ok in ("Qogir", "Bibata-Modern-Classic", "Papirus Dark", "Adwaita_1.0"):
            self.assertTrue(rx.search(ok), ok)
        for bad in ("", "a\nb", 'a"b', "a'b", "a\\b", "../x", "-x", "a;b", "x" * 65):
            self.assertFalse(rx.search(bad), bad)


class FallbackTests(unittest.TestCase):
    SPEC = {"type": "ini", "section": "Settings", "key": "gtk-icon-theme-name", "from": "appearance.icons.theme",
            "fallback": {"from": "appearance.mode", "map": {"dark": "Papirus-Dark", "light": "Papirus"}}}

    def f(self, eff):
        return patch.fields(eff, self.SPEC)

    def test_null_or_missing_follows_mode(self):
        self.assertEqual(self.f({"appearance.mode": "dark"}), {"v": "Papirus-Dark"})
        self.assertEqual(self.f({"appearance.mode": "light", "appearance.icons.theme": None}), {"v": "Papirus"})

    def test_explicit_theme_wins_in_any_mode(self):
        for mode in ("dark", "light"):
            self.assertEqual(self.f({"appearance.mode": mode, "appearance.icons.theme": "Tela"}), {"v": "Tela"})

    def test_unknown_mode_is_an_error(self):
        with self.assertRaises(patch.PatchError):
            self.f({"appearance.mode": "sepia"})


class HyprEmitTests(unittest.TestCase):
    def test_defaults_emit_no_cursor_block(self):
        self.assertNotIn("XCURSOR", test_hypr.gen())

    def test_custom_theme_and_size(self):
        t = test_hypr.gen({"appearance.cursor.theme": "Bibata-Modern-Ice", "appearance.cursor.size": 32})
        for k, v in (("XCURSOR_THEME", "Bibata-Modern-Ice"), ("HYPRCURSOR_THEME", "Bibata-Modern-Ice"),
                     ("XCURSOR_SIZE", "32"), ("HYPRCURSOR_SIZE", "32")):
            self.assertIn('hl.env("%s", "%s")' % (k, v), t)

    def test_size_only_change_keeps_default_theme(self):
        t = test_hypr.gen({"appearance.cursor.size": 40})
        self.assertIn('hl.env("XCURSOR_THEME", "Qogir")', t)
        self.assertIn('hl.env("XCURSOR_SIZE", "40")', t)

    def test_invalid_values_rejected(self):
        for over in ({"appearance.cursor.theme": 'x"y'}, {"appearance.cursor.theme": ""},
                     {"appearance.cursor.theme": 5}, {"appearance.cursor.size": 15},
                     {"appearance.cursor.size": 65}, {"appearance.cursor.size": "24"}):
            with self.subTest(over=over):
                with self.assertRaises(hypr.HyprError):
                    test_hypr.gen(over)


class ThemeCase(FontCase):
    """FontCase + цель cursor, поддельные темы и hyprctl, запущенный «в Hyprland»."""

    def _make_root(self):
        super()._make_root()
        with open(os.path.join(SETTINGS_DIR, "targets.json"), encoding="utf-8") as f:
            real = {t["id"]: t for t in json.load(f)["targets"]}
        tj = os.path.join(self.root, "settings", "targets.json")
        with open(tj, encoding="utf-8") as f:
            man = json.load(f)
        man["targets"].append(real["cursor"])
        with open(tj, "w", encoding="utf-8") as f:
            json.dump(man, f)

    def setUp(self):
        super().setUp()
        self.themes_dir = os.path.join(self.tmp, "themes")
        os.makedirs(self.themes_dir)
        for n in ("Papirus", "Papirus-Dark", "Tela"):
            mk_icon_theme(self.themes_dir, n)
        for n in ("Qogir", "Bibata"):
            mk_cursor_theme(self.themes_dir, n)
        p = mock.patch.dict(os.environ, {"ZEPHYRINE_ICON_DIRS": self.themes_dir,
                                         "HYPRLAND_INSTANCE_SIGNATURE": "test"})
        p.start()
        self.addCleanup(p.stop)

    def apply_all(self, *extra):
        return self.run_cli("apply", "--targets", ",".join(IDS), *extra)

    def setcursor_calls(self):
        return [c for c in self.calls() if c.startswith("hyprctl setcursor")]


class DefaultsAreNoOpsTests(ThemeCase):
    def test_default_apply_changes_nothing(self):
        before = self.snapshot()
        code, r = self.apply_all()
        self.assertEqual((code, r["ok"], r["errors"], r["changed"]), (0, True, [], []))
        self.assertEqual(self.gs_sets(), [])
        self.assertEqual(self.setcursor_calls(), [])
        self.assertEqual(self.snapshot(), before)


class SetIconsTests(ThemeCase):
    def test_icon_theme_patches_gtk_qt_and_gsettings(self):
        code, r = self.run_cli("set", "appearance.icons.theme=Tela", "--no-apply")
        self.assertEqual((code, r["errors"]), (0, []))
        code, r = self.apply_all()
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertEqual(sorted(r["changed"]), ["gsettings", "gtk3-settings", "gtk4-settings", "qt6ct-conf"])
        for rel in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini"):
            for path in (self.repo(".config/" + rel), self.cfg(rel)):
                self.assertIn("gtk-icon-theme-name=Tela\n", self.read(path).decode())
        for path in (self.repo(".config/qt6ct/qt6ct.conf"), self.cfg("qt6ct/qt6ct.conf")):
            self.assertIn("icon_theme=Tela\n", self.read(path).decode())
        self.assertEqual(self.gs_sets(), ["gsettings set org.gnome.desktop.interface icon-theme Tela"])
        self.assertEqual(self.setcursor_calls(), [])

    def test_explicit_icons_survive_mode_switch_and_reset_follows_mode(self):
        self.run_cli("set", "appearance.icons.theme=Tela", "appearance.mode=light", "--no-apply")
        code, r = self.apply_all()
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertIn("gtk-icon-theme-name=Tela\n", self.read(self.cfg("gtk-3.0/settings.ini")).decode())
        self.assertIn("gtk-theme-name=adw-gtk3\n", self.read(self.cfg("gtk-3.0/settings.ini")).decode())
        self.run_cli("reset", "appearance.icons.theme", "--no-apply")
        code, r = self.apply_all()
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertIn("gtk-icon-theme-name=Papirus\n", self.read(self.cfg("gtk-3.0/settings.ini")).decode())
        self.assertIn("icon-theme Papirus", self.gs_sets()[-1])

    def test_uninstalled_theme_is_rejected_and_nothing_written(self):
        before = self.snapshot()
        code, r = self.run_cli("set", "appearance.icons.theme=Ghost")
        self.assertEqual(code, 2)
        self.assertEqual(r["errors"][0]["key"], "appearance.icons.theme")
        self.assertIn("not installed", r["errors"][0]["error"])
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(os.path.exists(self.settings_file) and "Ghost" in self.read(self.settings_file).decode())

    def test_cursor_theme_must_have_cursors(self):
        code, r = self.run_cli("set", "appearance.cursor.theme=Tela")  # иконки, не курсор
        self.assertEqual(code, 2)
        self.assertIn("cursor theme not installed", r["errors"][0]["error"])

    def test_invalid_name_is_rejected_by_schema(self):
        for bad in ('a"b', "../x", ""):
            code, r = self.run_cli("set", "appearance.icons.theme=" + bad)
            self.assertEqual(code, 2, bad)

    def test_dry_run_and_reset_to_default_never_need_the_theme(self):
        self.run_cli("set", "appearance.cursor.theme=Bibata", "--no-apply")
        import shutil
        shutil.rmtree(os.path.join(self.themes_dir, "Bibata"))  # только внутри tmp
        code, r = self.run_cli("reset", "appearance.cursor.theme", "--no-apply")
        self.assertEqual((code, r["errors"]), (0, []))


class SetCursorTests(ThemeCase):
    def test_cursor_patches_gtk_gsettings_and_calls_hyprctl(self):
        self.run_cli("set", "appearance.cursor.theme=Bibata", "appearance.cursor.size=32", "--no-apply")
        code, r = self.apply_all()
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertEqual(sorted(r["changed"]), ["cursor", "gsettings", "gtk3-settings", "gtk4-settings"])
        for rel in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini"):
            for path in (self.repo(".config/" + rel), self.cfg(rel)):
                txt = self.read(path).decode()
                self.assertIn("gtk-cursor-theme-name=Bibata\n", txt)
                self.assertIn("gtk-cursor-theme-size=32\n", txt)
                self.assertIn("gtk-icon-theme-name=Papirus-Dark\n", txt)
        self.assertEqual(sorted(self.gs_sets()), [
            "gsettings set org.gnome.desktop.interface cursor-size 32",
            "gsettings set org.gnome.desktop.interface cursor-theme Bibata"])
        self.assertEqual(self.setcursor_calls(), ["hyprctl setcursor Bibata 32"])
        self.assertIn("cursor:setcursor", r["actions"])

    def test_second_apply_is_idempotent(self):
        self.run_cli("set", "appearance.cursor.size=40", "--no-apply")
        self.apply_all()
        n_gs, n_cur = len(self.gs_sets()), len(self.setcursor_calls())
        code, r = self.apply_all()
        self.assertEqual((code, r["changed"]), (0, []))
        self.assertEqual((len(self.gs_sets()), len(self.setcursor_calls())), (n_gs, n_cur))

    def test_back_to_defaults_calls_setcursor_again(self):
        self.run_cli("set", "appearance.cursor.size=40", "--no-apply")
        self.apply_all()
        self.run_cli("reset", "appearance.cursor.size", "--no-apply")
        code, r = self.apply_all()
        self.assertIn("cursor", r["changed"])
        self.assertEqual(self.setcursor_calls(), ["hyprctl setcursor Qogir 40", "hyprctl setcursor Qogir 24"])

    def test_outside_hyprland_is_skipped_not_an_error(self):
        self.run_cli("set", "appearance.cursor.size=40", "--no-apply")
        with mock.patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": ""}):
            code, r = self.apply_all()
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertNotIn("cursor", r["changed"])
        self.assertIn({"target": "cursor", "reason": "hyprland-not-running"}, r["skipped"])
        self.assertEqual(self.setcursor_calls(), [])
        code, r = self.apply_all()  # вернулись в Hyprland - применяется
        self.assertIn("cursor", r["changed"])

    def test_no_exec_does_not_mark_done(self):
        self.run_cli("set", "appearance.cursor.size=40", "--no-apply")
        code, r = self.apply_all("--no-exec")
        self.assertIn("cursor:setcursor", r["actionsSkipped"])
        self.assertEqual(self.setcursor_calls(), [])
        code, r = self.apply_all()
        self.assertIn("cursor", r["changed"])
        self.assertEqual(self.setcursor_calls(), ["hyprctl setcursor Qogir 40"])

    def test_hyprctl_error_text_is_reported(self):
        self._script("hyprctl", '#!/bin/sh\necho "$@" >> "$ZS_LOG"\necho "no such cursor theme"\n')
        self.run_cli("set", "appearance.cursor.size=40", "--no-apply")
        code, r = self.apply_all()
        self.assertTrue(any(e.get("target") == "cursor" and "no such cursor theme" in e["error"] for e in r["errors"]))
        self.assertNotIn("cursor", r["changed"])

    def test_status_reports_outdated_then_live(self):
        self.run_cli("set", "appearance.cursor.size=40", "--no-apply")
        code, r = self.run_cli("status")
        by = {t["id"]: t for t in r["targets"]}
        self.assertEqual(by["cursor"]["state"], "outdated")
        self.apply_all()
        code, r = self.run_cli("status")
        by = {t["id"]: t for t in r["targets"]}
        self.assertEqual(by["cursor"]["state"], "live")


class CliThemesTests(ThemeCase):
    def test_themes_listing_with_samples(self):
        d = os.path.join(self.themes_dir, "Tela", "48x48", "places")
        open(os.path.join(d, "folder.svg"), "w").close()
        code, r = self.run_cli("themes", "--kind", "icons")
        self.assertEqual((code, r["ok"], r["kind"]), (0, True, "icons"))
        by = {t["name"]: t for t in r["themes"]}
        self.assertEqual(sorted(by), ["Papirus", "Papirus-Dark", "Tela"])
        self.assertEqual(by["Tela"]["samples"], [os.path.join(self.themes_dir, "Tela", "48x48/places/folder.svg")])
        self.assertEqual(by["Papirus"]["samples"], [])

    def test_cursor_listing_makes_png_thumbs_in_state_cache(self):
        code, r = self.run_cli("themes", "--kind", "cursors")
        self.assertEqual((code, r["count"]), (0, 2))
        s = {t["name"]: t for t in r["themes"]}["Qogir"]["samples"]
        self.assertEqual(len(s), 1)  # у фикстуры только left_ptr
        self.assertTrue(s[0].startswith(os.path.join(self.state, "cache", "cursor-thumbs")))
        self.assertEqual(self.read(s[0])[:8], b"\x89PNG\r\n\x1a\n")
        code, r2 = self.run_cli("themes", "--kind", "cursors")  # из кэша
        self.assertEqual({t["name"]: t for t in r2["themes"]}["Qogir"]["samples"], s)

    def test_no_thumbs_and_bad_kind(self):
        code, r = self.run_cli("themes", "--kind", "cursors", "--no-thumbs")
        self.assertEqual(r["themes"][0]["samples"], [])
        code, r = self.run_cli("themes", "--kind", "fonts")
        self.assertEqual(code, 2)

    def test_open_section_known(self):
        code, r = self.run_cli("open", "appearance/icons", "--no-exec")
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
