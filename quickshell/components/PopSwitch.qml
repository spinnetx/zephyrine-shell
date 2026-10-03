import QtQuick
import "../"

// Переключатель on/off для попапов.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 38
    implicitHeight: 22
    radius: height / 2
    color: checked ? Colors.primary : Colors.surfaceContainerHighest
    border.width: 1
    border.color: checked ? Colors.primary : Colors.outline

    Behavior on color {
        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        color: root.checked ? Colors.primaryText : Colors.fg
        Behavior on x {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
