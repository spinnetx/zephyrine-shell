pragma ComponentBehavior: Bound

import QtQuick
import "../"
import "../components"
import "../services"

// Таймер: крупный остаток, пресеты, своё время (кнопками +/−), пауза/продолжить и сброс. Состояние - services/Countdown.qml.
Item {
    id: root

    readonly property var presets: [{ m: 1, label: "1 мин" }, { m: 5, label: "5 мин" }, { m: 10, label: "10 мин" },
                                    { m: 15, label: "15 мин" }, { m: 25, label: "25 мин" }, { m: 60, label: "1 час" }]

    implicitWidth: 260
    implicitHeight: col.implicitHeight

    // Своё время набирается кнопками (+/−), без клавиатуры: hover-попап не получает ввод с клавиатуры (layer-shell/xdg_popup),
    // поэтому текстовое поле здесь не работает. Набранное время запускается кнопкой «Старт».
    property int customSec: 0
    function adjust(delta) {
        customSec = Math.max(0, Math.min(99 * 3600 + 59 * 60, customSec + delta));
    }
    function startCustom() {
        if (customSec <= 0)
            return;
        Countdown.start(customSec);
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Row {
            spacing: 10
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.timer
                color: Countdown.finished ? Colors.error : Colors.tertiary
                font.pixelSize: Config.iconSize + 6
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Countdown.active ? (Countdown.finished ? "00:00" : Countdown.fmt(Countdown.remaining)) : "Таймер"
                font.bold: true
                font.pixelSize: Config.fontSize + 5
                color: Countdown.finished ? Colors.error : Colors.fg
            }
        }

        Rectangle {
            visible: Countdown.active
            width: parent.width
            height: 6
            radius: 3
            color: Colors.surfaceContainerHighest
            Rectangle {
                width: parent.width * Countdown.progress
                height: parent.height
                radius: 3
                color: Countdown.finished ? Colors.error : Colors.tertiary
            }
        }

        Txt {
            text: Countdown.active ? "Новый отсчёт" : "Быстрый старт"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: root.presets
                delegate: PopItem {
                    id: preset
                    required property var modelData
                    width: 76
                    centered: true
                    onClicked: Countdown.start(preset.modelData.m * 60)
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: preset.modelData.label
                    }
                }
            }
        }

        Txt {
            text: "Своё время"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }
        Row {
            spacing: 10
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                text: Countdown.fmt(root.customSec)
                font.bold: true
                font.pixelSize: Config.fontSize + 6
                color: root.customSec > 0 ? Colors.fg : Colors.fgVariant
            }
            PopItem {
                width: 80
                centered: true
                enabled: root.customSec > 0
                opacity: root.customSec > 0 ? 1 : 0.5
                onClicked: root.startCustom()
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.icons.play
                    color: Colors.primary
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Старт"
                }
            }
            PopItem {
                width: 70
                centered: true
                onClicked: root.customSec = 0
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Обнулить"
                    font.pixelSize: Config.fontSize - 1
                }
            }
        }
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: [{ d: 10, l: "+10 с" }, { d: 60, l: "+1 мин" }, { d: 300, l: "+5 мин" }, { d: 900, l: "+15 мин" },
                        { d: -10, l: "−10 с" }, { d: -60, l: "−1 мин" }, { d: -300, l: "−5 мин" }, { d: -900, l: "−15 мин" }]
                delegate: PopItem {
                    id: adj
                    required property var modelData
                    width: 76
                    centered: true
                    onClicked: root.adjust(adj.modelData.d)
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: adj.modelData.l
                        color: adj.modelData.d > 0 ? Colors.fg : Colors.fgVariant
                    }
                }
            }
        }

        Row {
            visible: Countdown.active
            spacing: 6
            PopItem {
                visible: !Countdown.finished
                width: 124
                centered: true
                onClicked: Countdown.toggle()
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Countdown.running ? Config.icons.pause : Config.icons.play
                    color: Colors.primary
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Countdown.running ? "Пауза" : "Продолжить"
                }
            }
            PopItem {
                width: 124
                centered: true
                onClicked: Countdown.reset()
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.icons.stop
                    color: Colors.error
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Сброс"
                }
            }
        }
    }
}
