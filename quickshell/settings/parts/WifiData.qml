import QtQuick
import Quickshell.Io
import "../../services"
import "../wifi.js" as WifiJs

// Данные страницы Wi-Fi, которых нет в services/Wifi.qml (он отвечает за радио, список сетей и подключение):
// детали подключения (IP, шлюз, DNS, MAC), параметры активной точки (сигнал, частота, канал), сохранённые профили
// и действия над ними (отключиться, забыть, автоподключение). Только nmcli (LC_ALL=C); разбор — settings/wifi.js.
// Опрашивается страницей (refresh()), сам по таймеру не работает.
Item {
    id: root

    property string device: ""                                  // wlan0
    property var details: WifiJs.parseDeviceShow("")             // { mac, state, connection, ip4[], gateway, dns[], ip6[] }
    property var ap: null                                        // активная точка: { ssid, signal, freq, band, chan, rate, security, bssid }
    property var saved: []                                       // [{ name, uuid, autoconnect, active }]
    property bool loaded: false
    readonly property bool connected: device !== "" && /^100\b/.test(details.state)

    // Действие пользователя (отключиться / забыть / автоподключение): один процесс за раз.
    property bool actBusy: false
    property string errorText: ""                                // по-русски; показывается баннером страницы
    property string errorRaw: ""
    property var pending: ({ ok: "", err: "" })

    function refresh() {
        if (!infoProc.running)
            infoProc.running = true;
    }

    function clearError() {
        errorText = "";
        errorRaw = "";
    }

    function run(cmd, okMsg, errTitle) {
        if (act.running)
            return;
        actBusy = true;
        clearError();
        pending = { ok: okMsg, err: errTitle };
        act.command = cmd;
        act.running = true;
    }

    // Отключиться от активной сети (устройство остаётся включённым; профиль не удаляется).
    function disconnectActive() {
        if (device !== "")
            run(["nmcli", "device", "disconnect", device], "Отключено" + (ap ? ": " + ap.ssid : ""), "Не удалось отключиться");
    }

    // Забыть сеть: удаляет профиль NetworkManager (пароль теряется).
    function forget(uuid, name) {
        run(["nmcli", "connection", "delete", "uuid", uuid], "Сеть забыта: " + name, "Не удалось забыть сеть");
    }

    function setAutoconnect(uuid, name, on) {
        run(["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", on ? "yes" : "no"],
            (on ? "Автоподключение включено: " : "Автоподключение выключено: ") + name, "Не удалось изменить автоподключение");
    }

    function parse(text) {
        const parts = text.split(/^---$/m);
        const head = parts[0] ?? "";
        const nl = head.indexOf("\n");
        const first = nl < 0 ? head : head.slice(0, nl);
        device = first.startsWith("DEV:") ? first.slice(4).trim() : "";
        details = WifiJs.parseDeviceShow(nl < 0 ? "" : head.slice(nl + 1));
        ap = WifiJs.parseActiveAp(parts[1] ?? "");
        saved = WifiJs.parseSaved(parts[2] ?? "");
        loaded = true;
    }

    Process {
        id: infoProc
        environment: ({ LC_ALL: "C" })
        command: ["sh", "-c",
            "d=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2==\"wifi\"{print $1;exit}'); echo \"DEV:$d\";"
            + " [ -n \"$d\" ] && nmcli -t -f GENERAL.HWADDR,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS device show \"$d\";"
            + " echo '---'; nmcli -t -f IN-USE,SSID,SIGNAL,FREQ,CHAN,RATE,SECURITY,BSSID device wifi list --rescan no;"
            + " echo '---'; nmcli -t -f NAME,UUID,TYPE,AUTOCONNECT,ACTIVE connection show"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Process {
        id: act
        environment: ({ LC_ALL: "C" })
        stderr: StdioCollector {
            id: actErr
        }
        onExited: code => {
            root.actBusy = false;
            if (code === 0) {
                Toaster.show("Wi-Fi", root.pending.ok, "", "success");
            } else {
                const lines = actErr.text.split("\n").map(l => l.trim()).filter(l => l !== "");
                root.errorText = root.pending.err;
                root.errorRaw = (lines.find(l => l.startsWith("Error:")) ?? lines[lines.length - 1] ?? "").replace(/^Error: /, "");
            }
            root.refresh();
            Wifi.refresh(false);
            Net.refresh();
        }
    }
}
