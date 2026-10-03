import QtQuick
import "../../"
import "../../components"

// Выбор акцентного цвета (DESIGN §3.7, §6.5): пресеты кружками + поле #rrggbb с образцом и контрастом.
// Ничего не пишет сам: picked(hex) — выбран пресет или введён цвет, resetRequested() — «из палитры».
// Допустимость цвета проверяет CLI (контраст, светлота); его ошибка приходит в error и показывается под полем.
Item {
    id: root

    // Пресеты дублируют schema.json (appearance.accent.presets) — править в обоих местах.
    // hex — то, что пишется в настройки (одно значение для обеих тем); lightHex — как этот акцент выглядит на светлой теме
    // (его приводит генератор: светлота не выше 0.52 по OKLCH, color.light_accent) — только для показа кружка.
    readonly property var presets: [
        { hex: "#bb9af7", lightHex: "#7554aa", name: "Фиолетовый" },
        { hex: "#7aa2f7", lightHex: "#4165b4", name: "Синий" },
        { hex: "#2ac3de", lightHex: "#007688", name: "Голубой" },
        { hex: "#9ece6a", lightHex: "#4d7802", name: "Зелёный" },
        { hex: "#e0af68", lightHex: "#8c5f0b", name: "Жёлтый" },
        { hex: "#ff9e64", lightHex: "#a44c00", name: "Оранжевый" },
        { hex: "#f7768e", lightHex: "#b03553", name: "Красный" },
        { hex: "#f5a3d4", lightHex: "#954c7a", name: "Розовый" }
    ]
    property bool light: false         // светлая тема: кружки показываются в приведённом виде
    property string current: ""        // действующий акцент "#rrggbb" (из настроек или из палитры)
    property bool custom: false        // акцент задан пользователем (иначе «из палитры»)
    property string error: ""          // отказ CLI по последнему вводу
    signal picked(string hex)
    signal resetRequested

    implicitWidth: 420
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 10

        Flow {
            width: parent.width
            spacing: 10

            Repeater {
                model: root.presets

                delegate: Rectangle {
                    id: dot
                    required property var modelData
                    readonly property bool selected: root.current.toLowerCase() === modelData.hex

                    width: 30
                    height: 30
                    radius: 15
                    color: root.light ? modelData.lightHex : modelData.hex
                    border.width: selected ? 3 : 1
                    border.color: selected ? Colors.fg : Qt.alpha(Colors.outline, 0.5)
                    scale: dotHover.hovered ? 1.1 : 1

                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Config.animEasing }
                    }

                    // Метка выбранного: контрастный кружок в центре.
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        visible: dot.selected
                        color: "#1a1a1a"
                        opacity: 0.7
                    }

                    HoverHandler {
                        id: dotHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.picked(dot.modelData.hex)
                    }
                    Tip {
                        target: dot
                        text: dot.modelData.name + " · " + dot.modelData.hex
                        hovered: dotHover.hovered
                    }
                }
            }
        }

        Row {
            spacing: 14

            HexField {
                id: hex
                width: 320
                value: root.current
                minContrast: 3
                onApplied: h => root.picked(h)
            }

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: root.custom ? "свой цвет" : "из палитры"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 1
            }

            SetButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.custom
                text: "Сбросить"
                icon: Config.icons.refresh
                onClicked: root.resetRequested()
            }
        }

        Txt {
            visible: root.error.length > 0
            width: parent.width
            text: "Не применено: " + root.error
            color: Colors.error
            font.pixelSize: Config.fontSize - 1
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignTop
        }
    }
}
