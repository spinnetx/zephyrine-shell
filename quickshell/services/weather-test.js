// node quickshell/services/weather-test.js — проверка разбора ответа wttr.in (j1) без QML.
const fs = require("fs");
const vm = require("vm");
const src = fs.readFileSync(__dirname + "/weather.js", "utf8").replace(/^\.pragma library/m, "");
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src + "\nthis.W = { emoji, desc, to24, hourLabel, dirRu, sign, parse };", ctx);
const W = ctx.W;
let fails = 0;
function eq(a, b, m) {
    if (JSON.stringify(a) !== JSON.stringify(b)) {
        console.error("FAIL", m, JSON.stringify(a), "!==", JSON.stringify(b));
        fails++;
    }
}

eq(W.emoji(113), "☀️", "sunny"); eq(W.emoji(116), "⛅", "partly"); eq(W.emoji(122), "☁️", "overcast");
eq(W.emoji(302), "🌧️", "rain"); eq(W.emoji(353), "🌦️", "shower"); eq(W.emoji(338), "❄️", "snow");
eq(W.emoji(389), "⛈️", "thunder"); eq(W.emoji(248), "🌫️", "fog"); eq(W.emoji(99999), "🌡️", "unknown");
eq(W.to24("06:20 AM"), "06:20", "am"); eq(W.to24("06:05 PM"), "18:05", "pm"); eq(W.to24("12:10 AM"), "00:10", "midnight");
eq(W.to24("garbage"), "", "bad time");
eq(W.hourLabel("0"), "00:00", "h0"); eq(W.hourLabel("300"), "03:00", "h3"); eq(W.hourLabel("1500"), "15:00", "h15");
eq(W.dirRu("NNW"), "ССЗ", "dir"); eq(W.sign(5.4), "+5°", "sign+"); eq(W.sign(-3), "-3°", "sign-"); eq(W.sign(0), "0°", "sign0");
eq(W.parse("not json").ok, false, "bad json"); eq(W.parse("{}").ok, false, "no current");

const sample = {
    current_condition: [{ temp_C: "12", FeelsLikeC: "10", humidity: "65", windspeedKmph: "18", winddir16Point: "NNW", pressure: "1010",
        visibility: "10", uvIndex: "3", precipMM: "0.2", cloudcover: "40", weatherCode: "116",
        weatherDesc: [{ value: "Partly cloudy" }], lang_ru: [{ value: "Переменная облачность" }] }],
    nearest_area: [{ areaName: [{ value: "Krakow" }], country: [{ value: "Poland" }] }],
    weather: [1, 2, 3, 4].map(i => ({ date: "2026-10-0" + i, maxtempC: String(10 + i), mintempC: String(2 + i),
        astronomy: [{ sunrise: "06:20 AM", sunset: "06:05 PM" }],
        hourly: [0, 300, 600, 900, 1200, 1500, 1800, 2100].map(t => ({ time: String(t), tempC: String(5 + t / 300), chanceofrain: String(t / 100),
            weatherCode: "113", weatherDesc: [{ value: "Sunny" }] })) }))
};
const r = W.parse(JSON.stringify(sample));
eq(r.ok, true, "ok"); eq(r.place, "Krakow, Poland", "place");
eq(r.current.tempC, 12, "temp"); eq(r.current.windMs, 5, "wind m/s"); eq(r.current.windDir, "ССЗ", "wind dir");
eq(r.current.pressureMm, 758, "pressure"); eq(r.current.desc, "Переменная облачность", "ru desc"); eq(r.current.emoji, "⛅", "cur emoji");
eq(r.days.length, 3, "3 days"); eq(r.days[0].maxC, 11, "max"); eq(r.days[0].sunset, "18:05", "sunset");
eq(r.days[0].hours.length, 8, "hours"); eq(r.days[0].hours[4].time, "12:00", "noon"); eq(r.days[0].rain, 21, "max rain");
eq(r.days[0].desc, "Sunny", "fallback desc"); eq(r.days[0].emoji, "☀️", "day emoji");

if (fails) {
    console.error(fails + " failed");
    process.exit(1);
}
console.log("weather-test.js: all tests passed!");
