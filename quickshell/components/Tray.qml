import QtQuick
import Quickshell.Services.SystemTray

// Системный трей (StatusNotifierItem).
Pill {
    readonly property bool shown: SystemTray.items.values.length > 0
    visible: shown
    spacing: 8

    Repeater {
        model: SystemTray.items

        TrayItem {
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
