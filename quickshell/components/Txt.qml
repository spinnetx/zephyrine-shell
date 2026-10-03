import QtQuick
import "../"

// Текст с шрифтом/цветом по умолчанию.
Text {
    color: Colors.fg
    font.family: Config.fontFamily
    font.pixelSize: Config.fontSize
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
    Behavior on color {
        ColorAnimation { duration: Config.animMs; easing.type: Config.animEasing }
    }
}
