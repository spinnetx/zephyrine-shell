import QtQuick
import "../../"
import "../../components"

// Диалог подтверждения настроек экрана (DESIGN §6.5, §7.2):
// Показывается после применения «try». Если пользователь не подтвердит (Enter / «Оставить»)
// в течение timeoutSec, компоситорный сторож и этот диалог автоматически возвращают прежние параметры.
Rectangle {
    id: root

    property string token: ""
    property int timeoutSec: 15
    property int remainingSec: 15

    signal confirmed()
    signal reverted()

    anchors.fill: parent
    color: Qt.alpha(Colors.background, 0.75)
    z: 1000
    focus: true

    onTokenChanged: {
        root.remainingSec = root.timeoutSec;
        countdown.restart();
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        running: root.visible && root.token !== ""
        onTriggered: {
            if (root.remainingSec > 1) {
                root.remainingSec--;
            } else {
                root.remainingSec = 0;
                countdown.stop();
                root.reverted();
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.confirmed();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.reverted();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 420
        height: cardCol.implicitHeight + 36
        radius: Config.popoutRadius
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Qt.alpha(Colors.outline, 0.4)

        Column {
            id: cardCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 18
            }
            spacing: 14

            Row {
                spacing: 12
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.icons.monitor
                    color: Colors.primary
                    font.pixelSize: Config.iconSize + 6
                }
                Column {
                    spacing: 2
                    Txt {
                        text: "Оставить новые настройки экранов?"
                        font.bold: true
                        font.pixelSize: Config.fontSize + 2
                    }
                    Txt {
                        text: "Без ответа вернём прежние через " + root.remainingSec + " с"
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 1
                    }
                }
            }

            // Полоса обратного отсчёта
            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Colors.surfaceContainerHighest

                Rectangle {
                    width: parent.width * (root.timeoutSec > 0 ? (root.remainingSec / root.timeoutSec) : 0)
                    height: parent.height
                    radius: 3
                    color: Colors.primary
                    Behavior on width {
                        NumberAnimation { duration: 950; easing.type: Easing.Linear }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                SetButton {
                    text: "Оставить · Enter"
                    kind: "primary"
                    onClicked: root.confirmed()
                }

                SetButton {
                    text: "Вернуть · Esc"
                    onClicked: root.reverted()
                }
            }
        }
    }
}
