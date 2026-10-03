import QtQuick
import Quickshell
import "../"
import "../services"

// Часы HH:mm; при наведении — попап календаря и уведомлений (kind "clock"), по клику — дата прямо
// в баре. Точка в углу — есть уведомления (яркая — непрочитанные).
Pill {
    id: root

    property bool showDate: false

    clickable: true
    onClicked: showDate = !showDate

    PopoutTrigger {
        parent: root
        kind: "clock"
    }

    // Нужна PopoutState, чтобы IPC `notifs toggle` мог закрепить карточку у часов нужного монитора.
    Component.onCompleted: PopoutState.registerClock(root)
    Component.onDestruction: PopoutState.unregisterClock(root)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // «Не беспокоить» включено: приглушённый зачёркнутый колокольчик слева от времени.
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: Notifs.dnd
        text: Config.icons.bellOff
        color: Colors.fgVariant
        opacity: 0.8
        font.pixelSize: Config.iconSize - 2
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.locale.toString(clock.date, root.showDate ? "ddd d MMM  HH:mm" : "HH:mm")
        font.bold: true
    }

    // Индикатор уведомлений поверх угла пилюли (не в Row — чтобы не сдвигать время).
    Rectangle {
        parent: root
        visible: Notifs.count > 0
        width: 8
        height: 8
        radius: 4
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 3
        anchors.rightMargin: 3
        color: Notifs.unread > 0 ? Colors.tertiary : Colors.outline
        border.width: 1
        border.color: Colors.background
    }
}
