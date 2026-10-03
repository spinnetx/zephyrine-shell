// zephyrine — горизонтальный бар Quickshell сверху экрана в стиле Caelestia.
// Запуск: qs -p ~/.config/quickshell/zephyrine 
import QtQuick
import Quickshell
import "launcher"
import "services"
import "powermenu"
import "toasts"
import "osd"
import "settings"

ShellRoot {
    // По одному бару на каждый монитор (eDP-1 + возможный внешний).
    // Окно бара пересоздаётся при смене положения (модель зависит от Config.barPosition): смена якорей layer-shell у живого окна
    // (вертикальная -> горизонтальная панель) оставляла панель пустой, а свежее окно ведёт себя так же, как при запуске шелла.
    Variants {
        model: Quickshell.screens.map(s => ({ screen: s, pos: Config.barPosition }))

        Bar {
            required property var modelData
            screen: modelData.screen
        }
    }

    // Центрированные оверлеи (состояние и IPC — services/Overlays.qml).
    Launcher {}
    PowerMenu {}

    // Окно настроек (обычное плавающее окно): существует, только пока Overlays.settingsOpen.
    LazyLoader {
        active: Overlays.settingsOpen
        SettingsWindow {}
    }

    // Тосты уведомлений/шелла (правый верх) и OSD громкости/яркости (низ по центру).
    Toasts {}
    Osd {}
}
