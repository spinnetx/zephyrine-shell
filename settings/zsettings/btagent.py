"""Агент BlueZ (org.bluez.Agent1) для сопряжения с вводом/подтверждением кода (DESIGN §4.2, §9.3 N3).

В сессии нет своего агента BlueZ (bluedevil удалён), поэтому устройства, которым нужен PIN/passkey/подтверждение
кода, сопрячь нельзя. Этот помощник на время сопряжения регистрирует Agent1 на системной шине (capability
KeyboardDisplay) и общается с UI (QML) JSON-строками по stdio. Запускает и останавливает его страница Bluetooth.

Выбор библиотеки (проверено `python3 -c` на этой машине, без установки пакетов): есть dbus-python, gi (PyGObject)
и jeepney; dasbus и pydbus нет. Берём dbus-python + GLib mainloop: экспорт объекта с методами Agent1 и
асинхронные ответы (async_callbacks) — штатные средства библиотеки, а GLib mainloop заодно обслуживает stdin,
таймеры и сигналы. Логика (ядро Core) от шины не зависит и тестируется без BlueZ; импорт dbus/gi отложен.

Протокол (по одной JSON-строке, UTF-8).
  stdout (агент -> UI):
    {"event":"ready","path":..,"capability":..,"default":true|false}   агент зарегистрирован
    {"event":"pair_request","id":N,"device":"Имя","address":"AA:..","kind":K,"timeout":60, ...}
        K: confirm (+passkey)        - «код совпадает?» (RequestConfirmation)
           display_passkey (+passkey, entered) - показать код, пользователь вводит его на устройстве
           display_pin (+pin)        - показать PIN, его вводят на устройстве
           passkey                   - запросить passkey 0..999999
           pin                       - запросить PIN (1..16 символов)
           authorize                 - разрешить входящее сопряжение (RequestAuthorization)
           authorize_service (+uuid) - разрешить использовать сервис (AuthorizeService)
    {"event":"pair_update","id":N,"entered":3}                         DisplayPasskey: введено цифр
    {"event":"pair_end","id":N,"reason":"answered|rejected|cancel|timeout|dismissed|shutdown"}
    {"event":"error","message":"..","id":N?}                           ошибка (в т.ч. неверный ввод; запрос остаётся)
    {"event":"stopped"}                                                последняя строка перед выходом
  stdin (UI -> агент), "id" необязателен (иначе - самый новый запрос, ждущий ответа):
    {"action":"confirm"}  {"action":"reject"}  {"action":"passkey","value":123456}
    {"action":"pin","value":"0000"}  {"action":"quit"}
Коды (passkey/pin) не пишутся ни в stderr, ни в логи - только в stdout-событие для UI.
EOF на stdin (UI умер), SIGTERM/SIGINT/SIGHUP: отклонить ждущие запросы, UnregisterAgent, выход.
Коды выхода: 0 - штатно; 2 - не удалось подключиться к шине или зарегистрировать агента; 3 - нет dbus/gi.
"""
import argparse
import json
import os
import signal
import sys

AGENT_PATH = "/org/zephyrine/btagent"
CAPABILITY = "KeyboardDisplay"
ERR_REJECTED = "org.bluez.Error.Rejected"
ERR_CANCELED = "org.bluez.Error.Canceled"
DEFAULT_TIMEOUT = 60.0
MAX_LINE = 8192

# Виды запросов, которым нужен ответ пользователя, и допустимые для них действия.
AWAITING = {
    "confirm": ("confirm", "reject"),
    "authorize": ("confirm", "reject"),
    "authorize_service": ("confirm", "reject"),
    "passkey": ("passkey", "reject"),
    "pin": ("pin", "reject"),
}
DISPLAY = ("display_passkey", "display_pin")


def address_from_path(path):
    """/org/bluez/hci0/dev_AA_BB_.. -> AA:BB:.. (запасной вариант, если свойства устройства недоступны)."""
    tail = str(path).rsplit("/", 1)[-1]
    if tail.startswith("dev_"):
        return tail[4:].replace("_", ":")
    return ""


def parse_passkey(value):
    """passkey 0..999999 из int или строки цифр; иначе ValueError."""
    if isinstance(value, bool):
        raise ValueError("passkey должен быть числом")
    if isinstance(value, str):
        s = value.strip()
        if not s.isascii() or not s.isdigit() or len(s) > 6:
            raise ValueError("passkey: до 6 цифр")
        value = int(s)
    if not isinstance(value, int) or not 0 <= value <= 999999:
        raise ValueError("passkey: число 0..999999")
    return value


def parse_pin(value):
    """PIN 1..16 байт UTF-8 (ограничение BlueZ); иначе ValueError."""
    if not isinstance(value, str) or value == "":
        raise ValueError("PIN не должен быть пустым")
    if len(value.encode("utf-8")) > 16:
        raise ValueError("PIN: не больше 16 символов")
    return value


class Request:
    def __init__(self, rid, kind, path, device, address, reply=None, error=None, **extra):
        self.id = rid
        self.kind = kind
        self.path = path
        self.device = device
        self.address = address
        self.reply = reply      # reply(value=None) - ответ BlueZ (только для ждущих ответа)
        self.error = error      # error(dbus_error_name, message)
        self.extra = extra
        self.timer = None

    @property
    def awaiting(self):
        return self.kind in AWAITING


class Core:
    """Логика агента без D-Bus.

    emit(dict)               - событие для UI;
    resolve(path) -> (имя, адрес) - сведения об устройстве (может бросать - тогда запасной вариант);
    schedule(sec, fn) -> token, cancel(token) - таймеры (в тестах - поддельные);
    on_quit()                - попросить главный цикл завершиться.
    """

    def __init__(self, emit, resolve, schedule, cancel, on_quit=None, timeout=DEFAULT_TIMEOUT):
        self.emit = emit
        self.resolve = resolve
        self.schedule = schedule
        self.cancel = cancel
        self.on_quit = on_quit or (lambda: None)
        self.timeout = timeout
        self.requests = {}
        self._next = 1
        self.closed = False

    # ---- вспомогательное ----
    def _describe(self, path):
        try:
            name, address = self.resolve(path)
        except Exception:
            name, address = "", ""
        address = address or address_from_path(path)
        return (name or address or str(path)), address

    def _new(self, kind, path, reply=None, error=None, **extra):
        # Повторный display_passkey для того же устройства - это обновление, а не новый запрос.
        device, address = self._describe(path)
        rid = self._next
        self._next += 1
        req = Request(rid, kind, path, device, address, reply, error, **extra)
        self.requests[rid] = req
        req.timer = self.schedule(self.timeout, lambda: self._expire(rid))
        ev = {"event": "pair_request", "id": rid, "device": device, "address": address,
              "kind": kind, "timeout": self.timeout}
        ev.update(extra)
        self.emit(ev)
        return req

    def _finish(self, req, reason):
        if self.requests.pop(req.id, None) is None:
            return
        if req.timer is not None:
            self.cancel(req.timer)
            req.timer = None
        self.emit({"event": "pair_end", "id": req.id, "reason": reason})

    def _expire(self, rid):
        req = self.requests.get(rid)
        if req is None:
            return
        req.timer = None
        if req.awaiting and req.error:
            req.error(ERR_CANCELED, "timeout")
        self._finish(req, "timeout")

    # ---- методы Agent1 (вызываются слоем D-Bus) ----
    def request_confirmation(self, path, passkey, reply, error):
        self._new("confirm", path, reply, error, passkey=int(passkey))

    def request_authorization(self, path, reply, error):
        self._new("authorize", path, reply, error)

    def authorize_service(self, path, uuid, reply, error):
        self._new("authorize_service", path, reply, error, uuid=str(uuid))

    def request_passkey(self, path, reply, error):
        self._new("passkey", path, reply, error)

    def request_pin(self, path, reply, error):
        self._new("pin", path, reply, error)

    def display_passkey(self, path, passkey, entered):
        passkey, entered = int(passkey), int(entered)
        for req in self.requests.values():
            if req.kind == "display_passkey" and req.path == path:
                if req.extra.get("entered") != entered:
                    req.extra["entered"] = entered
                    self.emit({"event": "pair_update", "id": req.id, "entered": entered})
                return
        self._new("display_passkey", path, passkey=passkey, entered=entered)

    def display_pin(self, path, pin):
        self._new("display_pin", path, pin=str(pin))

    def cancel_all(self):
        """Cancel() от BlueZ: ждущие вызовы уже отброшены самим BlueZ - отвечать на них не нужно."""
        for req in list(self.requests.values()):
            self._finish(req, "cancel")

    def released(self):
        """Release() от BlueZ: агент больше не нужен."""
        for req in list(self.requests.values()):
            self._finish(req, "cancel")
        self.on_quit()

    # ---- команды UI ----
    def _target(self, cmd):
        rid = cmd.get("id")
        if rid is not None:
            return self.requests.get(rid)
        waiting = [r for r in self.requests.values() if r.awaiting]
        if not waiting and cmd.get("action") == "reject":
            waiting = list(self.requests.values())     # «закрыть» показ кода
        return waiting[-1] if waiting else None

    def handle_command(self, cmd):
        """Одна команда UI (разобранный JSON). Ошибки ввода - событие error, запрос остаётся ждать."""
        if not isinstance(cmd, dict):
            self.emit({"event": "error", "message": "команда должна быть JSON-объектом"})
            return
        action = cmd.get("action")
        if action == "quit":
            self.shutdown()
            self.on_quit()
            return
        if action not in ("confirm", "reject", "passkey", "pin"):
            self.emit({"event": "error", "message": "неизвестное действие: %s" % (action,)})
            return
        rid = cmd.get("id")
        if rid is not None and (isinstance(rid, bool) or not isinstance(rid, int)):
            self.emit({"event": "error", "message": "id должен быть числом"})
            return
        req = self._target(cmd)
        if req is None:
            self.emit({"event": "error", "message": "нет запроса, ждущего ответа"
                       if rid is None else "нет запроса с id %s" % rid, **({"id": rid} if rid is not None else {})})
            return
        if action == "reject" and not req.awaiting:
            self._finish(req, "dismissed")
            return
        if not req.awaiting or action not in AWAITING[req.kind]:
            self.emit({"event": "error", "id": req.id,
                       "message": "действие %s не подходит к запросу %s" % (action, req.kind)})
            return
        try:
            if action == "reject":
                req.error(ERR_REJECTED, "rejected by user")
                self._finish(req, "rejected")
                return
            if action == "confirm":
                req.reply()
            elif action == "passkey":
                req.reply(parse_passkey(cmd.get("value")))
            else:
                req.reply(parse_pin(cmd.get("value")))
        except ValueError as e:
            self.emit({"event": "error", "id": req.id, "message": str(e)})
            return
        self._finish(req, "answered")

    def handle_line(self, line):
        line = line.strip()
        if not line:
            return
        try:
            cmd = json.loads(line)
        except ValueError:
            self.emit({"event": "error", "message": "некорректный JSON"})
            return
        self.handle_command(cmd)

    def shutdown(self):
        """Выход: ждущие запросы отклоняем (BlueZ получит ответ, а не таймаут), остальные закрываем."""
        if self.closed:
            return
        self.closed = True
        for req in list(self.requests.values()):
            if req.awaiting and req.error:
                try:
                    req.error(ERR_CANCELED, "agent stopped")
                except Exception:
                    pass
            self._finish(req, "shutdown")


class LineBuffer:
    """Склейка чтения из stdin в строки; слишком длинная строка отбрасывается целиком."""

    def __init__(self, limit=MAX_LINE):
        self.buf = b""
        self.limit = limit
        self.skipping = False

    def feed(self, data):
        out = []
        self.buf += data
        while True:
            i = self.buf.find(b"\n")
            if i < 0:
                break
            line, self.buf = self.buf[:i], self.buf[i + 1:]
            if self.skipping:
                self.skipping = False
            elif len(line) <= self.limit:
                out.append(line.decode("utf-8", "replace"))
            else:
                out.append("")
        if len(self.buf) > self.limit:
            self.buf = b""
            self.skipping = True
        return out


# ---------------------------------------------------------------------------------------------------------
# Слой D-Bus (dbus-python + GLib). Здесь нет логики, только проводка к Core.

def _make_agent_class(dbus, Core_):
    import dbus.service

    IFACE = "org.bluez.Agent1"

    def exc(name, msg):
        return dbus.exceptions.DBusException(msg, name=name)

    class Agent(dbus.service.Object):
        def __init__(self, bus, path, core):
            super().__init__(bus, path)
            self.core = core

        @dbus.service.method(IFACE, in_signature="", out_signature="")
        def Release(self):
            self.core.released()

        @dbus.service.method(IFACE, in_signature="o", out_signature="s", async_callbacks=("ok", "err"))
        def RequestPinCode(self, device, ok, err):
            self.core.request_pin(str(device), lambda v=None: ok(dbus.String(v)), lambda n, m: err(exc(n, m)))

        @dbus.service.method(IFACE, in_signature="os", out_signature="")
        def DisplayPinCode(self, device, pincode):
            self.core.display_pin(str(device), str(pincode))

        @dbus.service.method(IFACE, in_signature="o", out_signature="u", async_callbacks=("ok", "err"))
        def RequestPasskey(self, device, ok, err):
            self.core.request_passkey(str(device), lambda v=None: ok(dbus.UInt32(v)), lambda n, m: err(exc(n, m)))

        @dbus.service.method(IFACE, in_signature="ouq", out_signature="")
        def DisplayPasskey(self, device, passkey, entered):
            self.core.display_passkey(str(device), int(passkey), int(entered))

        @dbus.service.method(IFACE, in_signature="ou", out_signature="", async_callbacks=("ok", "err"))
        def RequestConfirmation(self, device, passkey, ok, err):
            self.core.request_confirmation(str(device), int(passkey), lambda v=None: ok(), lambda n, m: err(exc(n, m)))

        @dbus.service.method(IFACE, in_signature="o", out_signature="", async_callbacks=("ok", "err"))
        def RequestAuthorization(self, device, ok, err):
            self.core.request_authorization(str(device), lambda v=None: ok(), lambda n, m: err(exc(n, m)))

        @dbus.service.method(IFACE, in_signature="os", out_signature="", async_callbacks=("ok", "err"))
        def AuthorizeService(self, device, uuid, ok, err):
            self.core.authorize_service(str(device), str(uuid), lambda v=None: ok(), lambda n, m: err(exc(n, m)))

        @dbus.service.method(IFACE, in_signature="", out_signature="")
        def Cancel(self):
            self.core.cancel_all()

    return Agent


def run(bus_name="system", path=AGENT_PATH, capability=CAPABILITY, timeout=DEFAULT_TIMEOUT,
        make_default=True, stdin=None, stdout=None):
    """Главный цикл. Возвращает код выхода."""
    out = stdout or sys.stdout
    fd_in = (stdin or sys.stdin).fileno()
    loops = []

    def quit_loop():
        if loops and loops[0].is_running():
            loops[0].quit()

    def emit(obj):
        try:
            out.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
            out.flush()
        except (BrokenPipeError, ValueError):
            quit_loop()

    try:
        import dbus
        import dbus.mainloop.glib
        from gi.repository import GLib
    except ImportError as e:
        emit({"event": "error", "message": "нет dbus-python/gi: %s" % e})
        return 3

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()
    loops.append(loop)
    state = {"code": 0}

    try:
        if bus_name == "system":
            bus = dbus.SystemBus()
        elif bus_name == "session":
            bus = dbus.SessionBus()
        else:
            bus = dbus.bus.BusConnection(bus_name)
    except Exception as e:
        emit({"event": "error", "message": "нет подключения к шине: %s" % e})
        emit({"event": "stopped"})
        return 2

    def resolve(dev_path):
        obj = bus.get_object("org.bluez", dev_path)
        props = dbus.Interface(obj, "org.freedesktop.DBus.Properties").GetAll("org.bluez.Device1", timeout=2)
        return str(props.get("Alias") or props.get("Name") or ""), str(props.get("Address") or "")

    def schedule(sec, fn):
        def once():
            fn()
            return False
        return GLib.timeout_add(int(sec * 1000), once)

    def cancel(token):
        try:
            GLib.source_remove(token)
        except Exception:
            pass

    core = Core(emit, resolve, schedule, cancel, on_quit=quit_loop, timeout=timeout)
    agent = _make_agent_class(dbus, Core)(bus, path, core)

    registered = False
    manager = None
    try:
        manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
        manager.RegisterAgent(path, capability)
        registered = True
        if make_default:
            manager.RequestDefaultAgent(path)
    except Exception as e:
        emit({"event": "error", "message": "не удалось зарегистрировать агента: %s" % getattr(e, "get_dbus_message", lambda: e)()})
        state["code"] = 2
    else:
        emit({"event": "ready", "path": path, "capability": capability, "default": bool(make_default)})

    if state["code"] == 0:
        lines = LineBuffer()

        def on_stdin(fd, cond):
            if cond & GLib.IO_IN:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    data = b""
                if data:
                    for ln in lines.feed(data):
                        core.handle_line(ln)
                    return True
            quit_loop()    # EOF/HUP: UI закрыт - агент не нужен
            return False

        GLib.io_add_watch(fd_in, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
        try:
            from gi.repository import GLibUnix
            sig_add = GLibUnix.signal_add
        except (ImportError, AttributeError):
            sig_add = GLib.unix_signal_add     # старый PyGObject
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            sig_add(GLib.PRIORITY_HIGH, sig, lambda *a: (quit_loop(), False)[1])
        try:
            loop.run()
        except KeyboardInterrupt:
            pass

    core.shutdown()
    if registered:
        try:
            manager.UnregisterAgent(path, timeout=3)
        except Exception:
            pass
    try:
        agent.remove_from_connection()
    except Exception:
        pass
    emit({"event": "stopped"})
    return state["code"]


def main(argv=None):
    ap = argparse.ArgumentParser(prog="zs-btagent", description="Агент BlueZ для сопряжения (JSON по stdio).")
    ap.add_argument("--bus", default="system", help="system | session | адрес шины (для проверок на изолированной шине)")
    ap.add_argument("--path", default=AGENT_PATH)
    ap.add_argument("--capability", default=CAPABILITY)
    ap.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="секунд на ответ пользователя")
    ap.add_argument("--no-default", action="store_true", help="не вызывать RequestDefaultAgent")
    args = ap.parse_args(argv)
    return run(args.bus, args.path, args.capability, args.timeout, not args.no_default)


if __name__ == "__main__":
    sys.exit(main())
