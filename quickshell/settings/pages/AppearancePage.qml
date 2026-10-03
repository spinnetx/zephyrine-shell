import QtQuick
import "../../"
import "../../services"
import "../../components"
import "../parts"

// Страница «Внешний вид» (DESIGN §2.5, §3.7, §6.5) с под-вкладками «Цвета» · «Оформление» · «Панель» · «Шрифты» · «Курсор и иконки» · «Обои» · «Приложения».
// Вкладки только переключают видимость карточек: состояние (local, errors, статус целей, баннеры, снекбар) общее и живёт здесь.
// Поток значений: ползунок → Prefs.preview (бар меняется сразу, только для ключей, которые бар читает сам) →
// по отпусканию (с дебаунсом 300 мс) SettingsCli.set → ответ CLI → ошибки/снекбар/перезапуск → статус целей.
// Сам файл настроек страница не пишет никогда; значения читает из Prefs (settings.json) с «оптимистичным»
// слоем local до ответа CLI. Для остальных вызовов (undo, apply, status) — только SettingsCli.
Item {
    id: root

    property string sub: ""          // из openAt("appearance/<вкладка>")
    property string tab: "colors"    // colors | style | bar | fonts | icons | wallpaper | apps
    readonly property var tabIds: ["colors", "style", "bar", "fonts", "icons", "wallpaper", "apps"]
    onSubChanged: applySub()
    onTabChanged: flick.contentY = 0
    function applySub() {
        if (tabIds.indexOf(sub) >= 0)
            tab = sub;
    }

    // Дефолты ключей, которых нет в Prefs.spec (дублируют schema.json — править в обоих местах).
    readonly property var defaults: ({
        "appearance.mode": "dark",
        "appearance.windowRounding": 10,
        "hypr.windowMode": "tile",
        "hypr.glassOpacity": 0.7,
        "appearance.kittyOpacity": 0.7,
        "hypr.borders.size": 2,
        "hypr.borders.style": "legacy",
        "hypr.borders.custom": { active: ["rgba(33ccffee)", "rgba(00ff99ee)"], angle: 45, inactive: "rgba(595959aa)" }
    })
    // Ключи, которые бар умеет показывать вживую через Prefs.preview.
    readonly property var liveKeys: ["appearance.glassAlpha", "appearance.surfaceAlpha", "appearance.radius"]
    readonly property var targetNames: ({
        "quickshell": "Панель", "hypr": "Hyprland", "gtk3": "GTK 3", "gtk4": "GTK 4", "qt6ct": "Qt", "zed": "Zed",
        "kitty": "Kitty", "kitty-conf": "Kitty", "zathura": "Zathura", "obsidian": "Obsidian", "tb-css": "Thunderbird", "tb-theme": "Thunderbird",
        "zen-chrome": "Zen", "zen-content": "Zen", "hyprlock": "Экран блокировки", "sddm": "Экран входа", "cursor": "Курсор (Hyprland)"
    })

    property var local: ({})         // значения, отправленные в CLI, но ещё не подтверждённые файлом
    property var batch: ({})         // ползунки: ключ -> значение, ждущие дебаунса
    property var errors: ({})        // ключ настройки -> текст ошибки CLI
    property var targetErrors: ({})  // id цели -> текст ошибки применения
    property var statusMap: ({})     // id цели -> объект status
    property var lastReq: null       // для «Повторить»: { pairs } или { args }
    property int retries: 0
    property string bannerText: ""
    property string bannerDetail: ""
    // Приложения, которым нужен перезапуск: верхнеуровневый restartPending из status / apply / ack-restart
    // (список приложений: gtk, zed, thunderbird…). Сброс — только командой ack-restart или автоматически в CLI.
    property var restartApps: []
    readonly property var appNames: ({
        "quickshell": "Панель", "hypr": "Hyprland", "gtk": "GTK", "qt6ct": "Qt", "zed": "Zed", "kitty": "Kitty",
        "zathura": "Zathura", "obsidian": "Obsidian", "thunderbird": "Thunderbird", "zen": "Zen"
    })
    readonly property string restartText: restartApps.map(a => appNames[a] ?? a).join(", ")
    // Различия для drift-целей: ключ строки (ids через запятую) -> { loading, ids, results: { id: ответ diff }, error }.
    property var diffs: ({})
    property bool pollPending: false   // запущен фоновый опрос status: его результат обрабатывается молча

    // ---------- значения ----------
    function eff(key) {
        const l = local[key];
        if (l !== undefined)
            return l;
        if (Prefs.spec[key] !== undefined)
            return Prefs.get(key);
        const v = Prefs.lookup(Prefs.file, key);
        return (v === undefined || v === null) ? defaults[key] : v;
    }

    readonly property var accentRaw: {
        const l = local["appearance.accent"];
        if (l !== undefined)
            return l;
        const v = Prefs.lookup(Prefs.file, "appearance.accent");
        return typeof v === "string" ? v : null;
    }
    readonly property bool accentCustom: accentRaw !== null
    readonly property string accentCurrent: accentCustom ? accentRaw : String(Colors.primary)
    readonly property string borderStyle: eff("hypr.borders.style")
    readonly property var customBorder: eff("hypr.borders.custom")

    function parseRgba(s) {
        const m = /^rgba\(([0-9a-fA-F]{6})([0-9a-fA-F]{2})\)$/.exec(String(s));
        return m ? { hex: "#" + m[1].toLowerCase(), a: m[2].toLowerCase() } : { hex: "#ffffff", a: "ee" };
    }
    function rgba(hex, a) {
        return "rgba(" + hex.slice(1) + a + ")";
    }
    // QML-цвет из rgba(rrggbbaa) (строка "#rrggbbaa" Qt прочитал бы как #aarrggbb).
    function qtColor(s) {
        const p = parseRgba(s);
        return Qt.rgba(parseInt(p.hex.slice(1, 3), 16) / 255, parseInt(p.hex.slice(3, 5), 16) / 255,
                       parseInt(p.hex.slice(5, 7), 16) / 255, parseInt(p.a, 16) / 255);
    }
    // Число цветов градиента: минимум по schema.json (minItems), максимум — предел Hyprland (10); в схеме максимума нет.
    readonly property int minBorderColors: 1
    readonly property int maxBorderColors: 10
    // Новое значение hypr.borders.custom с добавленным (копия последнего) / убранным цветом; null — нельзя (лимиты).
    function withAddedColor() {
        const c = cloneBorder();
        if (c.active.length >= maxBorderColors)
            return null;
        c.active.push(c.active[c.active.length - 1]);
        return c;
    }
    function withoutColor(i) {
        const c = cloneBorder();
        if (c.active.length <= minBorderColors || i < 0 || i >= c.active.length)
            return null;
        c.active.splice(i, 1);
        return c;
    }
    function cloneBorder() {
        const c = customBorder;
        return { active: c.active.slice(), angle: c.angle, inactive: c.inactive };
    }

    // ---------- отправка ----------
    function clearErrors(keys) {
        const e = Object.assign({}, errors);
        for (const k of keys)
            delete e[k];
        errors = e;
        bannerText = "";
        bannerDetail = "";
    }

    // Немедленная фиксация (выбор пресета, сегмент, переключатель).
    function send(pairs) {
        const keys = Object.keys(pairs);
        clearErrors(keys);
        local = Object.assign({}, local, pairs);
        for (const k of keys)
            if (liveKeys.indexOf(k) >= 0)
                Prefs.preview(k, pairs[k]);
        lastReq = { pairs: pairs };
        retries = 0;
        SettingsCli.set(pairs);
    }

    function sendRun(args) {
        clearErrors([]);
        lastReq = { args: args };
        retries = 0;
        SettingsCli.run(args);
    }

    function resend() {
        if (!lastReq)
            return;
        if (lastReq.pairs)
            SettingsCli.set(lastReq.pairs);
        else
            SettingsCli.run(lastReq.args);
    }

    // Ползунки: живое превью.
    function sliderPreview(key, v) {
        if (liveKeys.indexOf(key) >= 0)
            Prefs.preview(key, v);
    }
    // Ползунки: фиксация с дебаунсом 300 мс (быстрые правки склеиваются в один set).
    function queueSet(key, v) {
        local = Object.assign({}, local, { [key]: v });
        sliderPreview(key, v);
        const b = Object.assign({}, batch);
        b[key] = v;
        batch = b;
        debounce.restart();
    }
    function sliderCommit(key, v, decimals) {
        queueSet(key, Number(Number(v).toFixed(decimals)));
    }

    Timer {
        id: debounce
        interval: 300
        onTriggered: {
            const p = root.batch;
            root.batch = ({});
            root.send(p);
        }
    }

    Timer {
        id: retryTimer
        interval: 500
        onTriggered: root.resend()
    }

    // После ответа CLI: снять превью и оптимистичные значения (теперь правда — settings.json).
    // С небольшой задержкой: FileView может перечитать файл чуть позже выхода процесса.
    Timer {
        id: settleTimer
        interval: 250
        onTriggered: {
            if (debounce.running || SettingsCli.busy || !root.cliIdle())
                return;
            for (const k of Object.keys(root.local))
                Prefs.clearPreview(k);
            root.local = ({});
        }
    }

    function cliIdle() {
        return SettingsCli.queue.length === 0 && Object.keys(SettingsCli.pendingSet).length === 0;
    }

    function applyStatus(res) {
        const m = {};
        for (const t of (res.targets ?? []))
            m[t.id] = t;
        statusMap = m;
        if (Array.isArray(res.restartPending))
            restartApps = res.restartPending;
        // Различия показываем, пока цель в статусе «изменён вручную».
        const d = Object.assign({}, diffs);
        let changed = false;
        for (const k of Object.keys(d)) {
            if (!d[k].ids.some(id => m[id] && m[id].state === "manual")) {
                delete d[k];
                changed = true;
            }
        }
        if (changed)
            diffs = d;
    }

    function showDiff(key, ids) {
        const d = Object.assign({}, diffs);
        const want = ids.filter(id => statusMap[id] && statusMap[id].state === "manual");
        d[key] = { loading: true, ids: want, results: ({}), error: "" };
        diffs = d;
        for (const id of want)
            SettingsCli.run(["diff", id]);
    }
    function hideDiff(key) {
        const d = Object.assign({}, diffs);
        delete d[key];
        diffs = d;
    }
    function acceptDiff(res) {
        const d = Object.assign({}, diffs);
        for (const k of Object.keys(d)) {
            if (d[k].ids.indexOf(res.target) < 0)
                continue;
            const r = Object.assign({}, d[k].results);
            r[res.target] = res;
            d[k] = { loading: Object.keys(r).length < d[k].ids.length, ids: d[k].ids, results: r, error: "" };
        }
        diffs = d;
    }
    function failDiffs(text) {
        const d = Object.assign({}, diffs);
        for (const k of Object.keys(d))
            if (d[k].loading)
                d[k] = { loading: false, ids: d[k].ids, results: d[k].results, error: text };
        diffs = d;
    }

    // Периодический опрос status (пока страница видна): автосброс restartPending в CLI подхватывается без действий пользователя.
    Timer {
        interval: 5000
        repeat: true
        running: root.visible
        onTriggered: {
            if (SettingsCli.busy || !root.cliIdle() || debounce.running || root.pollPending)
                return;
            root.pollPending = true;
            SettingsCli.run(["status"]);
        }
    }

    function errMsg(e) {
        return typeof e === "string" ? e : (e.error ?? e.message ?? JSON.stringify(e));
    }

    function handle(res, code) {
        // Фоновый опрос: только обновить статус, ошибки молча (следующий опрос повторит).
        if (pollPending) {
            pollPending = false;
            if (res && Array.isArray(res.targets))
                applyStatus(res);
            return;
        }
        // Ответ `diff TARGET`.
        if (res && res.target !== undefined && Array.isArray(res.files)) {
            acceptDiff(res);
            return;
        }
        // Ответ `ack-restart`: список ожидающих перезапуска обновился; ещё раз спросить status (чипы целей).
        if (res && res.acked !== undefined) {
            if (Array.isArray(res.restartPending))
                restartApps = res.restartPending;
            if (res.ok === false)
                Toaster.show("Настройки", errMsg((res.errors ?? [])[0] ?? "ack-restart: ошибка"), "", "error");
            if (cliIdle())
                SettingsCli.run(["status"]);
            return;
        }
        const idle = cliIdle();
        // Ответ `status` (список целей) — только обновить чипы.
        if (res && res.root !== undefined && Array.isArray(res.targets)) {
            applyStatus(res);
            settleTimer.restart();
            return;
        }
        // Занято (flock): тихий повтор через 500 мс, до трёх раз.
        if (code === 3 && lastReq && retries < 3) {
            retries++;
            retryTimer.restart();
            return;
        }
        const errs = (res && Array.isArray(res.errors)) ? res.errors : [];
        const keyed = {};
        const tgt = {};
        const general = [];
        for (const e of errs) {
            const msg = errMsg(e);
            if (e && e.key)
                keyed[e.key] = msg;
            else if (e && e.target && e.target !== "*")
                tgt[e.target] = msg;
            else
                general.push(msg);
        }
        errors = Object.assign({}, errors, keyed);
        targetErrors = tgt;

        for (const k of Object.keys(keyed))
            Toaster.show("Настройки", k + ": " + keyed[k], "", "error");
        for (const id of Object.keys(tgt))
            Toaster.show("Не применено: " + (targetNames[id] ?? id), tgt[id], "", "error");

        if (!res || (code !== 0 && errs.length === 0)) {
            failDiffs("не удалось получить различия");
            bannerText = "Не удалось выполнить команду zephyrine-settings";
            bannerDetail = SettingsCli.lastError;
        } else if (general.length > 0) {
            bannerText = "Ошибка настроек: " + general.join("; ");
            bannerDetail = "";
        }

        // Ответ apply несёт актуальный restartPending.
        if (res && Array.isArray(res.restartPending))
            restartApps = res.restartPending;

        const keys = (res && Array.isArray(res.keys)) ? res.keys : [];
        const okNoErrors = res && res.ok !== false && errs.length === 0;
        if (res && res.restored !== undefined && okNoErrors)
            snack.show("Изменения отменены", "");
        else if (keys.length > 0 && Object.keys(keyed).length === 0)
            snack.show(okNoErrors ? "Применено" : "Сохранено, но не всё применилось", "Отменить");
        else if (okNoErrors && res.keys === undefined && res.dryRun !== true)
            snack.show("Применено", "");

        // Свежий статус целей (чипы, перезапуск).
        if (idle)
            SettingsCli.run(["status"]);
        settleTimer.restart();
    }

    Connections {
        target: SettingsCli
        function onFinished(res, code) {
            root.handle(res, code);
        }
    }

    Component.onCompleted: {
        applySub();
        SettingsCli.run(["status"]);
    }

    // ---------- вид ----------
    SetSegmented {
        id: tabs
        anchors {
            left: parent.left
            top: parent.top
        }
        options: [
            { value: "colors", label: "Цвета" },
            { value: "style", label: "Оформление" },
            { value: "bar", label: "Панель" },
            { value: "fonts", label: "Шрифты" },
            { value: "icons", label: "Курсор и иконки" },
            { value: "wallpaper", label: "Обои" },
            { value: "apps", label: "Приложения" }
        ]
        current: root.tab
        onSelected: v => root.tab = v
    }

    Flickable {
        id: flick
        anchors {
            left: parent.left
            right: parent.right
            top: tabs.bottom
            topMargin: 12
            bottom: parent.bottom
        }
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 60   // запас под снекбар
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: 12

            Banner {
                width: parent.width
                visible: root.bannerText.length > 0
                kind: "error"
                text: root.bannerText
                detail: root.bannerDetail
                buttonText: root.lastReq ? "Повторить" : ""
                onClicked: {
                    root.bannerText = "";
                    root.retries = 0;
                    root.resend();
                }
            }

            Banner {
                width: parent.width
                visible: root.restartApps.length > 0
                kind: "warn"
                text: "Нужен перезапуск: " + root.restartText
                detail: "Оформление записано; эти приложения подхватят его после перезапуска. «Скрыть» — отметить, что перезапуск не нужен."
                buttonText: "Скрыть"
                onClicked: root.sendRun(["ack-restart"])
            }

            SetCard {
                width: parent.width
                visible: root.tab === "colors"
                title: "Тема"
                icon: Config.icons.palette

                SetRow {
                    width: parent.width
                    label: "Режим"
                    hint: "Тёмная или светлая палитра для панели, GTK/Qt, Obsidian, Zed, Kitty, Zen/Thunderbird, экрана блокировки и входа. Акцент в светлой теме автоматически затемняется."
                    error: root.errors["appearance.mode"] ?? ""
                    SetSegmented {
                        options: [
                            { value: "dark", label: "Тёмная" },
                            { value: "light", label: "Светлая" }
                        ]
                        current: root.eff("appearance.mode")
                        onSelected: v => root.send({ "appearance.mode": v })
                    }
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 2
                    text: "Некоторые приложения подхватят тему после перезапуска; встроенные светлые/тёмные элементы Zen и Thunderbird, Obsidian (базовая схема) и стекло окон Hyprland от режима не зависят."
                }
            }

            SetCard {
                width: parent.width
                visible: root.tab === "colors"
                title: "Акцент"
                icon: Config.icons.palette
                headerRight: [
                    Txt {
                        visible: SettingsCli.busy
                        text: "применяется…"
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 1
                    }
                ]

                AccentPicker {
                    width: parent.width
                    light: root.eff("appearance.mode") === "light"
                    current: root.accentCurrent
                    custom: root.accentCustom
                    error: root.errors["appearance.accent"] ?? ""
                    onPicked: hex => root.send({ "appearance.accent": hex })
                    onResetRequested: root.send({ "appearance.accent": null })
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Colors.fgVariant
                    font.pixelSize: Config.fontSize - 2
                    text: "Акцент применяется и к экрану блокировки (со следующей блокировки), и к окну входа — для него после смены выполните «sudo sddm/install-theme.sh»."
                }
            }

            SetCard {
                width: parent.width
                visible: root.tab === "style"
                title: "Стекло и формы"
                icon: Config.icons.monitor

                PrefSliderRow {
                    width: parent.width
                    prefKey: "appearance.glassAlpha"
                    label: "Прозрачность фона"
                    hint: "Панель, GTK, Obsidian, Thunderbird, Zen, Zed"
                    error: root.errors[prefKey] ?? ""
                    from: 0.5
                    to: 1
                    step: 0.01
                    decimals: 2
                    defaultValue: 0.88
                    value: root.eff(prefKey)
                    onPreviewed: (k, v) => root.sliderPreview(k, v)
                    onCommitted: (k, v) => root.sliderCommit(k, v, 2)
                }
                PrefSliderRow {
                    width: parent.width
                    prefKey: "appearance.surfaceAlpha"
                    label: "Плотность элементов"
                    hint: "Пилюли панели, контейнеры GTK, Obsidian, Thunderbird"
                    error: root.errors[prefKey] ?? ""
                    from: 0.7
                    to: 1
                    step: 0.01
                    decimals: 2
                    defaultValue: 0.94
                    value: root.eff(prefKey)
                    onPreviewed: (k, v) => root.sliderPreview(k, v)
                    onCommitted: (k, v) => root.sliderCommit(k, v, 2)
                }
                PrefSliderRow {
                    width: parent.width
                    prefKey: "appearance.radius"
                    label: "Скругление"
                    hint: "Панель, попапы, GTK, Obsidian, Thunderbird, Zen"
                    error: root.errors[prefKey] ?? ""
                    from: 0
                    to: 20
                    step: 1
                    decimals: 0
                    suffix: " px"
                    defaultValue: 12
                    value: root.eff(prefKey)
                    onPreviewed: (k, v) => root.sliderPreview(k, v)
                    onCommitted: (k, v) => root.sliderCommit(k, v, 0)
                }
                PrefSliderRow {
                    width: parent.width
                    prefKey: "appearance.windowRounding"
                    label: "Скругление окон"
                    hint: "Hyprland: углы окон"
                    error: root.errors[prefKey] ?? ""
                    from: 0
                    to: 20
                    step: 1
                    decimals: 0
                    suffix: " px"
                    defaultValue: 10
                    value: root.eff(prefKey)
                    onPreviewed: (k, v) => root.sliderPreview(k, v)
                    onCommitted: (k, v) => root.sliderCommit(k, v, 0)
                }
                SetRow {
                    width: parent.width
                    label: "Режим окон"
                    hint: "Поведение окон по умолчанию для всей системы: тайловый режим упорядочивает окна по сетке, плавающие окна открываются свободно."
                    error: root.errors["hypr.windowMode"] ?? ""
                    SetSegmented {
                        options: [
                            { value: "tile", label: "Тайловый" },
                            { value: "float", label: "Плавающие окна" }
                        ]
                        current: root.eff("hypr.windowMode")
                        onSelected: v => root.send({ "hypr.windowMode": v })
                    }
                }
                PrefSliderRow {
                    width: parent.width
                    prefKey: "hypr.glassOpacity"
                    label: "Стекло окон (hyprglass)"
                    hint: "Hyprland: непрозрачность стекла окон"
                    error: root.errors[prefKey] ?? ""
                    from: 0.3
                    to: 1
                    step: 0.01
                    decimals: 2
                    defaultValue: 0.7
                    value: root.eff(prefKey)
                    onPreviewed: (k, v) => root.sliderPreview(k, v)
                    onCommitted: (k, v) => root.sliderCommit(k, v, 2)
                }
                PrefSliderRow {
                    width: parent.width
                    prefKey: "appearance.kittyOpacity"
                    label: "Прозрачность kitty"
                    hint: "Фон терминала (kitty перечитает конфиг сам)"
                    error: root.errors[prefKey] ?? ""
                    from: 0.5
                    to: 1
                    step: 0.01
                    decimals: 2
                    defaultValue: 0.7
                    value: root.eff(prefKey)
                    onPreviewed: (k, v) => root.sliderPreview(k, v)
                    onCommitted: (k, v) => root.sliderCommit(k, v, 2)
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Colors.outline, 0.25)
                }

                SetRow {
                    width: parent.width
                    label: "Рамки окон"
                    hint: "Как сейчас — прежний градиент; Акцент — от акцентного цвета; Свои — ниже. Рамки читает Hyprland из settings.lua."
                    error: root.errors["hypr.borders.style"] ?? ""
                    SetSegmented {
                        options: [
                            { value: "legacy", label: "Как сейчас" },
                            { value: "accent", label: "Акцент" },
                            { value: "custom", label: "Свои" }
                        ]
                        current: root.borderStyle
                        onSelected: v => root.send({ "hypr.borders.style": v })
                    }
                }
                PrefSliderRow {
                    width: parent.width
                    prefKey: "hypr.borders.size"
                    label: "Толщина рамки"
                    error: root.errors[prefKey] ?? ""
                    from: 0
                    to: 4
                    step: 1
                    decimals: 0
                    suffix: " px"
                    defaultValue: 2
                    value: root.eff(prefKey)
                    onCommitted: (k, v) => root.sliderCommit(k, v, 0)
                }

                // Свои рамки: цвета градиента активной рамки, угол и цвет неактивной (прозрачность цвета сохраняется).
                Column {
                    width: parent.width
                    visible: root.borderStyle === "custom"
                    spacing: 4

                    BorderPreview {
                        width: parent.width
                        colors: root.customBorder.active.map(c => root.qtColor(c))
                        angle: root.customBorder.angle
                        inactiveColor: root.qtColor(root.customBorder.inactive)
                        borderSize: Number(root.eff("hypr.borders.size"))
                        rounding: Number(root.eff("appearance.windowRounding"))
                    }

                    Txt {
                        text: "Активная рамка — цвета градиента (от " + root.minBorderColors + " до " + root.maxBorderColors + "); прозрачность каждого цвета сохраняется"
                        color: Colors.fgVariant
                        font.pixelSize: Config.fontSize - 2
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                    Txt {
                        visible: (root.errors["hypr.borders.custom"] ?? "").length > 0
                        text: root.errors["hypr.borders.custom"] ?? ""
                        color: Colors.error
                        font.pixelSize: Config.fontSize - 1
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                    Repeater {
                        model: root.customBorder.active
                        delegate: SetRow {
                            id: colorRow
                            required property int index
                            required property string modelData
                            width: parent.width
                            label: "Цвет " + (index + 1)
                            HexField {
                                width: 190
                                showContrast: false
                                value: root.parseRgba(colorRow.modelData).hex
                                onApplied: h => {
                                    const c = root.cloneBorder();
                                    c.active[colorRow.index] = root.rgba(h, root.parseRgba(colorRow.modelData).a);
                                    root.send({ "hypr.borders.custom": c });
                                }
                            }
                            SetButton {
                                icon: Config.icons.trash
                                tooltip: root.customBorder.active.length <= root.minBorderColors
                                    ? "Нужен хотя бы " + root.minBorderColors + " цвет" : "Убрать цвет"
                                enabled: root.customBorder.active.length > root.minBorderColors
                                onClicked: root.send({ "hypr.borders.custom": root.withoutColor(colorRow.index) })
                            }
                        }
                    }
                    SetButton {
                        text: "+ цвет"
                        enabled: root.customBorder.active.length < root.maxBorderColors
                        tooltip: enabled ? "" : "Не больше " + root.maxBorderColors + " цветов (предел Hyprland)"
                        onClicked: root.send({ "hypr.borders.custom": root.withAddedColor() })
                    }
                    PrefSliderRow {
                        width: parent.width
                        prefKey: "hypr.borders.custom"
                        label: "Угол градиента"
                        from: 0
                        to: 360
                        step: 5
                        decimals: 0
                        suffix: "°"
                        defaultValue: 45
                        value: root.customBorder.angle
                        onCommitted: (k, v) => {
                            const c = root.cloneBorder();
                            c.angle = Math.round(v);
                            root.queueSet(k, c);
                        }
                    }
                    SetRow {
                        width: parent.width
                        label: "Неактивная рамка"
                        HexField {
                            width: 170
                            showContrast: false
                            value: root.parseRgba(root.customBorder.inactive).hex
                            onApplied: h => {
                                const c = root.cloneBorder();
                                c.inactive = root.rgba(h, root.parseRgba(root.customBorder.inactive).a);
                                root.send({ "hypr.borders.custom": c });
                            }
                        }
                    }
                }
            }

            WallpaperCard {
                width: parent.width
                visible: root.tab === "wallpaper"
                status: root.statusMap["wallpaper"] ?? null
                error: root.errors["appearance.wallpaper.desktop"] ?? ""
                onPick: value => root.send({ "appearance.wallpaper.desktop": value })
            }

            BarCard {
                width: parent.width
                visible: root.tab === "bar"
            }

            FontsCard { width: parent.width; page: root; visible: root.tab === "fonts" }

            ThemesCard { width: parent.width; page: root; visible: root.tab === "icons" }

            SetCard {
                width: parent.width
                visible: root.tab === "apps"
                title: "Применение к приложениям"
                icon: Config.icons.settings
                chipKind: root.restartApps.length > 0 ? "restart" : "neutral"
                chipText: root.restartApps.length > 0 ? root.restartApps.length + " ждут перезапуска" : ""
                headerRight: [
                    SetButton {
                        visible: targets.pendingCount > 0
                        text: "Применить"
                        kind: "primary"
                        onClicked: root.sendRun(["apply"])
                    }
                ]

                TargetsList {
                    id: targets
                    width: parent.width
                    statusMap: root.statusMap
                    targetErrors: root.targetErrors
                    diffs: root.diffs
                    onShowDiff: (key, ids) => root.showDiff(key, ids)
                    onHideDiff: key => root.hideDiff(key)
                    onToggled: (ids, on) => {
                        const p = {};
                        for (const id of ids)
                            p["appearance.targets." + id] = on;
                        root.send(p);
                    }
                    onOverwrite: ids => root.sendRun(["apply", "--force", "--targets", ids.join(",")])
                }
            }
        }
    }

    ScrollBar {
        target: flick
    }

    Snackbar {
        id: snack
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 14
        }
        z: 10
        onAction: root.sendRun(["undo"])
    }
}
