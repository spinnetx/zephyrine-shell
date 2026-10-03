import QtQuick
import QtMultimedia
import "components"

// Тема SDDM «zephyrine» (Theme-API 2.0, Qt 6). Контекстные объекты SDDM:
// sddm, config, userModel, sessionModel, keyboard.
Item {
    id: root

    width: 1920
    height: 1080

    // Палитре отдаём объект config (theme.conf); без него работают дефолты
    Component.onCompleted: {
        if (typeof config !== "undefined")
            Theme.conf = config;
        // play() только после того, как конфиг применён (путь к видео берётся из него)
        player.play();
        card.focusPassword();
    }

    // --- Подложка: градиент из палитры (виден, пока видео не загрузилось/при ошибке) ---
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.surfaceContainer }
            GradientStop { position: 1.0; color: Theme.background }
        }
    }

    // --- Видео-фон: зациклено, без звука ---
    // audioOutput намеренно не задан: в Qt 6 без AudioOutput звук не воспроизводится
    // вовсе (и аудиоустройство на greeter-е даже не открывается).
    MediaPlayer {
        id: player
        source: Qt.resolvedUrl(Theme.video)
        videoOutput: videoOut
        loops: MediaPlayer.Infinite
        onErrorOccurred: (error, errorString) => console.warn("zephyrine: видео не загрузилось:", errorString)
    }
    VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        // Плавно проявляем видео, когда пошли кадры; при ошибке остаётся градиент
        opacity: (player.playbackState === MediaPlayer.PlayingState && player.position > 0) ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Theme.animMs * 3; easing.type: Theme.easing }
        }
    }

    // Затемнение сверху и снизу — чтобы текст читался на любом кадре
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.alpha(Theme.background, Theme.dimTop) }
            GradientStop { position: 0.45; color: Theme.alpha(Theme.background, 0.15) }
            GradientStop { position: 1.0; color: Theme.alpha(Theme.background, Theme.dimBottom) }
        }
    }

    // Клик вне выпадающего списка сессий закрывает его
    MouseArea {
        anchors.fill: parent
        z: 5
        enabled: topBar.sessionOpen
        onClicked: topBar.closePopups()
    }

    TopBar {
        id: topBar
        z: 10
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.barMargin
    }

    // Карточка входа — чуть выше центра (оптический центр + место под чипы)
    LoginCard {
        id: card
        z: 1
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(topBar.height + 24, (parent.height - implicitHeight) / 2 - 30)
        sessionIndex: topBar.sessionIndex
    }

    // Внизу слева — имя хоста
    Txt {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 16
        text: (typeof sddm !== "undefined" && sddm.hostName) ? "  " + sddm.hostName : ""
        color: Theme.alpha(Theme.fg, 0.55)
        font.pixelSize: Theme.fontSize - 2
    }
}
