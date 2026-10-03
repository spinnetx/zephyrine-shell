import QtQuick
import "../"
import "../services"

// Таймер: значок, а пока отсчёт идёт/на паузе/закончился - ещё и остаток. Клик: пауза/продолжить (после окончания -
// сброс). Запуск и пресеты - в попапе (kind "timer").
Pill {
    id: root

    readonly property color tint: Countdown.finished ? Colors.error : Countdown.paused ? Colors.fgVariant : Colors.tertiary

    clickable: true
    spacing: 6
    tooltip: Countdown.active ? (Countdown.finished ? "Время вышло — клик сбросит" : "Клик — пауза / продолжить") : ""
    onClicked: {
        if (Countdown.finished)
            Countdown.reset();
        else
            Countdown.toggle();
    }

    PopoutTrigger {
        parent: root
        kind: "timer"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.timer
        color: Countdown.active ? root.tint : Colors.primary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        visible: Countdown.active
        text: Countdown.finished ? "00:00" : Countdown.fmt(Countdown.remaining)
        color: root.tint
        font.bold: true
    }
}
