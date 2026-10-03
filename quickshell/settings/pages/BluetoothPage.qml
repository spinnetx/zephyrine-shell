pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../../"
import "../../services"
import "../../components"
import "../parts"

// Страница «Bluetooth» окна настроек (DESIGN §4.2, §6.5, §7.3; этап N2): адаптер (вкл/выкл с подтверждением, имя,
// видимость) и список устройств (подключено / сопряжено / доступно): подключить, отключить, доверять, забыть
// (с подтверждением), сопряжение «Just Works», заряд батареи. Данные — Quickshell.Bluetooth, настроек в файлы не пишет.
// Сканирование (adapter.discovering) включается, только пока страница видна, и выключается при уходе/закрытии окна
// (останавливаем лишь то, что включили сами). Сопряжение с кодом/PIN (этап N3): агент BlueZ (parts/BtAgent.qml ->
// settings/bin/zs-btagent) запускается на время сопряжения (и пока включена «Видимость для других» — чтобы телефон мог
// сопрячься сам), карточка «Запрос сопряжения» (parts/BtPairCard.qml) показывает код/PIN или просит ввод; при уходе со
// страницы агент снимается. Без агента (не запустился) сопряжение идёт как раньше — работают устройства «Just Works».
//
// Подключается из раздела «Сеть и Bluetooth» через Loader (pages/BluetoothPage.qml). Размер: страница сама
// прокручивается (Flickable на всю область), а implicitHeight = высота содержимого — подойдёт и Loader'у в Flickable.
// adapter / deviceList / autoScan — точки подмены для проверки без настоящих устройств (временный стенд).
Item {
    id: root

    property var adapter: Bluetooth.defaultAdapter
    property var deviceList: Bluetooth.devices.values
    property bool autoScan: true

    readonly property bool powered: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    property bool userStopped: false       // пользователь сам остановил поиск — не перезапускаем, пока страница открыта
    property bool weScan: false            // поиск включили мы → мы же и выключаем
    property bool showUnnamed: false       // показывать ли «безымянные» (только MAC) найденные устройства
    property bool confirmOff: false        // ждём подтверждения выключения радио
    property int pairingCount: 0           // сколько устройств сейчас сопрягаем из этой страницы
    property var endReasons: ({})          // address -> причина отказа от агента (rejected|timeout|cancel) для заметки
    property var pendingPair: null         // действие «pair()», ждущее регистрации агента

    readonly property alias agent: btAgent

    readonly property bool wantScan: visible && autoScan && adapter !== null && powered && !userStopped

    function group(d) {
        if (!d)
            return -1;
        return d.connected ? 0 : (d.paired || d.bonded) ? 1 : 2;
    }
    function isUnnamed(d) {
        const n = String(d.name ?? "");
        return n === "" || n.replace(/-/g, ":").toUpperCase() === String(d.address).toUpperCase();
    }
    function title(d) {
        return String(d.name ?? "") !== "" ? d.name : d.address;
    }

    // Устройства, которые показываем: подключённые и сопряжённые всегда; найденные — пока идёт поиск.
    readonly property var visibleDevices: {
        const all = Array.from(deviceList ?? []);
        const scanning = discovering;
        return all.filter(d => group(d) < 2 || (scanning && (showUnnamed || !isUnnamed(d))));
    }
    readonly property var sorted: visibleDevices.slice().sort((a, b) => (group(a) - group(b)) || title(a).localeCompare(title(b)))
    readonly property int hiddenUnnamed: {
        if (!discovering || showUnnamed)
            return 0;
        return Array.from(deviceList ?? []).filter(d => group(d) === 2 && isUnnamed(d)).length;
    }
    readonly property int connectedCount: Array.from(deviceList ?? []).filter(d => d.connected).length

    // Агент нужен, пока страница видна и радио включено, и (идёт сопряжение отсюда или компьютер виден другим).
    readonly property bool agentWanted: visible && powered && (pairingCount > 0 || (adapter?.discoverable ?? false))
    onAgentWantedChanged: {
        if (agentWanted)
            btAgent.start();
        else
            idleStop.restart();
    }

    implicitHeight: col.implicitHeight + 12

    function deviceByAddress(address) {
        return Array.from(deviceList ?? []).find(d => d.address === address) ?? null;
    }
    // Запустить сопряжение, когда агент готов (или сразу, если агента не будет: Just Works работает и без него).
    function pairWhenReady(action) {
        if (btAgent.ready) {
            action();
            return;
        }
        pendingPair = action;
        pairStartGuard.restart();
        btAgent.start();
    }
    function runPending() {
        pairStartGuard.stop();
        const a = pendingPair;
        pendingPair = null;
        if (a)
            a();
    }

    function syncScan() {
        if (!adapter)
            return;
        if (wantScan) {
            if (!adapter.discovering)
                adapter.discovering = true;
            weScan = true;
        } else if (weScan) {
            if (adapter.discovering)
                adapter.discovering = false;
            weScan = false;
        }
    }
    onWantScanChanged: syncScan()
    onVisibleChanged: if (!visible) {
        userStopped = false;
        confirmOff = false;
        pendingPair = null;
        btAgent.stop();
    }
    Component.onCompleted: syncScan()
    Component.onDestruction: {
        if (weScan && adapter && adapter.discovering)
            adapter.discovering = false;
        btAgent.proc.running = false;
    }

    BtAgent {
        id: btAgent
        onReadyChanged: if (ready)
            root.runPending()
        onStopped: wasReady => {
            if (!wasReady)
                root.runPending();     // агент не поднялся — сопрягаем без него
            if (wasReady && root.agentWanted)
                start();     // только если он уже работал: иначе сбойный запуск зациклился бы
        }
        onRequestEnded: (reason, req) => {
            if (reason === "rejected" || reason === "timeout" || reason === "cancel")
                root.endReasons[req.address] = reason;
            if (!root.agentWanted)
                idleStop.restart();
        }
    }
    // Агент не успел зарегистрироваться за 4 с — не держим пользователя, сопрягаем без него.
    Timer {
        id: pairStartGuard
        interval: 4000
        onTriggered: root.runPending()
    }
    // Агент снимаем не сразу: сопряжение/подтверждение может закончиться чуть позже.
    Timer {
        id: idleStop
        interval: 3000
        onTriggered: if (!root.agentWanted && !btAgent.request)
            btAgent.stop()
    }

    onPoweredChanged: if (!powered)
        confirmOff = false

    Timer {
        id: offGuard
        interval: 8000
        running: root.confirmOff
        onTriggered: root.confirmOff = false
    }

    function toggleScan() {
        if (!adapter)
            return;
        if (adapter.discovering) {
            userStopped = true;
            adapter.discovering = false;
        } else {
            userStopped = false;
            adapter.discovering = true;
            weScan = true;
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 12
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: 12

            // ---------- запрос сопряжения (агент BlueZ) ----------
            BtPairCard {
                width: parent.width
                agent: btAgent
                onCancelRequested: {
                    // Показ кода (display_*): закрываем карточку и отменяем само сопряжение.
                    const addr = btAgent.request?.address;
                    btAgent.reject();
                    const d = addr ? root.deviceByAddress(addr) : null;
                    if (d && d.pairing)
                        d.cancelPair();
                }
            }

            // ---------- адаптер ----------
            SetCard {
                width: parent.width
                title: "Bluetooth"
                icon: root.powered ? Config.icons.bt : Config.icons.btOff
                chipKind: !root.adapter ? "missing" : root.powered ? "live" : "neutral"
                chipText: !root.adapter ? "нет адаптера"
                    : root.adapter.state === BluetoothAdapterState.Blocked ? "заблокирован"
                    : root.adapter.state === BluetoothAdapterState.Enabling ? "включается…"
                    : root.adapter.state === BluetoothAdapterState.Disabling ? "выключается…"
                    : root.powered ? "включён" : "выключен"

                headerRight: [
                    PopSwitch {
                        visible: root.adapter !== null
                        checked: root.powered
                        onToggled: value => {
                            if (!root.adapter)
                                return;
                            if (value)
                                root.adapter.enabled = true;
                            else
                                root.confirmOff = true;   // выключение радио — только после подтверждения (§7.3)
                        }
                    }
                ]

                SetRow {
                    width: parent.width
                    visible: root.confirmOff
                    label: "Выключить Bluetooth?"
                    hint: root.connectedCount > 0 ? "Подключённых устройств: " + root.connectedCount + " — они отключатся." : "Поиск и подключения остановятся."
                    SetButton {
                        text: "Выключить"
                        icon: Config.icons.btOff
                        kind: "danger"
                        onClicked: {
                            root.confirmOff = false;
                            if (root.adapter)
                                root.adapter.enabled = false;
                        }
                    }
                    SetButton {
                        text: "Отмена"
                        onClicked: root.confirmOff = false
                    }
                }

                Txt {
                    visible: !root.adapter
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Colors.fgVariant
                    text: "Адаптер Bluetooth не найден. Проверьте, что запущена служба bluetooth.service и адаптер не отключён в BIOS."
                }
                Txt {
                    visible: root.adapter !== null && !root.powered && !root.confirmOff
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Colors.fgVariant
                    text: root.adapter?.state === BluetoothAdapterState.Blocked
                        ? "Адаптер заблокирован (rfkill). Разблокируйте его, чтобы включить Bluetooth."
                        : "Bluetooth выключен. Включите переключатель справа, чтобы искать и подключать устройства."
                }

                SetRow {
                    width: parent.width
                    visible: root.powered
                    label: "Имя компьютера"
                    hint: "Так компьютер виден другим устройствам. Только чтение: Quickshell не позволяет менять имя адаптера."
                    Txt {
                        text: root.adapter?.name ?? ""
                        color: Colors.primary
                        font.bold: true
                    }
                }
                SetRow {
                    width: parent.width
                    visible: root.powered
                    label: "Видимость для других"
                    hint: root.adapter?.discoverable
                        ? ((root.adapter.discoverableTimeout ?? 0) > 0
                            ? "Компьютер виден всем; скроется через " + Math.round(root.adapter.discoverableTimeout / 60 * 10) / 10 + " мин."
                            : "Компьютер виден всем устройствам поблизости.")
                        : "Скрыт: найти компьютер смогут только уже сопряжённые устройства."
                    PopSwitch {
                        checked: root.adapter?.discoverable ?? false
                        onToggled: value => {
                            if (root.adapter)
                                root.adapter.discoverable = value;
                        }
                    }
                }
            }

            // ---------- устройства ----------
            SetCard {
                id: devCard
                width: parent.width
                visible: root.powered
                title: "Устройства"
                icon: Config.icons.headphones
                chipKind: "neutral"
                chipText: root.discovering ? "идёт поиск…" : ""

                headerRight: [
                    SetButton {
                        text: root.discovering ? "Остановить поиск" : "Найти устройства"
                        icon: Config.icons.refresh
                        onClicked: root.toggleScan()
                    }
                ]

                Txt {
                    visible: root.sorted.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Colors.fgVariant
                    text: root.discovering ? "Идёт поиск устройств… Включите режим сопряжения на нужном устройстве."
                        : "Нет сопряжённых устройств. Нажмите «Найти устройства»."
                }

                Column {
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: ScriptModel {
                            values: root.sorted
                            objectProp: "address"
                        }

                        delegate: Item {
                            id: dev

                            required property var modelData
                            required property int index

                            readonly property int grp: root.group(modelData)
                            readonly property bool firstOfGroup: index === 0 || root.group(root.sorted[index - 1]) !== grp
                            readonly property bool connecting: modelData.state === BluetoothDeviceState.Connecting
                            readonly property bool disconnecting: modelData.state === BluetoothDeviceState.Disconnecting
                            readonly property bool busy: connecting || disconnecting
                            readonly property bool pairBusy: modelData.pairing || tryPair
                            readonly property bool isPaired: modelData.paired || modelData.bonded
                            property bool tryConn: false
                            property bool tryPair: false
                            property string note: ""
                            property string noteKind: ""     // error | ok

                            function setNote(text, kind) {
                                note = text;
                                noteKind = kind;
                                noteClear.restart();
                            }
                            function startConnect() {
                                note = "";
                                tryConn = true;
                                watch.interval = 20000;
                                watch.restart();
                                modelData.connect();
                            }
                            function startPair() {
                                note = "";
                                tryPair = true;
                                watch.interval = 90000;    // с запасом на ввод/подтверждение кода (таймаут агента — 60 с)
                                watch.restart();
                                root.pairWhenReady(() => {
                                    if (dev.tryPair)
                                        dev.modelData.pair();
                                });
                            }
                            function pairFailed() {
                                tryPair = false;
                                const why = root.endReasons[modelData.address];
                                delete root.endReasons[modelData.address];
                                setNote(why === "rejected" ? "Сопряжение отклонено"
                                    : why === "timeout" ? "Время ожидания ответа истекло"
                                    : "Не удалось сопрячь. Проверьте, что устройство в режиме сопряжения.", "error");
                            }
                            // Сопряжение закончилось (успешно или нет): счётчик агента и закрытие показа кода.
                            onTryPairChanged: {
                                root.pairingCount += tryPair ? 1 : -1;
                                if (!tryPair && root.agent.request?.address === modelData.address && !root.agent.awaiting)
                                    root.agent.reject();
                            }
                            Component.onDestruction: if (tryPair)
                                root.pairingCount -= 1

                            width: parent.width
                            height: (firstOfGroup ? groupLabel.height + 6 : 0) + 56

                            Connections {
                                target: dev.modelData
                                function onPairingChanged() {
                                    if (dev.modelData.pairing || !dev.tryPair)
                                        return;
                                    if (dev.modelData.paired || dev.modelData.bonded) {
                                        dev.tryPair = false;
                                        dev.setNote("Сопряжено. Теперь можно подключить.", "ok");
                                    } else {
                                        dev.pairFailed();
                                    }
                                }
                                function onPairedChanged() {
                                    if (dev.modelData.paired && dev.tryPair) {
                                        dev.tryPair = false;
                                        dev.setNote("Сопряжено. Теперь можно подключить.", "ok");
                                    }
                                }
                                function onStateChanged() {
                                    if (!dev.tryConn)
                                        return;
                                    const s = dev.modelData.state;
                                    if (s === BluetoothDeviceState.Connected) {
                                        dev.tryConn = false;
                                    } else if (s === BluetoothDeviceState.Disconnected) {
                                        dev.tryConn = false;
                                        dev.setNote("Не удалось подключиться", "error");
                                    }
                                }
                            }

                            // Страховка: BlueZ не всегда сообщает об отказе — по таймеру снимаем «ожидание».
                            Timer {
                                id: watch
                                onTriggered: {
                                    if (dev.tryPair && !(dev.modelData.paired || dev.modelData.bonded)) {
                                        dev.modelData.cancelPair();
                                        dev.pairFailed();
                                    }
                                    if (dev.tryConn && !dev.modelData.connected && !dev.busy) {
                                        dev.tryConn = false;
                                        dev.setNote("Не удалось подключиться", "error");
                                    }
                                    dev.tryPair = false;
                                    dev.tryConn = false;
                                }
                            }
                            Timer {
                                id: noteClear
                                interval: 12000
                                onTriggered: dev.note = ""
                            }

                            Txt {
                                id: groupLabel
                                visible: dev.firstOfGroup
                                anchors {
                                    left: parent.left
                                    top: parent.top
                                    topMargin: dev.index === 0 ? 0 : 6
                                }
                                text: dev.grp === 0 ? "Подключено" : dev.grp === 1 ? "Сопряжено" : "Доступно"
                                color: Colors.fgVariant
                                font.bold: true
                                font.pixelSize: Config.fontSize - 1
                            }

                            Rectangle {
                                id: card
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                height: 56
                                radius: 10
                                color: dev.modelData.connected ? Qt.alpha(Colors.primaryContainer, 0.3)
                                    : cardHover.hovered ? Qt.alpha(Colors.surfaceContainerHighest, 0.5) : "transparent"
                                Behavior on color {
                                    ColorAnimation { duration: 120; easing.type: Config.animEasing }
                                }
                                HoverHandler {
                                    id: cardHover
                                }

                                Txt {
                                    id: devIcon
                                    anchors {
                                        left: parent.left
                                        leftMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: Config.iconSize + 8
                                    horizontalAlignment: Text.AlignHCenter
                                    readonly property string kind: String(dev.modelData.icon ?? "")
                                    text: kind.indexOf("head") >= 0 ? Config.icons.headphones
                                        : kind.indexOf("keyboard") >= 0 ? Config.icons.keyboard
                                        : kind.indexOf("audio") >= 0 ? Config.icons.speaker
                                        : dev.modelData.connected ? Config.icons.btConnected : Config.icons.bt
                                    color: dev.modelData.connected ? Colors.primary : Colors.fgVariant
                                    font.pixelSize: Config.iconSize + 4
                                }

                                Column {
                                    anchors {
                                        left: devIcon.right
                                        leftMargin: 8
                                        right: buttons.left
                                        rightMargin: 12
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 1

                                    Txt {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: root.title(dev.modelData)
                                        font.bold: dev.modelData.connected
                                    }
                                    Txt {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        font.pixelSize: Config.fontSize - 2
                                        color: dev.note !== "" ? (dev.noteKind === "error" ? Colors.error : Colors.success)
                                            : dev.modelData.connected ? Colors.success : Colors.fgVariant
                                        text: {
                                            if (dev.note !== "")
                                                return dev.note;
                                            if (dev.connecting)
                                                return "подключение…";
                                            if (dev.disconnecting)
                                                return "отключение…";
                                            if (dev.pairBusy)
                                                return "сопряжение…";
                                            let s = dev.modelData.connected ? "подключено" : dev.isPaired ? "сопряжено" : "доступно · " + dev.modelData.address;
                                            if (dev.isPaired && dev.modelData.trusted)
                                                s += " · доверенное";
                                            if (dev.modelData.batteryAvailable)
                                                s += " · " + Config.icons.battery + " " + Math.round(dev.modelData.battery * 100) + "%";
                                            return s;
                                        }
                                    }
                                }

                                Row {
                                    id: buttons
                                    anchors {
                                        right: parent.right
                                        rightMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 8

                                    SetButton {
                                        visible: dev.grp === 2
                                        text: "Сопрячь"
                                        icon: Config.icons.bt
                                        kind: "primary"
                                        enabled: !dev.pairBusy
                                        onClicked: dev.startPair()
                                    }
                                    SetButton {
                                        visible: dev.grp === 1
                                        text: "Подключить"
                                        enabled: !dev.busy
                                        onClicked: dev.startConnect()
                                    }
                                    SetButton {
                                        visible: dev.grp === 0
                                        text: "Отключить"
                                        enabled: !dev.busy
                                        onClicked: {
                                            dev.tryConn = false;
                                            dev.modelData.disconnect();
                                        }
                                    }
                                    Item {
                                        visible: dev.isPaired
                                        width: trustRow.implicitWidth
                                        height: 30
                                        Row {
                                            id: trustRow
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6
                                            Txt {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Доверять"
                                                color: Colors.fgVariant
                                                font.pixelSize: Config.fontSize - 1
                                            }
                                            PopSwitch {
                                                anchors.verticalCenter: parent.verticalCenter
                                                checked: dev.modelData.trusted
                                                onToggled: value => dev.modelData.trusted = value
                                            }
                                        }
                                        HoverHandler {
                                            id: trustHover
                                        }
                                        Tip {
                                            target: parent
                                            text: "Доверенное устройство подключается само, без запроса"
                                            hovered: trustHover.hovered
                                        }
                                    }
                                    SetButton {
                                        visible: dev.isPaired
                                        text: "Забыть"
                                        icon: Config.icons.trash
                                        kind: "danger"
                                        confirm: true
                                        confirmText: "Точно забыть?"
                                        enabled: !dev.busy
                                        tooltip: "Удалить сопряжение с устройством"
                                        onClicked: dev.modelData.forget()
                                    }
                                }
                            }
                        }
                    }
                }

                SetButton {
                    visible: root.hiddenUnnamed > 0 || root.showUnnamed
                    text: root.showUnnamed ? "Скрыть устройства без имени" : "Показать устройства без имени (" + root.hiddenUnnamed + ")"
                    onClicked: root.showUnnamed = !root.showUnnamed
                }

                Txt {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 2
                    text: "Наушники, колонки и мыши обычно сопрягаются сразу. Если устройство просит PIN или подтверждение кода, сверху появится карточка «Запрос сопряжения»."
                }
            }
        }
    }

    ScrollBar {
        target: flick
    }
}
