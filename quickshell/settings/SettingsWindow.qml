import QtQuick
import Quickshell
import "../"
import "../services"
import "../components"

// Окно центра настроек (DESIGN §2.7, §2.8, §6.1): обычное плавающее окно, не слой.
// Создаётся LazyLoader'ом в shell.qml по Overlays.settingsOpen: пока флаг false, окна нет вовсе;
// закрытие компоситором (SUPER+C, ✕ и т.п.) приходит сигналом closed и сбрасывает флаг.
// Заголовок ровно «Zephyrine · Настройки» — на него рассчитано правило окна в hyprland.lua
// (settings/patches/hyprland-settings.patch).
// Клавиатура: Ctrl+1…4 — раздел, Ctrl+Tab / Ctrl+Shift+Tab — следующий/предыдущий, Esc — закрыть
// (открытый выпадающий список сам перехватывает Esc раньше окна).
FloatingWindow {
    id: win

    readonly property var sections: [
        { id: "appearance", label: "Внешний вид", icon: Config.icons.palette },
        { id: "network", label: "Сеть и Bluetooth", icon: Config.icons.wifi3 },
        { id: "devices", label: "Звук, экран, питание", icon: Config.icons.monitor },
        { id: "system", label: "Система и приложения", icon: Config.icons.keyboard }
    ]
    readonly property int currentIndex: {
        for (let i = 0; i < sections.length; i++)
            if (sections[i].id === Overlays.settingsSection)
                return i;
        return 0;
    }

    title: "Zephyrine · Настройки"
    visible: true
    implicitWidth: 1040
    implicitHeight: 700
    minimumSize: Qt.size(860, 560)
    color: Qt.alpha(Colors.background, Config.barAlpha)

    onClosed: Overlays.closeSettings()

    function go(i) {
        const n = sections.length;
        Overlays.setSettingsSection(sections[((i % n) + n) % n].id);
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (event.key === Qt.Key_Escape) {
                Overlays.closeSettings();
            } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
                win.go(event.key - Qt.Key_1);
            } else if (ctrl && event.key === Qt.Key_Tab) {
                win.go(win.currentIndex + ((event.modifiers & Qt.ShiftModifier) ? -1 : 1));
            } else if (ctrl && event.key === Qt.Key_Backtab) {
                win.go(win.currentIndex - 1);
            } else {
                return;
            }
            event.accepted = true;
        }

        Sidebar {
            id: sidebar
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
                margins: 12
            }
            sections: win.sections
            current: Overlays.settingsSection
            onSelected: id => Overlays.setSettingsSection(id)
        }

        // Шапка страницы: заголовок раздела и кнопка закрытия.
        Item {
            id: header
            anchors {
                left: sidebar.right
                leftMargin: 20
                right: parent.right
                rightMargin: 12
                top: parent.top
                topMargin: 12
            }
            height: 40

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: win.sections[win.currentIndex].label
                font.bold: true
                font.pixelSize: Config.fontSize + 7
            }

            Rectangle {
                id: closeBtn
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 32
                height: 32
                radius: Config.pillRadius
                color: closeHover.hovered ? Colors.surfaceContainerHighest : "transparent"
                Behavior on color {
                    ColorAnimation { duration: 120; easing.type: Config.animEasing }
                }
                Txt {
                    anchors.centerIn: parent
                    text: Config.icons.close
                    color: closeHover.hovered ? Colors.error : Colors.fgVariant
                    font.pixelSize: Config.iconSize + 2
                }
                HoverHandler {
                    id: closeHover
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: Overlays.closeSettings()
                }
            }
        }

        PageHost {
            anchors {
                left: header.left
                right: header.right
                top: header.bottom
                topMargin: 8
                bottom: parent.bottom
                bottomMargin: 12
            }
            section: Overlays.settingsSection
            sub: Overlays.settingsSub
        }
    }
}
