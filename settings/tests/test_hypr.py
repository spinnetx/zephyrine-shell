"""Тесты эмиттера zsettings/hypr.py (S1.8): текст, ветки стилей, luac -p, прогон в mock_hl.lua,
эквивалентность живому hyprland.lua при дефолтах, блок подключения из patches/hyprland-settings.patch.

Всё в `tempfile.TemporaryDirectory(prefix="zs-s18-")`; живой hyprctl/Hyprland и реальный ~/.config не
затрагиваются (живой hyprland.lua только читается, в мок). Тесты, которым нужен `lua`/`luac`, пропускаются без них.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)
sys.path.insert(0, SETTINGS_DIR)

from zsettings import hypr, model, palette  # noqa: E402
from zsettings.util import Paths  # noqa: E402

REAL_ROOT = os.path.dirname(SETTINGS_DIR)
MOCK = os.path.join(HERE, "mock_hl.lua")
PATCH = os.path.join(SETTINGS_DIR, "patches", "hyprland-settings.patch")
LIVE = os.path.join(REAL_ROOT, ".config", "hypr", "hyprland.lua")
LUA = shutil.which("lua")
LUAC = shutil.which("luac")

DEFAULT_TEXT = (
    "-- СГЕНЕРИРОВАНО zephyrine-settings из settings/settings.json. Не править вручную.\n"
    "hl.config({ decoration = { rounding = 10 } })\n"
    "hl.config({ general = { border_size = 2, col = {\n"
    '    active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },\n'
    '    inactive_border = "rgba(595959aa)" } } })\n'
    "-- hyprglass: ключи плагина есть только после его загрузки\n"
    "if hl.plugin and hl.plugin.hyprglass then hl.plugin.hyprglass.config({ glass_opacity = 0.7 }) end\n"
    "-- Режим окон: тайловый (hypr.windowMode). Заголовки hyprbars только у плавающих окон\n"
    'hl.window_rule({ name = "default-floating-mode", enabled = false })\n'
    'hl.window_rule({ name = "hyprbars-floating-only", match = { float = false }, ["hyprbars:no_bar"] = true, enabled = true })\n'
)


def _kit():
    """-> (paths, schema defaults, scheme, roles) на реальных схеме/палитре репо (только чтение)."""
    paths = Paths.from_env({"HOME": "/nonexistent-home", "ZEPHYRINE_ROOT": REAL_ROOT})
    schema = model.Schema.load(paths.schema_file, paths.targets_file)
    scheme, roles = palette.load_inputs(paths)
    return paths, schema.defaults_flat(), scheme, roles


PATHS, DEFAULTS, SCHEME, ROLES = _kit()


def ctx_for(values):
    return palette.build_context(SCHEME, ROLES, values, DEFAULTS)


def eff(over=None):
    v = dict(DEFAULTS)
    v.update(over or {})
    return v


def gen(over=None):
    v = eff(over)
    return hypr.emit(v, ctx_for(v), PATHS)


class EmitText(unittest.TestCase):
    def test_default_text_exact(self):
        self.assertEqual(gen(), DEFAULT_TEXT)

    def test_deterministic_and_trailing_newline(self):
        self.assertEqual(gen(), gen())
        self.assertTrue(gen().endswith("\n"))
        self.assertNotIn("{{", gen())

    def test_values_without_optional_keys_use_defaults(self):
        self.assertEqual(hypr.emit({}, ctx_for(DEFAULTS), PATHS), gen())

    def test_autostart_lines(self):
        t = gen({"autostart": [
            {"id": "test", "name": "Test", "cmd": "test-cmd", "enabled": True, "delaySec": 0},
            {"id": "delayed", "name": "Delayed", "cmd": "delayed-cmd", "enabled": True, "delaySec": 5},
            {"id": "disabled", "name": "Disabled", "cmd": "off", "enabled": False, "delaySec": 0},
        ]})
        self.assertIn('-- Автозапуск (autostart): управляемый список центра настроек\n', t)
        self.assertIn('hl.on("hyprland.start", function()\n', t)
        self.assertIn('    hl.exec_cmd("test-cmd")\n', t)
        self.assertIn('    hl.exec_cmd("sleep 5 && delayed-cmd")\n', t)
        self.assertNotIn('hl.exec_cmd("off")', t)

    def test_rounding_size_glass(self):
        t = gen({"appearance.windowRounding": 0, "hypr.borders.size": 4, "hypr.glassOpacity": 0.55})
        self.assertIn("rounding = 0 }", t)
        self.assertIn("border_size = 4,", t)
        self.assertIn("glass_opacity = 0.55 }", t)
        t = gen({"appearance.windowRounding": 20, "hypr.borders.size": 0, "hypr.glassOpacity": 1})
        self.assertIn("rounding = 20 }", t)
        self.assertIn("border_size = 0,", t)
        self.assertIn("glass_opacity = 1.0 }", t)

    def test_style_accent_uses_palette(self):
        t = gen({"hypr.borders.style": "accent"})
        self.assertIn('{ "rgba(bb9af7ee)", "rgba(7aa2f7ee)" }, angle = 45', t)
        self.assertIn('inactive_border = "rgba(41466aaa)"', t)

    def test_style_accent_follows_accent_override(self):
        t = gen({"hypr.borders.style": "accent", "appearance.accent": "#ff00ff"})
        self.assertIn('"rgba(ff00ffee)", "rgba(7aa2f7ee)"', t)

    def test_style_custom(self):
        custom = {"active": ["rgba(112233FF)"], "angle": 90, "inactive": "rgba(445566AA)"}
        t = gen({"hypr.borders.style": "custom", "hypr.borders.custom": custom})
        self.assertIn('active_border = { colors = { "rgba(112233ff)" }, angle = 90 }', t)
        self.assertIn('inactive_border = "rgba(445566aa)"', t)

    def test_legacy_ignores_custom(self):
        custom = {"active": ["rgba(112233ff)"], "angle": 1, "inactive": "rgba(445566aa)"}
        self.assertEqual(gen({"hypr.borders.custom": custom}), gen())

    def test_invalid_values_rejected(self):
        bad = [
            {"appearance.windowRounding": 21}, {"appearance.windowRounding": -1}, {"appearance.windowRounding": 1.5},
            {"appearance.windowRounding": True}, {"hypr.borders.size": 5}, {"hypr.glassOpacity": 0.2},
            {"hypr.glassOpacity": "0.7"}, {"hypr.borders.style": "rainbow"},
            {"hypr.borders.style": "custom", "hypr.borders.custom": {"active": [], "angle": 45, "inactive": "rgba(00000000)"}},
            {"hypr.borders.style": "custom", "hypr.borders.custom": {"active": ['x"]})--'], "angle": 45, "inactive": "rgba(00000000)"}},
            {"hypr.borders.style": "custom", "hypr.borders.custom": {"active": ["rgba(00000000)"], "angle": 400, "inactive": "rgba(00000000)"}},
            {"hypr.borders.style": "custom", "hypr.borders.custom": {"active": ["rgba(00000000)"], "angle": 1, "inactive": "red"}},
            {"hypr.windowMode": "tabs"}, {"hypr.windowMode": 123},
        ]
        for over in bad:
            with self.subTest(over=over):
                with self.assertRaises(hypr.HyprError):
                    gen(over)

    def test_window_mode_tile_and_float(self):
        t_tile = gen({"hypr.windowMode": "tile"})
        self.assertEqual(t_tile, DEFAULT_TEXT)
        self.assertIn('hl.window_rule({ name = "default-floating-mode", enabled = false })', t_tile)
        self.assertIn('hl.window_rule({ name = "hyprbars-floating-only", match = { float = false }, ["hyprbars:no_bar"] = true, enabled = true })', t_tile)

        t_float = gen({"hypr.windowMode": "float"})
        self.assertIn('-- Режим окон: плавающие окна (hypr.windowMode). Заголовки hyprbars всегда включены\n', t_float)
        self.assertIn('hl.window_rule({ name = "default-floating-mode", match = { class = ".*" }, float = true, enabled = true })', t_float)
        self.assertIn('hl.window_rule({ name = "hyprbars-floating-only", enabled = false })', t_float)

        with self.assertRaises(hypr.HyprError):
            gen({"hypr.windowMode": "unknown"})

    def test_window_mode_hyprbars_titlebar_visibility_regression(self):
        """Регрессионный тест:
        В режиме 'float' (плавающие окна) заголовок показывается всегда (hyprbars-floating-only отключен).
        В режиме 'tile' (тайловый) заголовок показывается только у плавающих окон (hyprbars-floating-only активен).
        """
        code_float = gen({"hypr.windowMode": "float"})
        self.assertIn('hl.window_rule({ name = "default-floating-mode", match = { class = ".*" }, float = true, enabled = true })', code_float)
        self.assertIn('hl.window_rule({ name = "hyprbars-floating-only", enabled = false })', code_float)
        # В режиме float правило no_bar не должно активироваться
        self.assertNotIn('["hyprbars:no_bar"] = true, enabled = true', code_float)

        code_tile = gen({"hypr.windowMode": "tile"})
        self.assertIn('hl.window_rule({ name = "default-floating-mode", enabled = false })', code_tile)
        self.assertIn('hl.window_rule({ name = "hyprbars-floating-only", match = { float = false }, ["hyprbars:no_bar"] = true, enabled = true })', code_tile)

    def test_lua_str_escaping(self):
        self.assertEqual(hypr.lua_str('a"b\\c\nd'), '"a\\"b\\\\c\\nd"')

    def test_stable_numbers(self):
        self.assertEqual(hypr.lua_num(0.7, 0.3, 1.0, "x"), "0.7")
        self.assertEqual(hypr.lua_num(1, 0.3, 1.0, "x"), "1.0")
        self.assertEqual(hypr.lua_num(0.30000000000000004, 0.3, 1.0, "x"), "0.3")


@unittest.skipUnless(LUAC, "luac не найден")
class Syntax(unittest.TestCase):
    def test_luac_p_on_variants(self):
        variants = [None, {"hypr.borders.style": "accent", "appearance.accent": "#7aa2f7"},
                    {"hypr.borders.style": "custom", "hypr.borders.custom": {
                        "active": ["rgba(112233ff)", "rgba(445566ff)", "rgba(778899ff)"], "angle": 360,
                        "inactive": "rgba(00000000)"}},
                    {"appearance.windowRounding": 0, "hypr.borders.size": 0, "hypr.glassOpacity": 0.3}]
        with tempfile.TemporaryDirectory(prefix="zs-s18-") as td:
            for i, over in enumerate(variants):
                f = os.path.join(td, "v%d.lua" % i)
                with open(f, "w", encoding="utf-8") as fh:
                    fh.write(gen(over))
                r = subprocess.run([LUAC, "-p", f], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, r.stderr)


def run_mock(files, plugin=True, env=None):
    cmd = [LUA, MOCK] + (["--plugin"] if plugin else []) + list(files)
    r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=30, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        raise AssertionError("mock_hl: %s" % r.stderr)
    d = json.loads(r.stdout)
    d["config"] = d["config"] or {}
    d["calls"] = d["calls"] or []
    return d


@unittest.skipUnless(LUA and os.path.isfile(MOCK), "lua не найден")
class MockRun(unittest.TestCase):
    def setUp(self):
        td = tempfile.TemporaryDirectory(prefix="zs-s18-")
        self.addCleanup(td.cleanup)
        self.tmp = td.name

    def lua(self, text, name="settings.lua"):
        p = os.path.join(self.tmp, name)
        with open(p, "w", encoding="utf-8") as f:
            f.write(text)
        return p

    def test_default_calls_and_state(self):
        d = run_mock([self.lua(gen())])
        self.assertEqual(d["errors"], [])
        self.assertEqual([c["fn"] for c in d["calls"]],
                         ["config", "config", "plugin.hyprglass.config", "window_rule", "window_rule"])
        self.assertEqual(d["config"], {
            "decoration.rounding": 10,
            "general.border_size": 2,
            "general.col.active_border": {"colors": ["rgba(33ccffee)", "rgba(00ff99ee)"], "angle": 45},
            "general.col.inactive_border": "rgba(595959aa)",
            "plugin.hyprglass.glass_opacity": 0.7,
        })
        d_auto = run_mock([self.lua(gen({"autostart": [{"id": "x", "name": "X", "cmd": "true", "enabled": True, "delaySec": 0}]}))])
        self.assertIn("on", [c["fn"] for c in d_auto["calls"]])

    def test_without_plugin_no_glass_call(self):
        d = run_mock([self.lua(gen())], plugin=False)
        self.assertEqual(d["errors"], [])
        self.assertNotIn("plugin.hyprglass.config", [c["fn"] for c in d["calls"]])
        self.assertNotIn("plugin.hyprglass.glass_opacity", d["config"])

    def test_nondefault_changes_state(self):
        d = run_mock([self.lua(gen({"appearance.windowRounding": 14, "hypr.borders.size": 3,
                                    "hypr.borders.style": "accent", "hypr.glassOpacity": 0.5}))])
        self.assertEqual(d["errors"], [])
        c = d["config"]
        self.assertEqual((c["decoration.rounding"], c["general.border_size"], c["plugin.hyprglass.glass_opacity"]),
                         (14, 3, 0.5))
        self.assertEqual(c["general.col.active_border"]["colors"], ["rgba(bb9af7ee)", "rgba(7aa2f7ee)"])

    def test_partial_glass_call_keeps_other_plugin_keys_in_mock(self):
        base = self.lua('hl.plugin.hyprglass.config({ glass_opacity = 0.7, dark = { brightness = 1.0 } })', "base.lua")
        d = run_mock([base, self.lua(gen({"hypr.glassOpacity": 0.4}))])
        self.assertEqual(d["config"]["plugin.hyprglass.glass_opacity"], 0.4)
        self.assertEqual(d["config"]["plugin.hyprglass.dark.brightness"], 1)

    @unittest.skipUnless(os.path.isfile(LIVE), "нет живого hyprland.lua в репо")
    def test_defaults_do_not_change_live_config_state(self):
        """hyprland.lua (как есть) -> состояние A; затем settings.lua по умолчанию -> состояние B; A == B."""
        # герметично: пустой XDG_CONFIG_HOME, чтобы блок подключения в hyprland.lua не подтянул
        # настоящий ~/.config/hypr/settings.lua с пользовательскими значениями
        env = dict(os.environ, XDG_CONFIG_HOME=self.tmp)
        a = run_mock([LIVE], env=env)
        if a["errors"]:
            self.skipTest("hyprland.lua не исполняется в моке: %s" % a["errors"])
        b = run_mock([LIVE, self.lua(gen())], env=env)
        self.assertEqual(b["errors"], [])
        owned = ["decoration.rounding", "general.border_size", "general.col.active_border",
                 "general.col.inactive_border", "plugin.hyprglass.glass_opacity"]
        for k in owned:
            with self.subTest(key=k):
                self.assertIn(k, a["config"])
                self.assertEqual(b["config"][k], a["config"][k])
        self.assertEqual(b["config"], a["config"])  # и ничего лишнего (например dark.*) не изменилось


def patch_added_lines():
    with open(PATCH, encoding="utf-8") as f:
        return [ln[1:] for ln in f.read().splitlines() if ln.startswith("+") and not ln.startswith("+++")]


def dofile_block():
    lines = patch_added_lines()
    start = max(i for i, ln in enumerate(lines) if ln == "do")
    return "\n".join(lines[start:]) + "\n"


@unittest.skipUnless(os.path.isfile(PATCH), "нет patches/hyprland-settings.patch")
class PatchContent(unittest.TestCase):
    def test_added_text(self):
        added = "\n".join(patch_added_lines())
        for needle in ('hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(qsIpc .. "settings toggle"), { description = "zp:settings · Центр управления" })',
                       'name  = "zephyrine-settings"', 'match = { title = "^Zephyrine · (Центр управления|Настройки)$" }',
                       'size   = "1040 700"', "center = true", "float  = true", "pcall(dofile, path)"):
            self.assertIn(needle, added)

    def test_patch_removes_nothing(self):
        with open(PATCH, encoding="utf-8") as f:
            body = f.read().split("\n--- ", 1)[1]
        self.assertEqual([ln for ln in body.splitlines() if ln.startswith("-") and not ln.startswith("---")], [])

    @unittest.skipUnless(shutil.which("patch"), "patch не найден")
    def test_applies_to_live_file(self):
        if not os.path.isfile(LIVE):
            self.skipTest("нет живого hyprland.lua")
        with tempfile.TemporaryDirectory(prefix="zs-s18-") as td:
            d = os.path.join(td, ".config", "hypr")
            os.makedirs(d)
            shutil.copy(LIVE, d)
            with open(os.path.join(d, "hyprland.lua"), encoding="utf-8") as f:
                applied = "zephyrine-settings" in f.read()
            args = ["patch", "-p1", "--dry-run", "-d", td] + (["-R"] if applied else [])
            with open(PATCH, "rb") as pf:
                r = subprocess.run(args, stdin=pf, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


@unittest.skipUnless(LUA and os.path.isfile(PATCH), "lua или патч не найдены")
class DofileBlock(unittest.TestCase):
    """Блок подключения из патча в моке: файла нет / обычный / сломанный."""

    def setUp(self):
        td = tempfile.TemporaryDirectory(prefix="zs-s18-")
        self.addCleanup(td.cleanup)
        self.tmp = td.name
        self.hyprdir = os.path.join(self.tmp, "cfg", "hypr")
        os.makedirs(self.hyprdir)
        self.block = os.path.join(self.tmp, "block.lua")
        with open(self.block, "w", encoding="utf-8") as f:
            f.write(dofile_block())
        self.env = {"PATH": os.environ.get("PATH", ""), "HOME": self.tmp, "XDG_CONFIG_HOME": os.path.join(self.tmp, "cfg")}

    def run_block(self):
        return run_mock([self.block], env=self.env)

    def test_block_syntax(self):
        if LUAC:
            r = subprocess.run([LUAC, "-p", self.block], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_no_file_is_silent(self):
        d = run_mock([self.block], env=self.env)
        self.assertEqual((d["errors"], d["calls"]), ([], []))

    def test_file_is_executed(self):
        with open(os.path.join(self.hyprdir, "settings.lua"), "w", encoding="utf-8") as f:
            f.write(gen({"appearance.windowRounding": 7}))
        d = self.run_block()
        self.assertEqual(d["errors"], [])
        self.assertEqual(d["config"]["decoration.rounding"], 7)

    def test_home_fallback_without_xdg(self):
        os.makedirs(os.path.join(self.tmp, ".config", "hypr"))
        with open(os.path.join(self.tmp, ".config", "hypr", "settings.lua"), "w", encoding="utf-8") as f:
            f.write(gen({"appearance.windowRounding": 9}))
        env = dict(self.env)
        del env["XDG_CONFIG_HOME"]
        d = run_mock([self.block], env=env)
        self.assertEqual(d["config"]["decoration.rounding"], 9)

    def test_broken_file_notifies_and_does_not_raise(self):
        for body in ("hl.config({ decoration = { rounding = 10 } }\n", "error('boom')\n"):
            with open(os.path.join(self.hyprdir, "settings.lua"), "w", encoding="utf-8") as f:
                f.write(body)
            d = self.run_block()
            self.assertEqual(d["errors"], [])
            notes = [c for c in d["calls"] if c["fn"] == "notification.create"]
            self.assertEqual(len(notes), 1)
            self.assertIn("ошибка в settings.lua", notes[0]["args"][0]["text"])
            self.assertEqual(notes[0]["args"][0]["timeout"], 15000)


if __name__ == "__main__":
    unittest.main()


class AdoptGeneratedTests(unittest.TestCase):
    """settings.lua, принесённый git pull (нет записи в state), - не drift, пока шапка «СГЕНЕРИРОВАНО» цела."""

    def adoptable(self, content):
        from zsettings import targets

        class D:
            pass
        d, repo = D(), D()
        d.current = content
        repo.current = None
        p = type("P", (), {"t": {"kind": "emit"}, "default_content": lambda self: b"other"})()
        class E:  # движок без рендера: режим «другая тема» не используется
            def render(self, *a, **k):
                raise ValueError

        return targets.Engine._adoptable(E(), p, d, d)

    def test_header_adopted_manual_edit_is_drift(self):
        self.assertTrue(self.adoptable("-- СГЕНЕРИРОВАНО zephyrine-settings из x\nhl.config({})\n".encode("utf-8")))
        self.assertFalse(self.adoptable(b"hl.config({ my = 1 })\n"))
