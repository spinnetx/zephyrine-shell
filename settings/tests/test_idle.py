"""Тесты генератора секций hypridle.conf (zsettings/idle.py)."""
import os
import unittest

from zsettings import idle, model, palette, render

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_DIR = os.path.dirname(HERE)
GOLDEN = os.path.join(HERE, "golden", "hypridle", "hypridle.conf")
TMPL = os.path.join(SETTINGS_DIR, "templates", "hypr", "hypridle.conf.tmpl")


class IdleTests(unittest.TestCase):
    def test_fmt_mins(self):
        self.assertEqual(idle.fmt_mins(60), "1 минута")
        self.assertEqual(idle.fmt_mins(120), "2 минуты")
        self.assertEqual(idle.fmt_mins(150), "2.5 минуты")
        self.assertEqual(idle.fmt_mins(300), "5 минут")
        self.assertEqual(idle.fmt_mins(330), "5.5 минуты")
        self.assertEqual(idle.fmt_mins(1800), "30 минут")
        self.assertEqual(idle.fmt_mins(3600), "60 минут")

    def test_default_renders_golden_byte_identical(self):
        with open(GOLDEN, encoding="utf-8") as f:
            expected = f.read()
        with open(TMPL, encoding="utf-8") as f:
            template = f.read()

        # Defaults from schema
        schema = model.Schema.load(os.path.join(SETTINGS_DIR, "schema.json"), os.path.join(SETTINGS_DIR, "targets.json"))
        defaults = schema.defaults_flat()
        scheme, roles = palette.load_inputs(schema.targets[0].paths if hasattr(schema.targets[0], "paths") else None) if False else ({}, {})
        # Or directly build idle context
        ctx = {"idle": idle.build_idle_context(defaults)}
        out = render.render(template, ctx)
        self.assertEqual(out, expected)

    def test_custom_values_generate_valid_listeners(self):
        ctx = {"idle": idle.build_idle_context({
            "power.idle.dimSec": 60,
            "power.idle.dimLevel": "20%",
            "power.idle.lockSec": 300,
            "power.idle.dpmsSec": 600,
            "power.idle.suspendSec": 1800
        })}
        self.assertIn("timeout = 60\n    on-timeout = brightnessctl -s set 20%", ctx["idle"]["dimBlock"])
        self.assertIn("timeout = 300\n    on-timeout = loginctl lock-session", ctx["idle"]["lockBlock"])
        self.assertIn("timeout = 600\n    on-timeout = hyprctl dispatch", ctx["idle"]["dpmsBlock"])
        self.assertIn("timeout = 1800\n    on-timeout = systemctl suspend", ctx["idle"]["suspendBlock"])

    def test_disabled_listeners_comment_out_blocks(self):
        ctx = {"idle": idle.build_idle_context({
            "power.idle.dimSec": None,
            "power.idle.lockSec": None,
            "power.idle.dpmsSec": None,
            "power.idle.suspendSec": None
        })}
        self.assertIn("# Затемнение подсветки по бездействию отключено:", ctx["idle"]["dimBlock"])
        self.assertIn("# listener {", ctx["idle"]["dimBlock"])
        self.assertIn("# Автолок по бездействию отключён", ctx["idle"]["lockBlock"])
        self.assertIn("# Гашение экрана через dpms отключено:", ctx["idle"]["dpmsBlock"])
        self.assertIn("# Suspend по таймауту отключён по умолчанию", ctx["idle"]["suspendBlock"])


if __name__ == "__main__":
    unittest.main()
