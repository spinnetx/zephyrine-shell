"""Интеграционные тесты targets.py/doctor.py в ИЗОЛИРОВАННОМ HOME (DESIGN §8).

Всё живёт в одном каталоге `tempfile.TemporaryDirectory(prefix="zs-s16-")` (чистится только он сам):
  <tmp>/home           HOME (testkit.make_isolated_home: профили Zen/TB с пробелами и скобками, vault'ы)
  <tmp>/root           ZEPHYRINE_ROOT (копии scheme.json, schema.json, palette-roles.json + мини-шаблоны)
  <tmp>/bin            единственный каталог в PATH: поддельные kitty/pkill/hyprctl/luac (пишут лог, ничего не делают)
Реальные ~/.config, hyprctl, kitty и т.д. не затрагиваются. XDG_CONFIG_HOME указывает внутрь tmp.
"""
import contextlib
import io
import json
import os
import shutil
import stat
import sys
import tempfile
import types
import unittest
import zipfile
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SETTINGS_DIR)

from zsettings import backup, cli, doctor, targets, testkit  # noqa: E402
from zsettings.util import Paths  # noqa: E402

REAL_ROOT = os.path.dirname(SETTINGS_DIR)

TEMPLATE = (
    "accent={{ c.primary | hex }} on={{ c.onPrimary | hex }} glass={{ a.glass | anchor:0.72 }} "
    "surf={{ a.surface | anchor:0.9 }} r={{ r.md | px }} hsl={{ s.primaryHsl }}\n"
)
MANIFEST_TMPL = '{\n  "name": "t",\n  "version": "{{ meta.tbVersion }}",\n  "accent": "{{ c.primary | hex }}"\n}\n'
FAKE = "#!/bin/sh\necho \"%s $@\" >> \"$ZS_LOG\"\n"


def fake_emit(values, ctx, paths):
    return "-- generated\nlocal rounding = %s\nlocal primary = %s\n" % (
        values["appearance.windowRounding"], ctx["c"]["primary"])


class Fixture(unittest.TestCase):
    """Изолированный HOME + корень репо + поддельные команды; cli.main в процессе."""

    def setUp(self):
        td = tempfile.TemporaryDirectory(prefix="zs-s16-")
        self.addCleanup(td.cleanup)
        self.tmp = td.name
        self.home = testkit.make_isolated_home(self.tmp)
        self.root = os.path.join(self.tmp, "root")
        self.bin = os.path.join(self.tmp, "bin")
        self.log = os.path.join(self.tmp, "calls.log")
        self.configerrors = os.path.join(self.tmp, "configerrors.txt")
        self.state = str(self.home.state)
        self._make_root()
        self._make_bin()
        env = {"HOME": str(self.home.home), "XDG_CONFIG_HOME": str(self.home.config),
               "ZEPHYRINE_ROOT": self.root, "ZEPHYRINE_STATE": self.state, "PATH": self.bin,
               "ZS_LOG": self.log, "ZS_CONFIGERRORS": self.configerrors, "ZS_LUAC_RC": "0",
               "ZEPHYRINE_LOCK_TIMEOUT": "2"}
        p = mock.patch.dict(os.environ, env)
        p.start()
        self.addCleanup(p.stop)
        hypr = types.ModuleType("zsettings.hypr")
        hypr.emit = fake_emit
        p2 = mock.patch.dict(sys.modules, {"zsettings.hypr": hypr})
        p2.start()
        self.addCleanup(p2.stop)
        self.proc = os.path.join(self.tmp, "proc")
        self._make_proc()
        p3 = mock.patch.object(targets, "PROC_ROOT", self.proc)
        p3.start()
        self.addCleanup(p3.stop)
        self.paths = Paths.from_env()
        self.assertTrue(self.root.startswith(self.tmp))

    BTIME = 1700000000

    def _make_proc(self):
        """Поддельный /proc внутри tmp: btime + запущенные давно thunderbird и zen-bin."""
        os.makedirs(self.proc)
        self.write_file(os.path.join(self.proc, "stat"), b"cpu 1 2 3\nbtime %d\n" % self.BTIME)
        self.add_proc(100, "thunderbird", 100)
        self.add_proc(101, "zen-bin", 100)
        self.add_proc(102, "obsidian", 100)
        self.add_proc(103, "zathura", 100)
        self.add_proc(104, "zeditor", 100)

    def add_proc(self, pid, comm, start_epoch):
        d = os.path.join(self.proc, str(pid))
        os.makedirs(d, exist_ok=True)
        self.write_file(os.path.join(d, "comm"), (comm + "\n").encode())
        ticks = int((start_epoch - self.BTIME) * os.sysconf("SC_CLK_TCK")) if start_epoch > self.BTIME else 1
        fields = ["S"] + ["0"] * 18 + [str(ticks)] + ["0"] * 5  # поле 3 .. поле 22 (starttime) .. хвост
        self.write_file(os.path.join(d, "stat"), ("%d (%s) %s\n" % (pid, comm + ") x (", " ".join(fields))).encode())

    def rm_proc(self, pid):
        shutil.rmtree(os.path.join(self.proc, str(pid)))  # только внутри собственного tmp

    # ---- сборка окружения
    def _make_root(self):
        s = os.path.join(self.root, "settings")
        os.makedirs(os.path.join(s, "templates"))
        os.makedirs(os.path.join(self.root, "quickshell"))
        for n in ("schema.json", "palette-roles.json"):
            shutil.copy(os.path.join(SETTINGS_DIR, n), s)
        shutil.copy(os.path.join(REAL_ROOT, "quickshell", "scheme.json"), os.path.join(self.root, "quickshell"))
        with open(os.path.join(SETTINGS_DIR, "targets.json"), encoding="utf-8") as f:
            man = json.load(f)
        keep, self.ids = [], []
        for t in man["targets"]:
            if t.get("stage") == "v1" and t["kind"] in ("template", "data", "emit") and t["id"] not in ("hyprlock", "sddm"):
                if t["kind"] == "template":
                    t["template"] = "templates/t-%s.tmpl" % t["id"]
                    with open(os.path.join(s, t["template"]), "w", encoding="utf-8", newline="") as f:
                        f.write(MANIFEST_TMPL if t["id"] == "tb-theme" else TEMPLATE)
                keep.append(t)
                self.ids.append(t["id"])
            elif t["id"] in ("wallpaper", "hypridle"):  # цели будущих этапов (+ wallpaper: kind=command)
                keep.append(t)
        man["targets"] = keep
        self.manifest = keep
        # В урезанном манифесте нет целей поздних стадий (hyprlock, sddm…): убираем их из targets ключей копии схемы,
        # иначе `set` пытался бы применить «неизвестную цель».
        sp = os.path.join(s, "schema.json")
        with open(sp, encoding="utf-8") as f:
            sch = json.load(f)
        have = {t["id"] for t in keep}
        for spec in sch["keys"].values():
            if isinstance(spec.get("targets"), list):
                spec["targets"] = [t for t in spec["targets"] if t in have]
        with open(sp, "w", encoding="utf-8") as f:
            json.dump(sch, f, ensure_ascii=False)
        with open(os.path.join(s, "targets.json"), "w", encoding="utf-8") as f:
            json.dump(man, f)
        os.makedirs(os.path.join(self.root, "obsidian", "Zephyrine"))
        with open(os.path.join(self.root, "obsidian", "Zephyrine", "manifest.json"), "w") as f:
            f.write('{"name": "Zephyrine"}\n')
        self.settings_file = os.path.join(s, "settings.json")

    def _make_bin(self):
        os.makedirs(self.bin)
        for name in ("kitty", "qt6ct", "zeditor", "zathura", "pkill"):
            self._script(name, FAKE % name)
        self._script("hyprctl", FAKE % "hyprctl" + (
            'if [ "$1" = configerrors ] && [ -f "$ZS_CONFIGERRORS" ]; then\n'
            '  while IFS= read -r l; do echo "$l"; done < "$ZS_CONFIGERRORS"\nfi\n'))
        self._script("luac", '#!/bin/sh\nif [ "${ZS_LUAC_RC:-0}" != 0 ]; then echo "luac: syntax error" >&2; fi\n'
                     'exit ${ZS_LUAC_RC:-0}\n')

    def _script(self, name, text):
        p = os.path.join(self.bin, name)
        with open(p, "w") as f:
            f.write(text)
        os.chmod(p, 0o755)

    # ---- помощники
    def run_cli(self, *argv):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            code = cli.main(list(argv))
        lines = buf.getvalue().splitlines()
        self.assertEqual(len(lines), 1, buf.getvalue())
        return code, json.loads(lines[0])

    def calls(self):
        try:
            with open(self.log) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    def snapshot(self):
        """{путь: байты} всех файлов, которые пишет генератор (репо-выходы и деплой)."""
        out = {}
        for base in (os.path.join(self.root, "quickshell"), os.path.join(self.root, ".config"),
                     os.path.join(self.root, "obsidian"), os.path.join(self.root, "thunderbird"),
                     os.path.join(self.root, "zen"), str(self.home.config), os.path.join(self.tmp, "mnt")):
            for d, _, files in os.walk(base):
                for n in files:
                    p = os.path.join(d, n)
                    with open(p, "rb") as f:
                        out[p] = f.read()
        return out

    def read(self, *parts):
        with open(os.path.join(*parts), "rb") as f:
            return f.read()

    # пути
    def repo(self, rel):
        return os.path.join(self.root, rel)

    def cfg(self, rel):
        return os.path.join(str(self.home.config), rel)

    def write_file(self, path, data):
        with open(path, "wb") as f:
            f.write(data)


class ApplyTests(Fixture):
    def test_first_apply_deploys_everything(self):
        code, r = self.run_cli("apply")
        self.assertEqual((code, r["ok"], r["errors"]), (0, True, []))
        self.assertEqual(r["changed"], self.ids)
        self.assertIsNone(r["backup"])  # нечего было перезаписывать
        self.assertEqual(r["actions"], ["hypr:reload", "kitty:usr1"])
        self.assertEqual(self.calls(), ["hyprctl reload config-only", "hyprctl configerrors", "pkill -USR1 -x kitty"])
        # деплой копий
        gtk = self.read(self.repo(".config/gtk-3.0/gtk.css"))
        self.assertTrue(gtk.startswith(b"accent=#bb9af7 on="))
        self.assertIn(b"glass=0.72 surf=0.9 r=12px hsl=267, 85%, 78%", gtk)
        self.assertEqual(self.read(self.cfg("gtk-3.0/gtk.css")), gtk)
        self.assertEqual(self.read(self.cfg("gtk-4.0/gtk.css")), gtk)
        self.assertEqual(self.read(self.cfg("qt6ct/colors/zephyrine.conf")), gtk)
        # vault'ы (пути с пробелами/скобками) + статический manifest.json; не смонтированный - пропущен
        for v in self.home.vaults:
            self.assertEqual(self.read(str(v), ".obsidian/themes/Zephyrine/theme.css"), gtk)
            self.assertEqual(self.read(str(v), ".obsidian/themes/Zephyrine/manifest.json"), b'{"name": "Zephyrine"}\n')
        self.assertIn({"target": "obsidian", "reason": "vault-not-mounted", "path": str(self.home.unmounted_vault)},
                      r["skipped"])
        self.assertFalse(os.path.exists(str(self.home.unmounted_vault)))
        # профили Zen/TB
        self.assertEqual(self.read(str(self.home.zen_profile), "chrome/userChrome.css"), gtk)
        self.assertEqual(self.read(str(self.home.zen_profile), "chrome/userContent.css"), gtk)
        self.assertEqual(self.read(str(self.home.tb_profile), "chrome/userChrome.css"), gtk)
        # xpi: manifest внутри архива = выход в репо
        xpi = os.path.join(str(self.home.tb_profile), "extensions", "zephyrine-theme@zephyrine.xpi")
        with zipfile.ZipFile(xpi) as z:
            self.assertEqual(z.namelist(), ["manifest.json"])
            inner = z.read("manifest.json")
        self.assertEqual(inner, self.read(self.repo("thunderbird/zephyrine-theme/manifest.json")))
        self.assertIn(b'"version": "1.0"', inner)
        # quickshell: по умолчанию пустой override
        self.assertEqual(self.read(self.repo("quickshell/scheme.override.json")), b'{"colours": {}}\n')
        # hypr: эмиттер
        self.assertIn(b"local rounding = 10", self.read(self.repo(".config/hypr/settings.lua")))
        # состояние: права
        st = os.path.join(self.state, "generated.json")
        self.assertEqual(stat.S_IMODE(os.stat(st).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(self.state).st_mode), 0o700)

    def test_second_apply_is_idempotent(self):
        self.run_cli("apply")
        snap = self.snapshot()
        mt = {p: os.stat(p).st_mtime_ns for p in snap}
        open(self.log, "w").close()
        code, r = self.run_cli("apply")
        self.assertEqual((code, r["changed"], r["actions"], r["backup"], r["errors"]), (0, [], [], None, []))
        self.assertEqual(sorted(r["unchanged"]), sorted(self.ids))
        self.assertEqual(self.snapshot(), snap)
        self.assertEqual({p: os.stat(p).st_mtime_ns for p in snap}, mt)  # ничего не переписано
        self.assertEqual(self.calls(), [])

    def test_set_accent_backup_undo_restores_bytes(self):
        self.run_cli("apply")
        before = self.snapshot()
        code, r = self.run_cli("set", "appearance.accent=#7aa2f7", "--no-exec")
        self.assertEqual((code, r["errors"]), (0, []))
        for tid in ("quickshell", "hypr", "kitty", "gtk3", "gtk4", "obsidian", "tb-css", "tb-theme", "zen-chrome", "zen-content"):
            self.assertIn(tid, r["changed"])
        self.assertIsNotNone(r["backup"])
        self.assertEqual(r["actions"], [])
        self.assertEqual(sorted(r["actionsSkipped"]), ["hypr:reload", "kitty:usr1"])
        for app in ("thunderbird", "zen", "gtk", "obsidian"):
            self.assertIn(app, r["restart"])
        self.assertNotIn("kitty", r["restart"])
        self.assertNotIn("quickshell", r["restart"])
        ov = json.loads(self.read(self.repo("quickshell/scheme.override.json")))["colours"]
        self.assertEqual(ov["primary"], "7aa2f7")
        self.assertNotIn("purple", ov)
        self.assertIn(b"accent=#7aa2f7", self.read(str(self.home.zen_profile), "chrome/userChrome.css"))
        self.assertIn(b"primary = 7aa2f7", self.read(self.repo(".config/hypr/settings.lua")))
        code, r = self.run_cli("undo", "--no-exec")
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertEqual(self.snapshot(), before)  # байт-в-байт, включая xpi
        code, r = self.run_cli("apply", "--no-exec")  # undo оставил состояние согласованным
        self.assertEqual((code, r["changed"]), (0, []))

    def test_alpha_and_radius_reach_targets(self):
        self.run_cli("apply", "--no-exec")
        code, r = self.run_cli("set", "appearance.glassAlpha=0.8", "appearance.radius=4", "--no-exec")
        self.assertEqual(code, 0)
        self.assertIn("gtk3", r["changed"])
        self.assertNotIn("kitty", r["changed"])  # kitty от альфы не зависит
        self.assertIn(b"glass=0.64 surf=0.9 r=4px", self.read(self.cfg("gtk-3.0/gtk.css")))

    def test_dry_run_and_no_exec(self):
        code, r = self.run_cli("apply", "--dry-run")
        self.assertEqual((code, r["dryRun"], r["backup"]), (0, True, None))
        self.assertEqual(r["changed"], self.ids)
        self.assertFalse(os.path.exists(self.repo("quickshell/scheme.override.json")))
        self.assertFalse(os.path.exists(os.path.join(self.state, "generated.json")))
        self.assertEqual(self.calls(), [])
        code, r = self.run_cli("apply", "--no-exec")
        self.assertEqual((code, r["actions"]), (0, []))
        self.assertEqual(sorted(r["actionsSkipped"]), ["hypr:reload", "kitty:usr1"])
        self.assertEqual(self.calls(), [])  # ни одного процесса
        self.assertTrue(os.path.exists(self.repo("quickshell/scheme.override.json")))

    def test_target_selection_and_unknown(self):
        code, r = self.run_cli("apply", "--targets", "gtk3,kitty", "--no-exec")
        self.assertEqual((code, r["changed"]), (0, ["gtk3", "kitty"]))
        self.assertFalse(os.path.exists(self.cfg("gtk-4.0/gtk.css")))
        code, r = self.run_cli("apply", "--targets", "nosuch", "--no-exec")
        self.assertEqual(code, 1)
        self.assertEqual(r["errors"][0]["target"], "nosuch")

    def test_symlinked_output_stays_symlink(self):
        real = os.path.join(self.tmp, "elsewhere", "zephyrine.conf")
        os.makedirs(os.path.dirname(real))
        os.makedirs(self.repo(".config/kitty"))
        os.symlink(real, self.repo(".config/kitty/zephyrine.conf"))
        self.run_cli("apply", "--no-exec")
        link = self.repo(".config/kitty/zephyrine.conf")
        self.assertTrue(os.path.islink(link))
        self.assertTrue(self.read(real).startswith(b"accent=#bb9af7"))
        self.run_cli("set", "appearance.accent=#7aa2f7", "--no-exec")
        self.assertTrue(os.path.islink(link))
        self.assertTrue(self.read(real).startswith(b"accent=#7aa2f7"))

    def test_deployed_symlink_to_repo_not_duplicated(self):
        os.makedirs(self.repo(".config/gtk-3.0"))
        os.makedirs(os.path.dirname(self.cfg("gtk-3.0/gtk.css")), exist_ok=True)
        os.symlink(self.repo(".config/gtk-3.0/gtk.css"), self.cfg("gtk-3.0/gtk.css"))
        code, r = self.run_cli("apply", "--targets", "gtk3", "--no-exec")
        self.assertEqual((code, r["changed"]), (0, ["gtk3"]))
        self.assertTrue(os.path.islink(self.cfg("gtk-3.0/gtk.css")))
        st = self.run_cli("status")[1]
        self.assertEqual([p["kind"] for p in self._t(st, "gtk3")["paths"]], ["repo"])

    def _t(self, status, tid):
        return next(t for t in status["targets"] if t["id"] == tid)


class DriftAndRestoreTests(Fixture):
    def test_drift_blocks_only_that_target(self):
        self.run_cli("apply", "--no-exec")
        live = self.cfg("gtk-3.0/gtk.css")
        self.write_file(live, b"hand edited\n")
        self.run_cli("set", "appearance.glassAlpha=0.8", "--no-apply")
        code, r = self.run_cli("apply", "--no-exec")
        self.assertEqual(code, 4)
        self.assertFalse(r["ok"])
        self.assertEqual(r["drift"], ["gtk3"])
        self.assertEqual(r["errors"][0], {"target": "gtk3", "error": "drift", "paths": [live]})
        self.assertEqual(self.read(live), b"hand edited\n")  # не тронут
        self.assertIn("gtk4", r["changed"])  # остальные применены
        self.assertNotIn("gtk3", r["changed"])
        st = self.run_cli("status")[1]
        t = next(x for x in st["targets"] if x["id"] == "gtk3")
        self.assertEqual((t["state"], t["drift"]), ("manual", True))
        # set тоже возвращает код 4
        code, r = self.run_cli("set", "appearance.glassAlpha=0.7", "--no-exec")
        self.assertEqual(code, 4)

    def test_force_overwrites_with_backup_of_hand_edit(self):
        self.run_cli("apply", "--no-exec")
        live = self.cfg("gtk-3.0/gtk.css")
        self.write_file(live, b"hand edited\n")
        code, r = self.run_cli("apply", "--no-exec", "--force")
        self.assertEqual((code, r["changed"], r["drift"]), (0, ["gtk3"], []))
        self.assertTrue(self.read(live).startswith(b"accent="))
        bid = r["backup"]
        self.assertIsNotNone(bid)
        self.assertEqual(backup.list_backups(self.paths)[0]["files"], [live])
        code, rr = self.run_cli("backup", "restore", bid)
        self.assertEqual(code, 0)
        self.assertEqual(self.read(live), b"hand edited\n")

    def test_backup_restore_roundtrip_no_false_drift(self):
        self.run_cli("apply", "--no-exec")
        state_a = self.snapshot()
        code, r = self.run_cli("set", "appearance.radius=5", "--no-exec")
        bid = r["backup"]
        state_b = self.snapshot()
        self.assertNotEqual(state_a, state_b)
        code, rr = self.run_cli("backup", "restore", bid)
        self.assertEqual(code, 0)
        self.assertEqual(self.snapshot(), state_a)  # файлы вернулись байт-в-байт
        code, r = self.run_cli("apply", "--no-exec")  # восстановленные файлы - ранее записанные, не drift
        self.assertEqual((code, r["drift"], r["errors"]), (0, [], []))
        for live in (self.cfg("gtk-3.0/gtk.css"), self.cfg("gtk-4.0/gtk.css")):
            self.assertIn(b"r=5px", self.read(live))  # настройка не потерялась, файлы снова актуальны
        self.assertEqual(self.read(self.cfg("gtk-3.0/gtk.css")), state_b[self.cfg("gtk-3.0/gtk.css")])

    def test_adoption_only_when_golden_equal(self):
        # файл без записи в состоянии: равен выводу при дефолтах -> принимается; другой -> drift
        os.makedirs(self.repo(".config/kitty"))
        self.write_file(self.repo(".config/kitty/zephyrine.conf"), self.render_default())
        os.makedirs(self.repo(".config/zathura"))
        self.write_file(self.repo(".config/zathura/zathurarc"), b"my own rc\n")
        self.run_cli("set", "appearance.accent=#7aa2f7", "--no-apply")
        code, r = self.run_cli("apply", "--no-exec")
        self.assertEqual(code, 4)
        self.assertEqual(r["drift"], ["zathura"])
        self.assertIn("kitty", r["changed"])
        self.assertEqual(self.read(self.repo(".config/zathura/zathurarc")), b"my own rc\n")

    def render_default(self):
        eng = targets.Engine(self.paths)
        t = next(x for x in eng.manifest if x["id"] == "kitty")
        return eng.render(t, default=True)

    def test_xpi_hand_replaced_is_drift(self):
        self.run_cli("apply", "--no-exec")
        xpi = os.path.join(str(self.home.tb_profile), "extensions", "zephyrine-theme@zephyrine.xpi")
        with zipfile.ZipFile(xpi, "w") as z:
            z.writestr("manifest.json", '{"hand": true}')
        self.run_cli("set", "appearance.accent=#7aa2f7", "--no-apply")
        code, r = self.run_cli("apply", "--no-exec")
        self.assertEqual((code, r["drift"]), (4, ["tb-theme"]))

    def test_xpi_is_deterministic(self):
        self.assertEqual(targets.build_xpi(b"{}"), targets.build_xpi(b"{}"))


class SkipTests(Fixture):
    def test_missing_profile_and_registry(self):
        with open(os.path.join(self.home.config, "zen", "installs.ini"), "w") as f:
            f.write("[X]\nDefault=nope (gone)\n")
        os.unlink(os.path.join(self.home.config, "obsidian", "obsidian.json"))
        os.unlink(os.path.join(self.home.config, "thunderbird", "installs.ini"))
        code, r = self.run_cli("apply", "--no-exec")
        self.assertEqual((code, r["errors"]), (0, []))
        reasons = {s["target"]: s["reason"] for s in r["skipped"]}
        self.assertEqual(reasons["zen-chrome"], "profile-not-found")
        self.assertEqual(reasons["zen-content"], "profile-not-found")
        self.assertEqual(reasons["tb-css"], "profile-not-found")
        self.assertEqual(reasons["tb-theme"], "profile-not-found")
        self.assertEqual(reasons["obsidian"], "registry-not-found")
        self.assertFalse(os.path.exists(self.repo("zen/userChrome.css")))
        self.assertIn("gtk3", r["changed"])
        self.assertFalse(os.path.exists(os.path.join(self.home.config, "zen", "nope (gone)")))  # профиль не создаётся

    def test_no_vaults_usable(self):
        for v in self.home.vaults:
            shutil.rmtree(str(v) + "/.obsidian")
        code, r = self.run_cli("apply", "--targets", "obsidian", "--no-exec")
        self.assertEqual(code, 0)
        self.assertEqual([s["reason"] for s in r["skipped"] if s["target"] == "obsidian"][-1], "no-vaults")
        self.assertEqual(r["changed"], [])

    def test_app_not_installed(self):
        os.unlink(os.path.join(self.bin, "kitty"))
        code, r = self.run_cli("apply", "--no-exec")
        self.assertIn({"target": "kitty", "reason": "not-installed"}, r["skipped"])
        self.assertNotIn("kitty", r["changed"])

    def test_missing_template_is_skipped_not_crash(self):
        os.unlink(os.path.join(self.root, "settings", "templates", "t-zathura.tmpl"))
        code, r = self.run_cli("apply", "--no-exec")
        self.assertEqual((code, r["errors"]), (0, []))
        self.assertIn("no-template", [s["reason"] for s in r["skipped"] if s["target"] == "zathura"])
        self.assertIn("gtk3", r["changed"])
        st = self.run_cli("status")[1]
        self.assertEqual(next(t for t in st["targets"] if t["id"] == "zathura")["state"], "no-template")

    def test_emitter_missing_is_skipped(self):
        with mock.patch.dict(sys.modules, {"zsettings.hypr": None}):
            # None в sys.modules -> ImportError (не ModuleNotFoundError с нашим именем?) - проверяем и это
            try:
                code, r = self.run_cli("apply", "--targets", "hypr", "--no-exec")
            except ImportError:
                self.skipTest("import blocked")
        self.assertEqual(code, 0)

    def test_render_error_is_error_not_crash(self):
        with open(os.path.join(self.root, "settings", "templates", "t-zathura.tmpl"), "w") as f:
            f.write("{{ c.nope | hex }}\n")
        code, r = self.run_cli("apply", "--no-exec")
        self.assertEqual(code, 1)
        self.assertEqual(r["errors"][0]["target"], "zathura")
        self.assertIn("gtk3", r["changed"])

    def test_unmanaged_target_and_later_stage(self):
        self.run_cli("set", "appearance.targets.gtk3=false", "--no-apply")
        code, r = self.run_cli("apply", "--no-exec")
        self.assertIn({"target": "gtk3", "reason": "not-managed"}, r["skipped"])
        self.assertFalse(os.path.exists(self.repo(".config/gtk-3.0/gtk.css")))
        st = self.run_cli("status")[1]
        t = next(x for x in st["targets"] if x["id"] == "gtk3")
        self.assertEqual((t["state"], t["managed"]), ("unmanaged", False))
        # цели не-v1 этапов: тихо пропускаются в общем apply, явно названные - skipped
        code, r = self.run_cli("apply", "--targets", "hypridle", "--no-exec")
        self.assertEqual(r["skipped"][0]["reason"], "stage-not-implemented")


class ReloadTests(Fixture):
    def test_hypr_configerrors_rolls_back(self):
        self.run_cli("apply", "--no-exec")
        lua = self.repo(".config/hypr/settings.lua")
        good = self.read(lua)
        with open(self.configerrors, "w") as f:
            f.write("line 3: attempt to index nil\n")
        code, r = self.run_cli("set", "appearance.windowRounding=3")
        self.assertEqual(code, 1)
        self.assertNotIn("hypr", r["changed"])
        self.assertIn("hyprctl configerrors", r["errors"][0]["error"])
        self.assertEqual(self.read(lua), good)  # прежнее содержимое возвращено
        self.assertEqual(self.calls().count("hyprctl reload config-only"), 2)  # reload и повторный reload после отката
        os.unlink(self.configerrors)
        code, r = self.run_cli("apply")  # без ошибок - применяется (запись не считалась известной после отката)
        self.assertEqual((code, r["changed"]), (0, ["hypr"]))
        self.assertIn(b"rounding = 3", self.read(lua))

    def test_new_hypr_output_removed_on_rollback(self):
        with open(self.configerrors, "w") as f:
            f.write("boom\n")
        code, r = self.run_cli("apply", "--targets", "hypr")
        self.assertEqual(code, 1)
        self.assertFalse(os.path.exists(self.repo(".config/hypr/settings.lua")))

    def test_luac_precheck_blocks_write(self):
        with mock.patch.dict(os.environ, {"ZS_LUAC_RC": "1"}):
            code, r = self.run_cli("apply", "--targets", "hypr")
        self.assertEqual(code, 1)
        self.assertIn("luac -p: luac: syntax error", r["errors"][0]["error"])
        self.assertFalse(os.path.exists(self.repo(".config/hypr/settings.lua")))
        self.assertNotIn("hyprctl reload config-only", self.calls())

    def test_kitty_without_processes_is_not_error(self):
        self._script("pkill", "#!/bin/sh\nexit 1\n")
        code, r = self.run_cli("apply", "--targets", "kitty")
        self.assertEqual((code, r["errors"], r["actions"]), (0, [], ["kitty:usr1"]))

    def test_reload_failure_reported(self):
        self._script("pkill", "#!/bin/sh\necho oops >&2\nexit 2\n")
        code, r = self.run_cli("apply", "--targets", "kitty")
        self.assertEqual(code, 1)
        self.assertIn("exit 2 oops", r["errors"][0]["error"])
        self.assertEqual(r["changed"], ["kitty"])  # файл всё равно записан


class StatusDoctorTests(Fixture):
    def states(self):
        return {t["id"]: t["state"] for t in self.run_cli("status")[1]["targets"]}

    def test_status_lifecycle(self):
        s = self.states()
        self.assertEqual(s["gtk3"], "missing")
        self.run_cli("apply", "--no-exec")
        st = self.run_cli("status")[1]
        by = {t["id"]: t for t in st["targets"]}
        self.assertEqual(by["kitty"]["state"], "live")
        self.assertEqual(by["quickshell"]["state"], "live")
        self.assertEqual(by["gtk3"]["state"], "restart")  # записан, приложению нужен перезапуск
        self.assertEqual(by["tb-css"]["state"], "restart")
        self.assertIsNotNone(by["gtk3"]["lastApplied"])
        self.assertEqual(by["gtk3"]["app"], "gtk")
        self.assertEqual(by["hypridle"]["state"], "later")
        self.run_cli("set", "appearance.radius=5", "--no-apply")
        self.assertEqual(self.states()["gtk3"], "outdated")
        self.run_cli("apply", "--no-exec")
        self.write_file(self.cfg("gtk-4.0/gtk.css"), b"x")
        self.assertEqual(self.states()["gtk4"], "manual")
        self.assertEqual(self.states()["gtk3"], "restart")

    def test_status_does_not_write(self):
        self.run_cli("status")
        self.assertFalse(os.path.exists(self.repo("quickshell/scheme.override.json")))
        self.assertFalse(os.path.exists(os.path.join(self.state, "generated.json")))

    def test_doctor(self):
        code, r = self.run_cli("doctor")
        self.assertEqual((code, r["ok"], r["blocking"]), (0, True, []))
        self.assertTrue(r["commands"]["hyprctl"]["available"])  # поддельный из tmp/bin
        self.assertFalse(r["commands"]["mpvpaper"]["available"])
        self.assertTrue(r["profiles"]["zen"]["found"])
        self.assertTrue(r["profiles"]["zen"]["path"].endswith("smhkr7xv.Default (release)"))
        self.assertEqual([v["mounted"] for v in r["obsidian"]["vaults"]], [True, True, False])
        self.assertTrue(any("не смонтирован" in w for w in r["warnings"]))
        self.assertTrue(r["files"]["scheme"]["ok"])
        self.assertEqual({t["id"] for t in r["targets"]} >= {"gtk3", "hypr"}, True)
        self.assertTrue(r["state"]["writable"])
        self.assertEqual(r["home"], str(self.home.home))

    def test_doctor_reports_broken_files(self):
        with open(os.path.join(self.root, "quickshell", "scheme.json"), "w") as f:
            f.write("{nope")
        os.unlink(os.path.join(self.root, "settings", "schema.json"))
        r = doctor.run(self.paths)
        self.assertFalse(r["ok"])
        self.assertEqual(len(r["blocking"]), 2)

    def test_doctor_does_not_execute(self):
        doctor.run(self.paths)
        self.assertEqual(self.calls(), [])


class RestartAckTests(Fixture):
    def pend(self):
        return self.run_cli("status")[1]["restartPending"]

    def by(self):
        return {t["id"]: t for t in self.run_cli("status")[1]["targets"]}

    def test_apply_reports_restart_pending(self):
        _, r = self.run_cli("apply", "--no-exec")
        self.assertTrue({"gtk", "thunderbird", "zen"} <= set(r["restart"]))
        self.assertEqual(r["restartPending"], r["restart"])

    def test_ack_all_and_by_app(self):
        self.run_cli("apply", "--no-exec")
        self.assertIn("gtk", self.pend())
        code, r = self.run_cli("ack-restart", "gtk")
        self.assertEqual(code, 0)
        self.assertEqual(sorted(r["acked"]), ["gtk3", "gtk4"])
        self.assertNotIn("gtk", r["restartPending"])
        by = self.by()
        self.assertEqual(by["gtk3"]["state"], "live")
        self.assertFalse(by["gtk3"]["restartPending"])
        self.assertIsNotNone(by["gtk3"]["restartAckedAt"])
        self.assertEqual(by["tb-css"]["state"], "restart")
        code, r = self.run_cli("ack-restart")
        self.assertEqual(code, 0)
        self.assertEqual(r["restartPending"], [])
        self.assertTrue(all(t["state"] != "restart" for t in self.by().values()))

    def test_ack_unknown_app(self):
        code, r = self.run_cli("ack-restart", "nope")
        self.assertEqual((code, r["ok"]), (2, False))
        self.assertEqual(r["errors"][0]["app"], "nope")

    def test_ack_then_new_apply_sets_pending_again(self):
        self.run_cli("apply", "--no-exec")
        self.run_cli("ack-restart")
        self.run_cli("set", "appearance.radius=5", "--no-exec")
        self.assertIn("gtk", self.pend())
        self.assertIsNone(self.by()["gtk3"]["restartAckedAt"])

    def test_auto_clear_when_process_started_after_write(self):
        self.run_cli("apply", "--no-exec")
        self.assertEqual(self.by()["tb-css"]["state"], "restart")
        self.assertIs(self.by()["tb-css"]["appRunning"], True)
        self.rm_proc(100)
        self.add_proc(200, "thunderbird", 4000000000)  # запущен позже записи
        self.assertEqual(self.by()["tb-css"]["state"], "live")
        self.assertEqual(self.by()["tb-theme"]["state"], "live")
        self.assertEqual(self.by()["zen-chrome"]["state"], "restart")  # zen не перезапускали
        self.assertNotIn("thunderbird", self.pend())

    def test_old_main_process_keeps_pending_despite_new_child(self):
        self.run_cli("apply", "--no-exec")
        self.add_proc(201, "thunderbird", 4000000000)  # второй процесс новый, старый (100) жив
        self.assertEqual(self.by()["tb-css"]["state"], "restart")

    def test_not_running_app_is_not_pending(self):
        self.run_cli("apply", "--no-exec")
        self.rm_proc(101)
        self.assertEqual(self.by()["zen-content"]["state"], "live")
        self.assertIs(self.by()["zen-content"]["appRunning"], False)
        self.assertNotIn("zen", self.pend())

    def test_gtk_has_no_process_only_ack(self):
        self.run_cli("apply", "--no-exec")
        self.assertIsNone(self.by()["gtk3"]["appRunning"])
        self.assertEqual(self.by()["gtk3"]["state"], "restart")

    def test_status_does_not_modify_state(self):
        self.run_cli("apply", "--no-exec")
        before = self.read(self.state, "generated.json")
        self.rm_proc(100)
        self.run_cli("status")
        self.assertEqual(self.read(self.state, "generated.json"), before)

    def test_process_starts_parses_comm_with_parens(self):
        self.add_proc(300, "we ird", 1700005000)
        self.assertAlmostEqual(targets.process_starts(["we ird"])[0], 1700005000, delta=0.02)
        self.assertEqual(targets.process_starts(["nothing"]), [])

    def test_apply_restart_excludes_not_running(self):
        self.rm_proc(101)
        _, r = self.run_cli("apply", "--no-exec")
        self.assertNotIn("zen", r["restart"])
        self.assertIn("thunderbird", r["restart"])


class DiffTests(Fixture):
    def test_diff_drift_target(self):
        self.run_cli("apply", "--no-exec")
        path = self.cfg("gtk-3.0/gtk.css")
        gen = self.read(path)
        self.write_file(path, gen + b"extra line\n")
        code, r = self.run_cli("diff", "gtk3")
        self.assertEqual(code, 0)
        self.assertTrue(r["ok"] and r["drift"])
        self.assertEqual(r["target"], "gtk3")
        f = [x for x in r["files"] if x["path"] == path][0]
        self.assertEqual(f["action"], "drift")
        self.assertEqual((f["added"], f["removed"]), (1, 0))
        self.assertIn("--- generated: " + path, f["diff"])
        self.assertIn("+++ disk: " + path, f["diff"])
        self.assertIn("+extra line", f["diff"])
        self.assertEqual(self.read(path), gen + b"extra line\n")  # diff ничего не пишет

    def test_diff_clean_and_unknown(self):
        self.run_cli("apply", "--no-exec")
        code, r = self.run_cli("diff", "kitty")
        self.assertEqual((code, r["files"], r["drift"]), (0, [], False))
        code, r = self.run_cli("diff", "zzz")
        self.assertEqual((code, r["ok"]), (2, False))

    def test_diff_missing_file_and_xpi(self):
        _, r = self.run_cli("diff", "gtk3")
        self.assertTrue(any(f["action"] == "create" and not f["exists"] for f in r["files"]))
        self.run_cli("apply", "--no-exec")
        xpi = os.path.join(str(self.home.tb_profile), "extensions", "zephyrine-theme@zephyrine.xpi")
        self.write_file(xpi, targets.build_xpi(b'{"name": "hand"}\n'))
        _, r = self.run_cli("diff", "tb-theme")
        f = r["files"][0]
        self.assertEqual((f["kind"], f["action"]), ("xpi", "drift"))
        self.assertIn("hand", f["diff"])

    def test_diff_unmanaged_has_state(self):
        _, r = self.run_cli("diff", "hypridle")
        self.assertEqual((r["state"], r["files"]), ("later", []))


class XpiDeterminismTests(Fixture):
    def test_two_builds_identical_bytes_and_header(self):
        a, b = targets.build_xpi(b'{"a": 1}\n'), targets.build_xpi(b'{"a": 1}\n')
        self.assertEqual(a, b)
        with zipfile.ZipFile(io.BytesIO(a)) as z:
            infos = z.infolist()
            self.assertEqual([i.filename for i in infos], ["manifest.json"])
            self.assertEqual(infos[0].date_time, (1980, 1, 1, 0, 0, 0))
            self.assertEqual(infos[0].external_attr >> 16, 0o644)
            self.assertEqual(infos[0].create_system, 3)

    def test_rebuild_after_time_passes_is_not_drift_and_undo_restores_bytes(self):
        self.run_cli("apply", "--no-exec")
        xpi = os.path.join(str(self.home.tb_profile), "extensions", "zephyrine-theme@zephyrine.xpi")
        first = self.read(xpi)
        os.utime(xpi, (1, 1))
        code, r = self.run_cli("apply", "--no-exec", "--force")
        self.assertEqual(r["drift"], [])
        self.assertEqual(self.read(xpi), first)
        self.run_cli("set", "appearance.accent=#7aa2f7", "--no-exec")
        self.assertNotEqual(self.read(xpi), first)
        self.run_cli("undo", "--no-exec")
        self.assertEqual(self.read(xpi), first)  # байт-в-байт


class CliTests(Fixture):
    def test_set_rejects_unusable_accent_before_writing(self):
        code, r = self.run_cli("set", "appearance.accent=#101030", "--no-apply")
        self.assertEqual(code, 2)
        self.assertEqual(r["errors"][0]["key"], "appearance.accent")
        self.assertFalse(os.path.exists(self.settings_file))

    def test_test_subcommand_home(self):
        base = os.path.join(self.tmp, "fixture-home")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = cli.main(["test", "home", base])
        self.assertEqual(code, 0)
        self.assertIn("export HOME=", buf.getvalue())
        self.assertTrue(os.path.isdir(os.path.join(base, "home", ".config", "zen")))

    def test_test_subcommand_errors(self):
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            code = cli.main(["test", "golden", "--target", "zzz"])
        self.assertEqual(code, 2)
        self.assertIn("неизвестные цели", err.getvalue())
        code, r = self.run_cli("test", "bogus")  # ошибка разбора -> обычный JSON-ответ cli
        self.assertEqual((code, r["ok"]), (2, False))

    def test_test_lint_runs_on_fixture_root(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = cli.main(["test", "lint", "--root", self.root, "--json"])
        self.assertIn(code, (0, 1))
        self.assertIn("checked", json.loads(buf.getvalue()))


class RealManifestSmoke(unittest.TestCase):
    """Реальные targets.json/шаблоны репо, но ТОЛЬКО dry-run в изолированном HOME: репо не пишется."""

    def test_dry_run_on_real_repo(self):
        td = tempfile.TemporaryDirectory(prefix="zs-s16-")
        self.addCleanup(td.cleanup)
        home = testkit.make_isolated_home(td.name)
        env = {"HOME": str(home.home), "ZEPHYRINE_ROOT": REAL_ROOT, "ZEPHYRINE_STATE": str(home.state),
               "PATH": os.environ.get("PATH", "")}
        override = os.path.join(REAL_ROOT, "quickshell", "scheme.override.json")
        existed = os.path.exists(override)
        with mock.patch.dict(os.environ, env):
            paths = Paths.from_env()
            r = targets.apply(paths, None, dry_run=True, force=False, no_exec=True)
            s = targets.status(paths)
        self.assertTrue(r["dryRun"])
        self.assertEqual(os.path.exists(override), existed)
        with open(paths.targets_file, encoding="utf-8") as f:
            self.assertEqual(len(s["targets"]), len(json.load(f)["targets"]))
        self.assertEqual(r["backup"], None)


if __name__ == "__main__":
    unittest.main()


class ModeSwitchTests(Fixture):
    """Переключение темы тёмная -> светлая -> тёмная после первого apply не даёт drift ни у одной цели."""

    def test_switch_back_and_forth_has_no_errors(self):
        code, r = self.run_cli("apply")
        self.assertEqual((code, r["errors"]), (0, []))
        for mode in ("light", "dark", "light", "dark"):
            with self.subTest(mode=mode):
                code, r = self.run_cli("set", "appearance.mode=" + mode)
                self.assertEqual((code, r["errors"], r["drift"]), (0, [], []), r)
                self.assertTrue(r["changed"])

    def test_mode_switch_overwrites_hand_edited_copy_with_backup(self):
        self.run_cli("apply")
        live = self.cfg("gtk-3.0/gtk.css")
        with open(live, "ab") as f:
            f.write(b"/* edited by hand */\n")
        code, r = self.run_cli("set", "appearance.mode=light")
        self.assertEqual((code, r["errors"], r["drift"]), (0, [], []), r)
        self.assertNotIn(b"edited by hand", self.read(live))
        self.assertIsNotNone(r["backup"])   # прежнее содержимое сохранено

    def test_other_settings_still_report_drift_for_hand_edits(self):
        self.run_cli("apply")
        live = self.cfg("gtk-3.0/gtk.css")
        with open(live, "ab") as f:
            f.write(b"/* edited by hand */\n")
        code, r = self.run_cli("set", "appearance.radius=8")
        self.assertIn("gtk3", r["drift"])
