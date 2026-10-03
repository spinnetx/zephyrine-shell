pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../"

// Всплывающая подсказка под элементом target (появляется с задержкой при hovered).
Item {
    id: root

    required property Item target
    property string text: ""
    property bool hovered: false
    property bool shown: false

    onHoveredChanged: {
        if (hovered && text !== "") {
            delay.restart();
        } else {
            delay.stop();
            shown = false;
        }
    }

    Timer {
        id: delay
        interval: Config.tipDelayMs
        onTriggered: root.shown = root.hovered && root.text !== ""
    }

    LazyLoader {
        active: root.shown

        PopupWindow {
            visible: true
            color: "transparent"
            // Подсказка раскрывается от панели: под верхней, над нижней, справа от левой, слева от правой.
            readonly property string side: Config.barPosition
            anchor.item: root.target
            anchor.edges: side === "bottom" ? Edges.Top : side === "left" ? Edges.Right : side === "right" ? Edges.Left : Edges.Bottom
            anchor.gravity: side === "bottom" ? Edges.Top : side === "left" ? Edges.Right : side === "right" ? Edges.Left : Edges.Bottom
            implicitWidth: box.implicitWidth + (Config.barVertical ? 6 : 0)
            implicitHeight: box.implicitHeight + (Config.barVertical ? 0 : 6)

            Rectangle {
                id: box
                x: side === "left" ? 6 : 0
                y: side === "top" ? 6 : 0
                implicitWidth: label.implicitWidth + 20
                implicitHeight: label.implicitHeight + 14
                radius: 10
                color: Colors.surfaceContainerHigh
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.5)

                Txt {
                    id: label
                    anchors.centerIn: parent
                    text: root.text
                    font.pixelSize: Config.fontSize - 1
                }
            }
        }
    }
}
