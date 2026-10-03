import QtQuick
import Quickshell.Services.SystemTray
import "../"

// Системный трей для вертикальной панели: иконки в колонку.
Pill {
    id: root

    readonly property bool shown: SystemTray.items.values.length > 0

    visible: shown
    horizontalPadding: 0
    implicitWidth: Config.pillHeight + 8
    implicitHeight: icons.implicitHeight + 12

    Column {
        id: icons
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: SystemTray.items

            TrayItem {}
        }
    }
}
