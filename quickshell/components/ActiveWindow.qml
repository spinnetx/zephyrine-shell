import QtQuick
import Quickshell.Hyprland
import "../"

// Заголовок активного окна с elide.
Pill {
    id: root

    readonly property string title: Hyprland.activeToplevel?.title ?? ""

    readonly property bool shown: title !== ""
    visible: shown

    Txt {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Config.titleMaxWidth)
        text: root.title
        elide: Text.ElideRight
        color: Colors.fgVariant
    }
}
