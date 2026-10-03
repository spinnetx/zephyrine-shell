"""Тесты управления мониторами (zsettings/monitors.py)."""
import json
import os
import shutil
import tempfile
import unittest

from zsettings import hypr, model, monitors
from zsettings.util import Paths

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)

SAMPLE_HYPRCTL_OUTPUT = json.dumps([{
    "id": 0,
    "name": "eDP-1",
    "description": "Najing CEC Panda FPD Technology CO. ltd 0x0050",
    "make": "Najing CEC Panda FPD Technology CO. ltd",
    "model": "0x0050",
    "width": 1920,
    "height": 1080,
    "refreshRate": 60.002,
    "x": 0,
    "y": 0,
    "scale": 1.0,
    "transform": 0,
    "disabled": False,
    "mirrorOf": "none",
    "availableModes": ["1920x1080@60.00Hz", "1280x720@60.00Hz"],
    "focused": True
}])


class MockCompletedProcess:
    def __init__(self, stdout="", returncode=0, stderr=""):
        self.stdout = stdout
        self.returncode = returncode
        self.stderr = stderr


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="zs-test-mon-")
        self.home = os.path.join(self.tmp, "home")
        self.state = os.path.join(self.home, ".local", "state", "zephyrine")
        self.root = os.path.join(self.tmp, "repo")
        os.makedirs(self.state, exist_ok=True)
        os.makedirs(os.path.join(self.root, "settings"), exist_ok=True)
        os.makedirs(os.path.join(self.root, ".config", "hypr"), exist_ok=True)
        os.makedirs(os.path.join(self.root, "quickshell"), exist_ok=True)

        shutil.copy(os.path.join(SETTINGS_DIR, "schema.json"), os.path.join(self.root, "settings", "schema.json"))
        shutil.copy(os.path.join(SETTINGS_DIR, "targets.json"), os.path.join(self.root, "settings", "targets.json"))
        shutil.copy(os.path.join(SETTINGS_DIR, "palette-roles.json"), os.path.join(self.root, "settings", "palette-roles.json"))
        shutil.copy(os.path.join(SETTINGS_DIR, "settings.json"), os.path.join(self.root, "settings", "settings.json"))
        shutil.copy(os.path.join(os.path.dirname(SETTINGS_DIR), "quickshell", "scheme.json"),
                    os.path.join(self.root, "quickshell", "scheme.json"))

        self.paths = Paths.from_env({
            "HOME": self.home,
            "ZEPHYRINE_ROOT": self.root,
            "ZEPHYRINE_STATE": self.state
        })
        self.calls = []

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def mock_runner(self, cmd):
        self.calls.append(cmd)
        if cmd[:3] == ["hyprctl", "monitors", "all"]:
            return MockCompletedProcess(stdout=SAMPLE_HYPRCTL_OUTPUT)
        return MockCompletedProcess(stdout="ok", returncode=0)

    def test_snapshot_parses_monitors(self):
        res = monitors.snapshot(self.paths, runner=self.mock_runner)
        self.assertEqual(len(res), 1)
        m = res[0]
        self.assertEqual(m["name"], "eDP-1")
        self.assertEqual(m["width"], 1920)
        self.assertEqual(m["match"], "desc:Najing CEC Panda FPD Technology CO. ltd 0x0050")

    def test_validate_spec_rejects_disabling_all(self):
        cur = monitors.snapshot(self.paths, runner=self.mock_runner)
        bad_spec = [{"match": cur[0]["match"], "disabled": True}]
        with self.assertRaises(monitors.MonitorError) as ctx:
            monitors.validate_spec(cur, bad_spec)
        self.assertIn("Нельзя отключить все мониторы", str(ctx.exception))

    def test_validate_spec_rejects_too_small_resolution(self):
        cur = monitors.snapshot(self.paths, runner=self.mock_runner)
        # Scale 3.0 on 1920x1080 gives 640x360 (< 1024x600)
        bad_spec = [{"match": cur[0]["match"], "scale": 3.0}]
        with self.assertRaises(monitors.MonitorError) as ctx:
            monitors.validate_spec(cur, bad_spec)
        self.assertIn("Слишком мелкий масштаб", str(ctx.exception))

    def test_try_config_and_confirm(self):
        spec = [{"match": "eDP-1", "mode": "1920x1080@60", "scale": 1.25, "position": "0x0"}]
        res = monitors.try_config(self.paths, spec, timeout_sec=10, runner=self.mock_runner)
        self.assertTrue(res["ok"])
        token = res["token"]
        self.assertEqual(res["timeoutSec"], 10)

        # Check pending file created
        pending_file = os.path.join(self.state, "monitor-pending.json")
        self.assertTrue(os.path.exists(pending_file))

        # Confirm
        res2 = monitors.confirm(self.paths, token, runner=self.mock_runner)
        self.assertTrue(res2["ok"])
        self.assertFalse(os.path.exists(pending_file))

        # Verify settings.json updated
        with open(self.paths.settings_file, encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(data.get("display", {}).get("monitors"), spec)

        # Verify settings.lua emitted with hl.monitor
        lua_path = os.path.join(self.root, ".config", "hypr", "settings.lua")
        self.assertTrue(os.path.exists(lua_path))
        with open(lua_path, encoding="utf-8") as f:
            lua_txt = f.read()
        self.assertIn('hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1.25 })', lua_txt)

    def test_revert_removes_pending(self):
        spec = [{"match": "eDP-1", "scale": 1.0}]
        res = monitors.try_config(self.paths, spec, timeout_sec=10, runner=self.mock_runner)
        token = res["token"]
        pending_file = os.path.join(self.state, "monitor-pending.json")
        self.assertTrue(os.path.exists(pending_file))

        rev = monitors.revert(self.paths, token, runner=self.mock_runner)
        self.assertTrue(rev["ok"])
        self.assertFalse(os.path.exists(pending_file))

    def test_cmd_monitors_cli_envelope_regression(self):
        """Регрессионный тест: cmd_monitors не должен падать с TypeError при вызове envelope."""
        from zsettings import cli
        class Args:
            action = "try"
            payload = json.dumps([{"match": "eDP-1", "scale": 1.25}])
            timeout = 15
            no_exec = True
        code, env = cli.cmd_monitors(Args(), self.paths)
        self.assertEqual(code, 0, "CLI try command must exit with 0")
        self.assertTrue(env["ok"])
        self.assertIn("token", env)

        class ConfirmArgs:
            action = "confirm"
            payload = env["token"]
            no_exec = True
        code2, env2 = cli.cmd_monitors(ConfirmArgs(), self.paths)
        self.assertEqual(code2, 0, "CLI confirm command must exit with 0")
        self.assertTrue(env2["ok"])


if __name__ == "__main__":
    unittest.main()
