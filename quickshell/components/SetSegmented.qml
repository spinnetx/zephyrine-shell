import QtQuick
import "../"

// Переключатель на 2–4 варианта. options — массив строк или {value, label}; current — выбранное значение.
Rectangle {
    id: root

    property var options: []
    property var current: undefined
    signal selected(var value)

    function valueOf(o) {
        return (o !== null && typeof o === "object") ? o.value : o;
    }
    function labelOf(o) {
        return (o !== null && typeof o === "object") ? String(o.label !== undefined ? o.label : o.value) : String(o);
    }

    implicitHeight: 30
    implicitWidth: row.implicitWidth + 6
    radius: 10
    color: Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
    border.width: 1
    border.color: activeFocus ? Qt.alpha(Colors.primary, 0.7) : Qt.alpha(Colors.outline, 0.35)
    opacity: enabled ? 1 : 0.5
    activeFocusOnTab: true

    function indexOfCurrent() {
        for (var i = 0; i < options.length; i++)
            if (valueOf(options[i]) === current)
                return i;
        return -1;
    }
    function move(dir) {
        if (options.length === 0)
            return;
        var i = indexOfCurrent();
        i = Math.max(0, Math.min(options.length - 1, i < 0 ? 0 : i + dir));
        selected(valueOf(options[i]));
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) {
            root.move(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.move(1);
            event.accepted = true;
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.options

            delegate: Rectangle {
                id: seg
                required property var modelData
                readonly property bool isCurrent: root.valueOf(modelData) === root.current

                width: segText.implicitWidth + 22
                height: root.height - 6
                radius: 7
                color: isCurrent ? Qt.alpha(Colors.primaryContainer, 0.75)
                    : segHover.hovered ? Colors.surfaceContainerHighest : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 120; easing.type: Config.animEasing }
                }

                Txt {
                    id: segText
                    anchors.centerIn: parent
                    text: root.labelOf(seg.modelData)
                    color: seg.isCurrent ? Colors.fg : Colors.fgVariant
                }
                HoverHandler {
                    id: segHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: {
                        root.forceActiveFocus();
                        root.selected(root.valueOf(seg.modelData));
                    }
                }
            }
        }
    }
}
