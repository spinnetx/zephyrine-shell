pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../"
import "../components"
import "../services"

// Часы: крупное время/дата, месячный календарь (неделя с понедельника, ru) и список уведомлений.
// Календарь фиксированной высоты (всегда 6 недель), список — со скроллом до Config.notifListMaxHeight.
Item {
    id: root

    readonly property real cellW: 44
    readonly property real cellH: 30
    readonly property var loc: Config.locale

    // Показываемый месяц (month: 0..11) и выбранный день (ключ "г-м-д", "" — нет).
    property int viewYear: clock.date.getFullYear()
    property int viewMonth: clock.date.getMonth()
    property string selectedKey: ""
    // Для подписей «5 мин назад»: обновляется, пока попап открыт.
    property real now: Date.now()

    readonly property bool isCurrentMonth: viewYear === clock.date.getFullYear() && viewMonth === clock.date.getMonth()
    readonly property int firstDow: loc.firstDayOfWeek   // 0 = вс, 1 = пн
    // Смещение 1-го числа от начала недели.
    readonly property int offset: (new Date(viewYear, viewMonth, 1).getDay() - firstDow + 7) % 7

    implicitWidth: cellW * 7
    implicitHeight: col.implicitHeight

    function key(d) {
        return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate();
    }
    function shiftMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1);
        viewYear = d.getFullYear();
        viewMonth = d.getMonth();
    }
    function goToday() {
        viewYear = clock.date.getFullYear();
        viewMonth = clock.date.getMonth();
        selectedKey = "";
    }
    function cap(s) {
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Открыли попап — возвращаемся к текущему месяцу и обновляем «время назад».
    Connections {
        target: PopoutState
        function onKindChanged() {
            if (PopoutState.kind === "clock") {
                root.goToday();
                root.now = Date.now();
            }
        }
    }
    Timer {
        interval: 15000
        running: PopoutState.kind === "clock"
        repeat: true
        onTriggered: root.now = Date.now()
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        // --- Шапка: время/дата + «Не беспокоить» ---
        Item {
            width: parent.width
            height: headText.implicitHeight

            Column {
                id: headText
                Txt {
                    text: root.loc.toString(clock.date, "HH:mm")
                    font.pixelSize: 30
                    font.bold: true
                }
                Txt {
                    text: root.cap(root.loc.toString(clock.date, "dddd, d MMMM"))
                    color: Colors.fgVariant
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Notifs.dnd ? Config.icons.bellOff : Config.icons.bell
                    color: Notifs.dnd ? Colors.tertiary : Colors.fgVariant
                    font.pixelSize: Config.iconSize + 2
                }
                PopSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Notifs.dnd
                    onToggled: v => Notifs.dnd = v
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outlineVariant, 0.6)
        }

        // --- Навигация по месяцам ---
        Row {
            width: parent.width
            spacing: 4

            PopItem {
                width: 32
                centered: true
                onClicked: root.shiftMonth(-1)
                Txt {
                    text: Config.icons.chevronLeft
                    font.pixelSize: Config.iconSize
                }
            }
            // Заголовок: клик — вернуться к текущему месяцу.
            PopItem {
                width: parent.width - 32 * 2 - 4 * 2
                centered: true
                clickable: !root.isCurrentMonth
                onClicked: root.goToday()
                Txt {
                    text: root.cap(root.loc.monthName(root.viewMonth)) + " " + root.viewYear
                    font.bold: true
                    color: root.isCurrentMonth ? Colors.fg : Colors.primary
                }
            }
            PopItem {
                width: 32
                centered: true
                onClicked: root.shiftMonth(1)
                Txt {
                    text: Config.icons.chevronRight
                    font.pixelSize: Config.iconSize
                }
            }
        }

        // --- Дни недели ---
        Row {
            Repeater {
                model: 7
                Txt {
                    required property int index
                    width: root.cellW
                    horizontalAlignment: Text.AlignHCenter
                    text: root.loc.dayName((root.firstDow + index) % 7, Locale.ShortFormat)
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 2
                }
            }
        }

        // --- Сетка 7×6 ---
        Grid {
            columns: 7

            Repeater {
                model: 42

                Item {
                    id: cell

                    required property int index
                    readonly property date day: new Date(root.viewYear, root.viewMonth, 1 - root.offset + index)
                    readonly property bool inMonth: day.getMonth() === root.viewMonth
                    readonly property bool today: root.key(day) === root.key(clock.date)
                    readonly property bool selected: root.key(day) === root.selectedKey

                    width: root.cellW
                    height: root.cellH

                    Rectangle {
                        anchors.centerIn: parent
                        width: 34
                        height: root.cellH - 2
                        radius: 9
                        color: cell.today ? Colors.primary : dayHover.hovered ? Colors.surfaceContainerHighest : "transparent"
                        border.width: cell.selected && !cell.today ? 1 : 0
                        border.color: Colors.primary

                        Behavior on color {
                            ColorAnimation { duration: 120; easing.type: Config.animEasing }
                        }

                        Txt {
                            anchors.centerIn: parent
                            text: cell.day.getDate()
                            font.bold: cell.today
                            color: cell.today ? Colors.primaryText : cell.inMonth ? Colors.fg : Qt.alpha(Colors.fgVariant, 0.4)
                        }
                    }

                    HoverHandler {
                        id: dayHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: {
                            root.selectedKey = root.key(cell.day);
                            // Клик по дню соседнего месяца — переходим в него.
                            if (!cell.inMonth) {
                                root.viewYear = cell.day.getFullYear();
                                root.viewMonth = cell.day.getMonth();
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outlineVariant, 0.6)
        }

        // --- Уведомления: заголовок + «Очистить все» ---
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Уведомления"
                    font.bold: true
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Notifs.count > 0
                    text: Notifs.count
                    color: Colors.fgVariant
                }
            }

            PopItem {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                visible: Notifs.count > 0
                onClicked: Notifs.clearAll()
                Txt {
                    text: Config.icons.trash
                    color: Colors.fgVariant
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    text: "Очистить все"
                    font.pixelSize: Config.fontSize - 1
                }
            }
        }

        // --- Пусто ---
        Column {
            visible: Notifs.count === 0
            width: parent.width
            spacing: 4
            topPadding: 6
            bottomPadding: 10

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Config.icons.bellOutline
                color: Qt.alpha(Colors.fgVariant, 0.6)
                font.pixelSize: 30
            }
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Нет уведомлений"
                color: Colors.fgVariant
            }
        }

        // --- Список уведомлений (скролл) ---
        Item {
            visible: Notifs.count > 0
            width: parent.width
            height: visible ? list.height : 0

            ListView {
                id: list

                width: parent.width
                height: Math.min(contentHeight, Config.notifListMaxHeight)
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel {
                    values: Notifs.list
                    objectProp: "uid"
                }

                delegate: NotifCard {
                    required property var modelData
                    notif: modelData
                    now: root.now
                    width: list.width
                }

                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: Config.animMs; easing.type: Config.animEasing }
                }
            }

            // Тонкий индикатор прокрутки (только если список длиннее окна).
            Rectangle {
                visible: list.contentHeight > list.height
                x: parent.width - width
                width: 3
                radius: 1.5
                color: Qt.alpha(Colors.outline, 0.6)
                height: Math.max(20, list.height * list.height / list.contentHeight)
                y: list.contentHeight > list.height ? list.contentY * (list.height - height) / (list.contentHeight - list.height) : 0
            }
        }
    }
}
