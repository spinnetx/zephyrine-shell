.pragma library

// Разбор ответа wttr.in (?format=j1) для виджета/попапа «Погода». Чистые функции, без QML — проверяются в weather-test.js.

const THUNDER = [200, 386, 389, 392];
const SNOW = [179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 395, 350];
const RAIN = [182, 185, 281, 284, 299, 302, 305, 308, 311, 314, 317, 320, 356, 359, 362, 365, 374, 377];
const SHOWER = [176, 263, 266, 293, 296, 353];
const FOG = [143, 248, 260];

function emoji(code) {
    code = Number(code);
    if (code === 113)
        return "☀️";
    if (code === 116)
        return "⛅";
    if (code === 119 || code === 122)
        return "☁️";
    if (THUNDER.indexOf(code) >= 0)
        return "⛈️";
    if (SNOW.indexOf(code) >= 0)
        return "❄️";
    if (RAIN.indexOf(code) >= 0)
        return "🌧️";
    if (SHOWER.indexOf(code) >= 0)
        return "🌦️";
    if (FOG.indexOf(code) >= 0)
        return "🌫️";
    return "🌡️";
}

// Описание на русском, если сервис его отдал (lang=ru), иначе английское.
function desc(x) {
    if (!x)
        return "";
    if (x.lang_ru && x.lang_ru[0] && x.lang_ru[0].value)
        return x.lang_ru[0].value;
    return (x.weatherDesc && x.weatherDesc[0]) ? x.weatherDesc[0].value : "";
}

// "06:20 AM" -> "06:20", "06:20 PM" -> "18:20".
function to24(s) {
    const m = /^\s*(\d{1,2}):(\d{2})\s*([AP]M)?\s*$/i.exec(String(s || ""));
    if (!m)
        return "";
    let h = Number(m[1]);
    const ap = (m[3] || "").toUpperCase();
    if (ap === "PM" && h < 12)
        h += 12;
    if (ap === "AM" && h === 12)
        h = 0;
    return (h < 10 ? "0" : "") + h + ":" + m[2];
}

// "300" -> "03:00", "1200" -> "12:00".
function hourLabel(t) {
    const n = Number(t);
    const h = Math.floor(n / 100);
    return (h < 10 ? "0" : "") + h + ":00";
}

const DIRS = { N: "С", S: "Ю", E: "В", W: "З" };
function dirRu(d) {
    return String(d || "").split("").map(c => DIRS[c] || c).join("");
}

function sign(n) {
    n = Math.round(Number(n));
    return (n > 0 ? "+" : "") + n + "°";
}

// text -> { ok, place, current:{…}, days:[{date, maxC, minC, emoji, desc, rain, sunrise, sunset, hours:[…]}] } | { ok:false }
function parse(text) {
    let o;
    try {
        o = JSON.parse(text);
    } catch (e) {
        return { ok: false };
    }
    const c = o && o.current_condition && o.current_condition[0];
    if (!c)
        return { ok: false };
    const a = o.nearest_area && o.nearest_area[0];
    const place = a ? [a.areaName && a.areaName[0] && a.areaName[0].value, a.country && a.country[0] && a.country[0].value].filter(x => x).join(", ") : "";
    const current = {
        tempC: Number(c.temp_C),
        feelsC: Number(c.FeelsLikeC),
        humidity: Number(c.humidity),
        windMs: Math.round(Number(c.windspeedKmph) / 3.6),
        windDir: dirRu(c.winddir16Point),
        pressureMm: Math.round(Number(c.pressure) * 0.750062),
        visKm: Number(c.visibility),
        uv: Number(c.uvIndex),
        precipMm: Number(c.precipMM),
        cloud: Number(c.cloudcover),
        desc: desc(c),
        code: Number(c.weatherCode),
        emoji: emoji(c.weatherCode)
    };
    const days = (o.weather || []).slice(0, 3).map(d => {
        const hours = (d.hourly || []).map(h => ({
            time: hourLabel(h.time),
            tempC: Number(h.tempC),
            rain: Number(h.chanceofrain),
            emoji: emoji(h.weatherCode),
            desc: desc(h)
        }));
        const noon = (d.hourly || [])[4] || (d.hourly || [])[0] || {};
        const ast = d.astronomy && d.astronomy[0];
        return {
            date: d.date,
            maxC: Number(d.maxtempC),
            minC: Number(d.mintempC),
            emoji: emoji(noon.weatherCode),
            desc: desc(noon),
            rain: hours.reduce((m, h) => Math.max(m, h.rain || 0), 0),
            sunrise: ast ? to24(ast.sunrise) : "",
            sunset: ast ? to24(ast.sunset) : "",
            hours: hours
        };
    });
    return { ok: true, place: place, current: current, days: days };
}
