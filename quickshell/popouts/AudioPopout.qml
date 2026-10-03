pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import "../"
import "../components"

// Звук: громкость и mute выхода по умолчанию, выбор выхода из списка, микрофон (громкость + mute).
Item {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.type === PwNodeType.AudioSink)

    // Без трекера audio-свойства узлов недоступны.
    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.sinks).filter(n => n)
    }

    implicitWidth: 300
    implicitHeight: col.implicitHeight

    function volIcon(n) {
        const a = n?.audio;
        if (!a || a.muted)
            return Config.icons.volMute;
        return a.volume > 0.66 ? Config.icons.volHigh : a.volume > 0.33 ? Config.icons.volMed : a.volume > 0 ? Config.icons.volLow : Config.icons.volOff;
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Txt {
            text: root.sink?.description ?? "Нет выхода"
            font.bold: true
            width: parent.width
            elide: Text.ElideRight
        }

        Row {
            spacing: 10
            height: 28

            PopItem {
                width: 32
                height: 28
                centered: true
                onClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.volIcon(root.sink)
                    color: root.sink?.audio?.muted ? Colors.fgVariant : Colors.primary
                    font.pixelSize: Config.iconSize + 2
                }
            }
            PopSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: 190
                value: root.sink?.audio?.volume ?? 0
                onMoved: v => {
                    if (root.sink?.audio)
                        root.sink.audio.volume = v * Config.volumeMax;
                }
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round((root.sink?.audio?.volume ?? 0) * 100) + "%"
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.35)
        }

        Txt {
            text: "Выход"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }

        Repeater {
            model: root.sinks

            PopItem {
                id: sinkItem

                required property var modelData

                width: col.width
                highlighted: root.sink !== null && modelData.id === root.sink.id
                onClicked: Pipewire.preferredDefaultAudioSink = modelData

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sinkItem.highlighted ? Config.icons.check : Config.icons.speaker
                    color: sinkItem.highlighted ? Colors.success : Colors.fgVariant
                    font.pixelSize: Config.iconSize
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 240
                    elide: Text.ElideRight
                    text: sinkItem.modelData.description
                    font.bold: sinkItem.highlighted
                }
            }
        }

        Rectangle {
            visible: root.source !== null
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.35)
        }

        Row {
            visible: root.source !== null
            spacing: 10
            height: 28

            PopItem {
                width: 32
                height: 28
                centered: true
                onClicked: if (root.source?.audio) root.source.audio.muted = !root.source.audio.muted
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.source?.audio?.muted ? Config.icons.micOff : Config.icons.mic
                    color: root.source?.audio?.muted ? Colors.fgVariant : Colors.tertiary
                    font.pixelSize: Config.iconSize + 2
                }
            }
            PopSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: 190
                accent: Colors.tertiary
                value: root.source?.audio?.volume ?? 0
                onMoved: v => {
                    if (root.source?.audio)
                        root.source.audio.volume = v;
                }
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"
            }
        }
    }
}
