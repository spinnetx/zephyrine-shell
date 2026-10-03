import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../services"
import "../../components"

// Карточка «Экраны» (DESIGN §4.3, §6.5):
// - Список подключённых мониторов со снимка (zephyrine-settings monitors snapshot).
// - Редактирование разрешения, масштаба, поворота, взаимного расположения.
// - Ползунок яркости подсветки (brightnessctl).
// - Безопасное применение (monitors try SPEC -> сторож -> подтверждение).
SetCard {
    id: root

    title: "Экраны"
    icon: Config.icons.monitor

    property var initialMonitors: []
    property var monitors: []
    property bool loading: false
    property string errorMessage: ""

    signal tryPending(string token, int timeoutSec)

    readonly property bool hasChanges: {
        if (monitors.length !== initialMonitors.length)
            return monitors.length > 0;
        return JSON.stringify(monitors) !== JSON.stringify(initialMonitors);
    }

    readonly property int activeCount: {
        let count = 0;
        for (let i = 0; i < monitors.length; i++) {
            if (!monitors[i].disabled)
                count++;
        }
        return count;
    }

    headerRight: Row {
        spacing: 6

        PopItem {
            width: 28
            height: 24
            centered: true
            onClicked: root.refresh()
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.refresh
                color: Colors.fgVariant
                font.pixelSize: Config.iconSize - 2
            }
        }
    }

    Component.onCompleted: refresh()

    function refresh() {
        if (snapshotProc.running)
            return;
        loading = true;
        errorMessage = "";
        snapshotProc.running = true;
    }

    function parseSnapshot(text) {
        loading = false;
        try {
            const lines = text.trim().split("\n");
            for (let i = lines.length - 1; i >= 0; i--) {
                const line = lines[i].trim();
                if (line.startsWith("{")) {
                    const obj = JSON.parse(line);
                    if (obj && Array.isArray(obj.monitors)) {
                        root.initialMonitors = JSON.parse(JSON.stringify(obj.monitors));
                        root.monitors = JSON.parse(JSON.stringify(obj.monitors));
                        return;
                    }
                }
            }
        } catch (e) {
            errorMessage = "Ошибка разбора параметров экранов: " + e;
        }
    }

    Process {
        id: snapshotProc
        command: [Config.settingsCli, "monitors", "snapshot"]
        stdout: StdioCollector {
            onStreamFinished: root.parseSnapshot(text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("monitors snapshot:", text);
            }
        }
    }

    // Применение настроек экрана
    function applyMonitors() {
        errorMessage = "";
        const spec = monitors.map(m => {
            const pos = m.position || ((m.x || 0) + "x" + (m.y || 0));
            const modeStr = m.mode || ((m.width || 1920) + "x" + (m.height || 1080) + "@" + Math.round(m.refreshRate || 60));
            return {
                match: m.match || ("desc:" + m.description) || m.name,
                enabled: !m.disabled,
                mode: modeStr,
                position: pos,
                scale: m.scale || 1.0,
                transform: m.transform || 0,
                mirror: m.mirror || null
            };
        });

        tryProc.command = [Config.settingsCli, "monitors", "try", JSON.stringify(spec)];
        tryProc.running = true;
    }

    Process {
        id: tryProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const lines = text.trim().split("\n");
                    for (let i = lines.length - 1; i >= 0; i--) {
                        if (lines[i].startsWith("{")) {
                            const res = JSON.parse(lines[i]);
                            if (res.ok && res.token) {
                                root.tryPending(res.token, res.timeoutSec || 15);
                                return;
                            } else if (res.errors && res.errors.length > 0) {
                                root.errorMessage = res.errors.join("; ");
                                return;
                            }
                        }
                    }
                } catch (e) {
                    root.errorMessage = "Не удалось применить параметры: " + e;
                }
            }
        }
    }

    // --- Ошибка ---
    Txt {
        visible: root.errorMessage !== ""
        width: parent.width
        text: root.errorMessage
        color: Colors.error
        font.pixelSize: Config.fontSize - 1
        wrapMode: Text.WordWrap
    }

    // --- Список мониторов ---
    Column {
        width: parent.width
        spacing: 12

        Repeater {
            model: root.monitors

            delegate: MonitorCard {
                id: monCard
                required property var modelData
                required property int index

                width: parent.width
                monitor: monCard.modelData
                allMonitors: root.monitors
                activeMonitorCount: root.activeCount

                onUpdated: newMon => {
                    const copy = JSON.parse(JSON.stringify(root.monitors));
                    copy[monCard.index] = newMon;
                    root.monitors = copy;
                }
            }
        }
    }

    // --- Кнопки подтверждения/сброса изменений ---
    Item {
        visible: root.hasChanges
        width: parent.width
        height: 38

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            SetButton {
                text: "Сбросить"
                onClicked: root.monitors = JSON.parse(JSON.stringify(root.initialMonitors))
            }

            SetButton {
                text: "Применить…"
                kind: "primary"
                onClicked: root.applyMonitors()
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // --- Яркость экрана ---
    Item {
        id: brightItem
        width: parent.width
        height: 36

        property int currentPercent: 100

        Process {
            id: blQuery
            running: true
            command: ["brightnessctl", "-m"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const parts = text.trim().split(",");
                    if (parts.length >= 4) {
                        const pct = parseInt(parts[3].replace("%", ""), 10);
                        if (!isNaN(pct))
                            brightItem.currentPercent = pct;
                    }
                }
            }
        }

        Process {
            id: blSet
        }

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: Config.icons.brightness
                color: Colors.primary
                font.pixelSize: Config.iconSize + 2
            }

            Txt {
                width: 70
                anchors.verticalCenter: parent.verticalCenter
                text: "Яркость"
                font.bold: true
            }

            SetSlider {
                width: parent.width - 24 - 70 - 50 - 24
                anchors.verticalCenter: parent.verticalCenter
                from: 1
                to: 100
                step: 1
                decimals: 0
                suffix: "%"
                value: brightItem.currentPercent
                onPreview: v => {
                    brightItem.currentPercent = Math.round(v);
                    blSet.command = ["brightnessctl", "-e4", "-n2", "set", Math.round(v) + "%"];
                    blSet.running = true;
                }
                onCommit: v => {
                    brightItem.currentPercent = Math.round(v);
                    blSet.command = ["brightnessctl", "-e4", "-n2", "set", Math.round(v) + "%"];
                    blSet.running = true;
                }
            }

            Txt {
                width: 44
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: brightItem.currentPercent + "%"
                font.bold: true
            }
        }
    }
}
