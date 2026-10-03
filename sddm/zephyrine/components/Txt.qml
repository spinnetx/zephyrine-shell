import QtQuick

// Текст с шрифтом и цветом из палитры.
Text {
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    renderType: Text.NativeRendering
    elide: Text.ElideRight
}
