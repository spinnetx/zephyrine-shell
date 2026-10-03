pragma ComponentBehavior: Bound

import QtQuick
import "../../"
import "../../components"

// Сохранённые Wi-Fi сети (профили NetworkManager): автоподключение (переключатель) и «Забыть» с подтверждением
// (двойное нажатие, DESIGN §7.3). Действия выполняет WifiData (nmcli connection modify/delete по UUID).
SetCard {
    id: root

    property var store: null             // WifiData

    readonly property var items: store ? store.saved : []

    title: "Сохранённые сети"
    icon: Config.icons.lock
    chipKind: "neutral"
    chipText: items.length > 0 ? String(items.length) : ""

    Txt {
        visible: root.items.length === 0
        width: parent.width
        text: root.store && root.store.loaded ? "Сохранённых сетей нет" : "Загрузка…"
        color: Colors.fgVariant
    }

    Repeater {
        model: root.items

        delegate: Item {
            id: line

            required property var modelData

            width: parent.width
            height: 40

            Row {
                anchors {
                    left: parent.left
                    leftMargin: 4
                    right: ctl.left
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                spacing: 10
                clip: true

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: line.modelData.active ? Config.icons.wifi4 : Config.icons.wifi1
                    color: line.modelData.active ? Colors.primary : Colors.fgVariant
                    font.pixelSize: Config.iconSize + 2
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: line.modelData.name
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 300)
                    font.bold: line.modelData.active
                }
                StatusChip {
                    visible: line.modelData.active
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "live"
                    text: "подключено"
                }
            }

            Row {
                id: ctl
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Автоподключение"
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                }
                PopSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: line.modelData.autoconnect
                    enabled: !root.store.actBusy
                    opacity: enabled ? 1 : 0.5
                    onToggled: value => root.store.setAutoconnect(line.modelData.uuid, line.modelData.name, value)
                }
                SetButton {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "danger"
                    icon: Config.icons.trash
                    text: "Забыть"
                    confirm: true
                    confirmText: "Забыть сеть?"
                    enabled: !root.store.actBusy
                    tooltip: "Удалить сохранённый профиль и пароль"
                    onClicked: root.store.forget(line.modelData.uuid, line.modelData.name)
                }
            }
        }
    }
}
