-- Безопасная запись файлов (без зависимости от love.*).
-- Данные пишутся во временный файл рядом, и только после успешной записи он переименовывается
-- в целевой: если что-то пошло не так, старая версия файла остаётся нетронутой.

local fileio = {}

local defaults = {open = io.open, rename = os.rename, remove = os.remove}

local function ops(custom)
    if not custom then return defaults end
    return {
        open = custom.open or defaults.open,
        rename = custom.rename or defaults.rename,
        remove = custom.remove or defaults.remove,
    }
end

--- Атомарно записывает data в path. Возвращает true  или  false, "причина".
--- custom (необязательно) подменяет open/rename/remove - так проверяются ошибки в тестах.
function fileio.atomicWrite(path, data, custom)
    local io_ = ops(custom)
    local tmp = path .. ".tmp"

    local file, err = io_.open(tmp, "wb")
    if not file then return false, "cannot create " .. tmp .. " (" .. tostring(err) .. ")" end

    local okWrite, werr = file:write(data)
    local okClose, cerr = file:close()
    if not okWrite or not okClose then
        io_.remove(tmp)
        return false, "write failed (" .. tostring(werr or cerr) .. ")"
    end

    if io_.rename(tmp, path) then return true end

    -- На Windows rename не заменяет существующий файл: переносим старый в .bak, ставим новый,
    -- при неудаче возвращаем старый обратно.
    local bak = path .. ".bak"
    io_.remove(bak)
    local hadOld = io_.rename(path, bak)
    if hadOld then
        if io_.rename(tmp, path) then
            io_.remove(bak)
            return true
        end
        io_.rename(bak, path)
    end
    io_.remove(tmp)
    return false, "cannot replace " .. path
end

return fileio
