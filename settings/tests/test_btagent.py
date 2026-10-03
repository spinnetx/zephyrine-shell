"""Агент BlueZ (zsettings/btagent.py): логика Core без шины + интеграция на изолированной шине с поддельным BlueZ.

Реальные шина/адаптер/устройства не затрагиваются: интеграционные тесты поднимают свой dbus-daemon (если его нет,
они пропускаются) и tests/fake_bluez.py.
"""
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

from zsettings import btagent  # noqa: E402

DEV = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"


class FakeClock:
    def __init__(self):
        self.now = 0.0
        self.timers = {}
        self.n = 0

    def schedule(self, sec, fn):
        self.n += 1
        self.timers[self.n] = (self.now + sec, fn)
        return self.n

    def cancel(self, tok):
        self.timers.pop(tok, None)

    def advance(self, sec):
        self.now += sec
        for tok, (at, fn) in sorted(self.timers.items(), key=lambda kv: kv[1][0]):
            if at <= self.now and tok in self.timers:
                del self.timers[tok]
                fn()


class Rec:
    """Запоминает ответы BlueZ (reply/error)."""

    def __init__(self):
        self.calls = []

    def reply(self, v=None):
        self.calls.append(("ok", v))

    def error(self, name, msg=""):
        self.calls.append(("err", name))


class CoreCase(unittest.TestCase):
    def setUp(self):
        self.ev = []
        self.clock = FakeClock()
        self.quit = []
        self.core = btagent.Core(self.ev.append, lambda p: ("Наушники", "AA:BB:CC:DD:EE:FF"),
                                 self.clock.schedule, self.clock.cancel, lambda: self.quit.append(1), timeout=60)

    def kinds(self):
        return [(e["event"], e.get("kind") or e.get("reason")) for e in self.ev]


class TestParsers(unittest.TestCase):
    def test_passkey(self):
        self.assertEqual(btagent.parse_passkey(123456), 123456)
        self.assertEqual(btagent.parse_passkey("007"), 7)
        self.assertEqual(btagent.parse_passkey(" 0 "), 0)
        for bad in (-1, 1000000, "1234567", "12a", "", True, None, 1.5, "١٢٣"):
            with self.assertRaises(ValueError, msg=repr(bad)):
                btagent.parse_passkey(bad)

    def test_pin(self):
        self.assertEqual(btagent.parse_pin("0000"), "0000")
        self.assertEqual(btagent.parse_pin("a" * 16), "a" * 16)
        for bad in ("", "a" * 17, None, 1234, "я" * 9):
            with self.assertRaises(ValueError, msg=repr(bad)):
                btagent.parse_pin(bad)

    def test_address_from_path(self):
        self.assertEqual(btagent.address_from_path(DEV), "AA:BB:CC:DD:EE:FF")
        self.assertEqual(btagent.address_from_path("/x/y"), "")

    def test_linebuffer(self):
        lb = btagent.LineBuffer(limit=10)
        self.assertEqual(lb.feed(b'{"a":1}\n{"b"'), ['{"a":1}'])
        self.assertEqual(lb.feed(b':2}\n'), ['{"b":2}'])
        self.assertEqual(lb.feed(b"x" * 30), [])          # слишком длинная строка: отбрасывается целиком
        self.assertEqual(lb.feed(b"yy\nok\n"), ["ok"])
        self.assertEqual(btagent.LineBuffer(limit=20).feed("привет\n".encode()), ["привет"])


class TestConfirm(CoreCase):
    def test_confirm_flow(self):
        r = Rec()
        self.core.request_confirmation(DEV, 123456, r.reply, r.error)
        e = self.ev[0]
        self.assertEqual((e["event"], e["kind"], e["passkey"], e["device"], e["address"], e["id"]),
                         ("pair_request", "confirm", 123456, "Наушники", "AA:BB:CC:DD:EE:FF", 1))
        self.assertEqual(e["timeout"], 60)
        self.core.handle_line('{"action":"confirm"}')
        self.assertEqual(r.calls, [("ok", None)])
        self.assertEqual(self.ev[-1], {"event": "pair_end", "id": 1, "reason": "answered"})
        self.assertEqual(self.clock.timers, {})
        # повторный ответ - нет ждущего запроса
        self.core.handle_line('{"action":"confirm"}')
        self.assertEqual(self.ev[-1]["event"], "error")
        self.assertEqual(r.calls, [("ok", None)])

    def test_reject(self):
        r = Rec()
        self.core.request_confirmation(DEV, 1, r.reply, r.error)
        self.core.handle_line('{"action":"reject"}')
        self.assertEqual(r.calls, [("err", btagent.ERR_REJECTED)])
        self.assertEqual(self.ev[-1]["reason"], "rejected")

    def test_timeout(self):
        r = Rec()
        self.core.request_confirmation(DEV, 1, r.reply, r.error)
        self.clock.advance(59)
        self.assertEqual(r.calls, [])
        self.clock.advance(2)
        self.assertEqual(r.calls, [("err", btagent.ERR_CANCELED)])
        self.assertEqual(self.ev[-1], {"event": "pair_end", "id": 1, "reason": "timeout"})
        self.assertEqual(self.core.requests, {})

    def test_cancel_from_bluez(self):
        r = Rec()
        self.core.request_confirmation(DEV, 1, r.reply, r.error)
        self.core.cancel_all()
        self.assertEqual(r.calls, [])            # BlueZ сам отбросил вызов - не отвечаем
        self.assertEqual(self.ev[-1]["reason"], "cancel")
        self.assertEqual(self.clock.timers, {})
        self.core.handle_line('{"action":"confirm"}')    # поздний ответ UI безвреден
        self.assertEqual(r.calls, [])

    def test_wrong_action_keeps_request(self):
        r = Rec()
        self.core.request_confirmation(DEV, 1, r.reply, r.error)
        self.core.handle_line('{"action":"pin","value":"0000"}')
        self.assertEqual(self.ev[-1]["event"], "error")
        self.assertEqual(r.calls, [])
        self.assertIn(1, self.core.requests)

    def test_authorize_and_service(self):
        r1, r2 = Rec(), Rec()
        self.core.request_authorization(DEV, r1.reply, r1.error)
        self.core.authorize_service(DEV, "0000110b-0000-1000-8000-00805f9b34fb", r2.reply, r2.error)
        self.assertEqual(self.ev[1]["kind"], "authorize_service")
        self.assertEqual(self.ev[1]["uuid"], "0000110b-0000-1000-8000-00805f9b34fb")
        self.core.handle_line('{"action":"confirm","id":1}')       # по id - старый запрос
        self.assertEqual((r1.calls, r2.calls), ([("ok", None)], []))
        self.core.handle_line('{"action":"reject"}')               # без id - самый новый
        self.assertEqual(r2.calls, [("err", btagent.ERR_REJECTED)])


class TestInput(CoreCase):
    def test_passkey(self):
        r = Rec()
        self.core.request_passkey(DEV, r.reply, r.error)
        self.core.handle_line('{"action":"passkey","value":"12345678"}')    # неверно: запрос остаётся
        self.assertEqual(self.ev[-1]["event"], "error")
        self.assertEqual(r.calls, [])
        self.core.handle_line('{"action":"passkey","value":"042"}')
        self.assertEqual(r.calls, [("ok", 42)])

    def test_pin(self):
        r = Rec()
        self.core.request_pin(DEV, r.reply, r.error)
        self.core.handle_line('{"action":"pin","value":""}')
        self.assertEqual(r.calls, [])
        self.core.handle_line('{"action":"pin","value":"0000"}')
        self.assertEqual(r.calls, [("ok", "0000")])

    def test_pin_reject_and_timeout(self):
        r = Rec()
        self.core.request_pin(DEV, r.reply, r.error)
        self.core.handle_line('{"action":"reject"}')
        self.assertEqual(r.calls, [("err", btagent.ERR_REJECTED)])
        r2 = Rec()
        self.core.request_passkey(DEV, r2.reply, r2.error)
        self.clock.advance(61)
        self.assertEqual(r2.calls, [("err", btagent.ERR_CANCELED)])


class TestDisplay(CoreCase):
    def test_display_passkey_updates(self):
        self.core.display_passkey(DEV, 654321, 0)
        self.core.display_passkey(DEV, 654321, 0)    # без изменений - тишина
        self.core.display_passkey(DEV, 654321, 3)
        self.assertEqual([e["event"] for e in self.ev], ["pair_request", "pair_update"])
        self.assertEqual(self.ev[0]["passkey"], 654321)
        self.assertEqual(self.ev[1]["entered"], 3)
        self.assertEqual(len(self.core.requests), 1)

    def test_display_pin_dismiss_and_timeout(self):
        self.core.display_pin(DEV, "1234")
        self.assertEqual(self.ev[0]["pin"], "1234")
        self.core.handle_line('{"action":"reject"}')      # закрыть показ
        self.assertEqual(self.ev[-1]["reason"], "dismissed")
        self.core.display_pin(DEV, "1234")
        self.clock.advance(61)
        self.assertEqual(self.ev[-1]["reason"], "timeout")

    def test_display_not_answerable(self):
        self.core.display_passkey(DEV, 1, 0)
        self.core.handle_line('{"action":"confirm"}')
        self.assertEqual(self.ev[-1]["event"], "error")     # нет ждущего ответа запроса

    def test_confirm_goes_to_awaiting_not_display(self):
        r = Rec()
        self.core.request_confirmation(DEV, 5, r.reply, r.error)
        self.core.display_pin(DEV, "1")
        self.core.handle_line('{"action":"confirm"}')
        self.assertEqual(r.calls, [("ok", None)])


class TestLifecycle(CoreCase):
    def test_shutdown_rejects_pending(self):
        r, r2 = Rec(), Rec()
        self.core.request_confirmation(DEV, 1, r.reply, r.error)
        self.core.request_pin(DEV, r2.reply, r2.error)
        self.core.display_pin(DEV, "1")
        self.core.shutdown()
        self.core.shutdown()
        self.assertEqual(r.calls, [("err", btagent.ERR_CANCELED)])
        self.assertEqual(r2.calls, [("err", btagent.ERR_CANCELED)])
        self.assertEqual(self.core.requests, {})
        self.assertEqual(self.clock.timers, {})

    def test_quit_command_and_release(self):
        r = Rec()
        self.core.request_pin(DEV, r.reply, r.error)
        self.core.handle_line('{"action":"quit"}')
        self.assertEqual(self.quit, [1])
        self.assertEqual(r.calls, [("err", btagent.ERR_CANCELED)])
        c2 = btagent.Core(lambda e: None, lambda p: ("", ""), self.clock.schedule, self.clock.cancel,
                          lambda: self.quit.append(2))
        c2.released()
        self.assertEqual(self.quit, [1, 2])

    def test_bad_input_is_harmless(self):
        for line in ("", "   ", "не json", "[1]", '"x"', '{"action":"boom"}', '{"action":"confirm","id":"x"}',
                     '{"action":"confirm","id":99}', '{}', "null"):
            self.core.handle_line(line)
        self.assertTrue(all(e["event"] == "error" for e in self.ev))

    def test_resolve_failure_falls_back_to_path(self):
        def boom(p):
            raise RuntimeError("no bluez")
        c = btagent.Core(self.ev.append, boom, self.clock.schedule, self.clock.cancel)
        c.request_pin(DEV, lambda v=None: None, lambda n, m: None)
        self.assertEqual((self.ev[-1]["device"], self.ev[-1]["address"]), ("AA:BB:CC:DD:EE:FF",) * 2)

    def test_no_secrets_on_stderr(self):
        # ядро вообще ничего не пишет в stderr/логи
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            r = Rec()
            self.core.request_confirmation(DEV, 123456, r.reply, r.error)
            self.core.handle_line('{"action":"confirm"}')
            self.core.request_pin(DEV, r.reply, r.error)
            self.core.handle_line('{"action":"pin","value":"9876"}')
        self.assertEqual(buf.getvalue(), "")


# ------------------------------- интеграция на изолированной шине ------------------------------------------

def _have_stack():
    if not shutil.which("dbus-daemon"):
        return False
    try:
        import dbus  # noqa: F401
        from gi.repository import GLib  # noqa: F401
    except ImportError:
        return False
    return True


class Proc:
    """Подпроцесс с JSON-строками на stdout (читаются потоком в очередь, чтобы тест не зависал)."""

    def __init__(self, args, **kw):
        self.p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, **kw)
        self.q = queue.Queue()
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for line in self.p.stdout:
            try:
                self.q.put(json.loads(line))
            except ValueError:
                self.q.put({"raw": line})
        self.q.put(None)

    def send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def get(self, timeout=10):
        return self.q.get(timeout=timeout)

    def until(self, pred, timeout=10):
        while True:
            m = self.get(timeout)
            self.assertion_none = m
            if m is None or pred(m):
                return m

    def stop(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.wait(5)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()
        self.p.stdout.close()
        self.p.stderr.close()


@unittest.skipUnless(_have_stack(), "нет dbus-daemon / dbus-python / gi")
class TestBus(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="zs-btagent-")
        sock = os.path.join(self.tmp, "bus")
        self.daemon = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--address=unix:path=" + sock,
                                        "--print-address=1"], stdout=subprocess.PIPE, text=True)
        self.addr = self.daemon.stdout.readline().strip()
        self.assertTrue(self.addr.startswith("unix:"))
        self.fake = Proc([sys.executable, os.path.join(HERE, "fake_bluez.py"), self.addr])
        self.assertEqual(self.fake.get()["event"], "up")
        self.agent = None

    def tearDown(self):
        if self.agent:
            self.agent.stop()
        self.fake.stop()
        self.daemon.terminate()
        self.daemon.wait(5)
        self.daemon.stdout.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def start_agent(self, *extra):
        env = dict(os.environ, PYTHONPATH=ROOT)
        self.agent = Proc([sys.executable, "-m", "zsettings.btagent", "--bus", self.addr, *extra], env=env)
        reg = self.fake.get()
        self.assertEqual((reg["event"], reg["capability"], reg["path"]), ("registered", "KeyboardDisplay", btagent.AGENT_PATH))
        self.assertEqual(self.fake.get()["event"], "default")
        ready = self.agent.get()
        self.assertEqual((ready["event"], ready["default"]), ("ready", True))

    def call(self, i, method, *args):
        self.fake.send({"id": i, "method": method, "args": list(args)})

    def test_confirm_roundtrip(self):
        self.start_agent()
        self.call(1, "RequestConfirmation", DEV, 123456)
        ev = self.agent.get()
        self.assertEqual((ev["event"], ev["kind"], ev["passkey"], ev["device"], ev["address"]),
                         ("pair_request", "confirm", 123456, "Тест-наушники", "AA:BB:CC:DD:EE:FF"))
        self.agent.send({"action": "confirm", "id": ev["id"]})
        self.assertEqual(self.fake.get(), {"id": 1, "result": []})
        self.assertEqual(self.agent.get()["reason"], "answered")

    def test_reject_gives_dbus_error(self):
        self.start_agent()
        self.call(1, "RequestConfirmation", DEV, 1)
        self.agent.get()
        self.agent.send({"action": "reject"})
        self.assertEqual(self.fake.get(), {"id": 1, "error": "org.bluez.Error.Rejected"})

    def test_pin_passkey_values(self):
        self.start_agent()
        self.call(1, "RequestPinCode", DEV)
        ev = self.agent.get()
        self.assertEqual(ev["kind"], "pin")
        self.agent.send({"action": "pin", "value": "0000"})
        self.assertEqual(self.fake.get(), {"id": 1, "result": ["0000"]})
        self.agent.until(lambda m: m.get("event") == "pair_end")
        self.call(2, "RequestPasskey", DEV)
        self.assertEqual(self.agent.get()["kind"], "passkey")
        self.agent.send({"action": "passkey", "value": 424242})
        self.assertEqual(self.fake.get(), {"id": 2, "result": [424242]})

    def test_display_and_cancel(self):
        self.start_agent()
        self.call(1, "DisplayPasskey", DEV, 111222, 0)
        self.assertEqual(self.fake.get(), {"id": 1, "result": []})
        ev = self.agent.get()
        self.assertEqual((ev["kind"], ev["passkey"]), ("display_passkey", 111222))
        self.call(2, "DisplayPasskey", DEV, 111222, 2)
        self.assertEqual(self.fake.get(), {"id": 2, "result": []})
        self.assertEqual(self.agent.get(), {"event": "pair_update", "id": ev["id"], "entered": 2})
        self.call(3, "RequestConfirmation", DEV, 5)
        self.agent.get()
        self.call(4, "Cancel")
        self.assertEqual(self.fake.get()["id"], 4)
        ends = {self.agent.get()["reason"], self.agent.get()["reason"]}
        self.assertEqual(ends, {"cancel"})

    def test_timeout_over_bus(self):
        self.start_agent("--timeout", "0.5")
        self.call(1, "RequestConfirmation", DEV, 1)
        self.agent.get()
        self.assertEqual(self.fake.get(), {"id": 1, "error": "org.bluez.Error.Canceled"})
        self.assertEqual(self.agent.get()["reason"], "timeout")

    def _clean_exit(self, trigger):
        self.start_agent()
        self.call(1, "RequestConfirmation", DEV, 1)
        self.agent.get()
        trigger()
        self.assertEqual(self.fake.get(), {"id": 1, "error": "org.bluez.Error.Canceled"})
        self.assertEqual(self.fake.get()["event"], "unregistered")
        last = self.agent.until(lambda m: m is None or m.get("event") == "stopped")
        self.assertEqual(last, {"event": "stopped"})
        self.assertEqual(self.agent.p.wait(5), 0)

    def test_exit_on_eof(self):
        self._clean_exit(lambda: self.agent.p.stdin.close())

    def test_exit_on_sigterm(self):
        self._clean_exit(lambda: self.agent.p.send_signal(signal.SIGTERM))

    def test_exit_on_quit(self):
        self._clean_exit(lambda: self.agent.send({"action": "quit"}))

    def test_release_stops_agent(self):
        self.start_agent()
        self.call(1, "Release")
        self.assertEqual(self.fake.get()["id"], 1)
        self.assertEqual(self.agent.until(lambda m: m is None or m.get("event") == "stopped"), {"event": "stopped"})

    def test_no_bluez_exit_code(self):
        self.fake.stop()
        env = dict(os.environ, PYTHONPATH=ROOT)
        p = subprocess.run([sys.executable, "-m", "zsettings.btagent", "--bus", self.addr], env=env, input="",
                           capture_output=True, text=True, timeout=30)
        self.assertEqual(p.returncode, 2)
        lines = [json.loads(x) for x in p.stdout.splitlines()]
        self.assertEqual(lines[0]["event"], "error")
        self.assertEqual(lines[-1], {"event": "stopped"})


if __name__ == "__main__":
    unittest.main()
