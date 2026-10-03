import QtQuick
import "../"

// Полоса прокрутки для Flickable / ListView.
// Тонкая, элегантная полоса с интерактивным перетаскиванием (drag) и кликом по треку.
Item {
    id: root

    property Flickable target: null

    // Настройки внешнего вида
    property real barWidth: hoverArea.containsMouse || dragArea.pressed ? 6 : 4
    property real minThumbHeight: 24
    property color thumbColor: dragArea.pressed ? Colors.primary
                                                : (hoverArea.containsMouse ? Qt.alpha(Colors.primary, 0.85)
                                                                           : Qt.alpha(Colors.outline, 0.55))

    visible: target !== null && target.contentHeight > target.height
    anchors.right: target ? target.right : parent.right
    anchors.rightMargin: 2
    anchors.top: target ? target.top : parent.top
    anchors.bottom: target ? target.bottom : parent.bottom
    width: 12
    z: 99

    // Полупрозрачный трек при наведении
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: hoverArea.containsMouse || dragArea.pressed ? Qt.alpha(Colors.surfaceContainerHighest, 0.35) : "transparent"
        Behavior on color {
            ColorAnimation { duration: 120; easing.type: Config.animEasing }
        }
    }

    // Ползунок (thumb)
    Rectangle {
        id: thumb
        anchors.right: parent.right
        anchors.rightMargin: 1
        width: root.barWidth
        radius: width / 2
        color: root.thumbColor

        height: {
            if (!root.target || root.target.height <= 0 || root.target.contentHeight <= 0)
                return root.minThumbHeight;
            const h = root.target.height * root.target.height / root.target.contentHeight;
            return Math.max(root.minThumbHeight, Math.min(root.target.height, h));
        }

        y: {
            if (!root.target || root.target.contentHeight <= root.target.height)
                return 0;
            const scrollRange = root.target.contentHeight - root.target.height;
            const trackRange = root.target.height - height;
            const progress = Math.max(0, Math.min(1, root.target.contentY / scrollRange));
            return progress * trackRange;
        }

        Behavior on width {
            NumberAnimation { duration: 120; easing.type: Config.animEasing }
        }
        Behavior on color {
            ColorAnimation { duration: 120; easing.type: Config.animEasing }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.NoButton
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        property real dragStartY: 0
        property real startContentY: 0

        onPressed: mouse => {
            if (!root.target)
                return;
            if (mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height) {
                dragStartY = mouse.y;
                startContentY = root.target.contentY;
            } else {
                const trackRange = root.target.height - thumb.height;
                if (trackRange > 0) {
                    const progress = Math.max(0, Math.min(1, (mouse.y - thumb.height / 2) / trackRange));
                    root.target.contentY = progress * (root.target.contentHeight - root.target.height);
                    dragStartY = thumb.y + thumb.height / 2;
                    startContentY = root.target.contentY;
                }
            }
        }

        onPositionChanged: mouse => {
            if (!pressed || !root.target)
                return;
            const deltaY = mouse.y - dragStartY;
            const trackRange = root.target.height - thumb.height;
            const scrollRange = root.target.contentHeight - root.target.height;
            if (trackRange > 0 && scrollRange > 0) {
                const deltaContent = deltaY * scrollRange / trackRange;
                root.target.contentY = Math.max(0, Math.min(scrollRange, startContentY + deltaContent));
            }
        }
    }
}
