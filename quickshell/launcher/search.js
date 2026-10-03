// Поиск и ранжирование приложений лаунчера. Чистый JS без зависимостей от Quickshell —
// поэтому проверяется отдельно через node (см. launcher/search-test.js).
//
// Элемент индекса (plain-объект): { id, name, enName, genericName, comment, keywords: [], exec }
//   name   — отображаемое (возможно локализованное) имя;
//   enName — английское `Name=` из .desktop (Quickshell отдаёт локализованное, английское берём из файла);
//   exec   — имя исполняемого файла (basename первого слова команды).
// История: { "<id>": { count, last } } — last в мс.
.pragma library

function norm(s) {
    return (s || "").toString().toLowerCase().replace(/ё/g, "е");
}

// Разделители слов: пробелы и типичная пунктуация (\p{L} в QML-движке не используем).
function words(s) {
    return s.split(/[\s\-_.()\/,:;+]+/).filter(w => w.length > 0);
}

// Совпадение подпоследовательностью: возвращает штраф разрыва (меньше — лучше) или -1.
function subseq(hay, needle) {
    if (needle.length < 2)
        return -1;
    let pos = 0;
    let gaps = 0;
    let last = -1;
    for (let i = 0; i < needle.length; i++) {
        const f = hay.indexOf(needle[i], pos);
        if (f < 0)
            return -1;
        if (last >= 0)
            gaps += f - last - 1;
        last = f;
        pos = f + 1;
    }
    return gaps;
}

// Оценка одного токена по одному «имени»: точное > префикс > префикс слова > подстрока.
function nameScore(h, t) {
    if (!h)
        return 0;
    if (h === t)
        return 1000;
    if (h.startsWith(t))
        return 900;
    if (words(h).some(w => w.startsWith(t)))
        return 700;
    if (h.indexOf(t) >= 0)
        return 500;
    return 0;
}

// Оценка токена по полям, не являющимся именем (id, keywords, genericName, exec, comment).
function tokenScore(f, t) {
    let best = 0;
    // Имя (любое из двух) — самый высокий приоритет.
    best = Math.max(nameScore(f.name, t), nameScore(f.enName, t));
    // id: «virt-manager», «org.kde.kate» — точное/префикс/слово/подстрока.
    if (f.id === t)
        best = Math.max(best, 920); // точный id («thunar») важнее слова в имени других программ
    else if (f.id.startsWith(t))
        best = Math.max(best, 600);
    else if (words(f.id).some(w => w.startsWith(t)))
        best = Math.max(best, 450);
    else if (f.id.indexOf(t) >= 0)
        best = Math.max(best, 350);
    // Исполняемая команда.
    if (f.exec === t)
        best = Math.max(best, 550);
    else if (f.exec.startsWith(t))
        best = Math.max(best, 400);
    // keywords.
    for (const k of f.keywords) {
        if (k === t)
            best = Math.max(best, 420);
        else if (k.startsWith(t))
            best = Math.max(best, 380);
        else if (words(k).some(w => w.startsWith(t)))
            best = Math.max(best, 330);
    }
    // genericName.
    best = Math.max(best, nameScore(f.genericName, t) > 0 ? 250 + nameScore(f.genericName, t) / 20 : 0);
    // comment — самое слабое.
    if (f.comment) {
        if (words(f.comment).some(w => w.startsWith(t)))
            best = Math.max(best, 150);
        else if (f.comment.indexOf(t) >= 0)
            best = Math.max(best, 100);
    }
    return best;
}

// Нормализованные поля элемента (считается один раз на элемент).
function prepare(it) {
    return {
        id: norm(it.id).replace(/\.desktop$/, ""),
        name: norm(it.name),
        enName: norm(it.enName),
        genericName: norm(it.genericName),
        comment: norm(it.comment),
        keywords: (it.keywords || []).map(norm),
        exec: norm(it.exec)
    };
}

// «Частотность с затуханием»: число запусков, вес каждого падает вдвое за 14 дней.
function frecency(h, now) {
    if (!h)
        return 0;
    const days = Math.max(0, (now - (h.last || 0)) / 86400000);
    return (h.count || 0) * Math.pow(0.5, days / 14);
}

// Главная функция. items — индекс (с уже подготовленными полями .f, если есть), query — строка,
// history — объект, now — Date.now(). Возвращает массив элементов, лучшие первыми (не более limit).
function rank(items, query, history, now, limit) {
    const q = norm(query).trim();
    const tokens = words(q);
    const hist = history || {};
    const res = [];

    for (const it of items) {
        const f = it.f || prepare(it);
        const fr = frecency(hist[it.id], now);
        if (tokens.length === 0) {
            res.push({ it: it, score: fr });
            continue;
        }
        // Все токены должны найтись; счёт — сумма по токенам (усреднённая, чтобы число слов не завышало).
        let sum = 0;
        let ok = true;
        for (const t of tokens) {
            const s = tokenScore(f, t);
            if (s <= 0) {
                ok = false;
                break;
            }
            sum += s;
        }
        let score = ok ? sum / tokens.length : 0;
        if (!ok) {
            // Запасной вариант: нечёткий поиск подпоследовательностью по имени/id/исполняемому файлу.
            const flat = tokens.join("");
            let best = -1;
            for (const h of [f.name, f.enName, f.id, f.exec]) {
                const g = subseq(h, flat);
                if (g >= 0 && g <= flat.length && (best < 0 || g < best))
                    best = g;
            }
            if (best >= 0)
                score = Math.max(1, 60 - best);
        }
        if (score <= 0)
            continue;
        // История — небольшая добавка к счёту (не перебивает более точное совпадение имени).
        res.push({ it: it, score: score + Math.min(fr, 10) * 4 });
    }

    res.sort((a, b) => {
        if (b.score !== a.score)
            return b.score - a.score;
        // При равенстве — короткое имя выше (обычно это «сама» программа), затем по алфавиту.
        // При пустом запросе (нет истории) — просто алфавит.
        const la = tokens.length ? (a.it.name || "").length : 0, lb = tokens.length ? (b.it.name || "").length : 0;
        return la !== lb ? la - lb : (a.it.name || "").localeCompare(b.it.name || "");
    });
    return res.slice(0, limit || 50).map(r => r.it);
}

// Запись запуска в историю (возвращает НОВЫЙ объект — удобно для присваивания QML-свойству).
function bump(history, id, now) {
    const h = Object.assign({}, history || {});
    const old = h[id] || { count: 0, last: 0 };
    h[id] = { count: old.count + 1, last: now };
    return h;
}
