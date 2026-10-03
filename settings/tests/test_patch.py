"""Тесты A1 (шрифты): patch-механизм (zsettings/patch.py), gsettings, fonts.py, шаблоны zathura/Obsidian.

Всё в изолированном каталоге (test_targets.Fixture: HOME/корень репо/PATH внутри `tempfile`); реальные
~/.config, gsettings, fc-list не затрагиваются: в PATH только поддельные скрипты. Настоящие файлы репо
(settings.ini, qt6ct.conf, kitty.conf) копируются в tmp как образцы содержимого.
"""
import json
import os
import shutil
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SETTINGS_DIR)
sys.path.insert(0, HERE)

try:
    from .test_targets import FAKE, Fixture
except ImportError:  # unittest discover -s tests: модули верхнего уровня
    from test_targets import FAKE, Fixture

from zsettings import fonts, patch, testkit  # noqa: E402
from zsettings.render import TemplateRenderer  # noqa: E402

REAL_ROOT = os.path.dirname(SETTINGS_DIR)
PATCH_IDS = ["gtk3-settings", "gtk4-settings", "qt6ct-conf", "kitty-conf", "gsettings"]
FAKE_GSETTINGS = (
    '#!/bin/sh\necho "gsettings $@" >> "$ZS_LOG"\nf="$ZS_GS/$3"\n'
    'case "$1" in\n'
    '  get) if [ -f "$f" ]; then IFS= read -r v < "$f"; echo "\'$v\'"; else exit 1; fi ;;\n'
    '  set) printf "%s\\n" "$4" > "$f" ;;\nesac\n')
FAKE_FC = ('#!/bin/sh\nf="$ZS_FC.all"\nif [ "$1" = ":spacing=mono" ]; then f="$ZS_FC.mono"; fi\n'
           'while IFS= read -r l; do echo "$l"; done < "$f"\n')
ALL_FONTS = "Inter\nJetBrainsMono Nerd Font,JetBrainsMono NF\nHack Nerd Font\nHack\nCantarell\nDejaVu Sans\n"
MONO_FONTS = "JetBrainsMono Nerd Font,JetBrainsMono NF\nHack Nerd Font\nHack\n"

INI = "[Settings]\ngtk-theme-name=adw\ngtk-font-name=Inter,  10\ngtk-icon-theme-name=Papirus\n"
QT = ('[Appearance]\ncolor_scheme_path=/home/testuser/x.conf\n\n[Fonts]\nfixed="Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"\n'
      'general="Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"\n\n[Interface]\na=1\n')
EFF = {"appearance.fonts.ui.family": "Cantarell", "appearance.fonts.ui.size": 12,
       "appearance.fonts.mono.family": "Hack Nerd Font", "appearance.fonts.mono.size": 14,
       "appearance.kittyOpacity": 0.8}
GTK_PATCH = {"type": "ini", "section": "Settings", "key": "gtk-font-name", "from": "appearance.fonts.ui",
             "value": "{family},  {size}"}


def qt_patch(key, frm, **extra):
    return dict({"type": "ini", "section": "Fonts", "key": key, "from": frm,
                 "value": "\"{family},{size}{tail}\"", "tail": "^\"[^,\"]*,[^,\"]*(?P<tail>,[^\"]*)\"\\s*$",
                 "tailDefault": ",-1,5,400,0,0,0,0,0,0,0,0,0,0,1", "forbid": ","}, **extra)


class PatchTextTests(unittest.TestCase):
    def run_patch(self, text, specs, eff=None, home="/h"):
        return patch.patch_text(text, specs, EFF if eff is None else eff, home)

    def test_ini_replaces_only_the_key(self):
        out, notes = self.run_patch(INI, [GTK_PATCH])
        self.assertEqual(out, INI.replace("Inter,  10", "Cantarell,  12"))
        self.assertEqual(notes, [])

    def test_ini_idempotent(self):
        once, _ = self.run_patch(INI, [GTK_PATCH])
        twice, _ = self.run_patch(once, [GTK_PATCH])
        self.assertEqual(once, twice)

    def test_ini_keeps_spacing_around_equals_and_other_sections(self):
        text = "[Other]\ngtk-font-name=keep\n[Settings]\n  gtk-font-name =   Old 9  \n"
        out, _ = self.run_patch(text, [GTK_PATCH])
        self.assertEqual(out, "[Other]\ngtk-font-name=keep\n[Settings]\n  gtk-font-name =   Cantarell,  12\n")

    def test_ini_inserts_missing_key_at_end_of_section(self):
        text = "[Settings]\na=1\nb=2\n\n[Next]\nc=3\n"
        out, notes = self.run_patch(text, [GTK_PATCH])
        self.assertEqual(out, "[Settings]\na=1\nb=2\ngtk-font-name=Cantarell,  12\n\n[Next]\nc=3\n")
        self.assertEqual(len(notes), 1)

    def test_ini_adds_missing_section_without_trailing_newline(self):
        out, _ = self.run_patch("[Other]\na=1", [GTK_PATCH])
        self.assertEqual(out, "[Other]\na=1\n\n[Settings]\ngtk-font-name=Cantarell,  12\n")

    def test_crlf_preserved(self):
        out, _ = self.run_patch(INI.replace("\n", "\r\n"), [GTK_PATCH])
        self.assertEqual(out, INI.replace("Inter,  10", "Cantarell,  12").replace("\n", "\r\n"))

    def test_qt_font_tail_preserved_and_size_from_other_key(self):
        specs = [qt_patch("general", "appearance.fonts.ui"),
                 qt_patch("fixed", "appearance.fonts.mono", sizeFrom="appearance.fonts.mono.size")]
        out, _ = self.run_patch(QT, specs)
        self.assertIn('fixed="Hack Nerd Font,14,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"\n', out)
        self.assertIn('general="Cantarell,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"\n', out)
        self.assertIn("color_scheme_path=/home/testuser/x.conf\n", out)  # чужие ключи не тронуты

    def test_qt_custom_tail_kept_and_default_tail_for_new_key(self):
        text = '[Fonts]\ngeneral="Old,9,-1,5,700,1,0,0,0,0,0,0,0,0,0,1"\n'
        out, _ = self.run_patch(text, [qt_patch("general", "appearance.fonts.ui"),
                                       qt_patch("fixed", "appearance.fonts.mono")])
        self.assertIn('general="Cantarell,12,-1,5,700,1,0,0,0,0,0,0,0,0,0,1"', out)
        self.assertIn('fixed="Hack Nerd Font,14,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"', out)

    def test_line_patch_group_val_and_commented_line_untouched(self):
        text = "#font_family  Commented\nfont_family        Old Font\nfont_size          9.0\nbold_font auto\n"
        specs = [{"type": "line", "pattern": "^font_family\\s+(?P<val>.*)$", "from": "appearance.fonts.mono.family"},
                 {"type": "line", "pattern": "^font_size\\s+(?P<val>.*)$", "from": "appearance.fonts.mono.size",
                  "value": "{v:.1f}"}]
        out, _ = self.run_patch(text, specs)
        self.assertEqual(out, "#font_family  Commented\nfont_family        Hack Nerd Font\nfont_size          14.0\n"
                              "bold_font auto\n")

    def test_line_patch_float_format_and_insert_or_note(self):
        spec = {"type": "line", "pattern": "^background_opacity\\s+(?P<val>.*)$", "from": "appearance.kittyOpacity",
                "value": "{v:.2f}", "line": "background_opacity {v:.2f}"}
        out, _ = self.run_patch("a 1\n", [spec])
        self.assertEqual(out, "a 1\nbackground_opacity 0.80\n")
        spec2 = dict(spec)
        del spec2["line"]
        out2, notes = self.run_patch("a 1\n", [spec2])
        self.assertEqual((out2, len(notes)), ("a 1\n", 1))

    def test_home_substitution_with_spaces_and_no_from(self):
        spec = {"type": "ini", "section": "Appearance", "key": "color_scheme_path",
                "value": "{HOME}/.config/qt6ct/colors/zephyrine.conf"}
        out, _ = self.run_patch(QT, [spec], home="/home/my user (x)")
        self.assertIn("color_scheme_path=/home/my user (x)/.config/qt6ct/colors/zephyrine.conf\n", out)

    def test_dangerous_values_rejected(self):
        for fam in ("a\nb", "a\rb", "a\x00b"):
            with self.subTest(fam=repr(fam)):
                with self.assertRaises(patch.PatchError):
                    self.run_patch(INI, [GTK_PATCH], eff=dict(EFF, **{"appearance.fonts.ui.family": fam}))
        with self.assertRaises(patch.PatchError):  # запятая ломает строку шрифта Qt
            self.run_patch(QT, [qt_patch("general", "appearance.fonts.ui")],
                           eff=dict(EFF, **{"appearance.fonts.ui.family": "A,B"}))
        with self.assertRaises(patch.PatchError):
            self.run_patch(INI, [dict(GTK_PATCH, value="{nope}")])
        with self.assertRaises(patch.PatchError):
            self.run_patch(INI, [dict(GTK_PATCH, **{"from": "appearance.fonts.zzz"})])
        with self.assertRaises(patch.PatchError):
            self.run_patch(INI, [dict(GTK_PATCH, type="weird")])


class FontCase(Fixture):
    """Корень с реальными целями шрифтов и копиями файлов репо; поддельные gsettings/fc-list."""

    def _make_root(self):
        super()._make_root()
        with open(os.path.join(SETTINGS_DIR, "targets.json"), encoding="utf-8") as f:
            real = {t["id"]: t for t in json.load(f)["targets"]}
        tj = os.path.join(self.root, "settings", "targets.json")
        with open(tj, encoding="utf-8") as f:
            man = json.load(f)
        for tid in PATCH_IDS:
            man["targets"].append(real[tid])
        with open(tj, "w", encoding="utf-8") as f:
            json.dump(man, f)
        for rel in (".config/gtk-3.0/settings.ini", ".config/gtk-4.0/settings.ini", ".config/qt6ct/qt6ct.conf",
                    ".config/kitty/kitty.conf"):
            dst = os.path.join(self.root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            src = os.path.join(REAL_ROOT, rel)
            if not os.path.isfile(src) and rel.startswith(".config/"):
                alt = os.path.join(REAL_ROOT, "themes", rel[8:])
                if os.path.isfile(alt):
                    src = alt
            shutil.copy(src, dst)

    def _make_bin(self):
        super()._make_bin()
        self._script("gsettings", FAKE_GSETTINGS)
        self._script("fc-list", FAKE_FC)

    def setUp(self):
        super().setUp()
        self.gs = os.path.join(self.tmp, "gs")
        os.makedirs(self.gs)
        self.fc = os.path.join(self.tmp, "fc")
        self.write_file(self.fc + ".all", ALL_FONTS.encode())
        self.write_file(self.fc + ".mono", MONO_FONTS.encode())
        p = mock.patch.dict(os.environ, {"ZS_GS": self.gs, "ZS_FC": self.fc})
        p.start()
        self.addCleanup(p.stop)
        # живые копии, как после deploy.sh: settings.ini - копии (права 600), qt6ct.conf - с путём под HOME,
        # kitty - каталог-симлинк на репо
        for rel in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini"):
            shutil.copy(self.repo(".config/" + rel), self.cfg(rel))
            os.chmod(self.cfg(rel), 0o600)
        live_qt = self.read(self.repo(".config/qt6ct/qt6ct.conf")).decode().replace(
            "/home/testuser", str(self.home.home)).replace("~", str(self.home.home))
        self.write_file(self.cfg("qt6ct/qt6ct.conf"), live_qt.encode())
        shutil.rmtree(self.cfg("kitty"))
        os.symlink(self.repo(".config/kitty"), self.cfg("kitty"))
        self.write_file(os.path.join(self.gs, "font-name"), b"Inter  10\n")
        self.write_file(os.path.join(self.gs, "monospace-font-name"), b"JetBrainsMono Nerd Font  11\n")
        # режим темы (appearance.mode, дефолт dark): текущее состояние dconf совпадает с тем, что выставил бы apply
        self.write_file(os.path.join(self.gs, "color-scheme"), b"prefer-dark\n")
        self.write_file(os.path.join(self.gs, "gtk-theme"), b"adw-gtk3-dark\n")
        self.write_file(os.path.join(self.gs, "icon-theme"), b"Papirus-Dark\n")
        self.write_file(os.path.join(self.gs, "cursor-theme"), b"Qogir\n")
        self.write_file(os.path.join(self.gs, "cursor-size"), b"24\n")

    def font_files(self):
        return {p: b for p, b in self.snapshot().items() if p.endswith((".ini", ".conf"))
                and ("settings.ini" in p or "qt6ct.conf" in p or "kitty.conf" in p)}

    def apply_fonts(self, *extra):
        return self.run_cli("apply", "--targets", ",".join(PATCH_IDS), *extra)

    def gs_sets(self):
        return [c for c in self.calls() if c.startswith("gsettings set")]


class DefaultsAreNoOps(FontCase):
    def test_defaults_change_nothing_anywhere(self):
        before = self.snapshot()
        code, r = self.apply_fonts()
        self.assertEqual((code, r["ok"], r["errors"], r["changed"]), (0, True, [], []))
        self.assertEqual(sorted(r["unchanged"]), sorted(PATCH_IDS))
        self.assertIsNone(r["backup"])
        self.assertEqual(self.gs_sets(), [])
        self.assertEqual(self.snapshot(), before)

    def test_dry_run_with_changes_writes_nothing(self):
        self.run_cli("set", "appearance.fonts.ui.size=12", "--no-apply")
        before = self.snapshot()
        code, r = self.apply_fonts("--dry-run")
        self.assertEqual((code, r["dryRun"]), (0, True))
        self.assertEqual(sorted(r["changed"]), ["gsettings", "gtk3-settings", "gtk4-settings", "qt6ct-conf"])
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.gs_sets(), [])


class SetFontsTests(FontCase):
    def test_ui_font_patches_files_and_gsettings(self):
        code, r = self.run_cli("set", "appearance.fonts.ui.family=Cantarell", "appearance.fonts.ui.size=12")
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertEqual(sorted(r["changed"]), ["gsettings", "gtk3-settings", "gtk4-settings", "qt6ct-conf"])
        for rel in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini"):
            for path in (self.repo(".config/" + rel), self.cfg(rel)):
                txt = self.read(path).decode()
                self.assertIn("gtk-font-name=Cantarell,  12\n", txt)
                self.assertIn("gtk-icon-theme-name=Papirus-Dark\n", txt)  # остальное нетронуто
        self.assertEqual(oct(os.stat(self.cfg("gtk-3.0/settings.ini")).st_mode & 0o777), "0o600")  # права сохранены
        repo_qt = self.read(self.repo(".config/qt6ct/qt6ct.conf")).decode()
        live_qt = self.read(self.cfg("qt6ct/qt6ct.conf")).decode()
        for txt in (repo_qt, live_qt):
            self.assertIn('general="Cantarell,12,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"\n', txt)
            self.assertIn('fixed="JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"\n', txt)
        # путь палитры: в репо прежний (~ или /home/testuser), в живой копии - HOME (как делает deploy.sh)
        self.assertTrue("color_scheme_path=/home/testuser/.config/qt6ct/colors/zephyrine.conf\n" in repo_qt or
                        "color_scheme_path=~/.config/qt6ct/colors/zephyrine.conf\n" in repo_qt)
        self.assertIn("color_scheme_path=%s/.config/qt6ct/colors/zephyrine.conf\n" % self.home.home, live_qt)
        self.assertEqual(self.gs_sets(), [
            "gsettings set org.gnome.desktop.interface font-name Cantarell  12"])
        self.assertIn("gtk", r["restart"])

    def test_kitty_conf_patch_symlinked_and_reload(self):
        code, r = self.run_cli("set", "appearance.fonts.mono.family=Hack Nerd Font", "appearance.fonts.mono.size=13",
                               "appearance.kittyOpacity=0.85")
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertIn("kitty-conf", r["changed"])
        self.assertTrue(os.path.islink(self.cfg("kitty")))
        txt = self.read(self.repo(".config/kitty/kitty.conf")).decode()
        self.assertIn("font_family        Hack Nerd Font\n", txt)
        self.assertIn("font_size          13.0\n", txt)
        self.assertIn("background_opacity 0.85\n", txt)
        self.assertIn("bold_font          auto\n", txt)
        self.assertIn("pkill -USR1 -x kitty", self.calls())
        self.assertIn("kitty-conf:usr1", r["actions"])
        # шрифт терминала и qt fixed теперь используют mono.size
        self.assertIn('fixed="Hack Nerd Font,13,', self.read(self.cfg("qt6ct/qt6ct.conf")).decode())

    def test_second_apply_is_idempotent_and_undo_restores_bytes(self):
        self.run_cli("apply", "--no-exec")  # базовое состояние: шаблонные выходы тоже существуют
        before = self.snapshot()
        self.run_cli("set", "appearance.fonts.ui.family=Cantarell", "appearance.fonts.mono.size=15")
        changed = self.snapshot()
        self.assertNotEqual(changed, before)
        n = len(self.gs_sets())
        code, r = self.apply_fonts()
        self.assertEqual((r["changed"], r["backup"]), ([], None))
        self.assertEqual(self.snapshot(), changed)
        self.assertEqual(len(self.gs_sets()), n)  # gsettings уже в нужном состоянии - не пишется повторно
        code, r = self.run_cli("undo")
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertEqual(self.snapshot(), before)  # все файлы байт-в-байт, включая права/симлинки по содержимому
        self.assertEqual(self.read(self.gs, "font-name"), b"Inter  10\n")

    def test_foreign_lines_in_live_copy_survive(self):
        live = self.cfg("gtk-3.0/settings.ini")
        txt = self.read(live).decode().replace("[Settings]\n", "[Settings]\ngtk-custom=mine\n")
        self.write_file(live, txt.encode())
        self.run_cli("set", "appearance.fonts.ui.size=13", "--no-exec")
        out = self.read(live).decode()
        self.assertIn("gtk-custom=mine\n", out)
        self.assertIn("gtk-font-name=Inter,  13\n", out)

    def test_symlinked_repo_file_stays_symlink_and_live_symlink_deduped(self):
        real = self.repo("elsewhere/gtk4.ini")
        os.makedirs(os.path.dirname(real))
        shutil.move(self.repo(".config/gtk-4.0/settings.ini"), real)
        os.symlink(real, self.repo(".config/gtk-4.0/settings.ini"))
        os.remove(self.cfg("gtk-4.0/settings.ini"))
        os.symlink(self.repo(".config/gtk-4.0/settings.ini"), self.cfg("gtk-4.0/settings.ini"))  # живой -> репо
        self.run_cli("set", "appearance.fonts.ui.size=11", "--no-exec")
        for p in (self.repo(".config/gtk-4.0/settings.ini"), self.cfg("gtk-4.0/settings.ini")):
            self.assertTrue(os.path.islink(p), p)
        self.assertIn(b"gtk-font-name=Inter,  11\n", self.read(real))
        st = self.run_cli("status")[1]["targets"]
        t = next(x for x in st if x["id"] == "gtk4-settings")
        self.assertEqual(len(t["paths"]), 1)  # репо и живая копия - один файл

    def test_missing_live_copy_is_created_with_qt_path_substituted(self):
        os.remove(self.cfg("qt6ct/qt6ct.conf"))
        os.remove(self.cfg("gtk-3.0/settings.ini"))
        code, r = self.run_cli("set", "appearance.fonts.ui.size=11", "--no-exec")
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertIn("color_scheme_path=%s/.config/qt6ct/colors/zephyrine.conf\n" % self.home.home,
                      self.read(self.cfg("qt6ct/qt6ct.conf")).decode())
        self.assertIn(b"gtk-font-name=Inter,  11\n", self.read(self.cfg("gtk-3.0/settings.ini")))

    def test_missing_repo_file_is_skipped_not_created(self):
        os.remove(self.repo(".config/kitty/kitty.conf"))
        code, r = self.apply_fonts("--no-exec")
        self.assertIn({"target": "kitty-conf", "reason": "file-missing",
                       "message": self.repo(".config/kitty/kitty.conf")}, r["skipped"])
        self.assertFalse(os.path.exists(self.repo(".config/kitty/kitty.conf")))

    def test_unmanaged_patch_target_untouched(self):
        self.run_cli("set", "appearance.targets.gtk3-settings=false", "--no-apply")
        self.run_cli("set", "appearance.fonts.ui.size=11", "--no-exec")
        self.assertIn(b"Inter,  10", self.read(self.repo(".config/gtk-3.0/settings.ini")))
        self.assertIn(b"Inter,  11", self.read(self.repo(".config/gtk-4.0/settings.ini")))

    def test_no_exec_skips_gsettings_and_does_not_mark_it_done(self):
        code, r = self.run_cli("set", "appearance.fonts.ui.size=11", "--no-exec")
        self.assertIn("gsettings:set", r["actionsSkipped"])
        self.assertEqual(self.gs_sets(), [])
        code, r = self.apply_fonts()  # реальный запуск после --no-exec: gsettings всё ещё надо выставить
        self.assertIn("gsettings", r["changed"])
        self.assertEqual(len(self.gs_sets()), 1)  # font-name изменился, monospace-font-name нет (mono.size дефолт 11)

    def test_gsettings_failure_is_reported(self):
        self._script("gsettings", '#!/bin/sh\nif [ "$1" = set ]; then echo boom >&2; exit 1; fi\nexit 1\n')
        code, r = self.run_cli("set", "appearance.fonts.ui.size=11")
        self.assertEqual(code, 1)
        self.assertTrue(any(e.get("target") == "gsettings" and "boom" in e["error"] for e in r["errors"]))
        self.assertNotIn("gsettings", r["changed"])

    def test_status_shows_outdated_patch_and_gsettings(self):
        self.run_cli("set", "appearance.fonts.ui.size=11", "--no-apply")
        by = {t["id"]: t for t in self.run_cli("status")[1]["targets"]}
        for tid in ("gtk3-settings", "gtk4-settings", "qt6ct-conf", "gsettings"):
            self.assertEqual(by[tid]["state"], "outdated", tid)
        self.assertEqual(by["kitty-conf"]["state"], "live")
        self.apply_fonts()
        by = {t["id"]: t for t in self.run_cli("status")[1]["targets"]}
        self.assertEqual(by["gsettings"]["state"], "live")
        self.assertEqual(by["gtk3-settings"]["state"], "restart")  # GTK 3: нужен перезапуск приложений
        self.assertEqual(by["gtk4-settings"]["state"], "live")

    def test_diff_for_patch_target(self):
        self.run_cli("set", "appearance.fonts.ui.size=11", "--no-apply")
        code, r = self.run_cli("diff", "gtk3-settings")
        self.assertEqual(code, 0)
        d = r["files"][0]["diff"]
        self.assertIn("-gtk-font-name=Inter,  11\n+gtk-font-name=Inter,  10\n", d)  # generated -> disk


class ValidationTests(FontCase):
    def test_model_rejects_control_chars_and_quotes(self):
        for bad in ('"a\\nb"', '"a\\"b"', '"a\\\\b"', '"' + "x" * 200 + '"'):
            code, r = self.run_cli("set", "appearance.fonts.ui.family=" + bad, "--no-apply")
            self.assertEqual(code, 2, bad)
            self.assertEqual(r["errors"][0]["error"], "invalid font family name")

    def test_installed_check_and_nerd_filter(self):
        code, r = self.run_cli("set", "appearance.fonts.shell.family=Hack", "--no-apply")
        self.assertEqual(code, 2)
        self.assertIn("not a Nerd Font", r["errors"][0]["error"])
        code, r = self.run_cli("set", "appearance.fonts.ui.family=Nope", "--no-apply")
        self.assertEqual(code, 2)
        self.assertIn("not installed", r["errors"][0]["error"])
        code, r = self.run_cli("set", "appearance.fonts.mono.family=Cantarell", "--no-apply")  # не моноширинный
        self.assertEqual(code, 2)
        self.assertIn("monospace", r["errors"][0]["error"])
        code, r = self.run_cli("set", "appearance.fonts.shell.family=Hack Nerd Font", "appearance.fonts.mono.family=Hack",
                               "--no-apply")
        self.assertEqual((code, r["errors"]), (0, []))

    def test_alias_name_is_accepted(self):
        code, r = self.run_cli("set", "appearance.fonts.mono.family=JetBrainsMono NF", "--no-apply")
        self.assertEqual((code, r["errors"]), (0, []))

    def test_default_values_always_allowed_without_fc_list(self):
        os.remove(os.path.join(self.bin, "fc-list"))
        self.write_file(self.settings_file, b'{"version": 1}\n')
        code, r = self.run_cli("set", "appearance.fonts.ui.family=Whatever", "--no-apply")  # fc-list нет - не проверяем
        self.assertEqual((code, r["errors"]), (0, []))
        code, r = self.run_cli("set", "appearance.fonts.shell.family=Plain Font", "--no-apply")
        self.assertEqual(code, 2)  # Nerd Font проверяется и без fc-list
        code, r = self.run_cli("reset", "appearance.fonts.ui.family", "--no-apply")
        self.assertEqual(code, 0)

    def test_reset_always_allowed_even_if_font_vanished(self):
        self.run_cli("set", "appearance.fonts.ui.family=Cantarell", "--no-apply")
        self.write_file(self.fc + ".all", b"Inter\n")  # шрифт «удалили»
        code, r = self.run_cli("reset", "appearance.fonts.ui.family", "--no-apply")
        self.assertEqual((code, r["errors"]), (0, []))
        code, r = self.run_cli("set", "appearance.fonts.ui.size=11", "--no-apply")  # чужой ключ не упирается в шрифт
        self.assertEqual((code, r["errors"]), (0, []))


class FontsCommandTests(FontCase):
    def test_kinds(self):
        code, r = self.run_cli("fonts")
        self.assertEqual((code, r["count"]), (0, 6))
        self.assertEqual(r["families"], ["Cantarell", "DejaVu Sans", "Hack", "Hack Nerd Font", "Inter",
                                         "JetBrainsMono Nerd Font"])  # каноническое имя - первое; алиас NF скрыт
        code, r = self.run_cli("fonts", "--kind", "nerd")
        self.assertEqual(r["families"], ["Hack Nerd Font", "JetBrainsMono Nerd Font"])
        code, r = self.run_cli("fonts", "--kind", "mono")
        self.assertEqual(r["families"], ["Hack", "Hack Nerd Font", "JetBrainsMono Nerd Font"])

    def test_no_fc_list_is_an_error_envelope(self):
        os.remove(os.path.join(self.bin, "fc-list"))
        code, r = self.run_cli("fonts")
        self.assertEqual((code, r["ok"]), (1, False))
        self.assertIn("fc-list", r["errors"][0]["error"])

    def test_bad_kind_is_usage_error(self):
        code, r = self.run_cli("fonts", "--kind", "bold")
        self.assertEqual(code, 2)

    def test_fonts_module_no_fc_list(self):
        os.remove(os.path.join(self.bin, "fc-list"))
        with self.assertRaises(fonts.FontsError):
            fonts.scan("any")


class TemplateFontTests(unittest.TestCase):
    """Реальные шаблоны zathura/Obsidian: по умолчанию = golden, при смене шрифта - подставляют его."""

    @classmethod
    def setUpClass(cls):
        cls.kit = testkit.Kit(root=REAL_ROOT, settings_dir=SETTINGS_DIR)

    def render(self, tid, **over):
        t = next(x for x in self.kit.targets if x["id"] == tid)
        text = self.kit.template_path(t).read_text(encoding="utf-8")
        ctx = testkit.build_context(self.kit, over or None)
        return TemplateRenderer(ctx).render(text)

    def golden(self, tid):
        t = next(x for x in self.kit.targets if x["id"] == tid)
        return self.kit.golden_path(t).read_bytes().decode("utf-8")

    def test_defaults_equal_golden(self):
        for tid in ("zathura", "obsidian"):
            self.assertEqual(self.render(tid), self.golden(tid), tid)

    def test_zathura_font_line(self):
        out = self.render("zathura", **{"appearance.fonts.mono.family": "Hack Nerd Font",
                                        "appearance.fonts.mono.size": 14})
        self.assertIn('\nset font "Hack Nerd Font 14"\n', out)
        self.assertEqual(out.replace("Hack Nerd Font 14", "JetBrainsMono Nerd Font 11"), self.golden("zathura"))

    def test_obsidian_font_variables(self):
        out = self.render("obsidian", **{"appearance.fonts.mono.family": "Hack Nerd Font",
                                         "appearance.fonts.shell.size": 15})
        self.assertIn("--font-interface-theme: ", out)
        self.assertIn('"Hack Nerd Font Mono", monospace', out)
        self.assertIn("--font-ui-medium: 15px;", out)
        self.assertNotIn("JetBrainsMono", out)

    def test_target_keys_cover_font_placeholders(self):
        by = {t["id"]: t for t in self.kit.targets}
        self.assertTrue({"appearance.fonts.mono.family", "appearance.fonts.mono.size"} <= set(by["zathura"]["keys"]))
        self.assertTrue({"appearance.fonts.mono.family", "appearance.fonts.shell.size"} <= set(by["obsidian"]["keys"]))
        issues, _, _ = testkit.run_lint(self.kit, ["zathura", "obsidian"])
        self.assertEqual([str(i) for i in issues if "font" in i.msg], [])


if __name__ == "__main__":
    unittest.main()
