pragma ComponentBehavior: Bound

import QtQuick
import "../"
import "../components"
import "../services"

// Погода: крупная сводка, плитки подробностей (влажность, ветер, давление, видимость, УФ, осадки), восход/закат,
// почасовой прогноз на сегодня и прогноз на 3 дня. Данные — services/Weather.qml (wttr.in).
Item {
    id: root

    readonly property var cur: Weather.current
    // Целое число пикселей: с дробной шириной три плитки + зазоры не влезали в строку и сворачивались по две.
    readonly property int tileW: Math.floor((width - 12) / 3)

    implicitWidth: 380
    implicitHeight: col.implicitHeight

    readonly property var tiles: Weather.loaded ? [
        { k: "Влажность", v: cur.humidity + "%" },
        { k: "Ветер", v: cur.windMs + " м/с " + cur.windDir },
        { k: "Давление", v: cur.pressureMm + " мм" },
        { k: "Видимость", v: cur.visKm + " км" },
        { k: "УФ-индекс", v: String(cur.uv) },
        { k: "Осадки", v: cur.precipMm.toFixed(1) + " мм" }
    ] : []
    readonly property var today: Weather.days.length > 0 ? Weather.days[0] : null

    function dayLabel(i, date) {
        if (i === 0)
            return "Сегодня";
        if (i === 1)
            return "Завтра";
        const d = new Date(date + "T12:00:00");
        const s = Config.locale.toString(d, "dddd");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    function tint(t) {
        return t >= 30 ? Colors.error : t >= 22 ? Colors.tertiary : t <= 0 ? Colors.secondary : Colors.fg;
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // --- сводка ---
        Row {
            spacing: 14
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.loaded ? root.cur.emoji : Config.icons.weather
                font.pixelSize: 54
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Txt {
                    text: Weather.loaded ? Weather.sign(root.cur.tempC) : "—"
                    font.bold: true
                    font.pixelSize: Config.fontSize + 18
                    color: Weather.loaded ? root.tint(root.cur.tempC) : Colors.fgVariant
                }
                Txt {
                    text: Weather.loaded ? root.cur.desc : (Weather.failed ? "Погода недоступна" : "Загрузка…")
                }
                Txt {
                    visible: Weather.loaded
                    text: "Ощущается как " + Weather.sign(root.cur.feelsC)
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 1
                }
            }
        }
        Txt {
            visible: Weather.place !== ""
            width: parent.width
            text: Config.icons.info + "  " + Weather.place
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
            elide: Text.ElideRight
        }

        // --- плитки: три колонки ---
        Grid {
            visible: Weather.loaded
            columns: 3
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: root.tiles
                delegate: Rectangle {
                    id: tile
                    required property int index
                    required property var modelData
                    // Последняя колонка добирает остаток ширины - справа не остаётся пустого места.
                    width: index % 3 === 2 ? root.width - 2 * (root.tileW + 6) : root.tileW
                    height: 50
                    radius: 10
                    color: Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
                    border.width: 1
                    border.color: Qt.alpha(Colors.outline, 0.2)
                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.k
                            color: Colors.fgVariant
                            font.pixelSize: Config.fontSize - 2
                        }
                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.v
                            font.bold: true
                        }
                    }
                }
            }
        }

        // --- восход / закат ---
        Row {
            visible: root.today !== null && root.today.sunrise !== ""
            spacing: 18
            Txt {
                text: "🌅  Восход " + (root.today ? root.today.sunrise : "")
                color: Colors.fgVariant
            }
            Txt {
                text: "🌇  Закат " + (root.today ? root.today.sunset : "")
                color: Colors.fgVariant
            }
        }

        // --- почасовой прогноз на сегодня ---
        Rectangle {
            visible: root.today !== null
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.3)
        }
        Txt {
            visible: root.today !== null
            text: "Сегодня по часам"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }
        Row {
            visible: root.today !== null
            width: parent.width
            Repeater {
                model: root.today ? root.today.hours : []
                delegate: Column {
                    id: hour
                    required property var modelData
                    width: col.width / 8
                    spacing: 2
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hour.modelData.time
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 3
                    }
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hour.modelData.emoji
                        font.pixelSize: Config.fontSize + 4
                    }
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Weather.sign(hour.modelData.tempC)
                        font.bold: true
                        font.pixelSize: Config.fontSize - 1
                        color: root.tint(hour.modelData.tempC)
                    }
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: hour.modelData.rain > 0 ? "☔" + hour.modelData.rain + "%" : " "
                        color: Colors.tertiary
                        font.pixelSize: Config.fontSize - 3
                    }
                }
            }
        }

        // --- 3 дня ---
        Rectangle {
            visible: Weather.days.length > 0
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.3)
        }
        Repeater {
            model: Weather.days
            delegate: Item {
                id: day
                required property int index
                required property var modelData
                width: col.width
                height: 32

                Txt {
                    id: dayName
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    width: 96
                    text: root.dayLabel(day.index, day.modelData.date)
                    font.bold: day.index === 0
                }
                Txt {
                    id: dayEmoji
                    anchors {
                        left: dayName.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: day.modelData.emoji
                    font.pixelSize: Config.fontSize + 4
                }
                Txt {
                    anchors {
                        left: dayEmoji.right
                        leftMargin: 8
                        right: dayRain.left
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    text: day.modelData.desc
                    color: Colors.fgVariant
                    elide: Text.ElideRight
                    font.pixelSize: Config.fontSize - 1
                }
                Txt {
                    id: dayRain
                    anchors {
                        right: dayTemps.left
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: day.modelData.rain > 0 ? "☔" + day.modelData.rain + "%" : ""
                    color: Colors.tertiary
                    font.pixelSize: Config.fontSize - 2
                }
                Txt {
                    id: dayTemps
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    width: 88
                    horizontalAlignment: Text.AlignRight
                    text: Weather.sign(day.modelData.minC) + " … " + Weather.sign(day.modelData.maxC)
                    font.bold: true
                    color: root.tint(day.modelData.maxC)
                }
            }
        }

        // --- подвал ---
        Row {
            spacing: 10
            PopItem {
                width: 130
                onClicked: Weather.refresh()
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.icons.refresh
                    color: Colors.tertiary
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.busy ? "Обновляем…" : "Обновить"
                }
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                visible: Weather.updatedMs > 0
                text: "обновлено " + Config.locale.toString(new Date(Weather.updatedMs), "HH:mm")
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }
        }
    }
}
