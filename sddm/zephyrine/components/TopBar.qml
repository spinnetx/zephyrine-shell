import QtQuick

// Верхняя плавающая «пилюля»-панель: слева часы и дата, справа раскладка,
// сессия и кнопки питания.
Rectangle {
    id: root

    property alias sessionIndex: session.currentIndex
    readonly property bool sessionOpen: session.open
    function closePopups() { session.close(); }

    readonly property var loc: Qt.locale("ru_RU")
    property date now: new Date()

    implicitHeight: 44
    radius: Theme.barRadius
    color: Theme.alpha(Theme.surfaceContainer, Theme.panelAlpha)
    border.width: 1
    border.color: Theme.alpha(Theme.outlineVariant, 0.5)

    // Раз в секунду: время обновляется вовремя на границе минуты
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.loc.toString(root.now, "HH:mm")
            font.pixelSize: Theme.fontSize + 6
            font.bold: true
            color: Theme.primary
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.cap(root.loc.toString(root.now, "dddd, d MMMM"))
            color: Theme.fgVariant
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        LayoutSwitch {
            anchors.verticalCenter: parent.verticalCenter
        }
        SessionPicker {
            id: session
            anchors.verticalCenter: parent.verticalCenter
        }
        PowerButtons {
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
