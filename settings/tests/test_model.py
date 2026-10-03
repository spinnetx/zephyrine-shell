import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from zsettings import backup, model  # noqa: E402
from zsettings.util import FileLock, LockTimeout, Paths, atomic_write  # noqa: E402

SETTINGS_DIR = os.path.join(os.path.dirname(__file__), "..")
SCHEMA = os.path.join(SETTINGS_DIR, "schema.json")
TARGETS = os.path.join(SETTINGS_DIR, "targets.json")


def wr(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def rd(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def make_paths(tmp, timeout=5):
    env = {"HOME": tmp, "ZEPHYRINE_ROOT": os.path.join(tmp, "root"),
           "ZEPHYRINE_STATE": os.path.join(tmp, "state"), "ZEPHYRINE_LOCK_TIMEOUT": str(timeout)}
    paths = Paths.from_env(env)
    os.makedirs(paths.settings_dir)
    shutil.copy(SCHEMA, paths.schema_file)
    shutil.copy(TARGETS, paths.targets_file)
    return paths


class SchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = model.Schema.load(SCHEMA, TARGETS)

    def test_all_defaults_validate_against_own_spec(self):
        for k, spec in self.schema.concrete.items():
            with self.subTest(key=k):
                d = spec.get("default")
                self.assertTrue(model.strict_equal(self.schema.validate(k, d), d), k)

    def test_template_defaults(self):
        self.assertIs(self.schema.default("appearance.targets.kitty"), True)
        self.assertIsNone(self.schema.default("binds.launcher"))

    def test_unknown_and_bad_template(self):
        for k in ("nope", "appearance", "appearance.glassAlpha.x", "appearance.targets.nosuch",
                  "appearance.targets.", "binds.bad.name", "binds.1x"):
            with self.subTest(key=k), self.assertRaises(model.ValidationError):
                self.schema.lookup(k)

    def test_number_range_and_type(self):
        v = self.schema.validate
        self.assertEqual(v("appearance.glassAlpha", 1), 1.0)
        self.assertIsInstance(v("appearance.glassAlpha", 1), float)
        for bad in (0.49, 1.01, "0.8", True, None, float("nan"), float("inf")):
            with self.subTest(bad=bad), self.assertRaises(model.ValidationError):
                v("appearance.glassAlpha", bad)

    def test_integer(self):
        v = self.schema.validate
        self.assertEqual(v("appearance.radius", 12.0), 12)
        self.assertIsInstance(v("appearance.radius", 12.0), int)
        for bad in (12.5, True, -1, 21, "12"):
            with self.subTest(bad=bad), self.assertRaises(model.ValidationError):
                v("appearance.radius", bad)

    def test_color_and_nullable(self):
        v = self.schema.validate
        self.assertEqual(v("appearance.accent", "#7AA2F7"), "#7aa2f7")
        self.assertIsNone(v("appearance.accent", None))
        for bad in ("7aa2f7", "#7aa2f", "#gggggg", 5):
            with self.subTest(bad=bad), self.assertRaises(model.ValidationError):
                v("appearance.accent", bad)

    def test_enum_boolean_nullable_int(self):
        v = self.schema.validate
        self.assertEqual(v("hypr.borders.style", "accent"), "accent")
        with self.assertRaises(model.ValidationError):
            v("hypr.borders.style", "rainbow")
        with self.assertRaises(model.ValidationError):
            v("appearance.targets.kitty", 1)
        self.assertIsNone(v("power.idle.dimSec", None))
        with self.assertRaises(model.ValidationError):
            v("power.idle.dimSec", 5)  # min 10
        with self.assertRaises(model.ValidationError):
            v("appearance.radius", None)

    def test_object_and_array(self):
        v = self.schema.validate
        good = {"active": ["rgba(112233ff)"], "angle": 90, "inactive": "rgba(00000000)"}
        self.assertEqual(v("hypr.borders.custom", good), good)
        for bad in (dict(good, angle=361), dict(good, extra=1), {"angle": 1},
                    dict(good, active=[]), dict(good, active=["red"]), "x"):
            with self.subTest(bad=bad), self.assertRaises(model.ValidationError):
                v("hypr.borders.custom", bad)
        self.assertEqual(v("binds.launcher", ["SUPER + R"]), ["SUPER + R"])
        with self.assertRaises(model.ValidationError):
            v("binds.launcher", "SUPER + R")
        with self.assertRaises(model.ValidationError):
            v("input.layouts", [])  # minItems 1
        self.assertEqual(v("input.layouts", [{"layout": "us", "variant": ""}]),
                         [{"layout": "us", "variant": ""}])
        with self.assertRaises(model.ValidationError):
            v("input.layouts", [{"layout": "us"}])

    def test_affected_targets(self):
        t = self.schema.affected_targets(["appearance.windowRounding"])
        self.assertEqual(t, ["hypr"])
        self.assertEqual(self.schema.affected_targets(["network.confirmDisruptive", "appearance.targets.kitty"]), [])


class MergeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = model.Schema.load(SCHEMA, TARGETS)

    def test_flatten_nest_roundtrip_with_leaf_objects(self):
        raw = {"version": 1, "appearance": {"glassAlpha": 0.8, "targets": {"zed": False}},
               "hypr": {"borders": {"custom": {"active": ["rgba(112233ff)"], "angle": 1,
                                               "inactive": "rgba(00000000)"}}},
               "future": {"thing": 1}}
        flat = model.flatten(raw, self.schema)
        self.assertEqual(flat["appearance.targets.zed"], False)
        self.assertIn("hypr.borders.custom", flat)  # объект - лист, не раскрывается
        self.assertEqual(flat["future.thing"], 1)    # неизвестное сохраняется
        raw.pop("version")
        self.assertEqual(model.nest(flat), raw)

    def test_effective_sparse_merge(self):
        eff, w = model.effective(self.schema, {"appearance.glassAlpha": 0.7})
        self.assertEqual(eff["appearance.glassAlpha"], 0.7)
        self.assertEqual(eff["appearance.radius"], 12)
        self.assertEqual(w, [])

    def test_effective_ignores_invalid_stored(self):
        eff, w = model.effective(self.schema, {"appearance.radius": 99, "bogus": 1})
        self.assertEqual(eff["appearance.radius"], 12)
        self.assertEqual(len(w), 2)

    def test_default_value_removed_from_file(self):
        flat = {"appearance.glassAlpha": 0.7}
        new, changed, errs = model.apply_updates(self.schema, flat, [("appearance.glassAlpha", 0.88)])
        self.assertEqual((new, changed, errs), ({}, ["appearance.glassAlpha"], []))
        new, changed, _ = model.apply_updates(self.schema, {}, [("appearance.glassAlpha", 0.88)])
        self.assertEqual((new, changed), ({}, []))

    def test_nullable_non_null_default_keeps_explicit_null(self):
        new, changed, _ = model.apply_updates(self.schema, {}, [("power.idle.dimSec", None)])
        self.assertEqual(new, {"power.idle.dimSec": None})
        self.assertEqual(changed, ["power.idle.dimSec"])

    def test_remove_keys_prefix_and_unknown(self):
        flat = {"appearance.glassAlpha": 0.7, "appearance.radius": 5, "apps.terminal": "foot"}
        new, changed, errs = model.remove_keys(self.schema, flat, ["appearance"])
        self.assertEqual(new, {"apps.terminal": "foot"})
        self.assertEqual(sorted(changed), ["appearance.glassAlpha", "appearance.radius"])
        _, _, errs = model.remove_keys(self.schema, flat, ["nope"])
        self.assertEqual(errs[0]["key"], "nope")


class StoreAndFilesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.paths = make_paths(self.tmp)
        self.schema = model.Schema.load(self.paths.schema_file, self.paths.targets_file)
        self.store = model.Store(self.paths, self.schema)

    def test_missing_file_is_empty(self):
        self.assertEqual(self.store.read_flat(), {})

    def test_write_format_and_history(self):
        self.assertTrue(self.store.write({"appearance.radius": 5}))
        text = rd(self.paths.settings_file)
        self.assertEqual(json.loads(text), {"version": 1, "appearance": {"radius": 5}})
        self.assertTrue(text.endswith("\n"))
        self.assertEqual(len(backup.list_history(self.paths)), 1)
        self.assertFalse(self.store.write({"appearance.radius": 5}))  # без изменений - без записи
        self.assertEqual(len(backup.list_history(self.paths)), 1)

    def test_corrupt_and_bad_version(self):
        atomic_write(self.paths.settings_file, "{oops")
        with self.assertRaises(model.StoreError):
            self.store.read_flat()
        atomic_write(self.paths.settings_file, '{"version": 2}')
        with self.assertRaises(model.StoreError):
            self.store.read_flat()

    def test_atomic_write_keeps_symlink(self):
        real = os.path.join(self.tmp, "real.json")
        link = os.path.join(self.tmp, "link.json")
        wr(real, "old")
        os.symlink(real, link)
        atomic_write(link, "new")
        self.assertTrue(os.path.islink(link))
        self.assertEqual(rd(real), "new")
        self.assertEqual([n for n in os.listdir(self.tmp) if n.endswith(".tmp")], [])

    def test_history_order_and_rotation(self):
        for i in range(backup.HISTORY_KEEP + 5):
            backup.push_history(self.paths, str(i).encode())
        names = backup.list_history(self.paths)
        self.assertEqual(len(names), backup.HISTORY_KEEP)
        self.assertEqual(backup.peek_history(self.paths)[1], str(backup.HISTORY_KEEP + 4).encode())
        self.assertEqual(names, sorted(names))

    def test_backup_create_list_restore(self):
        f = os.path.join(self.tmp, "a.txt")
        wr(f, "one")
        bid = backup.create(self.paths, [f, os.path.join(self.tmp, "missing")], "set")
        wr(f, "two")
        self.assertEqual([b["id"] for b in backup.list_backups(self.paths)], [bid])
        files, safety = backup.restore(self.paths, bid)
        self.assertEqual(rd(f), "one")
        self.assertEqual(files, [os.path.realpath(f)])
        self.assertIsNotNone(safety)
        self.assertEqual(oct(os.stat(os.path.join(self.paths.backups_dir, bid)).st_mode & 0o777), "0o700")

    def test_backup_restore_rejects_bad_id(self):
        for bad in ("../x", "nope", ""):
            with self.assertRaises(backup.BackupError):
                backup.restore(self.paths, bad)

    def test_backup_rotation(self):
        f = os.path.join(self.tmp, "a.txt")
        wr(f, "x")
        for i in range(backup.BACKUPS_KEEP + 3):
            backup.create(self.paths, [f], "r%d" % i)
        self.assertEqual(len(backup.list_backups(self.paths)), backup.BACKUPS_KEEP)

    def test_lock_timeout_and_reentrancy(self):
        tmp2 = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp2, True)
        p = make_paths(tmp2, timeout=0.2)
        import fcntl
        os.makedirs(p.state, exist_ok=True)
        fd = os.open(p.lock_file, os.O_RDWR | os.O_CREAT)
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            with self.assertRaises(LockTimeout), FileLock(p):
                pass
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
        with FileLock(p):
            with FileLock(p):
                pass


if __name__ == "__main__":
    unittest.main()
