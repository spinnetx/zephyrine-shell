import QtQuick
import "../../"
import "../../components"
import "../wifi.js" as WifiJs

// Строка списка сетей на странице Wi-Fi: уровень сигнала, имя, замок, чипы, процент и кнопка действия.
// Активная сеть — «Отключить» (с подтверждением, DESIGN §7.3); остальные — «Подключить» (новая защищённая сеть
// сначала откроет форму пароля — решает Wifi.select в родителе).
Rectangle {
    id: root

    property var net: ({ ssid: "", signal: 0, security: "", active: false })
    property bool known: false          // есть сохранённый профиль
    property bool connecting: false     // к этой сети идёт подключение
    property bool busy: false           // идёт любое подключение — кнопки неактивны
    signal connectClicked
    signal disconnectClicked

    readonly property bool secured: net.security !== "" && net.security !== "--"
    readonly property var sigIcons: [Config.icons.wifi1, Config.icons.wifi1, Config.icons.wifi2, Config.icons.wifi3, Config.icons.wifi4]

    implicitHeight: 40
    radius: 10
    color: net.active ? Qt.alpha(Colors.primary, 0.12) : rowHover.hovered ? Qt.alpha(Colors.surfaceContainerHighest, 0.6) : "transparent"
    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Config.animEasing }
    }

    HoverHandler {
        id: rowHover
    }

    Row {
        anchors {
            left: parent.left
            leftMargin: 10
            right: actions.left
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        spacing: 10
        clip: true

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.sigIcons[WifiJs.signalLevel(root.net.signal)]
            color: root.net.active ? Colors.primary : Colors.fg
            font.pixelSize: Config.iconSize + 2
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.net.ssid
            font.bold: root.net.active
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 260)
        }
        Txt {
            visible: root.secured
            anchors.verticalCenter: parent.verticalCenter
            text: Config.icons.lock
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize
        }
        StatusChip {
            visible: root.net.active
            anchors.verticalCenter: parent.verticalCenter
            kind: "live"
            text: "подключено"
        }
        StatusChip {
            visible: root.connecting
            anchors.verticalCenter: parent.verticalCenter
            kind: "neutral"
            text: "подключение…"
        }
        StatusChip {
            visible: root.known && !root.net.active
            anchors.verticalCenter: parent.verticalCenter
            kind: "neutral"
            text: "сохранена"
        }
    }

    Row {
        id: actions
        anchors {
            right: parent.right
            rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        spacing: 10

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.net.signal + "%"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }
        SetButton {
            visible: root.net.active
            anchors.verticalCenter: parent.verticalCenter
            kind: "danger"
            confirm: true
            confirmText: "Отключить?"
            text: "Отключить"
            enabled: !root.busy
            onClicked: root.disconnectClicked()
        }
        SetButton {
            visible: !root.net.active
            anchors.verticalCenter: parent.verticalCenter
            text: "Подключить"
            enabled: !root.busy
            onClicked: root.connectClicked()
        }
    }
}
