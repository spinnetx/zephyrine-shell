pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../"
import "../components"
import "../services"
import "../launcher/search.js" as Search

// Меню приложений: поиск, категории и список из DesktopEntries (иконка, имя, описание). Без запроса — сначала часто и недавно
// запускаемые (история общая с лаунчером: ~/.local/state/zephyrine/launcher-history.json). Открывается закреплённым по клику на кнопку
// (PopoutState.togglePinnedAt), поэтому поле поиска получает клавиатуру. Enter — запустить выбранное, ↑/↓ — выбор, Esc — закрыть.
Item {
    id: root

    readonly property int rowH: 44
    readonly property int maxRows: 8

    implicitWidth: 420
    implicitHeight: col.implicitHeight

    property string category: ""          // "" — все
    property var history: ({})
    property int stamp: 0                  // пересчёт давности при каждом открытии
    property int current: 0

    readonly property var cats: [
        { id: "", label: "Все" }, { id: "Network", label: "Интернет" }, { id: "Office", label: "Офис" },
        { id: "Development", label: "Разработка" }, { id: "Graphics", label: "Графика" }, { id: "AudioVideo", label: "Мультимедиа" },
        { id: "Game", label: "Игры" }, { id: "Utility", label: "Утилиты" }, { id: "Settings", label: "Настройки" }, { id: "System", label: "Система" }
    ]

    readonly property var index: DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => {
        const it = {
            id: e.id,
            name: e.name || "",
            enName: "",
            genericName: e.genericName || "",
            comment: e.comment || "",
            keywords: (e.keywords || []).slice(),
            exec: ((e.command && e.command.length > 0 ? e.command[0] : "") || "").split("/").pop(),
            entry: e
        };
        it.f = Search.prepare(it);
        return it;
    })

    readonly property var results: {
        root.stamp;
        let list = Search.rank(root.index, field.text, root.history, Date.now(), 300);
        if (root.category !== "")
            list = list.filter(it => (it.entry.categories || []).indexOf(root.category) >= 0);
        return list.slice(0, 80);
    }

    readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/zephyrine/launcher-history.json"

    function reset() {
        stamp++;
        field.text = "";
        category = "";
        current = 0;
        focusTimer.restart();
    }
    function launch(it) {
        if (!it)
            return;
        root.history = Search.bump(root.history, it.id, Date.now());
        histFile.setText(JSON.stringify(root.history));
        PopoutState.close();
        it.entry.execute();
    }
    function move(d) {
        const n = results.length;
        if (n > 0)
            current = (current + d + n) % n;
        list.positionViewAtIndex(current, ListView.Contain);
    }

    Connections {
        target: PopoutState
        function onKindChanged() {
            if (PopoutState.kind === "apps")
                root.reset();
        }
        function onOpenChanged() {
            if (PopoutState.open && PopoutState.kind === "apps")
                root.reset();
        }
    }
    Component.onCompleted: reset()

    // Фокус после того, как HyprlandFocusGrab выдал попапу клавиатуру.
    Timer {
        id: focusTimer
        interval: 80
        onTriggered: field.focusInput()
    }

    FileView {
        id: histFile
        path: root.historyPath
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text());
                if (o && typeof o === "object")
                    root.history = o;
            } catch (e) {
                console.warn("zephyrine: не удалось разобрать launcher-history.json:", e);
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        PopField {
            id: field
            width: parent.width
            placeholder: "Поиск приложений…"
            onTextChanged: root.current = 0
            onAccepted: root.launch(root.results[root.current])
            onEscaped: PopoutState.close()
            onMoved: delta => root.move(delta)
        }

        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: root.cats
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool active: root.category === modelData.id
                    width: chipText.implicitWidth + 18
                    height: 26
                    radius: 13
                    color: active ? Qt.alpha(Colors.primaryContainer, 0.75) : chipHover.hovered ? Colors.surfaceContainerHighest : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
                    border.width: 1
                    border.color: active ? Qt.alpha(Colors.primary, 0.6) : Qt.alpha(Colors.outline, 0.25)
                    Txt {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        font.pixelSize: Config.fontSize - 1
                        color: chip.active ? Colors.fg : Colors.fgVariant
                    }
                    HoverHandler {
                        id: chipHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: {
                            root.category = chip.modelData.id;
                            root.current = 0;
                        }
                    }
                }
            }
        }

        Txt {
            visible: field.text === "" && root.category === "" && root.results.length > 0
            text: "Часто используемые"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 2
        }

        ListView {
            id: list
            width: parent.width
            height: Math.min(root.results.length, root.maxRows) * root.rowH
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.current
            highlightMoveDuration: 0
            model: ScriptModel {
                values: root.results
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === root.current

                width: ListView.view.width
                height: root.rowH
                radius: Config.pillRadius
                color: isCurrent ? Qt.alpha(Colors.primaryContainer, 0.75) : "transparent"

                IconImage {
                    id: icon
                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    implicitSize: 28
                    source: Quickshell.iconPath(row.modelData.entry.icon, "application-x-executable")
                }
                Column {
                    anchors {
                        left: icon.right
                        leftMargin: 10
                        right: parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        width: parent.width
                        text: row.modelData.name
                        elide: Text.ElideRight
                    }
                    Txt {
                        width: parent.width
                        readonly property string sub: row.modelData.genericName || row.modelData.comment
                        visible: sub.length > 0
                        text: sub
                        elide: Text.ElideRight
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 2
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.current = row.index
                    onClicked: root.launch(row.modelData)
                }
            }
        }

        Txt {
            visible: root.results.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Ничего не найдено"
            color: Colors.fgVariant
        }
    }
}
