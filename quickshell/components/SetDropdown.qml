import QtQuick
import "../"

// Выбор из списка. Список раскрывается внутри окна (поверх содержимого, в popupParent), не отдельным PopupWindow.
// options — массив строк или {value, label}; current — выбранное значение. При >searchThreshold пунктах есть поиск.
Rectangle {
    id: root

    property var options: []
    property var current: undefined
    property string placeholder: "—"
    property int searchThreshold: 10
    property int popupMaxHeight: 280
    property int popupMinWidth: 200
    // Куда класть раскрытый список: по умолчанию корневой Item окна.
    property Item popupParent: Window.contentItem
    property bool open: false
    property string query: ""
    signal selected(var value)

    function valueOf(o) {
        return (o !== null && typeof o === "object") ? o.value : o;
    }
    function labelOf(o) {
        return (o !== null && typeof o === "object") ? String(o.label !== undefined ? o.label : o.value) : String(o);
    }
    readonly property string currentLabel: {
        for (var i = 0; i < options.length; i++)
            if (valueOf(options[i]) === current)
                return labelOf(options[i]);
        return placeholder;
    }
    readonly property bool searchable: options.length > searchThreshold
    readonly property var filtered: {
        if (!searchable || query.length === 0)
            return options;
        var q = query.toLowerCase();
        var out = [];
        for (var i = 0; i < options.length; i++)
            if (labelOf(options[i]).toLowerCase().indexOf(q) >= 0)
                out.push(options[i]);
        return out;
    }

    function openList() {
        if (!enabled || !popupParent)
            return;
        query = "";
        // Позиция считается один раз при открытии (окно не двигается, пока список открыт).
        var p = root.mapToItem(popupParent, 0, root.height + 4);
        var w = Math.max(root.width, popupMinWidth);
        var h = Math.min(popupMaxHeight, list.contentHeight + (searchable ? 48 : 8));
        var x = Math.max(4, Math.min(p.x, popupParent.width - w - 4));
        var y = p.y;
        if (y + h > popupParent.height - 4)   // не влезает вниз — открыть вверх
            y = Math.max(4, root.mapToItem(popupParent, 0, 0).y - h - 4);
        panel.x = x;
        panel.y = y;
        panel.width = w;
        open = true;
        if (searchable)
            search.focusInput();
        else
            holder.forceActiveFocus();
    }
    function closeList() {
        open = false;
    }

    implicitHeight: 30
    implicitWidth: 200
    radius: 10
    color: hover.hovered ? Colors.surfaceContainerHighest : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
    border.width: 1
    border.color: open || activeFocus ? Qt.alpha(Colors.primary, 0.7) : Qt.alpha(Colors.outline, 0.35)
    opacity: enabled ? 1 : 0.5
    activeFocusOnTab: true

    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Config.animEasing }
    }
    Behavior on border.color {
        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }

    Txt {
        anchors {
            left: parent.left
            leftMargin: 10
            right: arrow.left
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        text: root.currentLabel
        elide: Text.ElideRight
        color: root.currentLabel === root.placeholder ? Colors.fgVariant : Colors.fg
    }
    Txt {
        id: arrow
        anchors {
            right: parent.right
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        text: "▾"
        color: Colors.fgVariant
        rotation: root.open ? 180 : 0
        Behavior on rotation {
            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
        }
    }

    HoverHandler {
        id: hover
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: root.enabled
        onTapped: {
            root.forceActiveFocus();
            if (root.open)
                root.closeList();
            else
                root.openList();
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
            root.openList();
            event.accepted = true;
        }
    }

    // Слой раскрытого списка: на весь popupParent, клик мимо закрывает.
    Item {
        id: holder
        parent: root.popupParent
        anchors.fill: parent
        visible: root.open
        z: 1000
        focus: root.open

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.closeList();
                root.forceActiveFocus();
                event.accepted = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeList()
        }

        Rectangle {
            id: panel
            height: Math.min(root.popupMaxHeight, list.contentHeight + (root.searchable ? 48 : 8))
            radius: 10
            color: Qt.alpha(Colors.surfaceContainer, 0.98)
            border.width: 1
            border.color: Qt.alpha(Colors.outline, 0.4)
            opacity: root.open ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Config.animEasing }
            }

            // Поглощает клики внутри панели, чтобы они не закрывали список.
            MouseArea {
                anchors.fill: parent
            }

            PopField {
                id: search
                visible: root.searchable
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 4
                }
                implicitHeight: 32
                placeholder: "Поиск…"
                onTextChanged: root.query = text
                onEscaped: {
                    root.closeList();
                    root.forceActiveFocus();
                }
                onAccepted: {
                    if (root.filtered.length > 0) {
                        root.selected(root.valueOf(root.filtered[0]));
                        root.closeList();
                        root.forceActiveFocus();
                    }
                }
            }

            ListView {
                id: list
                anchors {
                    left: parent.left
                    right: parent.right
                    top: root.searchable ? search.bottom : parent.top
                    bottom: parent.bottom
                    margins: 4
                }
                clip: true
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds

                delegate: PopItem {
                    id: item
                    required property var modelData
                    width: ListView.view.width
                    highlighted: root.valueOf(modelData) === root.current
                    onClicked: {
                        root.selected(root.valueOf(item.modelData));
                        root.closeList();
                        root.forceActiveFocus();
                    }
                    Txt {
                        text: root.labelOf(item.modelData)
                        color: item.highlighted ? Colors.primary : Colors.fg
                    }
                }
            }
        }
    }
}
