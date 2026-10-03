import QtQuick
import "../"

// Горизонтальный ползунок 0..1 (клик и перетаскивание). Значение отдаёт через moved(v).
Item {
    id: root

    property real value: 0
    property color accent: Colors.primary
    signal moved(real v)

    implicitWidth: 200
    implicitHeight: 20

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Colors.surfaceContainerHighest

        Rectangle {
            width: Math.max(0, Math.min(1, root.value)) * parent.width
            height: parent.height
            radius: 3
            color: root.accent
        }
    }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(1, root.value)) * (root.width - width)
        color: Colors.fg
        scale: area.pressed ? 1.15 : 1
        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Config.animEasing }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function setFrom(mx) {
            root.moved(Math.max(0, Math.min(1, (mx - 7) / (root.width - 14))));
        }
        onPressed: mouse => setFrom(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                setFrom(mouse.x);
        }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
