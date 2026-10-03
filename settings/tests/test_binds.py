import json
import os
import shutil
import subprocess
import tempfile
import unittest

from zsettings import autostart, binds, hypr
from tests.test_hypr import DEFAULTS, PATHS, ctx_for, eff


class FakeSchema:
    def default(self, key):
        return DEFAULTS[key]


def gen(over=None):
    v = eff(over)
    return hypr.emit(v, ctx_for(v), PATHS)


class NormTests(unittest.TestCase):
    def test_norm_and_mask(self):
        self.assertEqual(binds.norm("SUPER + CTRL + 4"), binds.norm("ctrl + super + 4"))
        self.assertEqual(binds.combo_from_mask(64 | 4, "4"), "SUPER + CTRL + 4")
        self.assertEqual(binds.combo_from_mask(0, "XF86AudioMute"), "XF86AudioMute")


class CheckTests(unittest.TestCase):
    def check(self, **flat):
        return binds.check_values(FakeSchema(), flat, list(flat))

    def test_ok(self):
        self.assertEqual(self.check(**{"binds.notifs": ["SUPER + K"]}), [])
        self.assertEqual(self.check(**{"binds.close": ["SUPER + SHIFT + C", "ALT + F4"]}), [])

    def test_errors(self):
        self.assertIn("unknown action", self.check(**{"binds.nope": ["SUPER + K"]})[0]["error"])
        self.assertIn("invalid combination", self.check(**{"binds.notifs": ["SUPER+K!"]})[0]["error"])
        self.assertIn("invalid combination", self.check(**{"binds.notifs": ["SUPER + SHIFT"]})[0]["error"])
        self.assertIn("duplicate", self.check(**{"binds.notifs": ["SUPER + K", "SUPER + K"]})[0]["error"])
        self.assertIn("at least one", self.check(**{"binds.notifs": []})[0]["error"])
        e = self.check(**{"binds.notifs": ["SUPER + Q"]})   # занято терминалом
        self.assertIn("already used by terminal", e[0]["error"])
        self.assertIn("invalid command", self.check(**{"apps.terminal": "a\nb"})[0]["error"])


class EmitTests(unittest.TestCase):
    def test_defaults_no_binds(self):
        self.assertNotIn("hl.bind", gen())
        self.assertNotIn("unbind", gen())

    def test_override(self):
        t = gen({"binds.notifs": ["SUPER + K"]})
        self.assertIn('pcall(hl.unbind, "SUPER + N")', t)
        self.assertIn('hl.bind("SUPER + K", hl.dsp.exec_cmd("qs -p $HOME/.config/quickshell/zephyrine ipc call notifs '
                      'toggle"), { description = "zp:notifs · Уведомления и календарь" })', t)

    def test_launcher_release_kept_and_raw_action(self):
        t = gen({"binds.launcher": ["SUPER + Super_L", "SUPER + F1"], "binds.close": ["ALT + F4"]})
        self.assertIn('"SUPER + Super_L", hl.dsp.exec_cmd', t)
        self.assertIn("release = true", t)
        self.assertEqual(t.count("release = true"), 1)
        self.assertIn('hl.bind("ALT + F4", hl.dsp.window.close(), { description = "zp:close · Закрыть окно" })', t)

    def test_app_terminal(self):
        t = gen({"apps.terminal": "foot"})
        self.assertIn('pcall(hl.unbind, "SUPER + Q")', t)
        self.assertIn('hl.bind("SUPER + Q", hl.dsp.exec_cmd("foot")', t)

    @unittest.skipUnless(shutil.which("luac"), "luac недоступен")
    def test_luac_syntax(self):
        d = tempfile.mkdtemp()
        p = os.path.join(d, "settings.lua")
        with open(p, "w", encoding="utf-8") as f:
            f.write(gen({"binds.shot-area": ['SUPER + SHIFT + S'], "apps.fileManager": 'thu"nar',
                         "autostart": [{"id": "a", "name": "A", "cmd": 'echo "hi"', "enabled": True, "delaySec": 3}]}))
        r = subprocess.run(["luac", "-p", p], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


class ListTests(unittest.TestCase):
    JSON = json.dumps([
        {"modmask": 64, "key": "Q", "description": "zp:terminal · Терминал", "dispatcher": "exec", "arg": "kitty"},
        {"modmask": 64, "key": "P", "description": "", "dispatcher": "pseudo", "arg": ""},
        {"modmask": 68, "key": "3", "description": "", "dispatcher": "exec", "arg": "grim"},
    ])

    def test_parse_skips_zp_and_maps_mask(self):
        out = binds.parse_hypr_binds(self.JSON)
        self.assertEqual([b["combo"] for b in out], ["SUPER + P", "SUPER + CTRL + 3"])
        self.assertEqual(binds.parse_hypr_binds("oops"), [])

    def test_listing_and_conflicts(self):
        runner = lambda argv: self.JSON  # noqa: E731
        lst = binds.listing({"binds.notifs": ["SUPER + K"]}, runner)
        notifs = next(a for a in lst["actions"] if a["id"] == "notifs")
        self.assertEqual((notifs["combos"], notifs["custom"]), (["SUPER + K"], True))
        self.assertEqual(len(lst["actions"]), len(binds.ACTIONS))
        c = binds.conflicts("super + p", {}, runner=runner)
        self.assertEqual([x["kind"] for x in c], ["hyprland"])
        c = binds.conflicts("SUPER + Q", {}, ignore_action="terminal", runner=runner)
        self.assertEqual(c, [])
        c = binds.conflicts("SUPER + Q", {}, runner=runner)
        self.assertEqual(c[0]["id"], "terminal")

    def make_runner(self, submap_after):
        """Мок hyprctl: `submap` отдаёт состояние, которое задаёт dispatch (если он «сработал»)."""
        state = {"s": "", "log": []}

        def runner(argv):
            state["log"].append(argv)
            if argv[:2] == ["hyprctl", "dispatch"]:
                tgt = argv[-1]
                if submap_after(argv):
                    state["s"] = "" if "reset" in tgt else binds.CAPTURE_SUBMAP
                return ""
            if argv == ["hyprctl", "submap"]:
                return state["s"] + "\n"
            if argv == ["hyprctl", "configerrors"]:
                return "bad config\n"
            return ""
        return runner, state

    def test_capture_confirmed(self):
        spawned = []
        runner, st = self.make_runner(lambda a: True)
        r = binds.capture(True, runner=runner, spawn=spawned.append, full=lambda a: (0, runner(a), ""))
        self.assertTrue(r["active"])
        self.assertEqual(r["submap"], "zp_capture")
        self.assertIn("sleep 20", spawned[0][2])
        r = binds.capture(False, runner=runner, spawn=spawned.append, full=lambda a: (0, runner(a), ""))
        self.assertFalse(r["active"])
        self.assertEqual(st["s"], "")

    def test_capture_legacy_syntax_fallback(self):
        runner, st = self.make_runner(lambda a: a[-2:] == ["submap", "zp_capture"] or "reset" in a[-1])
        r = binds.capture(True, runner=runner, spawn=lambda a: None, full=lambda a: (0, runner(a), ""))
        self.assertTrue(r["active"])
        self.assertEqual(len(r["actions"]), 3)

    def test_capture_not_activated_reports_and_resets(self):
        spawned = []
        runner, st = self.make_runner(lambda a: False)
        r = binds.capture(True, runner=runner, spawn=spawned.append, full=lambda a: (0, runner(a), ""))
        self.assertFalse(r["active"])
        self.assertIn("не включился", r["diagnostic"])
        self.assertIn("bad config", r["diagnostic"])
        self.assertIn("код 0", r["diagnostic"])   # вывод каждой попытки виден
        self.assertEqual(spawned, [])   # сторож не нужен, если режим не включился

    def test_capture_no_exec(self):
        r = binds.capture(True, no_exec=True)
        self.assertFalse(r["active"])
        self.assertIn("zp_capture", r["actions"][0])


class AutostartTests(unittest.TestCase):
    E = lambda self, **kw: dict({"id": "x", "name": "X", "cmd": "xterm", "enabled": True, "delaySec": 0}, **kw)  # noqa: E731

    def check(self, entries):
        return autostart.check_values(FakeSchema(), {"autostart": entries}, ["autostart"])

    def test_check(self):
        self.assertEqual(self.check([self.E()]), [])
        self.assertIn("duplicate", self.check([self.E(), self.E()])[0]["error"])
        self.assertIn("invalid id", self.check([self.E(id="Bad Id")])[0]["error"])
        self.assertIn("invalid cmd", self.check([self.E(cmd="a\nb")])[0]["error"])
        self.assertIn("invalid cmd", self.check([self.E(cmd="  ")])[0]["error"])
        self.assertIn("delaySec", self.check([self.E(delaySec=9999)])[0]["error"])
        self.assertEqual(autostart.check_values(FakeSchema(), {}, ["appearance.radius"]), [])

    def test_lua(self):
        ls = autostart.lua_lines([self.E(cmd="a"), self.E(id="y", cmd="b", delaySec=4), self.E(id="z", enabled=False)],
                                 hypr.lua_str)
        self.assertEqual(ls[1:], ['hl.on("hyprland.start", function()', '    hl.exec_cmd("a")',
                                  '    hl.exec_cmd("sleep 4 && b")', "end)"])
        self.assertEqual(autostart.lua_lines([self.E(enabled=False)], hypr.lua_str), [])

    def test_parse_system(self):
        t = ('hl.on("hyprland.start", function()\n    hl.exec_cmd("hypridle")\n'
             '    -- hl.exec_cmd("off")\n    hl.exec_cmd("sh -c \\"x\\"")\nend)\nhl.exec_cmd("outside")\n')
        self.assertEqual(autostart.parse_system(t), ["hypridle", 'sh -c "x"'])


if __name__ == "__main__":
    unittest.main()
