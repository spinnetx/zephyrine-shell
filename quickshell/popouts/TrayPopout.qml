pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../"
import "../components"
import "../services"

// Трей: заголовок/подсказка приложения + пункты его меню (верхний уровень, через QsMenuOpener).
// Пункты с подменю помечены «›» и открывают нативное меню по клику. ПКМ по иконке — как раньше.
Item {
    id: root

    readonly property var tray: PopoutState.payload

    implicitWidth: 260
    implicitHeight: col.implicitHeight

    QsMenuOpener {
        id: opener
        menu: root.tray?.hasMenu ? root.tray.menu : null
    }

    Column {
        id: col
        width: parent.width
        spacing: 6

        Txt {
            width: parent.width
            elide: Text.ElideRight
            font.bold: true
            text: root.tray ? (root.tray.tooltipTitle !== "" ? root.tray.tooltipTitle : root.tray.title !== "" ? root.tray.title : root.tray.id) : ""
        }
        Txt {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
            text: root.tray?.tooltipDescription ?? ""
        }

        Rectangle {
            visible: entries.count > 0
            width: parent.width
            height: 1
            color: Qt.alpha(Colors.outline, 0.35)
        }

        Repeater {
            id: entries
            model: opener.children

            delegate: Item {
                id: entry

                required property var modelData

                width: col.width
                height: modelData.isSeparator ? 7 : 30

                Rectangle {
                    visible: entry.modelData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Colors.outline, 0.35)
                }

                PopItem {
                    visible: !entry.modelData.isSeparator
                    width: parent.width
                    height: 30
                    clickable: entry.modelData.enabled
                    opacity: entry.modelData.enabled ? 1 : 0.5
                    onClicked: {
                        if (entry.modelData.hasChildren) {
                            // Подменю в попапе не рисуем — открываем нативное меню приложения.
                            const it = PopoutState.item;
                            const pos = it.mapToItem(null, 0, it.height + 4);
                            const tray = root.tray;
                            const win = it.QsWindow.window;
                            PopoutState.close();
                            tray.display(win, pos.x, pos.y);
                        } else {
                            entry.modelData.triggered();
                            PopoutState.close();
                        }
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 228
                        elide: Text.ElideRight
                        text: entry.modelData.text + (entry.modelData.hasChildren ? "  ›" : "")
                    }
                }
            }
        }
    }
}
