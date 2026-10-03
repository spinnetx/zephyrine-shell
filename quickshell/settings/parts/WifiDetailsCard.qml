pragma ComponentBehavior: Bound

import QtQuick
import "../../"
import "../../components"

// Детали текущего Wi-Fi подключения: сигнал, частота, канал, скорость, защита, IP, шлюз, DNS, MAC.
// Данные приходят из WifiData (nmcli device show + device wifi list); пустые поля не показываются.
SetCard {
    id: root

    property var store: null             // WifiData

    readonly property var rows: {
        const d = store;
        if (!d)
            return [];
        const ap = d.ap;
        const det = d.details;
        const out = [];
        const add = (k, v) => { if (v !== undefined && v !== null && String(v) !== "") out.push({ k: k, v: String(v) }); };
        add("Сеть", ap ? ap.ssid : det.connection);
        if (ap) {
            add("Сигнал", ap.signal + "%");
            add("Частота", ap.freq > 0 ? ap.freq + " МГц" + (ap.band ? " · " + ap.band : "") + (ap.chan ? " · канал " + ap.chan : "") : "");
            add("Скорость", ap.rate);
            add("Защита", ap.security !== "" ? ap.security : "открытая сеть");
            add("Точка доступа", ap.bssid);
        }
        add("IP-адрес", det.ip4.join(", "));
        add("Шлюз", det.gateway);
        add("DNS", det.dns.join(", "));
        add("IPv6", det.ip6.join(", "));
        add("MAC", det.mac);
        add("Интерфейс", d.device);
        return out;
    }

    title: "Текущее подключение"
    icon: Config.icons.info
    chipKind: "live"
    chipText: "подключено"

    Repeater {
        model: root.rows

        delegate: Item {
            id: line

            required property var modelData

            width: parent.width
            height: Math.max(24, val.implicitHeight + 4)

            Txt {
                id: lbl
                width: 130
                anchors.top: parent.top
                anchors.topMargin: 2
                text: line.modelData.k
                color: Colors.fgVariant
            }
            Txt {
                id: val
                anchors {
                    left: lbl.right
                    right: parent.right
                    top: parent.top
                    topMargin: 2
                }
                text: line.modelData.v
                wrapMode: Text.WrapAnywhere
                verticalAlignment: Text.AlignTop
            }
        }
    }
}
