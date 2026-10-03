pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../"
import "../components"
import "../services"
import "../launcher/search.js" as Search
import "apps-logic.js" as AppsLogic

// Меню приложений (двухпанельный вид в стиле KDE Plasma):
// - Вверху: строка поиска с иконкой и кнопкой очистки (ранжирование launcher/search.js).
// - Центр:
//     - Левая панель: группы/категории приложений (вертикальный список, иконка, имя, счётчик,
//       переключение по клику и при наведении с плавной задержкой).
//     - Разделитель: тонкая вертикальная линия.
//     - Правая панель: список приложений для выбранной категории или результаты поиска,
//       прокручиваемый список с иконками, заголовками и описаниями.
// - Внизу: панель действий в стиле KDE Plasma (аватар и имя пользователя слева, быстрые кнопки
//   блокировки, центра настроек и питания справа).
Item {
    id: root

    readonly property int rowH: 48
    readonly property int catRowH: 34
    readonly property int panelH: 400

    implicitWidth: 640
    implicitHeight: mainCol.implicitHeight

    property alias query: searchInput.text
    property string category: "favorites"
    property var history: ({})
    property int stamp: 0
    property int current: 0
    property var enNames: ({})
    property string pendingCategory: ""
    property string footerHint: ""

    readonly property var cats: AppsLogic.CATEGORIES

    readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/zephyrine/launcher-history.json"

    // Английские имена: фоновый сбор Name= без локали из .desktop файлов для поиска по оригинальным именам
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
                root.enNames = m;
            }
        }
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

    readonly property var index: {
        const en = root.enNames;
        return DesktopEntries.applications.values.filter(e => !e.noDisplay && (e.name || "").length > 0).map(e => {
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

    readonly property var categoryCounts: {
        root.stamp;
        return AppsLogic.computeCategoryCounts(root.index, root.history);
    }

    readonly property var currentCat: AppsLogic.getCategory(root.category)

    readonly property var results: {
        root.stamp;
        return AppsLogic.filterApps(root.index, root.query, root.category, root.history, Search, Date.now(), 80);
    }

    function reset() {
        stamp++;
        query = "";
        current = 0;
        hoverTimer.stop();
        pendingCategory = "";
        footerHint = "";
        category = "favorites";
        appsList.positionViewAtBeginning();
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

    function move(delta) {
        const n = results.length;
        if (n > 0) {
            current = (current + delta + n) % n;
            appsList.positionViewAtIndex(current, ListView.Contain);
        }
    }

    function selectCategory(catId) {
        hoverTimer.stop();
        pendingCategory = "";
        if (root.query.length > 0)
            root.query = "";
        category = catId;
        current = 0;
        appsList.positionViewAtBeginning();
    }

    function onCategoryHovered(catId) {
        if (category === catId) {
            hoverTimer.stop();
            return;
        }
        pendingCategory = catId;
        hoverTimer.restart();
    }

    Timer {
        id: hoverTimer
        interval: 90
        onTriggered: {
            if (root.pendingCategory !== "") {
                root.selectCategory(root.pendingCategory);
                root.pendingCategory = "";
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 80
        onTriggered: searchInput.forceActiveFocus()
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

    Column {
        id: mainCol
        width: parent.width
        spacing: 10

        // --- Верх: поле поиска ---
        Rectangle {
            id: searchBox
            width: parent.width
            height: 38
            radius: 10
            color: Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
            border.width: 1
            border.color: searchInput.activeFocus ? Qt.alpha(Colors.primary, 0.7) : Qt.alpha(Colors.outline, 0.3)
            Behavior on border.color {
                ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
            }

            Txt {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.search
                color: searchInput.activeFocus ? Colors.primary : Colors.fgVariant
                font.pixelSize: Config.iconSize
                Behavior on color { ColorAnimation { duration: Config.animMs } }
            }

            TextInput {
                id: searchInput
                anchors {
                    left: searchIcon.right
                    leftMargin: 10
                    right: clearBtn.left
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                color: Colors.fg
                selectionColor: Colors.primaryContainer
                selectedTextColor: Colors.fg
                font.family: Config.fontFamily
                font.pixelSize: Config.fontSize
                clip: true
                onTextChanged: {
                    root.current = 0;
                    appsList.positionViewAtBeginning();
                }

                Txt {
                    anchors.fill: parent
                    visible: searchInput.text.length === 0
                    text: "Поиск приложений…"
                    color: Colors.fgVariant
                    opacity: 0.6
                    font.pixelSize: Config.fontSize
                }

                Keys.onPressed: event => {
                    const n = root.results.length;
                    if (event.key === Qt.Key_Escape) {
                        if (root.query.length > 0) {
                            root.query = "";
                        } else {
                            PopoutState.close();
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.move(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.move(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageDown) {
                        root.move(6);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        root.move(-6);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (n > 0 && root.current >= 0 && root.current < n) {
                            root.launch(root.results[root.current]);
                        }
                        event.accepted = true;
                    }
                }
            }

            Rectangle {
                id: clearBtn
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: 13
                visible: root.query.length > 0
                color: clearMouse.containsMouse ? Qt.alpha(Colors.surfaceContainerHighest, 0.8) : "transparent"

                Txt {
                    anchors.centerIn: parent
                    text: Config.icons.close
                    color: clearMouse.containsMouse ? Colors.primary : Colors.fgVariant
                    font.pixelSize: Config.iconSize - 2
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.query = "";
                        searchInput.forceActiveFocus();
                    }
                }
            }
        }

        // --- Центр: Две вертикальные панели ---
        Row {
            width: parent.width
            height: root.panelH
            spacing: 12

            // Левая панель: Категории (200px)
            ListView {
                id: catList
                width: 200
                height: parent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                model: root.cats

                delegate: Rectangle {
                    id: catRow
                    required property var modelData
                    required property int index

                    readonly property bool active: root.query.length === 0 && root.category === modelData.id
                    readonly property bool isPending: root.pendingCategory === modelData.id
                    readonly property bool isHovered: catMouse.containsMouse

                    width: ListView.view.width
                    height: root.catRowH
                    radius: Config.pillRadius

                    color: active ? Qt.alpha(Colors.primaryContainer, 0.75)
                                  : (isHovered || isPending) ? Qt.alpha(Colors.surfaceContainerHighest, 0.6)
                                                             : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    // Акцентная полоска слева у активной категории
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 18
                        radius: 2
                        color: Colors.primary
                        visible: catRow.active
                    }

                    // Иконка категории
                    IconImage {
                        id: catIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 20
                        source: Quickshell.iconPath(catRow.modelData.icon, "applications-other")
                    }

                    // Название категории
                    Txt {
                        id: catLabel
                        anchors.left: catIcon.right
                        anchors.leftMargin: 8
                        anchors.right: catCount.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: catRow.modelData.label
                        font.pixelSize: Config.fontSize - 1
                        font.bold: catRow.active
                        color: catRow.active ? Colors.fg : Colors.fgVariant
                        elide: Text.ElideRight
                    }

                    // Счётчик приложений
                    Txt {
                        id: catCount
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(root.categoryCounts[catRow.modelData.id] || 0)
                        font.pixelSize: Config.fontSize - 3
                        color: catRow.active ? Colors.primary : Colors.fgVariant
                        opacity: 0.75
                    }

                    MouseArea {
                        id: catMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.onCategoryHovered(catRow.modelData.id)
                        onClicked: root.selectCategory(catRow.modelData.id)
                    }
                }
            }

            // Тонкий вертикальный разделитель
            Rectangle {
                width: 1
                height: parent.height
                color: Qt.alpha(Colors.outline, 0.18)
            }

            // Правая панель: Список приложений
            Item {
                id: rightPane
                width: parent.width - 200 - 1 - 24
                height: parent.height

                // Заголовок правой панели
                Row {
                    id: rightHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 24
                    spacing: 6

                    Txt {
                        text: root.query.length > 0 ? "Результаты поиска" : (root.currentCat?.label ?? "Приложения")
                        font.bold: true
                        color: Colors.fg
                        font.pixelSize: Config.fontSize
                    }

                    Txt {
                        text: "· " + root.results.length
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 1
                    }
                }

                // Список приложений
                ListView {
                    id: appsList
                    anchors {
                        top: rightHeader.bottom
                        topMargin: 6
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: root.current
                    highlightMoveDuration: 0
                    spacing: 2

                    model: ScriptModel {
                        values: root.results
                    }

                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        required property int index

                        readonly property bool isCurrent: index === root.current
                        readonly property bool isHovered: appRowMouse.containsMouse

                        width: ListView.view.width - 6
                        height: root.rowH
                        radius: Config.pillRadius

                        color: isCurrent ? Qt.alpha(Colors.primaryContainer, 0.75)
                                         : isHovered ? Qt.alpha(Colors.surfaceContainerHighest, 0.5)
                                                     : "transparent"
                        border.width: isCurrent ? 1 : 0
                        border.color: Qt.alpha(Colors.primary, 0.5)

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }

                        IconImage {
                            id: appIcon
                            anchors {
                                left: parent.left
                                leftMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            implicitSize: 32
                            source: Quickshell.iconPath(appRow.modelData.entry.icon, "application-x-executable")
                        }

                        Column {
                            anchors {
                                left: appIcon.right
                                leftMargin: 10
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 1

                            Txt {
                                width: parent.width
                                text: appRow.modelData.name
                                elide: Text.ElideRight
                                font.bold: appRow.isCurrent
                                font.pixelSize: Config.fontSize
                            }

                            Txt {
                                width: parent.width
                                readonly property string sub: appRow.modelData.genericName || appRow.modelData.comment
                                visible: sub.length > 0
                                text: sub
                                elide: Text.ElideRight
                                color: Colors.fgVariant
                                font.pixelSize: Config.fontSize - 2
                            }
                        }

                        MouseArea {
                            id: appRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: root.current = appRow.index
                            onClicked: root.launch(appRow.modelData)
                        }
                    }
                }

                // Индикатор прокрутки списка приложений
                Rectangle {
                    visible: appsList.contentHeight > appsList.height
                    anchors.right: parent.right
                    width: 3
                    radius: 1.5
                    color: Qt.alpha(Colors.outline, 0.6)
                    height: Math.max(20, appsList.height * appsList.height / appsList.contentHeight)
                    y: appsList.y + (appsList.contentHeight > appsList.height ? appsList.contentY * (appsList.height - height) / (appsList.contentHeight - appsList.height) : 0)
                }

                // Пустой список / ничего не найдено
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    visible: root.results.length === 0

                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.query.length > 0 ? "Ничего не найдено"
                                                    : (root.category === "favorites" ? "История запусков пуста"
                                                                                    : "В этой категории нет приложений")
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize
                    }

                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.query.length === 0 && root.category === "favorites"
                        text: "Запускайте приложения, чтобы они появились здесь"
                        color: Colors.fgVariant
                        opacity: 0.7
                        font.pixelSize: Config.fontSize - 2
                    }
                }
            }
        }

        // --- Разделитель перед нижней панелью ---
        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.18)
        }

        // --- Внизу: Панель действий в стиле KDE Plasma ---
        Item {
            width: parent.width
            height: 38

            // Слева: Аватар и имя пользователя
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: Colors.surfaceContainerHighest
                    clip: true

                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        source: "file://" + Quickshell.env("HOME") + "/.face"
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }

                    Txt {
                        anchors.centerIn: parent
                        visible: !avatarImg.visible
                        text: Config.icons.chip
                        color: Colors.primary
                        font.pixelSize: 14
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Txt {
                        text: root.footerHint !== "" ? root.footerHint : (Quickshell.env("USER") || "Пользователь")
                        font.bold: root.footerHint === ""
                        color: root.footerHint !== "" ? Colors.primary : Colors.fg
                        font.pixelSize: Config.fontSize - 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Txt {
                        visible: root.footerHint === ""
                        text: "Zephyrine Desktop"
                        color: Colors.fgVariant
                        opacity: 0.6
                        font.pixelSize: Config.fontSize - 3
                    }
                }
            }

            // Справа: Быстрые действия (Блокировка, Настройки, Питание)
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Блокировка
                Rectangle {
                    id: lockBtn
                    width: 32
                    height: 32
                    radius: 16
                    color: lockMouse.containsMouse ? Qt.alpha(Colors.surfaceContainerHighest, 0.9) : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
                    border.width: 1
                    border.color: lockMouse.containsMouse ? Qt.alpha(Colors.primary, 0.6) : Qt.alpha(Colors.outline, 0.25)

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Txt {
                        anchors.centerIn: parent
                        text: Config.icons.lock
                        color: lockMouse.containsMouse ? Colors.primary : Colors.fgVariant
                        font.pixelSize: Config.iconSize
                        scale: lockMouse.containsMouse ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: lockMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.footerHint = "Заблокировать экран"
                        onExited: if (root.footerHint === "Заблокировать экран") root.footerHint = ""
                        onClicked: {
                            PopoutState.close();
                            Quickshell.execDetached(Config.lockCommand);
                        }
                    }
                }

                // Настройки
                Rectangle {
                    id: settingsBtn
                    width: 32
                    height: 32
                    radius: 16
                    color: setMouse.containsMouse ? Qt.alpha(Colors.surfaceContainerHighest, 0.9) : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
                    border.width: 1
                    border.color: setMouse.containsMouse ? Qt.alpha(Colors.primary, 0.6) : Qt.alpha(Colors.outline, 0.25)

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Txt {
                        anchors.centerIn: parent
                        text: Config.icons.settings
                        color: setMouse.containsMouse ? Colors.primary : Colors.fgVariant
                        font.pixelSize: Config.iconSize
                        scale: setMouse.containsMouse ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: setMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.footerHint = "Центр управления"
                        onExited: if (root.footerHint === "Центр управления") root.footerHint = ""
                        onClicked: {
                            PopoutState.close();
                            Overlays.openSettings();
                        }
                    }
                }

                // Питание и выход
                Rectangle {
                    id: powerBtn
                    width: 32
                    height: 32
                    radius: 16
                    color: powMouse.containsMouse ? Qt.alpha(Colors.error, 0.22) : Qt.alpha(Colors.surfaceContainerHigh, Config.pillAlpha)
                    border.width: 1
                    border.color: powMouse.containsMouse ? Colors.error : Qt.alpha(Colors.outline, 0.25)

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Txt {
                        anchors.centerIn: parent
                        text: Config.icons.power
                        color: powMouse.containsMouse ? Colors.error : Colors.fgVariant
                        font.pixelSize: Config.iconSize
                        scale: powMouse.containsMouse ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: powMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.footerHint = "Выключение, перезагрузка и выход"
                        onExited: if (root.footerHint === "Выключение, перезагрузка и выход") root.footerHint = ""
                        onClicked: {
                            PopoutState.close();
                            Overlays.openPower();
                        }
                    }
                }
            }
        }
    }
}
