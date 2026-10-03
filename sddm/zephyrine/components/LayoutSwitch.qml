import QtQuick

// Переключатель раскладки: короткий код (PL/RU), клик — следующая раскладка.
// Безопасен, если keyboard пуст или недоступен.
Pill {
    id: root

    readonly property var layouts: (typeof keyboard !== "undefined" && keyboard && keyboard.layouts) ? keyboard.layouts : []
    readonly property int current: (typeof keyboard !== "undefined" && keyboard) ? keyboard.currentLayout : 0

    function code(l) {
        if (!l)
            return "--";
        const ln = String(l.longName || "").toLowerCase();
        if (ln.indexOf("polish") === 0 || ln.indexOf("polski") === 0)
            return "PL";
        if (ln.indexOf("russian") === 0 || ln.indexOf("рус") === 0)
            return "RU";
        const s = String(l.shortName || l.longName || "--");
        return s.substring(0, 2).toUpperCase();
    }

    visible: layouts.length > 0
    clickable: layouts.length > 1
    onClicked: keyboard.currentLayout = (current + 1) % layouts.length

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Theme.fgVariant
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: root.code(root.layouts[root.current])
        font.bold: true
        color: Theme.tertiary
    }
}
