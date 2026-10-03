import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../"
import "../services"

// Карточка уведомления: иконка, заголовок, текст, время, × (закрыть), доп. действия.
// Клик по карточке — действие по умолчанию (если есть) и закрытие. notif — обёртка из Notifs.list.
// toast: true — режим всплывающего тоста (toasts/Toasts.qml): «закрыть» только снимает тост
// (сигнал closeRequested), запись в истории остаётся; фон плотнее — под ним произвольный контент.
Rectangle {
    id: root

    required property var notif
    property real now: Date.now()
    property bool toast: false
    readonly property bool hovered: hover.hovered

    signal closeRequested

    function close() {
        if (toast)
            closeRequested();
        else
            Notifs.dismiss(notif);
    }

    readonly property bool critical: notif.urgency === NotificationUrgency.Critical
    // Живой объект Notification (null у архивных записей, восстановленных из файла: без кнопок и действий).
    readonly property bool isLive: notif.live !== null && notif.live !== undefined
    readonly property var extraActions: isLive ? notif.live.actions.filter(a => a.identifier !== "default") : []
    // Источник картинки: image (может быть image://…), иначе иконка приложения (имя или путь).
    readonly property string iconSrc: {
        if (notif.image !== "")
            return notif.image;
        const ic = notif.appIcon;
        if (ic === "")
            return "";
        if (ic.startsWith("/"))
            return "file://" + ic;
        if (ic.startsWith("file:") || ic.startsWith("image:"))
            return ic;
        return Quickshell.iconPath(ic, true);
    }

    implicitHeight: body.implicitHeight + 16
    radius: 10
    color: hover.hovered ? Colors.surfaceContainerHighest : Qt.alpha(Colors.surfaceContainerHigh, toast ? 0.97 : 0.9)
    border.width: 1
    border.color: critical ? Qt.alpha(Colors.error, 0.7) : Qt.alpha(Colors.outline, 0.2)

    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Config.animEasing }
    }

    HoverHandler {
        id: hover
    }
    TapHandler {
        // Клики по × и кнопкам действий обрабатываются ими самими.
        // Архивная карточка: клик ничего не делает (закрывается только ×).
        enabled: root.isLive && !closeHover.hovered && !actionsHover.hovered
        onTapped: {
            const a = Notifs.defaultAction(root.notif);
            if (a)
                a.invoke();
            root.close();
        }
    }

    Row {
        id: body
        x: 8
        y: 8
        width: parent.width - 16
        spacing: 10

        // Иконка приложения
        Rectangle {
            width: 34
            height: 34
            radius: 8
            color: Colors.primaryContainer

            Image {
                id: img
                anchors.fill: parent
                anchors.margins: 3
                source: root.iconSrc
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
            }
            Txt {
                anchors.centerIn: parent
                visible: !img.visible
                text: Config.icons.bell
                color: Colors.fg
                font.pixelSize: Config.iconSize + 2
            }
        }

        Column {
            width: parent.width - 34 - 10 - 22 - 10
            spacing: 2

            Txt {
                width: parent.width
                text: root.notif.summary !== "" ? root.notif.summary : root.notif.appName
                font.bold: true
                elide: Text.ElideRight
            }
            Txt {
                visible: text !== ""
                width: parent.width
                text: root.notif.body
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 1
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
            Txt {
                text: (root.notif.appName !== "" ? root.notif.appName + " · " : "") + Notifs.ago(root.notif, root.now)
                color: Qt.alpha(Colors.fgVariant, 0.7)
                font.pixelSize: Config.fontSize - 3
            }

            // Дополнительные действия отправителя (кроме «default»).
            Row {
                id: actionsRow
                visible: root.extraActions.length > 0
                spacing: 6
                topPadding: 4

                HoverHandler {
                    id: actionsHover
                }

                Repeater {
                    model: root.extraActions.slice(0, 3)

                    Rectangle {
                        id: btn
                        required property var modelData
                        width: lbl.implicitWidth + 16
                        height: 22
                        radius: 6
                        color: btnHover.hovered ? Colors.primary : Colors.surfaceContainerHighest

                        HoverHandler {
                            id: btnHover
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: {
                                btn.modelData.invoke();
                                root.close();
                            }
                        }
                        Txt {
                            id: lbl
                            anchors.centerIn: parent
                            text: btn.modelData.text
                            color: btnHover.hovered ? Colors.primaryText : Colors.fg
                            font.pixelSize: Config.fontSize - 2
                        }
                    }
                }
            }
        }

        // Закрыть
        Rectangle {
            width: 22
            height: 22
            radius: 11
            color: closeHover.hovered ? Colors.surfaceContainer : "transparent"

            HoverHandler {
                id: closeHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: root.close()
            }
            Txt {
                anchors.centerIn: parent
                text: Config.icons.close
                color: closeHover.hovered ? Colors.error : Colors.fgVariant
                font.pixelSize: Config.iconSize - 2
            }
        }
    }
}
