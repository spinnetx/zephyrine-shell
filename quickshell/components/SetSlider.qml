import QtQuick
import "../"

// Ползунок from..to с шагом, значением справа и необязательной кнопкой сброса.
// preview(v) — при движении (живое превью), commit(v) — при отпускании / после клавиши / колеса / сброса.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real step: 0              // 0 — непрерывно
    property real value: 0
    property real defaultValue: NaN    // если задано и showReset — рядом кнопка ↺
    property bool showReset: false
    property int decimals: 2
    property string suffix: ""
    property color accent: Colors.primary
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : value
    readonly property real fraction: to > from ? Math.max(0, Math.min(1, (shown - from) / (to - from))) : 0
    readonly property bool resettable: showReset && !isNaN(defaultValue) && Math.abs(value - defaultValue) > 1e-9
    signal preview(real v)
    signal commit(real v)

    implicitWidth: 280
    implicitHeight: 28
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.5

    function snap(v) {
        var r = Math.max(from, Math.min(to, v));
        if (step > 0)
            r = from + Math.round((r - from) / step) * step;
        return Math.max(from, Math.min(to, r));
    }
    function nudge(dir) {
        var d = step > 0 ? step : (to - from) / 100;
        var v = snap(value + dir * d);
        preview(v);
        commit(v);
    }

    Item {
        id: trackArea
        anchors {
            left: parent.left
            right: valueText.left
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        height: parent.height

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Colors.surfaceContainerHighest

            Rectangle {
                width: root.fraction * parent.width
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
            x: root.fraction * (trackArea.width - width)
            color: Colors.fg
            border.width: root.activeFocus ? 2 : 0
            border.color: Qt.alpha(Colors.primary, 0.8)
            scale: area.pressed ? 1.15 : 1
            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Config.animEasing }
            }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function valueAtX(mx) {
                var f = Math.max(0, Math.min(1, (mx - 7) / Math.max(1, trackArea.width - 14)));
                return root.snap(root.from + f * (root.to - root.from));
            }
            onPressed: mouse => {
                root.forceActiveFocus();
                root.dragging = true;
                root.dragValue = valueAtX(mouse.x);
                root.preview(root.dragValue);
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                var v = valueAtX(mouse.x);
                if (v !== root.dragValue) {
                    root.dragValue = v;
                    root.preview(v);
                }
            }
            onReleased: {
                root.dragging = false;
                root.commit(root.dragValue);
            }
            onCanceled: root.dragging = false
            // Колесо двигает ползунок только в фокусе (после клика/Tab): иначе прокрутка страницы
            // над ползунком молча меняла бы настройки (каждый шаг — запись файлов).
            onWheel: wheel => {
                if (root.activeFocus)
                    root.nudge(wheel.angleDelta.y > 0 ? 1 : -1);
                else
                    wheel.accepted = false;
            }
        }
    }

    Txt {
        id: valueText
        anchors {
            right: resetBtn.left
            rightMargin: resetBtn.visible ? 6 : 0
            verticalCenter: parent.verticalCenter
        }
        width: 56
        horizontalAlignment: Text.AlignRight
        text: Number(root.shown).toFixed(root.decimals) + root.suffix
        color: root.dragging ? Colors.primary : Colors.fg
    }

    Txt {
        id: resetBtn
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        // Место под кнопку резервируется всегда, чтобы ползунок не «прыгал».
        width: root.showReset ? 18 : 0
        text: root.resettable ? Config.icons.refresh : ""
        color: resetHover.hovered ? Colors.primary : Colors.fgVariant
        font.pixelSize: Config.iconSize - 2
        horizontalAlignment: Text.AlignHCenter

        HoverHandler {
            id: resetHover
            enabled: root.resettable
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: root.resettable
            onTapped: {
                root.preview(root.defaultValue);
                root.commit(root.defaultValue);
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
            root.nudge(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
            root.nudge(1);
            event.accepted = true;
        }
    }
}
