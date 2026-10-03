pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Состояние центрированных оверлеев (лаунчер приложений, меню питания), окна настроек и их IPC-таргеты.
// Открыт максимум один; окна (launcher/Launcher.qml, powermenu/PowerMenu.qml) создаются один раз
// в shell.qml и читают отсюда open-флаги и экран. Кнопка питания в баре и бинды Hyprland
// (`qs -p ~/.config/quickshell/zephyrine ipc call <target> <функция>`) приходят в одни и те же функции.
Singleton {
    id: root

    property bool launcherOpen: false
    property bool powerOpen: false
    // Окно настроек (settings/SettingsWindow.qml) — обычное окно, не оверлей: не входит в правило «открыт один»,
    // не закрывает лаунчер/меню питания. Раздел и подраздел живут здесь и после закрытия окна (DESIGN §6.1).
    property bool settingsOpen: false
    property string settingsSection: "appearance"   // appearance | network | devices | system
    property string settingsSub: ""                  // подраздел из openAt("раздел/подраздел"), "" — нет
    // Монитор с фокусом на момент открытия (окно не «прыгает» между мониторами, пока открыто).
    property var screen: Quickshell.screens[0]

    function focusScreen() {
        const name = Hyprland.focusedMonitor?.name;
        root.screen = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    function openLauncher() {
        if (launcherOpen)
            return;
        focusScreen();
        powerOpen = false;
        PopoutState.close();
        launcherOpen = true;
    }

    function closeLauncher() {
        launcherOpen = false;
    }

    function toggleLauncher() {
        launcherOpen ? closeLauncher() : openLauncher();
    }

    function openPower() {
        if (powerOpen)
            return;
        focusScreen();
        launcherOpen = false;
        PopoutState.close();
        powerOpen = true;
    }

    function closePower() {
        powerOpen = false;
    }

    function togglePower() {
        powerOpen ? closePower() : openPower();
    }

    readonly property var settingsSections: ["appearance", "network", "devices", "system"]

    // Разбор "раздел" или "раздел/подраздел"; неизвестный раздел — false, состояние не меняется.
    function setSettingsSection(spec) {
        const parts = String(spec).split("/");
        if (settingsSections.indexOf(parts[0]) < 0)
            return false;
        settingsSection = parts[0];
        settingsSub = parts.slice(1).join("/");
        return true;
    }

    function openSettings(spec) {
        if (spec !== undefined && spec !== "")
            setSettingsSection(spec);
        PopoutState.close();
        settingsOpen = true;
    }

    function closeSettings() {
        settingsOpen = false;
    }

    function toggleSettings() {
        settingsOpen ? closeSettings() : openSettings();
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { root.toggleLauncher(); }
        function open(): void { root.openLauncher(); }
        function close(): void { root.closeLauncher(); }
    }

    IpcHandler {
        target: "powermenu"

        function toggle(): void { root.togglePower(); }
        function open(): void { root.openPower(); }
        function close(): void { root.closePower(); }
    }

    IpcHandler {
        target: "settings"

        function open(): void { root.openSettings(); }
        function openAt(section: string): void { root.openSettings(section); }
        function toggle(): void { root.toggleSettings(); }
        function close(): void { root.closeSettings(); }
    }
}
