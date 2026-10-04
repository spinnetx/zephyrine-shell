pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../"

// Воркспейсы: показываем занятые + активный; активный — вытянутая пилюля.
Pill {
    id: root

    required property var screen
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int activeId: monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1

    horizontalPadding: 8
    spacing: 5

    onScrolled: delta => {
        if (delta > 0)
            Quickshell.execDetached(Config.workspaceCommand("m-1"));
        else if (delta < 0)
            Quickshell.execDetached(Config.workspaceCommand("m+1"));
    }

    Repeater {
        model: Config.workspaceCount

        Rectangle {
            id: dot

            required property int index
            readonly property int wsId: index + 1
            readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsId)
            readonly property bool active: root.activeId === wsId
            readonly property bool occupied: ws !== undefined && (ws.toplevels.values.length > 0 || (ws.lastIpcObject?.windows ?? 0) > 0)
            readonly property bool shown: active || occupied

            anchors.verticalCenter: parent.verticalCenter
            visible: shown || width > 0.5
            width: !shown ? 0 : active ? 26 : 10
            height: 10
            radius: 5
            opacity: shown ? 1 : 0
            color: active ? Colors.primary : Colors.outline

            Behavior on width {
                NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
            }
            Behavior on opacity {
                NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
            }
            Behavior on color {
                ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -3
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(Config.workspaceCommand(dot.wsId))
                onWheel: wheel => {
                    const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                    root.scrolled(d);
                }
            }
        }
    }
}
