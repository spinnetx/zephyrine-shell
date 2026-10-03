import QtQuick
import "../../"
import "../../services"
import "../../components"

// Карточка «Панель» (DESIGN §4.5, Y8): сторона экрана и состав зон панели (начало / центр / конец). Читает Prefs
// (bar.position, bar.left/center/right), пишет только через SettingsCli.set — шелл применяет вживую, перезапуск не нужен.
// Элемент можно сдвинуть в зоне, перенести в другую зону, убрать (он попадёт в «Скрытые») и вернуть.
// Каталог элементов дублирует settings/zsettings/barlayout.py и реестр в Bar.qml - править во всех трёх местах.
SetCard {
    id: root

    title: "Панель"
    icon: Config.icons.monitor

    readonly property var catalog: [
        { id: "workspaces", label: "Рабочие столы", v: true },
        { id: "activeWindow", label: "Заголовок окна", v: false },
        { id: "media", label: "Медиа", v: false },
        { id: "limits", label: "Лимиты ИИ", v: false },
        { id: "disk", label: "Диски", v: false },
        { id: "gpu", label: "Видеокарта", v: true },
        { id: "cpu", label: "Процессор", v: true },
        { id: "mem", label: "Память", v: true },
        { id: "net", label: "Сеть (скорость)", v: true },
        { id: "tray", label: "Трей", v: true },
        { id: "status", label: "Статус-иконки", v: true },
        { id: "clock", label: "Часы и календарь", v: true },
        { id: "power", label: "Кнопка питания", v: true },
        { id: "temp", label: "Температура", v: true },
        { id: "battery", label: "Батарея (с процентом)", v: true },
        { id: "kbd", label: "Раскладка клавиатуры", v: true },
        { id: "timer", label: "Таймер", v: true },
        { id: "weather", label: "Погода", v: true },
        { id: "volume", label: "Громкость", v: true },
        { id: "wifi", label: "Wi-Fi / сеть", v: true },
        { id: "bluetooth", label: "Bluetooth", v: true },
        { id: "apps", label: "Меню приложений", v: true }
    ]
    readonly property var zoneKeys: ["left", "center", "right"]
    readonly property var zones: [Prefs.barLeft, Prefs.barCenter, Prefs.barRight]
    readonly property bool vertical: Prefs.barPosition === "left" || Prefs.barPosition === "right"
    readonly property var zoneNames: vertical ? ["Начало (сверху)", "Центр", "Конец (снизу)"] : ["Начало (слева)", "Центр", "Конец (справа)"]
    readonly property var zoneShort: ["Начало", "Центр", "Конец"]
    readonly property var hidden: catalog.filter(c => zones.every(z => z.indexOf(c.id) < 0))

    property var page: null
    property int addZone: 2
    property string error: ""
    property bool sent: false

    function val(key) {
        const l = page ? page.local[key] : undefined;
        if (l !== undefined)
            return l;
        if (Prefs.spec[key] !== undefined)
            return Prefs.get(key);
        const v = Prefs.lookup(Prefs.file, key);
        return v === undefined ? Prefs.def(key) : v;
    }
    function def(key) {
        return Prefs.def(key);
    }
    function err(key) {
        return page ? (page.errors[key] ?? "") : "";
    }

    function info(id) {
        return catalog.find(c => c.id === id) ?? { id: id, label: id, v: false };
    }
    function copyZones() {
        return zones.map(z => z.slice());
    }
    function commit(z) {
        error = "";
        sent = true;
        console.log("BarCard: bar.left=" + JSON.stringify(z[0]) + " bar.center=" + JSON.stringify(z[1]) + " bar.right=" + JSON.stringify(z[2]));
        SettingsCli.set({ "bar.left": z[0], "bar.center": z[1], "bar.right": z[2] });
    }
    function shift(zi, i, delta) {
        const z = copyZones();
        const j = i + delta;
        if (j < 0 || j >= z[zi].length)
            return;
        const t = z[zi][i];
        z[zi][i] = z[zi][j];
        z[zi][j] = t;
        commit(z);
    }
    function moveTo(zi, i, to) {
        if (to === zi)
            return;
        const z = copyZones();
        const id = z[zi].splice(i, 1)[0];
        z[to].push(id);
        commit(z);
    }
    function removeAt(zi, i) {
        const z = copyZones();
        z[zi].splice(i, 1);
        commit(z);
    }
    function add(id) {
        const z = copyZones();
        z[addZone].push(id);
        commit(z);
    }

    function setCity(t) {
        t = t.trim();
        if (t === Prefs.weatherCity)
            return;
        error = "";
        sent = true;
        SettingsCli.set({ "weather.city": t });
    }
    Component.onCompleted: cityField.text = Prefs.weatherCity
    Connections {
        target: Prefs
        function onWeatherCityChanged() {
            if (!cityField.focused)
                cityField.text = Prefs.weatherCity;
        }
    }

    Connections {
        target: SettingsCli
        function onFinished(res, code) {
            if (!root.sent)
                return;
            root.sent = false;
            root.error = code === 0 ? "" : SettingsCli.errorText(res, code);
        }
    }

    SetRow {
        width: parent.width
        label: "Положение панели"
        hint: "У какой стороны экрана стоит панель"
        SetSegmented {
            options: [
                { value: "top", label: "Сверху" },
                { value: "bottom", label: "Снизу" },
                { value: "left", label: "Слева" },
                { value: "right", label: "Справа" }
            ]
            current: Prefs.barPosition
            onSelected: v => {
                root.error = "";
                root.sent = true;
                SettingsCli.set({ "bar.position": v });
            }
        }
    }
    Txt {
        visible: root.error.length > 0
        width: parent.width
        text: root.error
        color: Colors.error
        wrapMode: Text.WordWrap
    }

    SetRow {
        width: parent.width
        label: "Город для погоды"
        hint: "Для виджета «Погода» (wttr.in). Пусто — определить по IP"
        PopField {
            id: cityField
            width: 200
            placeholder: "напр. Warszawa"
            onAccepted: root.setCity(text)
            onFocusedChanged: if (!focused) root.setCity(text)
        }
    }
    Txt {
        visible: root.vertical
        width: parent.width
        text: "На вертикальной панели элементы показываются компактно (иконки). Заголовок окна, медиа, лимиты ИИ и диски на ней не отображаются."
        color: Colors.fgVariant
        font.pixelSize: Config.fontSize - 2
        wrapMode: Text.WordWrap
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    Repeater {
        model: 3

        delegate: Column {
            id: zcol
            required property int index
            readonly property var ids: root.zones[index]
            width: root.width - Config.popoutPadding * 2
            spacing: 2

            Txt {
                text: root.zoneNames[zcol.index]
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 1
            }
            Txt {
                visible: zcol.ids.length === 0
                text: "пусто"
                color: Colors.fgVariant
                font.pixelSize: Config.fontSize - 2
                opacity: 0.7
            }
            Repeater {
                model: zcol.ids

                delegate: Item {
                    id: erow
                    required property int index
                    required property string modelData
                    readonly property var meta: root.info(modelData)
                    width: zcol.width
                    height: 36

                    Txt {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        width: 190
                        elide: Text.ElideRight
                        text: erow.meta.label + (root.vertical && !erow.meta.v ? "  (нет на вертикальной)" : "")
                        opacity: root.vertical && !erow.meta.v ? 0.5 : 1
                    }
                    Row {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6
                        SetButton {
                            icon: Config.icons.arrowUp
                            tooltip: "Выше"
                            enabled: erow.index > 0
                            onClicked: root.shift(zcol.index, erow.index, -1)
                        }
                        SetButton {
                            icon: Config.icons.arrowDown
                            tooltip: "Ниже"
                            enabled: erow.index < zcol.ids.length - 1
                            onClicked: root.shift(zcol.index, erow.index, 1)
                        }
                        SetSegmented {
                            options: [{ value: 0, label: root.zoneShort[0] }, { value: 1, label: root.zoneShort[1] }, { value: 2, label: root.zoneShort[2] }]
                            current: zcol.index
                            onSelected: v => root.moveTo(zcol.index, erow.index, v)
                        }
                        SetButton {
                            icon: Config.icons.trash
                            tooltip: "Убрать с панели"
                            onClicked: root.removeAt(zcol.index, erow.index)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    Txt {
        text: "Добавить на панель"
        font.bold: true
    }
    Txt {
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.hidden.length === 0
            ? "Все доступные элементы (" + root.catalog.length + ") уже на панели. Убранный с панели элемент появится здесь, и его можно вернуть."
            : "Не на панели: " + root.hidden.length + ". Выберите зону и нажмите на элемент."
        color: Colors.fgVariant
        font.pixelSize: Config.fontSize - 1
    }
    Row {
        visible: root.hidden.length > 0
        spacing: 10
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: "Добавить в:"
            color: Colors.fgVariant
            font.pixelSize: Config.fontSize - 1
        }
        SetSegmented {
            options: [{ value: 0, label: "Начало" }, { value: 1, label: "Центр" }, { value: 2, label: "Конец" }]
            current: root.addZone
            onSelected: v => root.addZone = v
        }
    }
    Flow {
        width: parent.width
        spacing: 6
        Repeater {
            model: root.hidden
            delegate: SetButton {
                required property var modelData
                text: "+ " + modelData.label
                onClicked: root.add(modelData.id)
            }
        }
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Qt.alpha(Colors.outline, 0.25)
    }

    Txt {
        text: "Размеры и отступы"
        font.bold: true
    }

    PrefSliderRow {
        width: parent.width
        prefKey: "bar.height"
        label: "Высота панели"
        hint: "Толщина панели на экране"
        error: root.err(prefKey)
        from: 32
        to: 56
        step: 1
        decimals: 0
        suffix: " px"
        defaultValue: root.def(prefKey)
        value: root.val(prefKey)
        onPreviewed: (k, v) => page ? page.sliderPreview(k, v) : Prefs.preview(k, v)
        onCommitted: (k, v) => page ? page.sliderCommit(k, v, 0) : SettingsCli.set({ [k]: v })
    }

    PrefSliderRow {
        width: parent.width
        prefKey: "bar.margin"
        label: "Внешний отступ панели"
        hint: "Отступ от краёв экрана"
        error: root.err(prefKey)
        from: 0
        to: 24
        step: 1
        decimals: 0
        suffix: " px"
        defaultValue: root.def(prefKey)
        value: root.val(prefKey)
        onPreviewed: (k, v) => page ? page.sliderPreview(k, v) : Prefs.preview(k, v)
        onCommitted: (k, v) => page ? page.sliderCommit(k, v, 0) : SettingsCli.set({ [k]: v })
    }

    PrefSliderRow {
        width: parent.width
        prefKey: "bar.padding"
        label: "Внутренний отступ панели"
        hint: "Отступ от краёв панели до виджетов"
        error: root.err(prefKey)
        from: 2
        to: 24
        step: 1
        decimals: 0
        suffix: " px"
        defaultValue: root.def(prefKey)
        value: root.val(prefKey)
        onPreviewed: (k, v) => page ? page.sliderPreview(k, v) : Prefs.preview(k, v)
        onCommitted: (k, v) => page ? page.sliderCommit(k, v, 0) : SettingsCli.set({ [k]: v })
    }

    PrefSliderRow {
        width: parent.width
        prefKey: "bar.spacing"
        label: "Расстояние между виджетами"
        hint: "Зазор между блоками виджетов в зонах панели"
        error: root.err(prefKey)
        from: 2
        to: 20
        step: 1
        decimals: 0
        suffix: " px"
        defaultValue: root.def(prefKey)
        value: root.val(prefKey)
        onPreviewed: (k, v) => page ? page.sliderPreview(k, v) : Prefs.preview(k, v)
        onCommitted: (k, v) => page ? page.sliderCommit(k, v, 0) : SettingsCli.set({ [k]: v })
    }

    PrefSliderRow {
        width: parent.width
        prefKey: "bar.pillHeight"
        label: "Высота пилюль"
        hint: "Высота элементов виджетов"
        error: root.err(prefKey)
        from: 22
        to: 40
        step: 1
        decimals: 0
        suffix: " px"
        defaultValue: root.def(prefKey)
        value: root.val(prefKey)
        onPreviewed: (k, v) => page ? page.sliderPreview(k, v) : Prefs.preview(k, v)
        onCommitted: (k, v) => page ? page.sliderCommit(k, v, 0) : SettingsCli.set({ [k]: v })
    }

    PrefSliderRow {
        width: parent.width
        prefKey: "bar.pillPadding"
        label: "Внутренний отступ пилюль"
        hint: "Горизонтальный отступ внутри виджета"
        error: root.err(prefKey)
        from: 4
        to: 24
        step: 1
        decimals: 0
        suffix: " px"
        defaultValue: root.def(prefKey)
        value: root.val(prefKey)
        onPreviewed: (k, v) => page ? page.sliderPreview(k, v) : Prefs.preview(k, v)
        onCommitted: (k, v) => page ? page.sliderCommit(k, v, 0) : SettingsCli.set({ [k]: v })
    }

    PrefSliderRow {
        width: parent.width
        prefKey: "bar.pillSpacing"
        label: "Расстояние внутри пилюль"
        hint: "Зазор между иконкой и текстом внутри виджета"
        error: root.err(prefKey)
        from: 2
        to: 16
        step: 1
        decimals: 0
        suffix: " px"
        defaultValue: root.def(prefKey)
        value: root.val(prefKey)
        onPreviewed: (k, v) => page ? page.sliderPreview(k, v) : Prefs.preview(k, v)
        onCommitted: (k, v) => page ? page.sliderCommit(k, v, 0) : SettingsCli.set({ [k]: v })
    }

    SetButton {
        text: "Сбросить панель"
        tooltip: "Положение, состав зон и размеры — по умолчанию"
        onClicked: {
            root.error = "";
            root.sent = true;
            SettingsCli.run(["reset", "bar.position", "bar.left", "bar.center", "bar.right", "bar.margin", "bar.padding", "bar.spacing", "bar.height", "bar.pillHeight", "bar.pillPadding", "bar.pillSpacing"]);
        }
    }
}
