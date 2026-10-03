"""Цель `wallpaper` (zsettings/wallpaper.py): симлинки, перезапуск ТОЛЬКО mpvpaper рабочего стола, превью.

Изолированный HOME/корень репо из test_targets.Fixture; mpvpaper/ffmpeg - поддельные скрипты в PATH-каталоге
теста, /proc - поддельный каталог в tmp, запуск и убийство процессов подменены моками (реальные процессы не
трогаются никогда).
"""
import os
import signal
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

try:
    from .test_targets import FAKE, Fixture
except ImportError:  # unittest discover -s tests: модули верхнего уровня
    from test_targets import FAKE, Fixture

from zsettings import wallpaper  # noqa: E402

DEFAULT = "wallpapers/japanese-night-village.1920x1080.mp4"
FAKE_FFMPEG = '#!/bin/sh\necho "ffmpeg $@" >> "$ZS_LOG"\nfor last; do :; done\nprintf JPEG > "$last"\n'


class FakeProc:
    def __init__(self, pid=900, rc=None):
        self.pid, self.rc = pid, rc

    def poll(self):
        return self.rc


class WallpaperCase(Fixture):
    def setUp(self):
        super().setUp()
        for rel in (DEFAULT, "wallpapers/b.mp4", "wallpapers/sub/c.png"):
            os.makedirs(os.path.dirname(self.repo(rel)), exist_ok=True)
            self.write_file(self.repo(rel), b"x" * 10)
        self._script("mpvpaper", FAKE % "mpvpaper")
        self._script("ffmpeg", FAKE_FFMPEG)
        self.spawned, self.killed = [], []
        self.spawn_result = FakeProc()
        self.dead = set()

        def spawn(cmd, env):
            self.spawned.append((cmd, env))
            return self.spawn_result

        def kill(pid, sig):
            self.killed.append((pid, sig))
            if sig == signal.SIGTERM:
                self.dead.add(pid)

        for name, val in (("PROC_ROOT", self.proc), ("_spawn", spawn), ("_kill", kill),
                          ("_alive", lambda pid: pid not in self.dead), ("_sleep", lambda s: None)):
            p = mock.patch.object(wallpaper, name, val)
            p.start()
            self.addCleanup(p.stop)

    def add_mpvpaper(self, pid, *args):
        d = os.path.join(self.proc, str(pid))
        os.makedirs(d, exist_ok=True)
        self.write_file(os.path.join(d, "comm"), b"mpvpaper\n")
        self.write_file(os.path.join(d, "cmdline"), b"\0".join(["mpvpaper"] + list(args) + [""]) if False
                        else b"\0".join(a.encode() for a in ("mpvpaper",) + args) + b"\0")

    def add_desktop(self, pid=700, video=None):
        self.add_mpvpaper(pid, "-o", wallpaper.MPV_OPTS, "ALL", video or self.repo(DEFAULT))

    def add_lock(self, pid=701):
        self.add_mpvpaper(pid, "-l", "overlay", "-o", "no-audio loop input-ipc-server=/x/s.sock", "ALL",
                          self.repo(DEFAULT))

    def link(self, which):
        try:
            return os.readlink(os.path.join(self.state, "wallpaper-" + which))
        except OSError:
            return None


class InstancesTests(WallpaperCase):
    def test_desktop_and_lock_are_told_apart(self):
        self.add_desktop(700)
        self.add_lock(701)
        self.add_proc(702, "bash", 100)  # чужой процесс
        inst = {i["pid"]: i for i in wallpaper.mpvpaper_instances()}
        self.assertEqual(sorted(inst), [700, 701])
        self.assertFalse(inst[700]["lock"])
        self.assertTrue(inst[701]["lock"])
        self.assertEqual(inst[700]["file"], self.repo(DEFAULT))
        self.assertEqual([i["pid"] for i in wallpaper.desktop_instances()], [700])


class SetTests(WallpaperCase):
    def test_missing_file_rejected_before_write(self):
        code, r = self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/nope.mp4")
        self.assertEqual(code, 2)
        self.assertEqual(r["errors"][0]["key"], "appearance.wallpaper.desktop")
        self.assertIn("not found", r["errors"][0]["error"])
        self.assertFalse(os.path.exists(self.settings_file) and b"nope" in self.read(self.settings_file))

    def test_unsupported_extension_rejected(self):
        self.write_file(self.repo("wallpapers/x.txt"), b"x")
        code, r = self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/x.txt")
        self.assertEqual(code, 2)
        self.assertIn("unsupported", r["errors"][0]["error"])

    def test_switch_restarts_only_desktop_instance(self):
        self.add_desktop(700)
        self.add_lock(701)
        code, r = self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4")
        self.assertEqual((code, r["ok"], r["errors"]), (0, True, []))
        self.assertIn("wallpaper", r["changed"])
        self.assertIn("wallpaper:restart", r["actions"])
        self.assertEqual(self.link("desktop"), self.repo("wallpapers/b.mp4"))
        self.assertEqual(self.link("lock"), self.repo("wallpapers/b.mp4"))  # lock = null -> как рабочий стол
        self.assertEqual(len(self.spawned), 1)
        cmd, env = self.spawned[0]
        self.assertEqual(cmd, ["mpvpaper", "-o", wallpaper.MPV_OPTS, "ALL", self.repo("wallpapers/b.mp4")])
        self.assertEqual(env["ZEPHYRINE_STATE"], self.state)
        self.assertEqual(self.killed, [(700, signal.SIGTERM)])  # экземпляр lock (701) не тронут

    def test_launch_script_used_when_present(self):
        self.add_desktop(700)
        os.makedirs(self.repo("scripts"))
        self._script("../root/scripts/wallpaper-desktop.sh", "#!/bin/sh\n")
        self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4")
        self.assertEqual(self.spawned[0][0], [self.repo("scripts/wallpaper-desktop.sh")])

    def test_no_exec_creates_links_but_touches_no_process(self):
        self.add_desktop(700)
        code, r = self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4", "--no-exec")
        self.assertEqual(code, 0)
        self.assertIn("wallpaper:restart", r["actionsSkipped"])
        self.assertEqual((self.spawned, self.killed), ([], []))
        self.assertEqual(self.link("desktop"), self.repo("wallpapers/b.mp4"))
        # не перезапущенный mpvpaper подхватывается следующим apply
        code, r = self.run_cli("apply", "--targets", "wallpaper")
        self.assertIn("wallpaper:restart", r["actions"])
        self.assertEqual(len(self.spawned), 1)

    def test_idempotent_after_restart(self):
        self.add_desktop(700, self.repo("wallpapers/b.mp4"))
        self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4")
        self.assertEqual((self.spawned, self.killed), ([], []))  # уже играет выбранное: перезапуск не нужен
        code, r = self.run_cli("apply", "--targets", "wallpaper")
        self.assertEqual((r["changed"], r["actions"]), ([], []))

    def test_not_running_only_switches_links(self):
        code, r = self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4")
        self.assertEqual(code, 0)
        self.assertIn({"target": "wallpaper", "reason": "mpvpaper-not-running"}, r["skipped"])
        self.assertEqual((self.spawned, self.killed), ([], []))  # без запущенного mpvpaper сами не стартуем
        self.assertEqual(self.link("desktop"), self.repo("wallpapers/b.mp4"))

    def test_new_instance_failure_keeps_old(self):
        self.add_desktop(700)
        self.spawn_result = FakeProc(rc=1)
        code, r = self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4")
        self.assertEqual(code, 1)
        self.assertEqual(r["errors"][0]["target"], "wallpaper")
        self.assertIn("old instance kept", r["errors"][0]["error"])
        self.assertEqual(self.killed, [])

    def test_lock_override_does_not_restart_desktop(self):
        self.add_desktop(700)
        code, r = self.run_cli("set", "appearance.wallpaper.lock=wallpapers/sub/c.png")
        self.assertEqual(code, 0)
        self.assertEqual(self.link("lock"), self.repo("wallpapers/sub/c.png"))
        self.assertEqual((self.spawned, self.killed), ([], []))

    def test_dry_run_changes_nothing(self):
        self.add_desktop(700)
        self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4", "--no-apply")
        code, r = self.run_cli("apply", "--targets", "wallpaper", "--dry-run")
        self.assertEqual(r["changed"], ["wallpaper"])
        self.assertIsNone(self.link("desktop"))
        self.assertEqual((self.spawned, self.killed), ([], []))

    def test_default_needs_no_links(self):
        self.add_desktop(700)
        code, r = self.run_cli("apply", "--targets", "wallpaper")
        self.assertEqual((code, r["changed"]), (0, []))
        self.assertIsNone(self.link("desktop"))  # скрипты берут фолбэк на то же видео
        st = next(t for t in self.run_cli("status")[1]["targets"] if t["id"] == "wallpaper")
        self.assertEqual((st["state"], st["reason"]), ("live", None))

    def test_reset_returns_to_default(self):
        self.add_desktop(700)
        self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4", "--no-exec")
        code, r = self.run_cli("reset", "appearance.wallpaper.desktop")
        self.assertEqual(self.link("desktop"), self.repo(DEFAULT))
        self.assertEqual(len(self.spawned), 0)  # mpvpaper всё ещё играет default (b не применяли): перезапуск не нужен

    def test_unmanaged_target_skipped(self):
        self.run_cli("set", "appearance.targets.wallpaper=false", "--no-apply")
        code, r = self.run_cli("apply", "--targets", "wallpaper")
        self.assertIn({"target": "wallpaper", "reason": "not-managed"}, r["skipped"])

    def test_status_outdated_then_live(self):
        self.add_desktop(700)
        self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4", "--no-apply")
        get = lambda: next(t for t in self.run_cli("status")[1]["targets"] if t["id"] == "wallpaper")  # noqa: E731
        self.assertEqual(get()["state"], "outdated")
        self.run_cli("apply", "--targets", "wallpaper", "--no-exec")
        self.assertEqual(get()["state"], "outdated")  # mpvpaper ещё играет старое
        self.add_desktop(700, self.repo("wallpapers/b.mp4"))
        self.assertEqual(get()["state"], "live")

    def test_missing_mpvpaper_is_missing_state(self):
        os.unlink(os.path.join(self.bin, "mpvpaper"))
        st = next(t for t in self.run_cli("status")[1]["targets"] if t["id"] == "wallpaper")
        self.assertEqual((st["state"], st["reason"]), ("missing", "not-installed"))


class CliTests(WallpaperCase):
    def test_restart_no_exec(self):
        self.add_desktop(700)
        code, r = self.run_cli("wallpaper", "restart", "--no-exec")
        self.assertEqual(code, 0)
        self.assertEqual(r["old"], [700])
        self.assertFalse(r["executed"])
        self.assertEqual((self.spawned, self.killed), ([], []))

    def test_restart_executes_and_kills_only_desktop(self):
        self.add_desktop(700)
        self.add_lock(701)
        code, r = self.run_cli("wallpaper", "restart")
        self.assertEqual((code, r["new"]), (0, 900))
        self.assertEqual(self.killed, [(700, signal.SIGTERM)])

    def test_list_with_thumbs_cached(self):
        self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4", "--no-exec")
        code, r = self.run_cli("wallpaper", "list")
        self.assertEqual(code, 0)
        self.assertEqual([i["rel"] for i in r["items"]],
                         ["wallpapers/b.mp4", DEFAULT, "wallpapers/sub/c.png"])
        self.assertEqual([i["desktop"] for i in r["items"]], [True, False, False])
        self.assertEqual([i["kind"] for i in r["items"]], ["video", "video", "image"])
        self.assertEqual(r["items"][0]["value"], "wallpapers/b.mp4")
        for i in r["items"]:
            self.assertTrue(os.path.isfile(i["thumb"]), i)
            self.assertTrue(i["thumb"].startswith(os.path.join(self.state, "cache", "wallpaper-thumbs")))
        n = len([c for c in self.calls() if c.startswith("ffmpeg")])
        self.assertEqual(n, 3)
        self.assertIn("scale=320:-2", self.calls()[0])
        self.assertIn("-ss 2", self.calls()[0])          # видео: кадр с 2-й секунды
        self.assertNotIn("-ss", self.calls()[2])          # картинка: без seek
        self.run_cli("wallpaper", "list")
        self.assertEqual(len([c for c in self.calls() if c.startswith("ffmpeg")]), n)  # из кэша

    def test_list_without_ffmpeg_or_no_thumbs(self):
        code, r = self.run_cli("wallpaper", "list", "--no-thumbs")
        self.assertTrue(all(i["thumb"] is None for i in r["items"]))
        os.unlink(os.path.join(self.bin, "ffmpeg"))
        code, r = self.run_cli("wallpaper", "list")
        self.assertEqual((code, r["ffmpeg"]), (0, False))
        self.assertTrue(all(i["thumb"] is None for i in r["items"]))

    def test_list_includes_manual_file_outside_catalog(self):
        ext = os.path.join(self.tmp, "elsewhere.webm")
        self.write_file(ext, b"x")
        self.run_cli("set", "appearance.wallpaper.desktop=" + ext, "--no-exec")
        code, r = self.run_cli("wallpaper", "list", "--no-thumbs")
        cur = [i for i in r["items"] if i["desktop"]]
        self.assertEqual([i["path"] for i in cur], [ext])
        self.assertEqual(cur[0]["value"], ext)

    def test_sddm_hint(self):
        sd = os.path.join(self.tmp, "sddm")
        os.makedirs(os.path.join(sd, "mybar", "assets"))
        self.write_file(os.path.join(sd, "mybar", "assets", "background.mp4"), b"x" * 10)
        with mock.patch.object(wallpaper, "SDDM_ROOT", sd):
            code, r = self.run_cli("wallpaper", "list", "--no-thumbs")
            self.assertEqual(r["sddm"]["inSync"], True)
            self.write_file(self.repo("wallpapers/b.mp4"), b"y" * 30)
            self.run_cli("set", "appearance.wallpaper.desktop=wallpapers/b.mp4", "--no-exec")
            code, r = self.run_cli("wallpaper", "list", "--no-thumbs")
            self.assertEqual(r["sddm"]["inSync"], False)
        self.assertIn("install-theme.sh", r["sddm"]["hint"])


if __name__ == "__main__":
    unittest.main()
