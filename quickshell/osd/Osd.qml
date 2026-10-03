import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../"
import "../components"

// OSD громкости и яркости: пилюля по центру у нижнего края на мониторе с фокусом, Config.osdMs.
// Громкость/mute — Pipewire (сигналы volumeChanged/mutedChanged), яркость — sysfs backlight
// (опрос Config.brightnessPollMs: sysfs не даёт надёжных inotify-событий). Первые значения после
// старта/смены устройства — инициализация, OSD не показывают.
Scope {
    id: root

    // Что показано: "volume" | "brightness"; value 0..1; muted — только для громкости.
    property string kind: "volume"
    property real value: 0
    property bool muted: false
    property bool shown: false

    function show(k, v, m) {
        kind = k;
        value = Math.max(0, Math.min(1, v));
        muted = m;
        shown = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: Config.osdMs
        onTriggered: root.shown = false
    }

    // --- Громкость ---
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio ?? null
    // Пока идёт «разогрев» после появления/смены sink, изменения считаются инициализацией.
    property bool volArmed: false

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
    onSinkChanged: {
        volArmed = false;
        arm.restart();
    }
    Timer {
        id: arm
        interval: 1200
        running: true
        onTriggered: root.volArmed = true
    }
    function volChanged() {
        if (volArmed && audio)
            show("volume", audio.volume / Config.volumeMax, audio.muted);
    }
    Connections {
        target: root.audio
        function onVolumeChanged() { root.volChanged(); }
        function onMutedChanged() { root.volChanged(); }
    }

    // --- Яркость ---
    property string blDir: ""
    property real blMax: 0
    property real blLast: -1

    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -d \"$d\" ] && echo \"$d\" && break; done"]
        stdout: StdioCollector {
            onStreamFinished: root.blDir = text.trim()
        }
    }
    FileView {
        id: maxFile
        path: root.blDir !== "" ? root.blDir + "/max_brightness" : ""
        printErrors: false
        onLoaded: root.blMax = Number(text().trim())
    }
    FileView {
        id: curFile
        path: root.blDir !== "" ? root.blDir + "/brightness" : ""
        printErrors: false
        onLoaded: {
            const v = Number(text().trim());
            if (root.blMax <= 0 || isNaN(v))
                return;
            // Первое чтение — только запоминаем.
            if (root.blLast >= 0 && v !== root.blLast)
                root.show("brightness", v / root.blMax, false);
            root.blLast = v;
        }
    }
    Timer {
        interval: Config.brightnessPollMs
        repeat: true
        running: root.blDir !== "" && root.blMax > 0
        onTriggered: curFile.reload()
    }

    // --- Окна (по одному на монитор; видно только на сфокусированном) ---
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            readonly property bool focusedScreen: (Hyprland.focusedMonitor?.name ?? "") === modelData.name

            anchors.bottom: true
            margins.bottom: Config.osdBottomMargin + (Config.barPosition === "bottom" ? Config.barExtent : 0)
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "zephyrine-osd"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            implicitWidth: 300
            implicitHeight: 56
            color: "transparent"
            visible: focusedScreen && (root.shown || card.opacity > 0.01)
            // Пустая маска: OSD не перехватывает ввод.
            mask: Region {}

            Rectangle {
                id: card

                readonly property bool isVol: root.kind === "volume"
                readonly property color tint: root.muted ? Colors.fgVariant : Colors.primary

                anchors.fill: parent
                radius: Config.barRadius
                color: Qt.alpha(Colors.background, 0.94)
                border.width: 1
                border.color: Qt.alpha(Colors.outlineVariant, 0.6)
                opacity: root.shown ? 1 : 0
                transform: Translate {
                    y: root.shown ? 0 : 12
                    Behavior on y {
                        NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 12

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        horizontalAlignment: Text.AlignHCenter
                        color: card.tint
                        font.pixelSize: Config.iconSize + 8
                        text: !card.isVol ? Config.icons.brightness
                            : root.muted ? Config.icons.volMute
                            : root.value > 0.66 ? Config.icons.volHigh
                            : root.value > 0.33 ? Config.icons.volMed
                            : root.value > 0 ? Config.icons.volLow : Config.icons.volOff
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 170
                        height: 6
                        radius: 3
                        color: Colors.surfaceContainerHighest

                        Rectangle {
                            width: parent.width * (root.muted ? 0 : root.value)
                            height: parent.height
                            radius: 3
                            color: card.tint
                            Behavior on width {
                                NumberAnimation { duration: 100; easing.type: Config.animEasing }
                            }
                        }
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        font.bold: true
                        color: root.muted ? Colors.fgVariant : Colors.fg
                        text: root.muted ? "mute" : Math.round(root.value * 100) + "%"
                    }
                }
            }
        }
    }
}
