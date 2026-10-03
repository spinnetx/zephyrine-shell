pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../"
import "../services"
import "../components"
import "search.js" as Search

// Лаунчер приложений: центрированная карточка с полем поиска и списком (до 8 строк).
// Окно создаётся один раз (shell.qml), показывается по Overlays.launcherOpen (IPC `launcher`).
// Источник — DesktopEntries; ранжирование — launcher/search.js (проверено node-тестом).
PanelWindow {
    id: win

    readonly property bool open: Overlays.launcherOpen
    readonly property int rowHeight: 52
    readonly property int maxRows: 8
    readonly property int cardWidth: 640

    screen: Overlays.screen
    // Окно живёт, пока играет анимация закрытия.
    visible: open || t > 0.001
    color: "transparent"
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "zephyrine-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive — чтобы ввод гарантированно попадал в поле сразу после открытия.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Прогресс анимации появления 0..1 (opacity + scale карточки).
    property real t: open ? 1 : 0
    Behavior on t {
        NumberAnimation { duration: 180; easing.type: Config.animEasing }
    }

    // --- Данные ---
    // Английские `Name=` из .desktop (Quickshell отдаёт локализованное имя): id -> имя.
    property var enNames: ({})
    // История запусков: id -> { count, last }.
    property var history: ({})
    // Меняется при каждом открытии: заставляет пересчитать давность в ранжировании.
    property int stamp: 0

    readonly property var index: {
        const en = win.enNames;
        return DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => {
            const it = {
                id: e.id,
                name: e.name || "",
                enName: en[e.id] ?? "",
                genericName: e.genericName || "",
                comment: e.comment || "",
                keywords: (e.keywords || []).slice(),
                exec: ((e.command && e.command.length > 0 ? e.command[0] : "") || "").split("/").pop(),
                entry: e
            };
            it.f = Search.prepare(it);
            return it;
        });
    }

    readonly property var results: {
        win.stamp;
        return Search.rank(win.index, input.text, win.history, Date.now(), 50);
    }

    readonly property string historyDir: Quickshell.env("HOME") + "/.local/state/zephyrine"
    readonly property string historyPath: historyDir + "/launcher-history.json"

    Process {
        running: true
        command: ["mkdir", "-p", win.historyDir]
    }

    // Английские имена: для каждого .desktop из XDG-каталогов берём первую строку `Name=` (без локали).
    // Первым в выводе идёт пользовательский каталог — он и побеждает (как в DesktopEntries).
    Process {
        running: true
        command: ["sh", "-c", "for d in \"${XDG_DATA_HOME:-$HOME/.local/share}\" $(echo \"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\" | tr : ' '); do grep -rH -m1 '^Name=' \"$d/applications\" 2>/dev/null; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const line of text.split("\n")) {
                    const i = line.indexOf(":Name=");
                    if (i < 0)
                        continue;
                    const id = line.substring(0, i).split("/").pop().replace(/\.desktop$/, "");
                    if (!(id in m))
                        m[id] = line.substring(i + 6);
                }
                win.enNames = m;
            }
        }
    }

    FileView {
        id: histFile
        path: win.historyPath
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text());
                if (o && typeof o === "object")
                    win.history = o;
            } catch (e) {
                console.warn("zephyrine: не удалось разобрать launcher-history.json:", e);
            }
        }
    }

    function launch(it) {
        if (!it)
            return;
        win.history = Search.bump(win.history, it.id, Date.now());
        histFile.setText(JSON.stringify(win.history));
        Overlays.closeLauncher();
        it.entry.execute();
    }

    onOpenChanged: {
        if (open) {
            stamp++;
            input.text = "";
            list.currentIndex = 0;
            input.forceActiveFocus();
        }
    }

    // Клик вне карточки — закрыть.
    MouseArea {
        anchors.fill: parent
        onClicked: Overlays.closeLauncher()
    }

    Rectangle {
        id: card

        readonly property int listRows: Math.min(win.results.length, win.maxRows)
        readonly property int headerH: 56

        width: win.cardWidth
        // Верх фиксирован так, чтобы полный список (8 строк) стоял по центру экрана; карточка растёт вниз.
        x: (win.width - width) / 2
        y: (win.height - (headerH + win.maxRows * win.rowHeight + 2 * Config.popoutPadding)) / 2
        height: headerH + Config.popoutPadding * 2 + (listRows > 0 ? listRows * win.rowHeight + Config.popoutPadding : (input.text.length > 0 ? 40 + Config.popoutPadding : 0))
        Behavior on height {
            NumberAnimation { duration: 150; easing.type: Config.animEasing }
        }

        radius: Config.barRadius + 4
        color: Qt.alpha(Colors.background, 0.94)
        border.width: 1
        border.color: Qt.alpha(Colors.outlineVariant, 0.6)
        opacity: win.t
        scale: 0.95 + 0.05 * win.t
        transformOrigin: Item.Top

        // Съедает клики внутри карточки (иначе они дошли бы до «закрыть по клику вне»).
        MouseArea {
            anchors.fill: parent
        }

        // --- Поле поиска ---
        Rectangle {
            id: searchBox
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: Config.popoutPadding
            }
            height: card.headerH - Config.popoutPadding
            radius: Config.pillRadius + 2
            color: Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
            border.width: 1
            border.color: input.activeFocus ? Qt.alpha(Colors.primary, 0.7) : Qt.alpha(Colors.outline, 0.28)
            Behavior on border.color {
                ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
            }

            Txt {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.search
                color: Colors.primary
                font.pixelSize: Config.iconSize + 4
            }

            TextInput {
                id: input
                anchors {
                    left: searchIcon.right
                    leftMargin: 10
                    right: parent.right
                    rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                focus: true
                color: Colors.fg
                selectionColor: Colors.primaryContainer
                selectedTextColor: Colors.fg
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize + 3
                clip: true
                onTextChanged: list.currentIndex = 0

                Txt {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    text: "Поиск приложений…"
                    color: Colors.fgVariant
                    opacity: 0.7
                    font.pixelSize: Config.fontSize + 3
                }

                Keys.onPressed: event => {
                    const n = win.results.length;
                    if (event.key === Qt.Key_Escape) {
                        Overlays.closeLauncher();
                    } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                        if (n > 0)
                            list.currentIndex = (list.currentIndex + 1) % n;
                    } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) || event.key === Qt.Key_Backtab) {
                        if (n > 0)
                            list.currentIndex = (list.currentIndex - 1 + n) % n;
                    } else if (event.key === Qt.Key_PageDown) {
                        list.currentIndex = Math.min(n - 1, list.currentIndex + win.maxRows);
                    } else if (event.key === Qt.Key_PageUp) {
                        list.currentIndex = Math.max(0, list.currentIndex - win.maxRows);
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        win.launch(win.results[list.currentIndex]);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }
        }

        // --- Список результатов ---
        ListView {
            id: list
            anchors {
                top: searchBox.bottom
                topMargin: Config.popoutPadding
                left: parent.left
                right: parent.right
                leftMargin: Config.popoutPadding
                rightMargin: Config.popoutPadding
            }
            height: card.listRows * win.rowHeight
            clip: true
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            model: ScriptModel {
                values: win.results
            }
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: ListView.isCurrentItem

                width: ListView.view.width
                height: win.rowHeight
                radius: Config.pillRadius
                color: current ? Qt.alpha(Colors.primaryContainer, 0.75) : "transparent"
                Behavior on color {
                    ColorAnimation { duration: 100 }
                }

                IconImage {
                    id: icon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 32
                    source: Quickshell.iconPath(row.modelData.entry.icon, "application-x-executable")
                }

                Column {
                    anchors {
                        left: icon.right
                        leftMargin: 12
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    Txt {
                        width: parent.width
                        text: row.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: Config.fontSize + 1
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
                    // Не onEntered: список может «проехать» под неподвижным курсором.
                    onPositionChanged: list.currentIndex = row.index
                    onClicked: win.launch(row.modelData)
                }
            }
        }

        // Пустой результат.
        Txt {
            visible: win.results.length === 0 && input.text.length > 0
            anchors.top: searchBox.bottom
            anchors.topMargin: Config.popoutPadding
            anchors.horizontalCenter: parent.horizontalCenter
            height: 40
            text: "Ничего не найдено"
            color: Colors.fgVariant
        }
    }
}
