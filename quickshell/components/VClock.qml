import QtQuick
import Quickshell
import "../"
import "../services"

// Часы для вертикальной панели: часы над минутами; hover — календарь и уведомления (kind "clock"), как у Clock.
Pill {
    id: root

    horizontalPadding: 0
    implicitWidth: Config.pillHeight + 8
    implicitHeight: 48

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

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: Config.locale.toString(clock.date, "HH") + "\n" + Config.locale.toString(clock.date, "mm")
        font.bold: true
        lineHeight: 0.9
    }

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
