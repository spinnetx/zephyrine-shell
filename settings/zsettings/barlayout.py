"""Раскладка панели (DESIGN §4.5, Y8): положение `bar.position` и состав зон `bar.left` / `bar.center` / `bar.right`.

Эти ключи читает сам шелл (Prefs.qml) из settings.json, целей генератора у них нет. Каталог элементов дублируется в
quickshell/Bar.qml (реестр компонентов) и quickshell/settings/parts/BarCard.qml (подписи) - править во всех трёх местах.
"""
import re

# id, подпись, есть ли вариант для вертикальной панели
ITEMS = (
    ("workspaces", "Рабочие столы", True),
    ("activeWindow", "Заголовок окна", False),
    ("media", "Медиа", False),
    ("limits", "Лимиты ИИ", False),
    ("disk", "Диски", False),
    ("gpu", "Видеокарта", True),
    ("cpu", "Процессор", True),
    ("mem", "Память", True),
    ("net", "Сеть (скорость)", True),
    ("tray", "Трей", True),
    ("status", "Статус-иконки", True),
    ("clock", "Часы и календарь", True),
    ("power", "Кнопка питания", True),
    ("temp", "Температура", True),
    ("battery", "Батарея (с процентом)", True),
    ("kbd", "Раскладка клавиатуры", True),
    ("timer", "Таймер", True),
    ("weather", "Погода", True),
    ("volume", "Громкость", True),
    ("wifi", "Wi-Fi / сеть", True),
    ("bluetooth", "Bluetooth", True),
    ("apps", "Меню приложений", True),
)
# Не входят в зоны по умолчанию: добавляются через редактор панели («Добавить на панель»).
DEFAULT_HIDDEN = ("temp", "battery", "kbd", "timer", "weather", "volume", "wifi", "bluetooth", "apps")
IDS = tuple(i[0] for i in ITEMS)
ZONES = ("bar.left", "bar.center", "bar.right")
POSITIONS = ("top", "bottom", "left", "right")


CITY_BAD = re.compile(r"[\x00-\x1f/?#&%\\]")


def check_values(schema, flat, changed):
    """Известные id, ни одного элемента в двух зонах сразу, безопасный город для погоды -> [{"key", "error"}]."""
    errors = []
    if "weather.city" in changed:
        city = flat["weather.city"] if "weather.city" in flat else schema.default("weather.city")
        if len(city) > 60 or CITY_BAD.search(city):
            errors.append({"key": "weather.city", "error": "invalid city name"})
    if not any(k in changed for k in ZONES):
        return errors
    get = lambda k: flat[k] if k in flat else schema.default(k)  # noqa: E731
    seen = {}
    for z in ZONES:
        for i in get(z):
            if i not in IDS:
                errors.append({"key": z, "error": "unknown bar item: %s" % i})
            elif i in seen:
                other = seen[i]
                errors.append({"key": z if z in changed else other,
                               "error": "bar item %s is in two zones (%s and %s)" % (i, other, z)})
            else:
                seen[i] = z
    return errors
