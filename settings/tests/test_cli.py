import contextlib
import fcntl
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SETTINGS_DIR)

from zsettings import cli  # noqa: E402

BIN = os.path.join(SETTINGS_DIR, "bin", "zephyrine-settings")


class CliCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.root = os.path.join(self.tmp, "root")
        self.state = os.path.join(self.tmp, "state")
        os.makedirs(os.path.join(self.root, "settings"))
        for n in ("schema.json", "targets.json"):
            shutil.copy(os.path.join(SETTINGS_DIR, n), os.path.join(self.root, "settings", n))
        self.sfile = os.path.join(self.root, "settings", "settings.json")
        self.env = {"HOME": self.tmp, "ZEPHYRINE_ROOT": self.root, "ZEPHYRINE_STATE": self.state,
                    "ZEPHYRINE_LOCK_TIMEOUT": "5"}
        p = mock.patch.dict(os.environ, self.env)
        p.start()
        self.addCleanup(p.stop)

    def run_cli(self, *argv):
        """In-process: (код, строка stdout, разобранный JSON)."""
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            code = cli.main(list(argv))
        out = buf.getvalue()
        self.assertEqual(out.count("\n"), 1, "stdout must be exactly one line: %r" % out)
        return code, out, json.loads(out)

    def raw(self):
        with open(self.sfile, "rb") as f:
            return f.read()

    def file_json(self):
        with open(self.sfile, encoding="utf-8") as f:
            return json.load(f)

    def history(self):
        d = os.path.join(self.state, "settings-history")
        return sorted(os.listdir(d)) if os.path.isdir(d) else []


class GetTests(CliCase):
    def test_get_all_defaults(self):
        code, _, r = self.run_cli("get")
        self.assertEqual(code, 0)
        v = r["values"]
        self.assertEqual(v["appearance"]["glassAlpha"], 0.88)
        self.assertEqual(v["appearance"]["targets"]["kitty"], True)
        self.assertEqual(v["hypr"]["borders"]["custom"]["angle"], 45)
        self.assertIsNone(v["appearance"]["accent"])
        self.assertFalse(os.path.exists(self.sfile))  # get ничего не создаёт

    def test_get_key_prefix_unknown(self):
        _, _, r = self.run_cli("get", "appearance.radius")
        self.assertEqual((r["value"], r["default"], r["isDefault"]), (12, 12, True))
        _, _, r = self.run_cli("get", "hypr.borders")
        self.assertEqual(sorted(r["values"]), ["custom", "size", "style"])
        _, _, r = self.run_cli("get", "binds.launcher")
        self.assertIsNone(r["value"])
        code, _, r = self.run_cli("get", "nope.key")
        self.assertEqual((code, r["ok"]), (2, False))

    def test_get_reflects_file(self):
        self.run_cli("set", "appearance.radius=4", "--no-apply")
        _, _, r = self.run_cli("get", "appearance.radius")
        self.assertEqual((r["value"], r["isDefault"]), (4, False))


class SetTests(CliCase):
    def test_set_no_apply_sparse(self):
        code, _, r = self.run_cli("set", "appearance.glassAlpha=0.8", "appearance.accent=#7AA2F7", "--no-apply")
        self.assertEqual(code, 0)
        self.assertTrue(r["ok"])
        self.assertEqual(sorted(r["keys"]), ["appearance.accent", "appearance.glassAlpha"])
        self.assertIn("quickshell", r["targets"])
        self.assertEqual(self.file_json(),
                         {"version": 1, "appearance": {"accent": "#7aa2f7", "glassAlpha": 0.8}})

    def test_set_default_removes_key(self):
        self.run_cli("set", "appearance.radius=5", "--no-apply")
        self.run_cli("set", "appearance.radius=12", "--no-apply")
        self.assertEqual(self.file_json(), {"version": 1})

    def test_noop_does_not_write_or_touch_history(self):
        code, _, r = self.run_cli("set", "appearance.radius=12", "--no-apply")
        self.assertEqual((code, r["keys"]), (0, []))
        self.assertFalse(os.path.exists(self.sfile))
        self.assertEqual(self.history(), [])

    def test_value_parsing_json_then_string(self):
        self.run_cli("set", "apps.terminal=foot", "appearance.targets.kitty=false",
                     'binds.launcher=["SUPER + R","SUPER + space"]', "--no-apply")
        f = self.file_json()
        self.assertEqual(f["apps"]["terminal"], "foot")
        self.assertIs(f["appearance"]["targets"]["kitty"], False)
        self.assertEqual(f["binds"]["launcher"], ["SUPER + R", "SUPER + space"])
        self.run_cli("set", 'apps.terminal="kitty"', "--no-apply")  # JSON-строка == дефолт -> ключ убран
        self.assertNotIn("apps", self.file_json())

    def test_value_with_equals_sign(self):
        self.run_cli("set", "apps.terminal=kitty -o a=b", "--no-apply")
        self.assertEqual(self.file_json()["apps"]["terminal"], "kitty -o a=b")

    def test_invalid_values_exit2_and_file_untouched(self):
        self.run_cli("set", "appearance.radius=5", "--no-apply")
        before = self.raw()
        for arg in ("appearance.glassAlpha=0.1", "appearance.glassAlpha=abc", "appearance.radius=1.5",
                    "appearance.accent=red", "hypr.borders.style=zig", "appearance.targets.kitty=1",
                    "appearance.radius=NaN", "appearance.radius=null"):
            with self.subTest(arg=arg):
                code, _, r = self.run_cli("set", arg, "--no-apply")
                self.assertEqual(code, 2)
                self.assertFalse(r["ok"])
                self.assertEqual(r["errors"][0]["key"], arg.split("=")[0])
        self.assertEqual(self.raw(), before)

    def test_unknown_key_and_missing_equals(self):
        code, _, r = self.run_cli("set", "nope=1", "--no-apply")
        self.assertEqual(code, 2)
        self.assertEqual(r["errors"][0]["error"], "unknown key")
        code, _, r = self.run_cli("set", "appearance.radius", "--no-apply")
        self.assertEqual(code, 2)

    def test_transaction_all_or_nothing(self):
        code, _, r = self.run_cli("set", "appearance.radius=5", "appearance.glassAlpha=9", "--no-apply")
        self.assertEqual(code, 2)
        self.assertFalse(os.path.exists(self.sfile))
        self.assertEqual(len(r["errors"]), 1)

    def test_one_write_one_history_entry_per_transaction(self):
        self.run_cli("set", "appearance.radius=5", "appearance.windowRounding=3", "hypr.borders.size=1", "--no-apply")
        self.assertEqual(len(self.history()), 1)

    def test_template_keys(self):
        code, _, r = self.run_cli("set", "appearance.targets.gtk3=false", "binds.notifs=[\"SUPER + K\"]", "--no-apply")
        self.assertEqual(code, 0)
        code, _, r = self.run_cli("set", "appearance.targets.nosuch=false", "--no-apply")
        self.assertEqual(code, 2)
        code, _, r = self.run_cli("set", "binds.bad.name=[]", "--no-apply")
        self.assertEqual(code, 2)
        code, _, r = self.run_cli("set", "binds.x=\"SUPER\"", "--no-apply")  # не массив
        self.assertEqual(code, 2)
        _, _, r = self.run_cli("get", "appearance.targets.gtk3")
        self.assertIs(r["value"], False)

    def test_object_value(self):
        v = {"active": ["rgba(112233ff)"], "angle": 10, "inactive": "rgba(44556677)"}
        code, _, _ = self.run_cli("set", "hypr.borders.custom=" + json.dumps(v), "--no-apply")
        self.assertEqual(code, 0)
        self.assertEqual(self.file_json()["hypr"]["borders"]["custom"], v)

    def test_dry_run_writes_nothing(self):
        code, _, r = self.run_cli("set", "appearance.radius=5", "--dry-run")
        self.assertEqual((code, r["keys"]), (0, ["appearance.radius"]))
        self.assertFalse(os.path.exists(self.sfile))

    def test_set_with_apply_not_implemented_but_saved(self):
        with mock.patch.object(cli, "_import_hook", return_value=None):
            code, _, r = self.run_cli("set", "appearance.radius=5")
        self.assertEqual(code, 1)
        self.assertFalse(r["ok"])
        self.assertIn("not implemented", r["errors"][0]["error"])
        self.assertEqual(self.file_json()["appearance"]["radius"], 5)

    def test_set_without_targets_needs_no_apply(self):
        code, _, r = self.run_cli("set", "network.confirmDisruptive=false")
        self.assertEqual((code, r["ok"], r["targets"]), (0, True, []))

    def test_apply_hook_result_merged(self):
        calls = []

        def fake(paths, targets, **kw):
            calls.append((targets, kw))
            return {"changed": ["gtk3"], "restart": ["zen"], "errors": [], "backup": "B1"}
        with mock.patch.object(cli, "_import_hook", return_value=fake):
            code, _, r = self.run_cli("set", "appearance.radius=5", "--no-exec")
        self.assertEqual(code, 0)
        self.assertEqual((r["changed"], r["restart"], r["backup"]), (["gtk3"], ["zen"], "B1"))
        self.assertTrue(calls[0][1]["no_exec"])
        self.assertIn("gtk3", calls[0][0])

    def test_symlinked_settings_file_stays_symlink(self):
        real = os.path.join(self.tmp, "elsewhere.json")
        with open(real, "w") as f:
            f.write('{"version": 1}\n')
        os.symlink(real, self.sfile)
        self.run_cli("set", "appearance.radius=5", "--no-apply")
        self.assertTrue(os.path.islink(self.sfile))
        with open(real) as f:
            self.assertEqual(json.load(f)["appearance"]["radius"], 5)

    def test_corrupt_settings_exit5(self):
        with open(self.sfile, "w") as f:
            f.write("{nope")
        code, _, r = self.run_cli("set", "appearance.radius=5", "--no-apply")
        self.assertEqual((code, r["ok"]), (5, False))
        with open(self.sfile) as f:
            self.assertEqual(f.read(), "{nope")


class ResetUndoTests(CliCase):
    def test_reset(self):
        self.run_cli("set", "appearance.radius=5", "appearance.glassAlpha=0.7", "apps.terminal=foot", "--no-apply")
        code, _, r = self.run_cli("reset", "appearance.radius", "--no-apply")
        self.assertEqual((code, r["keys"]), (0, ["appearance.radius"]))
        self.assertNotIn("radius", self.file_json()["appearance"])
        code, _, r = self.run_cli("reset", "appearance", "--no-apply")  # префикс
        self.assertEqual(r["keys"], ["appearance.glassAlpha"])
        self.assertEqual(self.file_json(), {"version": 1, "apps": {"terminal": "foot"}})
        code, _, r = self.run_cli("reset", "appearance.radius", "--no-apply")  # уже дефолт
        self.assertEqual((code, r["keys"]), (0, []))
        code, _, r = self.run_cli("reset", "nope", "--no-apply")
        self.assertEqual(code, 2)

    def test_undo_walks_back_and_restores_bytes(self):
        self.run_cli("set", "appearance.radius=5", "--no-apply")
        a = self.raw()
        self.run_cli("set", "appearance.glassAlpha=0.7", "--no-apply")
        self.run_cli("reset", "appearance.radius", "--no-apply")
        code, _, r = self.run_cli("undo", "--no-apply")
        self.assertEqual((code, r["keys"]), (0, ["appearance.radius"]))
        self.assertEqual(self.file_json()["appearance"], {"radius": 5, "glassAlpha": 0.7})
        self.run_cli("undo", "--no-apply")
        self.assertEqual(self.raw(), a)
        self.run_cli("undo", "--no-apply")
        self.assertEqual(self.file_json(), {"version": 1})  # состояние до первой записи
        code, _, r = self.run_cli("undo", "--no-apply")
        self.assertEqual((code, r["ok"]), (2, False))

    def test_undo_triggers_apply_hook(self):
        self.run_cli("set", "appearance.radius=5", "--no-apply")
        seen = []
        with mock.patch.object(cli, "_import_hook", return_value=lambda p, t, **kw: seen.append(t) or {}):
            code, _, r = self.run_cli("undo")
        self.assertEqual(code, 0)
        self.assertIn("gtk3", seen[0])


class OtherCommandTests(CliCase):
    def test_stubs_not_implemented(self):
        with mock.patch.object(cli, "_import_hook", return_value=None):
            for cmd in ("apply", "status", "doctor"):
                with self.subTest(cmd=cmd):
                    code, _, r = self.run_cli(cmd)
                    self.assertEqual((code, r["ok"]), (5, False))
                    self.assertIn("not implemented", r["errors"][0]["error"])
        code, _, r = self.run_cli("monitors", "snapshot", "--no-exec")
        self.assertEqual(code, 0)
        self.assertTrue(r["ok"])

    def test_usage_error_is_json_exit2(self):
        code, _, r = self.run_cli("bogus")
        self.assertEqual((code, r["ok"]), (2, False))
        code, _, r = self.run_cli("set")
        self.assertEqual(code, 2)

    def test_open_no_exec_and_sections(self):
        code, _, r = self.run_cli("open", "--no-exec")
        self.assertEqual(r["command"][-2:], ["settings", "open"])
        code, _, r = self.run_cli("open", "devices/display", "--no-exec")
        self.assertEqual(r["command"][-3:], ["settings", "openAt", "devices/display"])
        self.assertTrue(r["command"][2].endswith(".config/quickshell/zephyrine"))
        code, _, r = self.run_cli("open", "bogus", "--no-exec")
        self.assertEqual(code, 2)

    def _fake_qs(self, body):
        p = os.path.join(self.tmp, "fakeqs")
        with open(p, "w") as f:
            f.write("#!/bin/sh\n" + body)
        os.chmod(p, 0o755)
        return p

    def test_open_runs_qs_and_detects_errors(self):
        log = os.path.join(self.tmp, "qs.log")
        qs = self._fake_qs('echo "$@" > %s\n' % log)
        with mock.patch.dict(os.environ, {"ZEPHYRINE_QS": qs}):
            code, _, r = self.run_cli("open", "network/wifi")
        self.assertEqual(code, 0)
        with open(log) as f:
            self.assertTrue(f.read().strip().endswith("ipc call settings openAt network/wifi"))
        qs = self._fake_qs('echo "Too few arguments provided"\n')  # IPC печатает ошибку, код 0
        with mock.patch.dict(os.environ, {"ZEPHYRINE_QS": qs}):
            code, _, r = self.run_cli("open")
        self.assertEqual((code, r["ok"]), (1, False))
        with mock.patch.dict(os.environ, {"ZEPHYRINE_QS": os.path.join(self.tmp, "absent")}):
            code, _, r = self.run_cli("open")
        self.assertEqual(code, 1)

    def test_backup_commands(self):
        code, _, r = self.run_cli("backup", "list")
        self.assertEqual((code, r["backups"]), (0, []))
        code, _, r = self.run_cli("backup", "restore", "../x")
        self.assertEqual(code, 2)
        from zsettings import backup
        from zsettings.util import Paths
        f = os.path.join(self.tmp, "f.txt")
        with open(f, "w") as fh:
            fh.write("v1")
        bid = backup.create(Paths.from_env(), [f], "test")
        with open(f, "w") as fh:
            fh.write("v2")
        code, _, r = self.run_cli("backup", "list")
        self.assertEqual(r["backups"][0]["id"], bid)
        code, _, r = self.run_cli("backup", "restore", bid)
        self.assertEqual(code, 0)
        with open(f) as fh:
            self.assertEqual(fh.read(), "v1")


class ProcessTests(CliCase):
    """Через настоящий bin/zephyrine-settings (отдельные процессы)."""

    def sub_env(self, **extra):
        env = dict(os.environ)
        env.update(extra)
        return env

    def run_bin(self, *argv, **extra):
        return subprocess.run([BIN, *argv], capture_output=True, text=True, env=self.sub_env(**extra))

    def test_bin_is_executable_and_one_line(self):
        self.assertTrue(os.stat(BIN).st_mode & stat.S_IXUSR)
        r = self.run_bin("set", "appearance.radius=7", "--no-apply")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(r.stdout.splitlines()), 1)
        self.assertEqual(json.loads(r.stdout)["keys"], ["appearance.radius"])

    def test_concurrent_writes_lose_nothing(self):
        ids = ["gtk3", "gtk4", "kitty", "zed", "zathura", "obsidian", "qt6ct", "hypr", "tb-css", "zen-chrome"]
        procs = [subprocess.Popen([BIN, "set", "appearance.targets.%s=false" % i, "--no-apply"],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=self.sub_env())
                 for i in ids]
        for p in procs:
            out, err = p.communicate(timeout=60)
            self.assertEqual(p.returncode, 0, out + err)
        got = self.file_json()["appearance"]["targets"]
        self.assertEqual(sorted(got), sorted(ids))
        self.assertTrue(all(v is False for v in got.values()))
        self.assertEqual(len(self.history()), len(ids))
        # файл целый, временных остатков нет
        self.assertEqual([n for n in os.listdir(os.path.dirname(self.sfile)) if n.endswith(".tmp")], [])

    def test_concurrent_same_key_final_value_valid(self):
        procs = [subprocess.Popen([BIN, "set", "appearance.radius=%d" % i, "--no-apply"],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=self.sub_env())
                 for i in range(1, 9)]
        for p in procs:
            p.communicate(timeout=60)
            self.assertEqual(p.returncode, 0)
        self.assertIn(self.file_json()["appearance"]["radius"], range(1, 9))

    def test_lock_busy_exit3(self):
        os.makedirs(self.state, exist_ok=True)
        fd = os.open(os.path.join(self.state, "settings.lock"), os.O_RDWR | os.O_CREAT)
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            r = self.run_bin("set", "appearance.radius=5", "--no-apply", ZEPHYRINE_LOCK_TIMEOUT="0.3")
            self.assertEqual(r.returncode, 3)
            self.assertFalse(json.loads(r.stdout)["ok"])
            r = self.run_bin("get")  # чтение не блокируется
            self.assertEqual(r.returncode, 0)
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
        self.assertFalse(os.path.exists(self.sfile))


if __name__ == "__main__":
    unittest.main()
