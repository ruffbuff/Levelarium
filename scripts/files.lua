-- Чистая логика списка файлов уровней (без зависимостей от love.*).
local files = {}

-- "level one.txt" -> "level one", "txt"; nil, если у файла нет расширения
function files.splitName(filename)
    local name, ext = filename:match("^(.+)%.([^%.]+)$")
    if not name then return nil end
    return name, ext:lower()
end

-- Имя уровня из поля ввода: без пробелов по краям, только буквы/цифры/пробел/_/-.
-- Возвращает nil, если имя пустое, содержит недопустимые символы или совпадает с именем устройства Windows.
function files.cleanName(s)
    s = (s or ""):match("^%s*(.-)%s*$")
    if s == "" or #s > 64 or not s:match("^[%w%s_%-]+$") then return nil end
    -- имена устройств Windows (CON, NUL, COM1...) нельзя использовать как файлы
    local base = s:upper()
    if base == "CON" or base == "PRN" or base == "AUX" or base == "NUL"
        or base:match("^COM%d$") or base:match("^LPT%d$") then
        return nil
    end
    return s
end

-- entries: {{name=, ext=, size=, modtime=}, ...}. mode: "date" (новые сверху) или "name" (А-Я без учёта регистра).
-- Сортирует на месте, порядок всегда стабилен (при равенстве - по имени, затем по расширению).
function files.sortEntries(entries, mode)
    table.sort(entries, function(a, b)
        if mode == "date" and (a.modtime or 0) ~= (b.modtime or 0) then
            return (a.modtime or 0) > (b.modtime or 0)
        end
        local la, lb = a.name:lower(), b.name:lower()
        if la ~= lb then return la < lb end
        if a.name ~= b.name then return a.name < b.name end
        return (a.ext or "") < (b.ext or "")
    end)
    return entries
end

function files.formatSize(bytes)
    if type(bytes) ~= "number" then return "-" end
    if bytes < 1024 then return ("%d B"):format(bytes) end
    if bytes < 1024 * 1024 then return ("%.1f KB"):format(bytes / 1024) end
    return ("%.1f MB"):format(bytes / 1024 / 1024)
end

function files.formatDate(t)
    if type(t) ~= "number" then return "-" end
    return os.date("%Y-%m-%d %H:%M", t)
end

-- Есть ли в списке уровень с таким именем (без учёта регистра: на Windows/macOS файлы так и работают)
function files.exists(entries, name)
    local lname = name:lower()
    for _, e in ipairs(entries) do
        if e.name:lower() == lname then return true, e end
    end
    return false
end

return files
