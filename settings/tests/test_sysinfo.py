import json
import unittest

from zsettings import sysinfo


class ParseTests(unittest.TestCase):
    def test_os_release(self):
        t = 'NAME="EndeavourOS"\nPRETTY_NAME="EndeavourOS"\nID=endeavouros\n# c\n'
        r = sysinfo.parse_os_release(t)
        self.assertEqual((r["NAME"], r["ID"]), ("EndeavourOS", "endeavouros"))
        self.assertEqual(sysinfo.parse_os_release(None), {})

    def test_meminfo_uptime_cpu(self):
        self.assertEqual(sysinfo.parse_meminfo("MemTotal:  1000 kB\nMemAvailable:   400 kB\n"), (1000, 400))
        self.assertEqual(sysinfo.parse_meminfo(""), (None, None))
        self.assertEqual(sysinfo.parse_uptime("123.45 678.9\n"), 123)
        self.assertIsNone(sysinfo.parse_uptime(""))
        self.assertEqual(sysinfo.parse_cpu("processor: 0\nmodel name\t: AMD  Ryzen 9\n"), "AMD Ryzen 9")

    def test_lspci(self):
        t = ("00:02.0 VGA compatible controller: Intel Corp UHD (rev 05)\n"
             "01:00.0 3D controller: NVIDIA Corporation TU106 [GeForce RTX 2060]\n"
             "00:1f.3 Audio device: Intel Audio\n")
        self.assertEqual(sysinfo.parse_lspci_gpus(t), ["Intel Corp UHD", "NVIDIA Corporation TU106 [GeForce RTX 2060]"])

    def test_versions(self):
        self.assertEqual(sysinfo.hypr_version(json.dumps({"version": "0.56.2"})), "0.56.2")
        self.assertEqual(sysinfo.hypr_version("Hyprland v0.56.2 built"), "0.56.2")
        self.assertEqual(sysinfo.qs_version("quickshell 0.3.1, revision abc"), "0.3.1")

    def test_summary_and_collect_shape(self):
        info = sysinfo.collect()
        for k in ("hostname", "os", "kernel", "components", "gpus", "memTotalKiB"):
            self.assertIn(k, info)
        self.assertTrue(all(set(c) == {"cmd", "label", "present"} for c in info["components"]))
        txt = sysinfo.summary_text({"hostname": "h", "os": "O", "kernel": "6", "hyprland": "0.5", "memTotalKiB": 1048576})
        self.assertIn("h · O · Linux 6", txt)
        self.assertIn("RAM: 1.0 ГиБ", txt)


if __name__ == "__main__":
    unittest.main()
