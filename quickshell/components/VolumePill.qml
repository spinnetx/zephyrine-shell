import QtQuick
import Quickshell.Services.Pipewire
import "../"

// Громкость отдельной пилюлей: значок и процент. Попап — kind "audio" (как у статус-иконок); клик — mute, колесо — громкость.
Pill {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool shown: sink !== null

    visible: shown
    clickable: true
    spacing: 6
    onClicked: if (sink?.audio) sink.audio.muted = !sink.audio.muted
    onScrolled: delta => {
        if (!sink?.audio)
            return;
        const v = sink.audio.volume + (delta > 0 ? Config.volumeStep : -Config.volumeStep);
        sink.audio.volume = Math.max(0, Math.min(Config.volumeMax, v));
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
    PopoutTrigger {
        parent: root
        kind: "audio"
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? Config.icons.volMute : root.vol > 0.66 ? Config.icons.volHigh : root.vol > 0.33 ? Config.icons.volMed : root.vol > 0 ? Config.icons.volLow : Config.icons.volOff
        color: root.muted ? Colors.fgVariant : Colors.primary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.vol * 100) + "%"
        color: root.muted ? Colors.fgVariant : Colors.fg
    }
}
