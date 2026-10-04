.pragma library

// Логика циклического переключения рабочих столов на виджете «Рабочие столы».
// Позволяет переключаться между занятыми столами, а также переходить на следующий
// (ещё пустой) рабочий стол, не создавая лишних пустых столов при непрерывном скролле.
//
// delta < 0: скролл вниз/вправо (следующий рабочий стол)
// delta > 0: скролл вверх/влево (предыдущий рабочий стол)

function calculateNextWorkspace(activeId, delta, occupiedList, maxWsCount) {
    if (!delta)
        return activeId;

    const maxWs = (typeof maxWsCount === "number" && maxWsCount > 0) ? maxWsCount : 10;
    const cur = (typeof activeId === "number" && activeId >= 1) ? activeId : 1;

    const occupied = Array.isArray(occupiedList)
        ? occupiedList.filter(id => typeof id === "number" && id >= 1 && id <= maxWs)
        : [];

    // Максимальный номер среди занятых рабочих столов (минимум 1).
    const maxOccupied = Math.max(...(occupied.length > 0 ? occupied : [1]));

    if (delta < 0) {
        // Скролл вперед (следующий):
        // Доступны: все занятые столы + текущий активный + ОДИН следующий пустой стол
        const nextEmpty = maxOccupied < maxWs ? maxOccupied + 1 : null;
        const set = new Set([...occupied, cur]);
        if (nextEmpty !== null)
            set.add(nextEmpty);

        const list = Array.from(set).sort((a, b) => a - b);
        const idx = list.indexOf(cur);
        if (idx === -1)
            return list[0];

        // Зацикливание: после последнего элемента (включая следующий пустой) возвращаемся на первый стол
        return list[(idx + 1) % list.length];
    } else {
        // Скролл назад (предыдущий):
        // Доступны: все занятые столы + текущий активный (без забегания вперед на пустой стол)
        const list = Array.from(new Set([...occupied, cur])).sort((a, b) => a - b);
        const idx = list.indexOf(cur);
        if (idx === -1)
            return list[list.length - 1];

        // Зацикливание назад: если мы на первом элементе — переходим на последний занятый
        return idx > 0 ? list[idx - 1] : list[list.length - 1];
    }
}
