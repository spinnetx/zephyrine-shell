import QtQuick
import "../"
import "../services"

// Wi-Fi / Ethernet отдельной пилюлей: значок (и уровень сигнала). Попап — kind "wifi" (как у статус-иконок).
Pill {
    id: root

    spacing: 6

    PopoutTrigger {
        parent: root
        kind: "wifi"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Net.kind === "ethernet" ? Config.icons.ethernet
            : Net.kind === "wifi" ? (Net.signal > 75 ? Config.icons.wifi4 : Net.signal > 50 ? Config.icons.wifi3 : Net.signal > 25 ? Config.icons.wifi2 : Config.icons.wifi1)
            : Config.icons.wifiOff
        color: Net.kind === "none" ? Colors.fgVariant : Colors.tertiary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: Net.kind === "wifi"
        text: Net.signal + "%"
    }
}
