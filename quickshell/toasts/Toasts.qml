import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../"
import "../components"
import "../services"

// Всплывающие тосты в правом верхнем углу под баром: уведомления (Notifs.toastList) и сообщения
// шелла (Toaster.list) в одном стеке, новые сверху, максимум Config.toastMax (остальные ждут очереди).
// Окно на каждом мониторе, но карточки есть только на мониторе с фокусом (Hyprland.focusedMonitor);
// поверх всего (overlay), место не занимает (exclusiveZone -1), ввод — только в пределах стека.
Scope {
    id: root

    // Единый список записей: {key, kind: notif|msg, notif / msg, t}. Новые первыми.
    readonly property var entries: {
        const out = [];
        for (const n of Notifs.toastList)
            out.push({ key: "n" + n.uid, kind: "notif", notif: n, t: n.time });
        for (const m of Toaster.list)
            out.push({ key: m.key, kind: "msg", msg: m, t: m.t });
        out.sort((a, b) => b.t - a.t);
        return out.slice(0, Config.toastMax);
    }

    // Что реально нарисовано: entries + ещё «уходящие» (анимация исчезновения) записи.
    // ListView-переходы add/remove здесь сбоили (карточки застревали полупрозрачными),
    // поэтому появление/исчезновение анимирует сам делегат, а список двигает соседей через displaced.
    property var displayed: []
    property var leaving: ({})     // key -> время (мс), когда запись можно выкинуть из displayed

    function sync() {
        const now = Date.now();
        const live = new Set(entries.map(e => e.key));
        const old = displayed.filter(d => live.has(d.key) || (leaving[d.key] ?? 0) > now || !(d.key in leaving));
        const oldKeys = new Set(old.map(d => d.key));
        const fresh = entries.filter(e => !oldKeys.has(e.key));
        const lv = {};
        const merged = fresh.concat(old.map(d => live.has(d.key) ? entries.find(e => e.key === d.key) : d));
        for (const d of merged) {
            if (!live.has(d.key))
                lv[d.key] = leaving[d.key] ?? (now + Config.animMs + 50);
        }
        leaving = lv;
        displayed = merged;
        cleanup.restart();
    }
    onEntriesChanged: sync()

    // Выкидывает из displayed записи, чья анимация ухода закончилась.
    Timer {
        id: cleanup
        interval: Config.animMs + 60
        onTriggered: {
            const now = Date.now();
            const keep = root.displayed.filter(d => !(d.key in root.leaving) || root.leaving[d.key] > now);
            if (keep.length !== root.displayed.length) {
                const lv = {};
                for (const d of keep)
                    if (d.key in root.leaving)
                        lv[d.key] = root.leaving[d.key];
                root.leaving = lv;
                root.displayed = keep;
            }
            if (keep.some(d => d.key in root.leaving))
                restart();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            readonly property bool focusedScreen: (Hyprland.focusedMonitor?.name ?? "") === modelData.name
            // Окно живёт, пока есть карточки и ещё 300 мс после (доигрывает анимация исчезновения).
            // Число карточек берём из списка записей, а не из ListView.count: у невидимого окна
            // ListView не обновляет count (нет layout), и окно бы никогда не показалось.
            readonly property int shownCount: focusedScreen ? root.displayed.length : 0
            onShownCountChanged: linger.restart()
            readonly property bool active: shownCount > 0 || linger.running

            anchors {
                top: true
                right: true
            }
            // Тосты в правом верхнем углу: отступают от панели, если она сверху или справа.
            margins {
                top: (Config.barPosition === "top" ? Config.barExtent : Config.barMargin) + Config.toastGap
                right: Config.barPosition === "right" ? Config.barExtent : Config.barMargin
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "zephyrine-toasts"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            implicitWidth: Config.toastWidth
            implicitHeight: 720
            color: "transparent"
            visible: active
            // Ввод только над стеком (явные x/y/w/h: Region { item: } в 0.3.1 даёт пустую маску).
            mask: Region {
                x: 0
                y: 0
                width: list.width
                height: list.contentHeight
            }

            Timer {
                id: linger
                interval: 350
            }

            ListView {
                id: list

                // Размеры заданы явно: у ещё не показанного окна parent.width/height = 0, и делегаты не создались бы.
                width: Config.toastWidth
                height: win.implicitHeight
                spacing: Config.toastGap
                interactive: false
                
                model: ScriptModel {
                    values: win.focusedScreen ? root.displayed : []
                    objectProp: "key"
                }

                delegate: Item {
                    id: del

                    required property var modelData
                    readonly property bool isNotif: modelData.kind === "notif"
                    readonly property bool gone: root.leaving[modelData.key] !== undefined
                    // Время показа, мс; 0 — не закрывать автоматически (critical).
                    readonly property real duration: isNotif ? Notifs.toastMs(modelData.notif) : Config.toastMessageMs
                    property real remaining: duration
                    // Анимация появления: false → true сразу после создания; исчезновения — gone.
                    property bool appeared: false

                    width: list.width
                    height: card.item ? card.item.implicitHeight : 0
                    Component.onCompleted: appeared = true

                    function dismissToast() {
                        if (isNotif)
                            Notifs.hideToast(modelData.notif);
                        else
                            Toaster.hide(modelData.key);
                    }

                    // Таймер с паузой под курсором: «оставшееся» не сбрасывается при уходе мыши.
                    Timer {
                        interval: 100
                        repeat: true
                        running: !del.gone && del.duration > 0 && !(card.item?.hovered ?? false)
                        onTriggered: {
                            del.remaining -= 100;
                            if (del.remaining <= 0)
                                del.dismissToast();
                        }
                    }

                    Loader {
                        id: card
                        width: parent.width
                        opacity: del.appeared && !del.gone ? 1 : 0
                        x: del.appeared && !del.gone ? 0 : 50
                        sourceComponent: del.isNotif ? notifCard : msgCard

                        Behavior on opacity {
                            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                        }
                        Behavior on x {
                            NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                        }
                    }

                    Component {
                        id: notifCard
                        NotifCard {
                            toast: true
                            notif: del.modelData.notif
                            onCloseRequested: del.dismissToast()
                        }
                    }
                    Component {
                        id: msgCard
                        ToastMsg {
                            msg: del.modelData.msg
                            onCloseRequested: del.dismissToast()
                        }
                    }
                }

                displaced: Transition {
                    NumberAnimation { property: "y"; duration: Config.animMs; easing.type: Config.animEasing }
                }
            }
        }
    }
}
