import QtQuick
import "../"
import "../services"

// Погода: эмодзи состояния и температура (wttr.in, город - настройка weather.city). Клик - обновить. Подробности - в подсказке.
Pill {
    id: root

    clickable: true
    spacing: 6
    onClicked: Weather.refresh()

    PopoutTrigger {
        parent: root
        kind: "weather"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Weather.loaded ? Weather.icon : Config.icons.weather
        color: Weather.failed && !Weather.loaded ? Colors.fgVariant : Colors.primary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Weather.brief
        color: Weather.loaded ? Colors.fg : Colors.fgVariant
    }
}
