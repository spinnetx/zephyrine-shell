"""Поддельный BlueZ для проверки btagent на ИЗОЛИРОВАННОЙ шине (dbus-daemon теста; реальный BlueZ не затрагивается).

Запуск: python3 fake_bluez.py <адрес шины>. Держит имя org.bluez: /org/bluez AgentManager1 (Register/Unregister/
RequestDefaultAgent) и /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF с Properties (Alias, Address). По stdin принимает
JSON-строки {"id":N,"method":"RequestConfirmation","args":[...]} и вызывает метод зарегистрированного агента;
в stdout пишет {"event":"registered|default|unregistered",...} и {"id":N,"result":..} / {"id":N,"error":"имя"}.
"""
import json
import os
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

DEV = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
SIGS = {"Release": "", "RequestPinCode": "o", "DisplayPinCode": "os", "RequestPasskey": "o",
        "DisplayPasskey": "ouq", "RequestConfirmation": "ou", "RequestAuthorization": "o",
        "AuthorizeService": "os", "Cancel": ""}


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Manager(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, "/org/bluez")
        self.agent = None   # (sender, path)

    @dbus.service.method("org.bluez.AgentManager1", in_signature="os", out_signature="", sender_keyword="sender")
    def RegisterAgent(self, path, cap, sender=None):
        if self.agent:
            raise dbus.exceptions.DBusException("exists", name="org.bluez.Error.AlreadyExists")
        self.agent = (sender, str(path))
        out({"event": "registered", "path": str(path), "capability": str(cap)})

    @dbus.service.method("org.bluez.AgentManager1", in_signature="o", out_signature="")
    def RequestDefaultAgent(self, path):
        out({"event": "default", "path": str(path)})

    @dbus.service.method("org.bluez.AgentManager1", in_signature="o", out_signature="")
    def UnregisterAgent(self, path):
        self.agent = None
        out({"event": "unregistered", "path": str(path)})


class Device(dbus.service.Object):
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return {"Alias": "Тест-наушники", "Address": "AA:BB:CC:DD:EE:FF"}


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.bus.BusConnection(sys.argv[1])
    bus.request_name("org.bluez")
    mgr = Manager(bus)
    Device(bus, DEV)
    loop = GLib.MainLoop()

    def call(cmd):
        if not mgr.agent:
            out({"id": cmd["id"], "error": "no-agent"})
            return
        sender, path = mgr.agent
        m = cmd["method"]
        args = [dbus.ObjectPath(a) if t == "o" else dbus.String(a) if t == "s" else dbus.UInt32(a) if t == "u"
                else dbus.UInt16(a) for t, a in zip(SIGS[m], cmd.get("args", []))]
        obj = bus.get_object(sender, path)
        i = dbus.Interface(obj, "org.bluez.Agent1")
        i.get_dbus_method(m)(*args, reply_handler=lambda *r: out({"id": cmd["id"], "result": [str(x) if not isinstance(x, int) else int(x) for x in r]}),
                             error_handler=lambda e: out({"id": cmd["id"], "error": e.get_dbus_name()}), timeout=20)

    def on_in(fd, cond):
        data = os.read(fd, 65536)
        if not data:
            loop.quit()
            return False
        for line in data.decode().splitlines():
            if line.strip():
                call(json.loads(line))
        return True

    GLib.io_add_watch(0, GLib.IO_IN | GLib.IO_HUP, on_in)
    out({"event": "up"})
    loop.run()


main()
