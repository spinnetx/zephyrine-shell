import QtQuick
import "../../"
import "../../components"

// Снекбар внизу страницы настроек: «Применено · Отменить» (DESIGN §2.5.4).
// show(текст, действие) показывает его на interval мс (пауза, пока курсор над ним);
// пустое действие — просто сообщение. Нажатие на действие шлёт action() и скрывает снекбар.
Rectangle {
    id: root

    property string text: ""
    property string actionText: ""
    property int interval: 5000
    property bool shown: false
    signal action

    function show(t, a) {
        text = t;
        actionText = a ?? "";
        shown = true;
        hideTimer.restart();
    }
    function hide() {
        shown = false;
        hideTimer.stop();
    }

    implicitWidth: row.implicitWidth + 28
    implicitHeight: 42
    radius: height / 2
    color: Qt.alpha(Colors.surfaceContainerHighest, 0.97)
    border.width: 1
    border.color: Qt.alpha(Colors.outline, 0.45)
    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    transform: Translate {
        y: root.shown ? 0 : 10
        Behavior on y {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
    }
    Behavior on opacity {
        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    Timer {
        id: hideTimer
        interval: root.interval
        running: false
        onTriggered: if (!hover.hovered) root.hide()
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 14

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
        }
        Rectangle {
            visible: root.actionText.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: actText.implicitWidth + 20
            height: 28
            radius: 14
            color: actHover.hovered ? Qt.alpha(Colors.primary, 0.28) : Qt.alpha(Colors.primary, 0.14)
            Behavior on color {
                ColorAnimation { duration: 120; easing.type: Config.animEasing }
            }
            Txt {
                id: actText
                anchors.centerIn: parent
                text: root.actionText
                color: Colors.primary
                font.bold: true
            }
            HoverHandler {
                id: actHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: {
                    root.hide();
                    root.action();
                }
            }
        }
    }

    HoverHandler {
        id: hover
    }
}
