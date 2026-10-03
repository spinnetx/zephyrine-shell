// Прозрачность Zen Browser на Linux/Wayland — через официальный мод
// "Transparent Zen" (github.com/sameerasw/zen-themes, id
// 642854b5-88b4-4c40-b256-e035532109df), установленный в самом Zen
// (Settings → Mods). Мод уже стоит и включён (проверено —
// ~/.config/zen/<профиль>/zen-themes.json содержит "enabled": true) —
// весь его функционал управляется обычными Firefox-префами (см. его
// preferences.json), поэтому настраивается здесь, без UI.
//
// Профильный каталог (~/.config/zen/<hash>.Default*) на каждой машине свой,
// поэтому этот файл нельзя симлинкнуть, как остальной конфиг — копируется
// вручную (или через ../deploy.sh, он сам находит активный профиль).
// Активный профиль — в ~/.config/zen/installs.ini (ключ Default в секции
// [<InstallID>], а не profiles.ini — там может быть устаревшая отметка).
//
// Известная проблема (issue #6729 в zen-browser/desktop): базовая
// прозрачность (первые два префа) на Linux периодически ломается апстримом
// между релизами Zen — если после обновления браузера прозрачность пропала,
// это не связано с нашим конфигом.

// Два обязательных общих флага (preferences.json самого мода перечисляет их
// как то, что нужно включить ДО его собственных настроек):
user_pref("browser.tabs.allow_transparent_browser", true);
user_pref("zen.widget.linux.transparency", true);

// Настройки самого мода "Transparent Zen":
//
// Свой цвет фона вместо стандартного (почти полностью прозрачного) —
// он и мешал читать вкладки. Формат — 8-значный hex RRGGBBAA (не rgba()!),
// значение по умолчанию у мода #00000000. Взят тот же тон и альфа, что у
// остальных стеклянных окон в этой сборке (kitty 0.80, GTK 0.85) —
// #141414 = rgb(20,20,20), D9 = 0.85 альфы.
user_pref("mod.sameerasw.zen_bg_color_enabled", true);
user_pref("mod.sameerasw.zen_transparency_color", "#141414E0");

// По умолчанию мод делает боковую панель (закладки/история/синхронизация)
// ПОЛНОСТЬЮ прозрачной независимо от заданного выше цвета — выключаем, чтобы
// сайдбар тоже был читаемым, а не поверх произвольного фона рабочего стола.
user_pref("mod.sameerasw.zen_transparent_sidebar_enabled", false);

// Мод отдельно (независимо от префов выше) красит именно область самой
// страницы (.browserStack > browser) через "tab tint" — по умолчанию
// mod.sameerasw_zen_light_tint = "2" ("Remove"), то есть background-color:
// transparent !important. На части сайтов, где страница сама не закрашивает
// весь вьюпорт, из-под неё было видно рабочий стол — текст было не прочитать.
// В UI мода (Settings -> Mods) у этого выбора всего два значения: "1" (Flip —
// лёгкий тон 10% альфы, всё равно почти прозрачно) и "2" (Remove — полностью
// прозрачно). Оба варианта в CSS мода (zen-themes.css) заданы через
// :root:has([mod-sameerasw_zen_light_tint="1"|"2"]) — значение "0" ни под одно
// условие не подпадает, поэтому мод просто не трогает фон страницы, и
// остаётся обычный непрозрачный фон браузера. Остальная прозрачность (тулбар,
// цвет из zen_transparency_color выше) не затронута — это единственное,
// точечное правило мода.
user_pref("mod.sameerasw_zen_light_tint", "0");

// Нужен для userChrome.css/userContent.css (стиль Zephyrine: палитра, стекло 0.88) —
// без него Zen/Firefox их игнорирует целиком. Мод Transparent Zen при этом выключен
// в профиле; прозрачность окна даёт userChrome.css (--zen-main-browser-background).
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Тёмная встроенная тема (в профиле стояла compact-light — на тёмном стекле нечитаемо)
user_pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.theme.content-theme", 0);
