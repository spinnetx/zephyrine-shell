import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../"

// Одна иконка трея: ЛКМ — activate (или меню), ПКМ — меню, СКМ — secondaryActivate.
Item {
    id: root

    required property var modelData

    implicitWidth: 20
    implicitHeight: 20
    visible: modelData.status !== Status.Passive

    function showMenu() {
        const p = root.mapToItem(null, 0, root.height + 4);
        modelData.display(root.QsWindow.window, p.x, p.y);
    }

    IconImage {
        anchors.fill: parent
        source: root.modelData.icon
        scale: mouse.containsMouse ? 1.15 : 1
        Behavior on scale {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.LeftButton) {
                if (root.modelData.onlyMenu && root.modelData.hasMenu)
                    root.showMenu();
                else
                    root.modelData.activate();
            } else if (event.button === Qt.RightButton) {
                if (root.modelData.hasMenu)
                    root.showMenu();
            } else {
                root.modelData.secondaryActivate();
            }
        }
        onWheel: wheel => root.modelData.scroll(wheel.angleDelta.y, false)
    }

    // Наведение → попап с заголовком/подсказкой и пунктами меню приложения.
    PopoutTrigger {
        kind: "tray"
        payload: root.modelData
    }
}
