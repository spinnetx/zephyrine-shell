import QtQuick
import "../"
import "../services"
import "../components"

// Боковая панель окна настроек (DESIGN §6.1): четыре раздела, выбранный подсвечен «едущей» плашкой.
// Клавиатура: Tab/Shift+Tab — по пунктам, Enter/Space — выбрать (Ctrl+1…4 и Ctrl+Tab обрабатывает окно).
// Внизу — сводка «N приложений ждут перезапуска» (по результату последнего вызова CLI).
Rectangle {
    id: root

    // [{ id, label, icon }] — задаёт окно, чтобы заголовок страницы и Ctrl+N брали те же данные.
    property var sections: []
    property string current: ""
    signal selected(string id)

    readonly property int headerH: 50
    readonly property int itemH: 44
    readonly property int itemGap: 4
    readonly property int pad: 8
    readonly property int currentIndex: {
        for (let i = 0; i < sections.length; i++)
            if (sections[i].id === current)
                return i;
        return 0;
    }
    readonly property int restartCount: SettingsCli.restart.length

    implicitWidth: 220
    radius: Config.popoutRadius
    color: Qt.alpha(Colors.surfaceContainer, Config.pillAlpha)
    border.width: 1
    border.color: Qt.alpha(Colors.outline, 0.28)

    // Шапка сайдбара с логотипом (ненавязчиво)
    Row {
        x: root.pad + 6
        y: root.pad + 2
        width: parent.width - (root.pad + 6) * 2
        height: root.headerH - root.pad - 4
        spacing: 10

        Image {
            anchors.verticalCenter: parent.verticalCenter
            source: Qt.resolvedUrl("../assets/zephyrine-logo.png")
            width: 28
            height: 28
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Txt {
                text: "Zephyrine"
                font.bold: true
                font.pixelSize: Config.fontSize + 1
            }
            Txt {
                text: "Центр управления"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
            }
        }
    }

    // Выбранный пункт.
    Rectangle {
        x: root.pad
        y: root.headerH + root.currentIndex * (root.itemH + root.itemGap)
        width: parent.width - root.pad * 2
        height: root.itemH
        radius: Config.pillRadius
        color: Qt.alpha(Colors.primaryContainer, 0.75)
        border.width: 1
        border.color: Qt.alpha(Colors.primary, 0.5)
        Behavior on y {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
    }

    Column {
        x: root.pad
        y: root.headerH
        width: parent.width - root.pad * 2
        spacing: root.itemGap

        Repeater {
            model: root.sections

            delegate: Item {
                id: entry
                required property var modelData
                required property int index
                readonly property bool isCurrent: modelData.id === root.current

                width: parent.width
                height: root.itemH
                activeFocusOnTab: true

                Keys.onPressed: event => {
                    if (event.modifiers === Qt.NoModifier && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
                        root.selected(entry.modelData.id);
                        event.accepted = true;
                    }
                }

                // Hover и рамка фокуса (для не выбранных).
                Rectangle {
                    anchors.fill: parent
                    radius: Config.pillRadius
                    visible: !entry.isCurrent
                    color: hover.hovered ? Colors.surfaceContainerHighest : "transparent"
                    border.width: entry.activeFocus ? 1 : 0
                    border.color: Qt.alpha(Colors.primary, 0.7)
                    Behavior on color {
                        ColorAnimation { duration: 120; easing.type: Config.animEasing }
                    }
                }

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        right: parent.right
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    Txt {
                        width: Config.iconSize + 4
                        horizontalAlignment: Text.AlignHCenter
                        text: entry.modelData.icon
                        color: entry.isCurrent ? Colors.primary : Colors.fgVariant
                        font.pixelSize: Config.iconSize + 2
                    }
                    Txt {
                        width: parent.width - (Config.iconSize + 4) - 8
                        text: entry.modelData.label
                        elide: Text.ElideRight
                        font.bold: entry.isCurrent
                        color: entry.isCurrent ? Colors.fg : Colors.fgVariant
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: {
                        entry.forceActiveFocus();
                        root.selected(entry.modelData.id);
                    }
                }
            }
        }
    }

    // Нижняя часть: сводка перезапусков и подсказка клавиш.
    Column {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 14
        }
        spacing: 6

        Txt {
            visible: root.restartCount > 0
            width: parent.width
            wrapMode: Text.WordWrap
            color: Colors.tertiary
            font.pixelSize: Config.fontSize - 1
            text: Config.icons.info + " " + root.restartCount + " " + (root.restartCount === 1 ? "приложение ждёт" : "приложений ждут") + " перезапуска"
        }
        Txt {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Colors.fgVariant
            opacity: 0.7
            font.pixelSize: Config.fontSize - 2
            text: "Ctrl+1…4 — раздел · Esc — закрыть"
        }
    }
}
