import QtQuick
import Quickshell.Services.Mpris
import "../"

// MPRIS: «исполнитель — трек», клик — play/pause. Виден, пока есть плеер с треком
// (играющий в приоритете); на паузе — приглушён, чтобы можно было продолжить.
Pill {
    id: root

    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) ?? ps.find(p => p.trackTitle !== "") ?? null;
    }

    readonly property bool shown: player !== null
    visible: shown
    clickable: true
    tooltip: player ? player.identity + (player.trackAlbum ? "\n" + player.trackAlbum : "") : ""
    onClicked: mouse => {
        if (player && player.canTogglePlaying)
            player.togglePlaying();
    }

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.icons.music
        color: Colors.primary
        font.pixelSize: Config.iconSize
    }
    Txt {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Config.mediaMaxWidth)
        text: root.player ? (root.player.trackArtist ? root.player.trackArtist + " — " : "") + root.player.trackTitle : ""
        elide: Text.ElideRight
        color: root.player && root.player.isPlaying ? Colors.fg : Colors.fgVariant
    }
}
