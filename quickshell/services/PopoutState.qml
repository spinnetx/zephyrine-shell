pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../"

// Общее состояние hover-попапов: ОДИН попап на всё приложение (на любом мониторе).
// Триггер (иконка в баре) вызывает enter()/leave(), сама карточка — popupEnter()/popupLeave().
// Закрытие — с задержкой popoutCloseDelayMs, если курсор не на триггере и не на карточке;
// при переходе иконка → иконка карточка плавно меняет содержимое/размер/позицию.
Singleton {
    id: root

    // Что открыто: "" | wifi | bluetooth | audio | battery | tray | clock | gpu | cpu | mem | net | timer | weather | apps
    property string kind: ""
    // Item-триггер (под ним центрируется карточка) и произвольные данные (например, SystemTrayItem).
    property Item item: null
    property var payload: null

    // Триггер, над которым сейчас курсор. leave(it) снимает hover, только если уходим именно с него:
    // при быстром движении Qt может прислать enter нового триггера раньше leave старого.
    property Item hoverItem: null
    readonly property bool triggerHover: hoverItem !== null
    property bool popupHover: false

    readonly property bool open: kind !== ""

    // Закреплённая карточка (IPC notifs toggle): не закрывается по уходу курсора и игнорирует hover
    // других триггеров; снимается Esc / кликом вне карточки (HyprlandFocusGrab в Popout) / повторным toggle.
    property bool pinned: false
    // Пилюли часов со всех мониторов (регистрируются самими часами) — чтобы закрепить на нужном.
    property var clocks: []
    // Кнопки приложений со всех мониторов
    property var appsButtons: []

    function registerClock(it) {
        clocks = clocks.concat([it]);
    }
    function unregisterClock(it) {
        clocks = clocks.filter(c => c !== it);
        if (item === it)
            close();
    }

    function registerApps(it) {
        appsButtons = appsButtons.concat([it]);
    }
    function unregisterApps(it) {
        appsButtons = appsButtons.filter(c => c !== it);
        if (item === it)
            close();
    }

    function toggleApps() {
        if (pinned && kind === "apps") {
            close();
            return;
        }
        const name = Hyprland.focusedMonitor?.name ?? "";
        const it = appsButtons.find(c => c.QsWindow.window?.screen?.name === name) ?? appsButtons[0];
        if (!it)
            return;
        openTimer.stop();
        closeTimer.stop();
        apply("apps", it, null);
        pinned = true;
    }

    // Открыть kind закреплённым у пилюли часов на мониторе с фокусом / закрыть, если уже закреплён.
    function togglePinned(k) {
        if (pinned) {
            close();
            return;
        }
        const name = Hyprland.focusedMonitor?.name ?? "";
        const it = clocks.find(c => c.QsWindow.window?.screen?.name === name) ?? clocks[0];
        if (!it)
            return;
        openTimer.stop();
        closeTimer.stop();
        apply(k, it, null);
        pinned = true;
    }

    // Открыть kind закреплённым у произвольного триггера по клику (меню приложений) / закрыть, если он уже открыт так.
    function togglePinnedAt(k, it) {
        if (pinned && kind === k) {
            close();
            return;
        }
        openTimer.stop();
        closeTimer.stop();
        apply(k, it, null);
        pinned = true;
    }

    // Закрепить/открепить текущий попап (форма пароля Wi-Fi): пока закреплён — не закрывается по hover
    // и получает клавиатуру (HyprlandFocusGrab в Popout). unpin() возвращает обычную hover-логику.
    function pin() {
        if (!open)
            return;
        closeTimer.stop();
        pinned = true;
    }

    function unpin() {
        pinned = false;
        update();
    }

    // Кандидат на открытие (ждёт popoutOpenDelayMs, если сейчас ничего не открыто).
    property string pendingKind: ""
    property Item pendingItem: null
    property var pendingPayload: null

    function enter(k, it, data) {
        if (pinned)
            return;
        hoverItem = it;
        closeTimer.stop();
        if (open) {
            // Переход иконка → иконка: сразу, без задержки.
            apply(k, it, data);
        } else {
            pendingKind = k;
            pendingItem = it;
            pendingPayload = data ?? null;
            openTimer.restart();
        }
    }

    function leave(it) {
        if (hoverItem !== it)
            return;
        hoverItem = null;
        openTimer.stop();
        update();
    }

    function popupEnter() {
        popupHover = true;
        closeTimer.stop();
    }

    function popupLeave() {
        popupHover = false;
        update();
    }

    function close() {
        openTimer.stop();
        closeTimer.stop();
        kind = "";
        pinned = false;
        hoverItem = null;
        popupHover = false;
    }

    function apply(k, it, data) {
        item = it;
        payload = data ?? null;
        kind = k;
    }

    function update() {
        if (!triggerHover && !popupHover && open && !pinned)
            closeTimer.restart();
    }

    Timer {
        id: openTimer
        interval: Config.popoutOpenDelayMs
        onTriggered: if (root.triggerHover) root.apply(root.pendingKind, root.pendingItem, root.pendingPayload)
    }

    Timer {
        id: closeTimer
        interval: Config.popoutCloseDelayMs
        onTriggered: if (!root.triggerHover && !root.popupHover && !root.pinned) root.kind = ""
    }

    // Если item-триггер исчез (например, иконка трея пропала) — закрываем.
    onItemChanged: if (item === null) close()

    IpcHandler {
        target: "apps"

        function toggle(): void { root.toggleApps(); }
        function open(): void { if (!root.pinned || root.kind !== "apps") root.toggleApps(); }
        function close(): void { if (root.pinned && root.kind === "apps") root.close(); }
    }
}
