import os
import tempfile
import unittest

from zsettings import mime

GIO = """Default application for “text/plain”: dev.zed.Zed.desktop
Registered applications:
\torg.gnome.gedit.desktop
\tdev.zed.Zed.desktop
Recommended applications:
\tdev.zed.Zed.desktop
"""


class ParseTests(unittest.TestCase):
    def test_parse(self):
        d, reg, rec = mime.parse_gio_mime(GIO)
        self.assertEqual(d, "dev.zed.Zed.desktop")
        self.assertEqual(reg, ["org.gnome.gedit.desktop", "dev.zed.Zed.desktop"])
        self.assertEqual(rec, ["dev.zed.Zed.desktop"])

    def test_no_default(self):
        d, reg, rec = mime.parse_gio_mime("No default applications for “x/y”\nNo registered applications\n")
        self.assertEqual((d, reg, rec), (None, [], []))

    def test_app_name(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "applications"))
        with open(os.path.join(d, "applications", "a.desktop"), "w", encoding="utf-8") as f:
            f.write("[Desktop Entry]\nName=Alpha\nName[ru]=Альфа\n[Desktop Action x]\nName=No\n")
        self.assertEqual(mime.app_name("a.desktop", [d]), "Альфа")
        self.assertEqual(mime.app_name("zzz.desktop", [d]), "zzz")


class ListSetTests(unittest.TestCase):
    def test_listing(self):
        calls = []

        def runner(argv):
            calls.append(argv)
            if argv[2] == "inode/directory":
                raise mime.MimeError("boom")
            return GIO

        out = mime.listing(runner, namer=lambda a: a.upper(), scanner=lambda t: [])
        self.assertEqual(len(out), len(mime.CATEGORIES))
        text = next(c for c in out if c["id"] == "text")
        self.assertEqual(text["current"], "dev.zed.Zed.desktop")
        self.assertEqual([a["id"] for a in text["apps"]], ["dev.zed.Zed.desktop", "org.gnome.gedit.desktop"])
        self.assertEqual(next(c for c in out if c["id"] == "files")["error"], "boom")

    def test_scan_fallback_and_locale(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, "applications"))
        with open(os.path.join(d, "applications", "v.desktop"), "w", encoding="utf-8") as f:
            f.write("[Desktop Entry]\nName=V\nMimeType=video/mp4;video/webm;\n")
        self.assertEqual(mime.scan_desktop(["video/mp4"], [d]), ["v.desktop"])
        self.assertEqual(mime.scan_desktop(["audio/flac"], [d]), [])
        out = mime.listing(lambda a: "Нет приложений по умолчанию\n", namer=lambda a: a,
                           scanner=lambda t: ["v.desktop"])
        self.assertEqual(out[0]["apps"][0]["id"], "v.desktop")   # пустой разбор gio -> запасной список
        # gio вызывается в локали C (иначе русские заголовки ломают разбор)
        from unittest import mock
        with mock.patch.object(mime.shutil, "which", return_value="/bin/true"), \
                mock.patch.object(mime.subprocess, "run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = ""
            mime._run(["gio", "mime", "text/plain"])
        self.assertEqual(run.call_args.kwargs["env"]["LC_ALL"], "C")

    def test_set_default(self):
        ran = []
        cmds = mime.set_default("browser", "zen.desktop", runner=ran.append)
        self.assertEqual(len(cmds), 4)
        self.assertEqual(ran[0], ["gio", "mime", "x-scheme-handler/http", "zen.desktop"])
        self.assertEqual(ran[-1][:3], ["xdg-settings", "set", "default-web-browser"])
        self.assertEqual(mime.set_default("pdf", "z.desktop", runner=ran.append, no_exec=True),
                         ["gio mime application/pdf z.desktop"])

    def test_set_rejects_bad_input(self):
        for cat, app in (("nope", "a.desktop"), ("pdf", "a b.desktop"), ("pdf", "../x.desktop"), ("pdf", "")):
            with self.subTest(cat=cat, app=app), self.assertRaises(mime.MimeError):
                mime.set_default(cat, app, runner=lambda a: "", no_exec=True)

    def test_xdg_settings_failure_ignored(self):
        def runner(argv):
            if argv[0] == "xdg-settings":
                raise mime.MimeError("no xdg-settings")
        self.assertEqual(len(mime.set_default("browser", "zen.desktop", runner=runner)), 4)


if __name__ == "__main__":
    unittest.main()
