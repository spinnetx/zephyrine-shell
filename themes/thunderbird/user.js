// Прозрачность интерфейса Thunderbird — не через Hyprland window-rule, а
// нативно, тем же способом, что в проекте thunderblurred
// (github.com/eromatiya/thunderblurred, форк github.com/manilarome/thunderblurred):
// userChrome.css поверх нескольких обязательных префов, без которых альфа-канал
// в CSS ничего не даёт — Thunderbird просто рисует непрозрачный фон поверх.
//
// Профильный каталог (~/.config/thunderbird/<hash>.default-release) на каждой
// машине свой — этот файл нельзя симлинкнуть, копируется вручную (или через
// ../deploy.sh, он сам находит активный профиль через installs.ini).
//
// Встроенная тема Dark включается префом ниже (без неё светлая/системная тема
// перекрывает прозрачность непрозрачным фоном — подтверждено в README thunderblurred).

user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("layers.acceleration.force-enabled", true);
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.enabled", true);
user_pref("svg.context-properties.content.enabled", true);
user_pref("extensions.activeThemeID", "zephyrine-theme@zephyrine");
// Тема кладётся в extensions/ вручную (sideload) — без этого Thunderbird её не включит.
user_pref("extensions.autoDisableScopes", 0);
