import QtQuick
import "../"

// Кнопка окна настроек: normal / primary / danger. У danger с confirm: true нужно нажать дважды
// (первое нажатие «взводит» кнопку на 3 с, как в меню питания).
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property string kind: "normal"       // normal | primary | danger
    property bool confirm: false         // двойное нажатие (имеет смысл для danger)
    property string confirmText: "Нажмите ещё раз"
    property bool armed: false
    property string tooltip: ""
    readonly property bool hovered: hover.hovered
    signal clicked

    readonly property color tone: kind === "primary" ? Colors.primary : kind === "danger" ? Colors.error : Colors.fg

    implicitHeight: 30
    implicitWidth: row.implicitWidth + 24
    radius: 10
    opacity: enabled ? 1 : 0.5
    color: kind === "primary"
        ? (hovered || armed ? Qt.lighter(Colors.primary, 1.12) : Colors.primary)
        : armed ? Qt.alpha(Colors.error, 0.3)
        : hovered ? Colors.surfaceContainerHighest
        : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
    border.width: 1
    border.color: kind === "primary" ? Colors.primary
        : kind === "danger" ? Qt.alpha(Colors.error, armed ? 0.9 : 0.5)
        : activeFocus ? Qt.alpha(Colors.primary, 0.7) : Qt.alpha(Colors.outline, 0.35)

    activeFocusOnTab: true

    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Config.animEasing }
    }
    Behavior on implicitWidth {
        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    function activate() {
        if (!enabled)
            return;
        if (confirm && !armed) {
            armed = true;
            disarm.restart();
            return;
        }
        armed = false;
        disarm.stop();
        clicked();
    }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = false
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Txt {
            visible: root.icon.length > 0 && !root.armed
            text: root.icon
            color: root.kind === "primary" ? Colors.primaryText : root.tone
            font.pixelSize: Config.iconSize
        }
        Txt {
            text: root.armed ? root.confirmText : root.text
            color: root.kind === "primary" ? Colors.primaryText : root.tone
        }
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: root.enabled
        onTapped: root.activate()
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activate();
            event.accepted = true;
        }
    }
    onActiveFocusChanged: if (!activeFocus) armed = false

    Tip {
        target: root
        text: root.tooltip
        hovered: root.hovered
    }
}
