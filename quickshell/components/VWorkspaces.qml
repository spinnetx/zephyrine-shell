pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "workspaces-logic.js" as WsLogic
import "../"

// Воркспейсы для вертикальной панели: колонка точек, активная — вытянутая вниз. Логика та же, что у Workspaces.
Pill {
    id: root

    required property var screen
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int activeId: monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1

    horizontalPadding: 0
    implicitWidth: Config.pillHeight + 8
    implicitHeight: dots.implicitHeight + 16

    function getOccupiedWorkspaces() {
        const occ = [];
        for (let i = 1; i <= Config.workspaceCount; i++) {
            const ws = Hyprland.workspaces.values.find(w => w.id === i);
            const onThisMon = !root.monitor || !ws?.monitor || ws.monitor.name === root.monitor.name || ws.monitor.id === root.monitor.id;
            const isOccupied = ws !== undefined && onThisMon && (ws.toplevels.values.length > 0 || (ws.lastIpcObject?.windows ?? 0) > 0);
            if (isOccupied)
                occ.push(i);
        }
        return occ;
    }

    onScrolled: delta => {
        const target = WsLogic.calculateNextWorkspace(root.activeId, delta, root.getOccupiedWorkspaces(), Config.workspaceCount);
        if (target && target !== root.activeId)
            Quickshell.execDetached(Config.workspaceCommand(target));
    }

    Column {
        id: dots
        y: (root.height - height) / 2
        spacing: 5

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

                visible: shown || height > 0.5
                width: 10
                height: !shown ? 0 : active ? 26 : 10
                radius: 5
                opacity: shown ? 1 : 0
                color: active ? Colors.primary : Colors.outline

                Behavior on height {
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
}
