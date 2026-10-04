import json
import os
import subprocess
import unittest

from zsettings import barlayout, model
from zsettings.util import Paths
from tests.test_hypr import REAL_ROOT


def schema():
    p = Paths.from_env({"HOME": "/nonexistent-home", "ZEPHYRINE_ROOT": REAL_ROOT})
    return model.Schema.load(p.schema_file, p.targets_file)


class LayoutTests(unittest.TestCase):
    def setUp(self):
        self.s = schema()

    def check(self, **flat):
        return barlayout.check_values(self.s, flat, list(flat))

    def test_defaults_valid_and_cover_all_items(self):
        flat = {z: self.s.default(z) for z in barlayout.ZONES}
        self.assertEqual(barlayout.check_values(self.s, flat, list(flat)), [])
        # в зонах по умолчанию - всё, кроме DEFAULT_HIDDEN (новые виджеты добавляются пользователем через редактор)
        self.assertEqual(sorted(i for z in flat.values() for i in z),
                         sorted(i for i in barlayout.IDS if i not in barlayout.DEFAULT_HIDDEN))
        self.assertEqual(self.s.default("bar.position"), "top")

    def test_errors(self):
        self.assertIn("unknown bar item", self.check(**{"bar.left": ["nope"]})[0]["error"])
        e = self.check(**{"bar.left": ["workspaces", "clock"]})   # clock уже в bar.right
        self.assertIn("two zones", e[0]["error"])
        self.assertEqual(self.check(**{"bar.left": ["workspaces"], "bar.right": ["clock"]}), [])
        self.assertEqual(barlayout.check_values(self.s, {}, ["appearance.radius"]), [])

    def test_new_widgets_known_and_city(self):
        for i in ("temp", "battery", "kbd", "timer", "weather", "volume", "wifi", "bluetooth", "apps"):
            self.assertIn(i, barlayout.IDS)
        self.assertEqual(self.check(**{"bar.right": ["clock", "timer", "weather"]}), [])
        self.assertEqual(self.check(**{"weather.city": "Kraków"}), [])
        self.assertEqual(self.check(**{"weather.city": "Санкт-Петербург"}), [])
        for bad in ("a/b", "x?y", "q&r", "a%20b", "a\nb", "x" * 61):
            self.assertIn("invalid city", self.check(**{"weather.city": bad})[0]["error"], bad)

    def test_position_enum_validated(self):
        self.assertEqual(self.s.validate("bar.position", "left"), "left")
        with self.assertRaises(model.ValidationError):
            self.s.validate("bar.position", "middle")

    def test_catalog_matches_bar_qml(self):
        with open(os.path.join(REAL_ROOT, "quickshell", "Bar.qml"), encoding="utf-8") as f:
            qml = f.read()
        if "registry" not in qml:
            self.skipTest("реестр в Bar.qml ещё не добавлен")
        for i in barlayout.IDS:
            self.assertIn(i + ":", qml, i)


    def test_bar_spacing_and_padding_schema_validation(self):
        """Проверка схемы настроек отступов и размеров панели и виджетов."""
        cases = [
            ("bar.margin", 6, 0, 24),
            ("bar.padding", 6, 2, 24),
            ("bar.spacing", 6, 2, 20),
            ("bar.height", 40, 32, 56),
            ("bar.pillHeight", 28, 22, 40),
            ("bar.pillPadding", 10, 4, 24),
            ("bar.pillSpacing", 6, 2, 16),
        ]
        for key, default, min_val, max_val in cases:
            with self.subTest(key=key):
                self.assertEqual(self.s.default(key), default)
                self.assertEqual(self.s.validate(key, min_val), min_val)
                self.assertEqual(self.s.validate(key, max_val), max_val)
                with self.assertRaises(model.ValidationError):
                    self.s.validate(key, min_val - 1)
                with self.assertRaises(model.ValidationError):
                    self.s.validate(key, max_val + 1)
                with self.assertRaises(model.ValidationError):
                    self.s.validate(key, "not-a-number")

    def test_workspaces_scroll_and_command_regression(self):
        """Проверка, что Workspaces.qml и VWorkspaces.qml обрабатывают скролл колеса мыши,
        умеют переключаться на следующий пустой рабочий стол и Config.workspaceCommand генерирует
        корректный синтаксис Lua-команд."""
        # 1. Проверка синтаксиса функции workspaceCommand в Config.qml
        config_path = os.path.join(REAL_ROOT, "quickshell", "Config.qml")
        with open(config_path, encoding="utf-8") as f:
            config_code = f.read()
        self.assertIn("function workspaceCommand(n)", config_code)
        self.assertTrue(
            ('typeof n === "number"' in config_code or "typeof n === 'number'" in config_code),
            "Config.workspaceCommand должен оборачивать строковые параметры в кавычки для Lua"
        )

        # 2. Проверка Workspaces.qml
        ws_path = os.path.join(REAL_ROOT, "quickshell", "components", "Workspaces.qml")
        with open(ws_path, encoding="utf-8") as f:
            ws_code = f.read()
        self.assertIn("onScrolled:", ws_code, "Workspaces.qml должен содержать обработчик onScrolled")
        self.assertIn("onWheel:", ws_code, "Dot MouseArea в Workspaces.qml должен перехватывать и передавать onWheel")
        self.assertIn("calculateNextWorkspace", ws_code, "Workspaces.qml должен использовать WsLogic.calculateNextWorkspace")
        self.assertIn("getOccupiedWorkspaces", ws_code, "Workspaces.qml должен определять занятые воркспейсы")

        # 3. Проверка VWorkspaces.qml
        vws_path = os.path.join(REAL_ROOT, "quickshell", "components", "VWorkspaces.qml")
        with open(vws_path, encoding="utf-8") as f:
            vws_code = f.read()
        self.assertIn("onScrolled:", vws_code, "VWorkspaces.qml должен содержать обработчик onScrolled")
        self.assertIn("onWheel:", vws_code, "Dot MouseArea в VWorkspaces.qml должен перехватывать и передавать onWheel")
        self.assertIn("calculateNextWorkspace", vws_code, "VWorkspaces.qml должен использовать WsLogic.calculateNextWorkspace")
        self.assertIn("getOccupiedWorkspaces", vws_code, "VWorkspaces.qml должен определять занятые воркспейсы")

        # 4. Проверка запуска юнит-тестов логики воркспейсов (workspaces-test.js)
        test_js = os.path.join(REAL_ROOT, "quickshell", "components", "workspaces-test.js")
        proc = subprocess.run(["node", test_js], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, f"workspaces-test.js failed: {proc.stderr}")
        self.assertIn("workspaces-test.js: all tests passed!", proc.stdout)

    def test_wallpaper_card_file_picker_regression(self):
        """Проверка, что в WallpaperCard.qml кнопка выбора файла не делает недопустимых присваиваний
        к свойству text у StdioCollector и корректно запускает wallpaper pick."""
        wp_card_path = os.path.join(REAL_ROOT, "quickshell", "settings", "parts", "WallpaperCard.qml")
        with open(wp_card_path, encoding="utf-8") as f:
            wp_code = f.read()

        # Защита от TypeError: Cannot assign to read-only property "text"
        self.assertNotIn("pickerOut.text =", wp_code, "Нельзя присваивать значение свойству pickerOut.text (read-only)")
        self.assertIn("wallpaper", wp_code)
        self.assertIn("pick", wp_code)
        self.assertIn("picker.command = [Config.settingsCli, \"wallpaper\", \"pick\"]", wp_code)

    def test_targets_list_hides_uninstalled_apps_regression(self):
        """Проверка, что TargetsList.qml и logic.js скрывают неустановленные приложения."""
        targets_path = os.path.join(REAL_ROOT, "quickshell", "settings", "parts", "TargetsList.qml")
        with open(targets_path, encoding="utf-8") as f:
            targets_code = f.read()

        # TargetsList.qml должен проверять статус установки цели (installed !== false и reason !== 'not-installed')
        self.assertTrue(
            "isInstalled" in targets_code or "isTargetInstalled" in targets_code,
            "TargetsList.qml должен содержать проверку установки приложения (isInstalled)"
        )
        self.assertTrue(
            "installed !== false" in targets_code or "isTargetPresent" in targets_code,
            "TargetsList.qml должен исключать цели с installed: false"
        )

        # Проверяем исполнение логики фильтрации через node logic-test.js
        test_js = os.path.join(REAL_ROOT, "quickshell", "settings", "logic-test.js")
        proc = subprocess.run(["node", test_js], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, f"logic-test.js failed: {proc.stderr}")
        self.assertIn("logic-test.js: all tests passed!", proc.stdout)


if __name__ == "__main__":
    unittest.main()

