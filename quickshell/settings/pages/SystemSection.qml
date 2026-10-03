import QtQuick
import "../../"
import "../../components"
import "../parts"

// Раздел «Система и приложения» (DESIGN §4.4, §6.5, этап 4) с под-вкладками. Подраздел — из openAt("system/<вкладка>").
// Вкладки добавляются по мере готовности бэкендов (Y1–Y6); пока: «Клавиатура», «Тачпад», «Сочетания», «Приложения», «Автозапуск», «Уведомления», «О системе».
Item {
    id: root

    property string sub: ""
    property string tab: "keyboard"
    readonly property var tabIds: ["keyboard", "touchpad", "binds", "apps", "autostart", "notifications", "about"]

    onSubChanged: applySub()
    onTabChanged: flick.contentY = 0
    Component.onCompleted: applySub()

    function applySub() {
        if (tabIds.indexOf(sub) >= 0)
            tab = sub;
    }

    // Вкладки тремя группами (ввод · приложения · сведения): 7 в одну полосу не помещаются в окно, Flow переносит группы.
    Flow {
        id: tabs
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: 8

        SetSegmented {
            options: [
                { value: "keyboard", label: "Клавиатура" },
                { value: "touchpad", label: "Тачпад" },
                { value: "binds", label: "Сочетания" }
            ]
            current: root.tab
            onSelected: v => root.tab = v
        }
        SetSegmented {
            options: [
                { value: "apps", label: "Приложения" },
                { value: "autostart", label: "Автозапуск" }
            ]
            current: root.tab
            onSelected: v => root.tab = v
        }
        SetSegmented {
            options: [
                { value: "notifications", label: "Уведомления" },
                { value: "about", label: "О системе" }
            ]
            current: root.tab
            onSelected: v => root.tab = v
        }
    }

    Flickable {
        id: flick
        anchors {
            left: parent.left
            right: parent.right
            top: tabs.bottom
            topMargin: 12
            bottom: parent.bottom
        }
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 20
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: 16

            KeyboardCard {
                width: parent.width
                visible: root.tab === "keyboard"
            }
            TouchpadCard {
                width: parent.width
                visible: root.tab === "touchpad"
            }
            BindsCard {
                width: parent.width
                visible: root.tab === "binds"
            }
            DefaultAppsCard {
                width: parent.width
                visible: root.tab === "apps"
            }
            AutostartCard {
                width: parent.width
                visible: root.tab === "autostart"
            }
            NotificationsCard {
                width: parent.width
                visible: root.tab === "notifications"
            }
            AboutCard {
                width: parent.width
                visible: root.tab === "about"
            }
        }
    }
}
