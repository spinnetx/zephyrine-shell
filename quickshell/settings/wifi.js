// Разбор вывода nmcli для страницы Wi-Fi окна настроек. Чистый JS без зависимостей от Quickshell —
// проверяется отдельно через node (settings/wifi-test.js). Весь вывод nmcli снимается с LC_ALL=C.
.pragma library

// Разбор строки `nmcli -t`: поля разделены ':', двоеточие внутри значения экранировано '\:'.
function splitTerse(line) {
    const out = [];
    let cur = "";
    for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (c === "\\" && i + 1 < line.length) {
            cur += line[i + 1];
            i++;
        } else if (c === ":") {
            out.push(cur);
            cur = "";
        } else {
            cur += c;
        }
    }
    out.push(cur);
    return out;
}

// Диапазон по частоте в МГц.
function bandOf(mhz) {
    if (!(mhz > 0))
        return "";
    return mhz < 3000 ? "2.4 ГГц" : mhz < 5925 ? "5 ГГц" : "6 ГГц";
}

// Вывод `nmcli -t -f GENERAL.HWADDR,...,IP4.DNS device show <dev>`: «КЛЮЧ[n]:значение» (значение — после
// ПЕРВОГО двоеточия, MAC в нём не экранирован). Возвращает { mac, state, connection, ip4: [], gateway, dns: [], ip6: [] }.
function parseDeviceShow(text) {
    const r = { mac: "", state: "", connection: "", ip4: [], gateway: "", dns: [], ip6: [] };
    for (const line of text.split("\n")) {
        const i = line.indexOf(":");
        if (i < 0)
            continue;
        const key = line.slice(0, i).replace(/\[\d+\]$/, "");
        const val = line.slice(i + 1).trim();
        if (val === "" || val === "--")
            continue;
        if (key === "GENERAL.HWADDR")
            r.mac = val;
        else if (key === "GENERAL.STATE")
            r.state = val;
        else if (key === "GENERAL.CONNECTION")
            r.connection = val;
        else if (key === "IP4.ADDRESS")
            r.ip4.push(val);
        else if (key === "IP4.GATEWAY")
            r.gateway = val;
        else if (key === "IP4.DNS")
            r.dns.push(val);
        else if (key === "IP6.ADDRESS")
            r.ip6.push(val);
    }
    return r;
}

// Строки `nmcli -t -f IN-USE,SSID,SIGNAL,FREQ,CHAN,RATE,SECURITY,BSSID device wifi list`: возвращает данные
// активной точки { ssid, signal, freq, band, chan, rate, security, bssid } или null.
function parseActiveAp(text) {
    for (const line of text.split("\n")) {
        if (line === "")
            continue;
        const f = splitTerse(line);
        if (f.length < 8 || f[0] !== "*")
            continue;
        const freq = parseInt(f[3]) || 0;
        return {
            ssid: f[1],
            signal: Number(f[2]) || 0,
            freq: freq,
            band: bandOf(freq),
            chan: f[4],
            rate: f[5],
            security: (f[6] === "" || f[6] === "--") ? "" : f[6],
            bssid: f[7]
        };
    }
    return null;
}

// Строки `nmcli -t -f NAME,UUID,TYPE,AUTOCONNECT,ACTIVE connection show`: только Wi-Fi профили,
// активные первыми, дальше по имени. [{ name, uuid, autoconnect, active }]
function parseSaved(text) {
    const out = [];
    for (const line of text.split("\n")) {
        if (line === "")
            continue;
        const f = splitTerse(line);
        if (f.length < 5 || f[2] !== "802-11-wireless")
            continue;
        out.push({ name: f[0], uuid: f[1], autoconnect: f[3] === "yes", active: f[4] === "yes" });
    }
    out.sort((a, b) => (b.active - a.active) || a.name.localeCompare(b.name));
    return out;
}

// «172.20.10.2/28» → «172.20.10.2»
function stripPrefix(addr) {
    const i = addr.indexOf("/");
    return i < 0 ? addr : addr.slice(0, i);
}

// Иконка-уровень по сигналу: 1..4.
function signalLevel(s) {
    return s > 75 ? 4 : s > 50 ? 3 : s > 25 ? 2 : 1;
}
