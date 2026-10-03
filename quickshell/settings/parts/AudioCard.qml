import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../"
import "../../services"
import "../../components"

// Карточка «Звук» (DESIGN §4.3, §6.5):
// - Выбор выхода по умолчанию, ползунок громкости, mute.
// - Выбор микрофона (входа), ползунок громкости, mute.
// - Громкость отдельных приложений (isStream).
// - Максимальная громкость (100% | 150%) через Prefs.
// - Кнопка запуска pavucontrol.
SetCard {
    id: root

    title: "Звук"
    icon: Config.icons.volHigh

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.type === PwNodeType.AudioSink)
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.type === PwNodeType.AudioSource)
    readonly property var appStreams: Pipewire.nodes.values.filter(n => n.isStream && n.audio)

    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.sinks).concat(root.sources).concat(root.appStreams).filter(n => n)
    }

    function volIcon(n) {
        const a = (n && n.audio) ? n.audio : null;
        if (!a || a.muted)
            return Config.icons.volMute;
        return a.volume > 0.66 ? Config.icons.volHigh : a.volume > 0.33 ? Config.icons.volMed : a.volume > 0 ? Config.icons.volLow : Config.icons.volOff;
    }

    function appName(n) {
        if (!n)
            return "Приложение";
        const props = n.properties || {};
        return props["application.name"] || props["media.name"] || n.description || n.name || "Приложение";
    }

    // --- Вывод звука ---
    SetRow {
        width: parent.width
        label: "Выход звука"
        hint: (root.sink && root.sink.description) ? root.sink.description : "Устройство вывода не выбрано"

        SetDropdown {
            width: 280
            options: root.sinks.map(s => ({ value: s.id, label: s.description }))
            current: root.sink ? root.sink.id : undefined
            placeholder: "Выберите выход"
            onSelected: val => {
                const target = root.sinks.find(s => s.id === val);
                if (target)
                    Pipewire.preferredDefaultAudioSink = target;
            }
        }
    }

    // Ползунок громкости выхода
    Item {
        width: parent.width
        height: 36

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            PopItem {
                width: 34
                height: 32
                centered: true
                enabled: root.sink && root.sink.audio !== undefined
                onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.volIcon(root.sink)
                    color: (root.sink && root.sink.audio && root.sink.audio.muted) ? Colors.fgVariant : Colors.primary
                    font.pixelSize: Config.iconSize + 2
                }
            }

            SetSlider {
                width: parent.width - 34 - 12 - 50
                anchors.verticalCenter: parent.verticalCenter
                from: 0
                to: Prefs.volumeMax
                step: Prefs.volumeStep > 0 ? Prefs.volumeStep : 0.01
                value: (root.sink && root.sink.audio) ? root.sink.audio.volume : 0
                accent: Colors.primary
                onPreview: v => {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.volume = v;
                }
                onCommit: v => {
                    if (root.sink && root.sink.audio)
                        root.sink.audio.volume = v;
                }
            }

            Txt {
                width: 50
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Math.round(((root.sink && root.sink.audio) ? root.sink.audio.volume : 0) * 100) + "%"
                font.bold: true
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // --- Ввод звука (микрофон) ---
    SetRow {
        width: parent.width
        label: "Вход звука"
        hint: (root.source && root.source.description) ? root.source.description : "Микрофон не выбран"

        SetDropdown {
            width: 280
            options: root.sources.map(s => ({ value: s.id, label: s.description }))
            current: root.source ? root.source.id : undefined
            placeholder: "Выберите вход"
            onSelected: val => {
                const target = root.sources.find(s => s.id === val);
                if (target)
                    Pipewire.preferredDefaultAudioSource = target;
            }
        }
    }

    // Ползунок громкости входа
    Item {
        width: parent.width
        height: 36

        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            PopItem {
                width: 34
                height: 32
                centered: true
                enabled: root.source && root.source.audio !== undefined
                onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.source && root.source.audio && root.source.audio.muted) ? Config.icons.micOff : Config.icons.mic
                    color: (root.source && root.source.audio && root.source.audio.muted) ? Colors.fgVariant : Colors.tertiary
                    font.pixelSize: Config.iconSize + 2
                }
            }

            SetSlider {
                width: parent.width - 34 - 12 - 50
                anchors.verticalCenter: parent.verticalCenter
                from: 0
                to: 1.0
                step: 0.01
                value: (root.source && root.source.audio) ? root.source.audio.volume : 0
                accent: Colors.tertiary
                onPreview: v => {
                    if (root.source && root.source.audio)
                        root.source.audio.volume = v;
                }
                onCommit: v => {
                    if (root.source && root.source.audio)
                        root.source.audio.volume = v;
                }
            }

            Txt {
                width: 50
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Math.round(((root.source && root.source.audio) ? root.source.audio.volume : 0) * 100) + "%"
                font.bold: true
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // --- Громкость приложений ---
    Txt {
        text: "Громкость приложений"
        font.bold: true
        font.pixelSize: Config.fontSize
        color: Colors.fg
    }

    Column {
        width: parent.width
        spacing: 8

        Txt {
            visible: root.appStreams.length === 0
            width: parent.width
            text: "Нет активных приложений, воспроизводящих звук"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }

        Repeater {
            model: root.appStreams

            delegate: Item {
                id: streamItem
                required property var modelData

                width: parent.width
                height: 32

                Row {
                    anchors.fill: parent
                    spacing: 10

                    PopItem {
                        width: 28
                        height: 28
                        centered: true
                        onClicked: if (streamItem.modelData.audio) streamItem.modelData.audio.muted = !streamItem.modelData.audio.muted
                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (streamItem.modelData.audio && streamItem.modelData.audio.muted) ? Config.icons.volMute : Config.icons.music
                            color: (streamItem.modelData.audio && streamItem.modelData.audio.muted) ? Colors.fgVariant : Colors.primary
                            font.pixelSize: Config.iconSize
                        }
                    }

                    Txt {
                        width: 140
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.appName(streamItem.modelData)
                        elide: Text.ElideRight
                    }

                    SetSlider {
                        width: parent.width - 28 - 140 - 50 - 30
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: 1.0
                        step: 0.01
                        value: (streamItem.modelData.audio) ? streamItem.modelData.audio.volume : 0
                        onPreview: v => {
                            if (streamItem.modelData.audio)
                                streamItem.modelData.audio.volume = v;
                        }
                        onCommit: v => {
                            if (streamItem.modelData.audio)
                                streamItem.modelData.audio.volume = v;
                        }
                    }

                    Txt {
                        width: 44
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(((streamItem.modelData.audio) ? streamItem.modelData.audio.volume : 0) * 100) + "%"
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    // --- Максимальная громкость ---
    SetRow {
        width: parent.width
        label: "Максимальная громкость"
        hint: "Разрешить программное усиление звука до 150%"

        SetSegmented {
            options: [
                { value: 1.0, label: "100%" },
                { value: 1.5, label: "150%" }
            ]
            current: Prefs.volumeMax
            onSelected: val => SettingsCli.set({ "audio.volumeMax": val })
        }
    }

    // --- Pavucontrol ---
    SetRow {
        width: parent.width
        label: "Системный микшер"
        hint: "Расширенная конфигурация профилей карт и каналов"

        SetButton {
            text: "Открыть pavucontrol"
            icon: Config.icons.settings
            onClicked: pavuProcess.running = true
        }
    }

    Process {
        id: pavuProcess
        command: ["pavucontrol"]
    }
}
