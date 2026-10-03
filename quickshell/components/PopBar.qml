import QtQuick
import "../"

// Горизонтальная полоска 0..1 для попапов (мониторинг).
Rectangle {
    id: root

    property real value: 0
    property color accent: Colors.primary

    implicitWidth: 100
    implicitHeight: 6
    radius: height / 2
    color: Colors.surfaceContainerHighest

    Rectangle {
        width: Math.max(0, Math.min(1, root.value)) * parent.width
        height: parent.height
        radius: parent.radius
        color: root.accent
        Behavior on width {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
        Behavior on color {
            ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
    }
}
