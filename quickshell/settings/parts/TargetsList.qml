import QtQuick
import "../../"
import "../../components"

// Список приложений, к которым применяется оформление (DESIGN §3.8, §6.3, §6.5): на каждое — чип статуса
// из `zephyrine-settings status` (вживую / нужен перезапуск / не установлено / изменён вручную / ошибка),
// подсказка «что нужно приложению» и переключатель «управлять». Несколько целей одного приложения
// (gtk3+gtk4, tb-css+tb-theme, …) сводятся в одну строку по худшему статусу.
// Сам ничего не вызывает: toggled(ids, on) и overwrite(ids) обрабатывает страница.
Column {
    id: root

    property var statusMap: ({})       // id цели -> объект из status.targets
    property var targetErrors: ({})    // id цели -> текст ошибки последнего применения
    property var diffs: ({})           // ключ строки (id через запятую) -> состояние показа различий (см. страницу)
    signal showDiff(string key, var ids)
    signal hideDiff(string key)
    signal toggled(var ids, bool on)
    signal overwrite(var ids)

    // Подписи приложений и id целей из targets.json; цели будущих этапов (state "later") не показываются.
    readonly property var apps: [
        { label: "Панель (Quickshell)", ids: ["quickshell"] },
        { label: "Hyprland (рамки, скругление окон)", ids: ["hypr"] },
        { label: "Kitty", ids: ["kitty", "kitty-conf"] },
        { label: "Zed", ids: ["zed"] },
        { label: "GTK 3/4", ids: ["gtk3", "gtk4", "gtk3-settings", "gtk4-settings", "gsettings"] },
        { label: "Qt (qt6ct)", ids: ["qt6ct", "qt6ct-conf"] },
        { label: "Zathura", ids: ["zathura"] },
        { label: "Obsidian", ids: ["obsidian"] },
        { label: "Thunderbird", ids: ["tb-css", "tb-theme"] },
        { label: "Zen Browser", ids: ["zen-chrome", "zen-content"] }
    ]
    readonly property var missingText: ({
        "not-installed": "не установлено",
        "profile-not-found": "профиль не найден",
        "registry-not-found": "vault'ы не найдены"
    })

    // Число приложений, ждущих перезапуска, и неприменённых (для сводки в шапке карточки).
    readonly property int restartCount: countSev(4)
    readonly property int pendingCount: countSev(2)
    readonly property var restartLabels: labelsSev(4)

    function present(t) {
        return t !== undefined && t !== null && t.state !== "later" && t.state !== "no-template";
    }

    // Статус одной цели -> {sev, kind, text, tip}; sev — «тяжесть» для свёртки (больше — хуже).
    function classify(t, err) {
        if (err)
            return { sev: 6, kind: "error", text: "", tip: err };
        switch (t.state) {
        case "error":
            return { sev: 6, kind: "error", text: "", tip: t.message ?? t.reason ?? "" };
        case "manual":
            return { sev: 5, kind: "manual", text: "", tip: "Файл изменён вручную: при применении он не будет перезаписан без подтверждения" };
        case "restart":
            return { sev: 4, kind: "restart", text: "", tip: t.restart ?? "" };
        case "missing":
            if (t.reason === "not-deployed")
                return { sev: 2, kind: "neutral", text: "не применено", tip: "Файл оформления ещё не создан: нажмите «Применить»" };
            return { sev: 3, kind: "missing", text: root.missingText[t.reason] ?? (t.reason ?? ""), tip: t.message ?? "" };
        case "outdated":
            return { sev: 2, kind: "neutral", text: "не применено", tip: "Файл отличается от текущих настроек: нажмите «Применить»" };
        case "unmanaged":
            return { sev: 1, kind: "neutral", text: "не управляется", tip: "Цель выключена переключателем справа" };
        default:
            return { sev: 0, kind: "live", text: "", tip: t.restart ?? "" };
        }
    }

    function infoFor(app, map, errs) {
        let best = null;
        let managed = true;
        let notRunning = false;
        let first = null;
        const ids = [];
        for (const id of app.ids) {
            const t = map[id];
            if (!present(t))
                continue;
            ids.push(id);
            if (first === null)
                first = t;
            if (t.managed === false)
                managed = false;
            if (t.appRunning === false)
                notRunning = true;
            const c = classify(t, errs[id] ?? "");
            if (best === null || c.sev > best.sev)
                best = c;
        }
        if (best === null)
            return { present: false, ids: [] };
        return {
            present: true,
            ids: ids,
            managed: managed,
            notRunning: notRunning,
            sev: best.sev,
            kind: best.kind,
            text: best.text,
            tip: best.tip,
            hint: first.restart ?? ""
        };
    }

    function countSev(sev) {
        let n = 0;
        for (const a of apps) {
            const i = infoFor(a, statusMap, targetErrors);
            if (i.present && i.sev === sev)
                n++;
        }
        return n;
    }

    function labelsSev(sev) {
        const out = [];
        for (const a of apps) {
            const i = infoFor(a, statusMap, targetErrors);
            if (i.present && i.sev === sev)
                out.push(a.label.replace(/ \(.*\)$/, ""));
        }
        return out;
    }

    spacing: 2

    Repeater {
        model: root.apps

        delegate: Column {
            id: row
            required property var modelData
            readonly property var info: root.infoFor(modelData, root.statusMap, root.targetErrors)
            readonly property string diffKey: info.present ? info.ids.join(",") : ""
            readonly property var diff: root.diffs[diffKey]

            visible: info.present
            width: root.width
            spacing: 6

            Item {
                id: head
                width: row.width
                height: row.info.present ? Math.max(46, texts.implicitHeight + 14) : 0
                opacity: row.info.present && row.info.managed ? 1 : 0.6

                Behavior on opacity {
                    NumberAnimation { duration: Config.animMs; easing.type: Config.animEasing }
                }

                Column {
                    id: texts
                    anchors {
                        left: parent.left
                        right: ctl.left
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1
                    Txt {
                        width: parent.width
                        text: row.modelData.label
                        elide: Text.ElideRight
                    }
                    Txt {
                        width: parent.width
                        visible: text.length > 0
                        text: !row.info.present ? ""
                            : row.info.notRunning ? "приложение не запущено" + (row.info.hint ? " · " + row.info.hint : "")
                            : row.info.hint
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 2
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: ctl
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    SetButton {
                        visible: row.info.present && row.info.kind === "manual"
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.diff ? "Скрыть различия" : "Показать различия"
                        onClicked: row.diff ? root.hideDiff(row.diffKey) : root.showDiff(row.diffKey, row.info.ids)
                    }
                    SetButton {
                        visible: row.info.present && row.info.kind === "manual"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Перезаписать"
                        kind: "danger"
                        confirm: true
                        confirmText: "Точно перезаписать?"
                        onClicked: root.overwrite(row.info.ids)
                    }
                    SetButton {
                        visible: row.info.present && row.info.kind === "manual"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Не управлять"
                        onClicked: root.toggled(row.info.ids, false)
                    }
                    StatusChip {
                        anchors.verticalCenter: parent.verticalCenter
                        kind: row.info.present ? row.info.kind : "neutral"
                        text: row.info.present ? row.info.text : ""
                        tooltip: row.info.present ? row.info.tip : ""
                    }
                    PopSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: row.info.present && row.info.managed
                        onToggled: v => root.toggled(row.info.ids, v)
                    }
                }
            }

            DiffView {
                visible: row.info.present && row.diff !== undefined
                width: row.width
                loading: row.diff ? row.diff.loading : false
                error: row.diff ? row.diff.error : ""
                ids: row.diff ? row.diff.ids : []
                results: row.diff ? row.diff.results : ({})
                onClosed: root.hideDiff(row.diffKey)
            }
        }
    }
}
