import QtQuick

// Выбор сессии/окружения: пилюля с названием текущей сессии, клик — выпадающий список.
// currentIndex наружу (Main передаёт его в sddm.login). Предвыбор — sessionModel.lastIndex.
Item {
    id: root

    readonly property var sm: (typeof sessionModel !== "undefined") ? sessionModel : null
    property int currentIndex: 0
    property bool open: false
    readonly property int count: sm ? sm.count : 0
    readonly property string currentName: {
        // count в зависимостях — пересчёт, когда модель наполнится
        const c = names.count;
        const it = c > 0 ? names.itemAt(Math.min(Math.max(currentIndex, 0), c - 1)) : null;
        return it ? it.sname : "";
    }

    function close() { open = false; }

    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight
    visible: count > 0

    Component.onCompleted: {
        if (sm && sm.lastIndex >= 0)
            currentIndex = sm.lastIndex;
    }

    // Невидимый «читатель» имён сессий по индексу
    Repeater {
        id: names
        model: root.sm
        delegate: Item {
            required property string name
            readonly property string sname: name
        }
    }

    Pill {
        id: pill
        clickable: root.count > 1
        active: root.open
        onClicked: root.open = !root.open

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: Theme.fgVariant
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: root.currentName
            color: Theme.primary
            font.bold: true
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.count > 1
            text: root.open ? "" : ""
            color: Theme.fgVariant
            font.pixelSize: Theme.fontSize - 3
        }
    }

    // Выпадающий список поверх остального
    Rectangle {
        id: dropdown
        z: 100
        anchors.top: pill.bottom
        anchors.topMargin: 6
        anchors.right: pill.right
        width: Math.max(180, pill.width)
        height: Math.min(list.contentHeight, 260) + 12
        radius: Theme.pillRadius + 2
        color: Theme.alpha(Theme.surfaceContainer, 0.96)
        border.width: 1
        border.color: Theme.alpha(Theme.outlineVariant, 0.5)
        visible: opacity > 0.01
        opacity: root.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animMs; easing.type: Theme.easing }
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            model: root.open ? root.sm : null
            spacing: 2
            delegate: Rectangle {
                id: item
                required property int index
                required property string name
                width: list.width
                height: 32
                radius: Theme.pillRadius - 2
                color: index === root.currentIndex ? Theme.primaryContainer
                     : itemMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                Behavior on color {
                    ColorAnimation { duration: Theme.animMs; easing.type: Theme.easing }
                }
                Txt {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    text: item.name
                    color: item.index === root.currentIndex ? Theme.fg : Theme.fgVariant
                }
                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.currentIndex = item.index;
                        root.open = false;
                    }
                }
            }
        }
    }
}
