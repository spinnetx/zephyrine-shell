import QtQuick

// Скруглённая «пилюля» (как в Quickshell-баре): полупрозрачная, тонкая рамка.
// Содержимое кладётся внутрь (попадает в Row).
Rectangle {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing
    property bool clickable: false
    property bool active: false          // подсветка (например, «Точно?» или открытый список)
    property color activeColor: Theme.primaryContainer
    property real horizontalPadding: 10
    readonly property bool hovered: mouse.containsMouse

    signal clicked()

    implicitHeight: 30
    implicitWidth: row.implicitWidth + horizontalPadding * 2
    radius: Theme.pillRadius
    color: active ? activeColor
         : (hovered && clickable) ? Theme.surfaceContainerHighest
         : Theme.alpha(Theme.surfaceContainerHigh, Theme.panelAlpha)
    border.width: 1
    border.color: Theme.alpha(Theme.outline, 0.28)

    Behavior on color {
        ColorAnimation { duration: Theme.animMs; easing.type: Theme.easing }
    }
    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.animMs; easing.type: Theme.easing }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        height: parent.height
    }
}
