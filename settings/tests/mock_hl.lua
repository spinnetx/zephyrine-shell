-- Мок Lua-API Hyprland для проверки конфигов без компоситора (DESIGN §8, S1.8).
--
-- Запуск:  lua mock_hl.lua [--plugin] [--set key=value ...] файл.lua [файл2.lua ...]
--   --plugin   создать hl.plugin.hyprglass (как после загрузки плагина); без флага плагина нет
--   файлы      выполняются по порядку в одном окружении (как dofile из hyprland.lua)
-- Результат - ОДНА строка JSON на stdout (ключи отсортированы, вывод детерминирован):
--   { "calls":  [ {"fn": "config", "args": [...]}, ... ],   -- каждый вызов hl.*(...), включая вложенные (dsp.exec_cmd)
--     "config": { "decoration.rounding": 10, ... },         -- плоское состояние hl.config и plugin.hyprglass.config
--     "errors": [ "файл: текст" ] }                          -- ошибки выполнения файлов (рантайм/синтаксис)
-- Мок хранит значения как переданы (строки цветов не переводятся в числа), hl.config сливает
-- таблицы по ключам (как делает Hyprland: частичный вызов не трогает остальные ключи - это ПРЕДПОЛОЖЕНИЕ мока,
-- в живом компоситоре проверяется отдельно). Любой другой hl.* - запоминающая заглушка.
-- Состояние живого Hyprland мок не читает и не меняет.

local calls, config, errors = {}, {}, {}
local plugin_enabled = false
local presets = {}

for i = 1, #arg do
    if arg[i] == "--plugin" then plugin_enabled = true end
end

-- ----------------------------------------------------------------- JSON
local function esc(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return m[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function is_array(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

local function enc(v)
    local ty = type(v)
    if ty == "nil" then return "null" end
    if ty == "boolean" then return tostring(v) end
    if ty == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if math.type(v) == "integer" or v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.14g", v)
    end
    if ty == "string" then return esc(v) end
    if ty == "table" then
        if getmetatable(v) and getmetatable(v).__zs_proxy then return esc("<" .. getmetatable(v).__zs_path .. ">") end
        if is_array(v) then
            local o = {}
            for i = 1, #v do o[i] = enc(v[i]) end
            return "[" .. table.concat(o, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local o = {}
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            o[#o + 1] = esc(k) .. ":" .. enc(val)
        end
        return "{" .. table.concat(o, ",") .. "}"
    end
    return esc("<" .. ty .. ">")
end

-- ----------------------------------------------------------------- состояние
local function copy(v)
    if type(v) ~= "table" then return v end
    local mt = getmetatable(v)
    if mt and mt.__zs_proxy then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = copy(x) end
    return o
end

local function is_leaf_table(t)
    -- {colors = {...}, angle = N} (значение градиента) и списки - листья, не ветки
    return type(t) == "table" and (t.colors ~= nil or #t > 0)
end

local function merge(prefix, tbl)
    for k, v in pairs(tbl) do
        local key = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
        if type(v) == "table" and not is_leaf_table(v) then
            merge(key, v)
        else
            config[key] = copy(v)
        end
    end
end

-- ----------------------------------------------------------------- заглушки
local function make_proxy(path)
    local p = {}
    return setmetatable(p, {
        __zs_proxy = true,
        __zs_path = path,
        __index = function(_, k)
            if type(k) ~= "string" then return nil end
            return make_proxy(path .. "." .. k)
        end,
        __call = function(_, ...)
            local args = { ... }
            calls[#calls + 1] = { fn = path, args = copy(args) }
            return make_proxy(path .. "()")
        end,
    })
end

local hl = {}
setmetatable(hl, {
    __index = function(t, k)
        if type(k) ~= "string" then return nil end
        local p = make_proxy(k)
        rawset(t, k, p)
        return p
    end,
})

hl.config = function(tbl)
    calls[#calls + 1] = { fn = "config", args = { copy(tbl) } }
    merge("", tbl)
end

hl.get_config = function(key)
    return config[key]
end

hl.notification = {
    create = function(opts)
        calls[#calls + 1] = { fn = "notification.create", args = { copy(opts) } }
        return make_proxy("notification")
    end,
}

if plugin_enabled then
    hl.plugin = {
        hyprglass = {
            config = function(tbl)
                calls[#calls + 1] = { fn = "plugin.hyprglass.config", args = { copy(tbl) } }
                merge("plugin.hyprglass", tbl)
            end,
        },
    }
else
    hl.plugin = {}
end

_G.hl = hl

-- ----------------------------------------------------------------- запуск файлов
local nfiles = 0
local skip = false
for i = 1, #arg do
    local a = arg[i]
    if a == "--plugin" then
        -- уже учтён
    elseif a == "--set" then
        skip = true -- резерв: --set key=value (предзадать значение до запуска файлов)
    elseif skip then
        local k, v = a:match("^([^=]+)=(.*)$")
        if k then config[k] = tonumber(v) or v end
        skip = false
    else
        nfiles = nfiles + 1
        local fn, err = loadfile(a)
        if not fn then
            errors[#errors + 1] = a .. ": " .. tostring(err)
        else
            local ok, e = pcall(fn)
            if not ok then errors[#errors + 1] = a .. ": " .. tostring(e) end
        end
    end
end

io.write(enc({ calls = calls, config = config, errors = errors }), "\n")
