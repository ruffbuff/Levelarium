-- История изменений (undo/redo) без зависимости от love.*.
-- Храним не копии уровня, а дельты: для каждой изменённой клетки - старое и новое значение.
-- Одно действие (мазок от нажатия до отпускания кнопки, заливка, линия, прямоугольник) = один шаг.
--
-- Использование:
--   h:record(layers, layerIndex, x, y)  -- ПЕРЕД изменением клетки (можно вызывать много раз за действие)
--   h:commit(layers)                    -- действие закончено: кладёт его в стек undo
--   h:undo(layers) / h:redo(layers)     -- возвращают номер затронутого слоя либо nil, если нечего отменять
--   h:reset()                           -- загрузка/новый уровень/удаление слоя/смена размера холста

local history = {}
history.__index = history

local STRIDE = 2048 -- координата клетки < 2048 (максимальный холст 1000x1000)

local function encode(layer, x, y)
    return (layer * STRIDE + y) * STRIDE + x
end

local function decode(key)
    local x = key % STRIDE
    key = (key - x) / STRIDE
    local y = key % STRIDE
    return (key - y) / STRIDE, x, y
end

--- limit - сколько шагов хранить (по умолчанию 100); maxCells - потолок суммарного числа
--- изменённых клеток во всей истории (защита памяти от многократных заливок большого холста).
function history.new(limit, maxCells)
    return setmetatable({
        limit = limit or 100,
        maxCells = maxCells or 2000000,
        undoStack = {}, redoStack = {},
        cells = 0,          -- сколько клеток хранится в обоих стеках
        pending = nil,      -- действие, которое сейчас записывается
    }, history)
end

function history:reset()
    self.undoStack, self.redoStack = {}, {}
    self.cells = 0
    self.pending = nil
end

function history:canUndo() return #self.undoStack > 0 or (self.pending ~= nil and self.pending.n > 0) end
function history:canRedo() return #self.redoStack > 0 end

--- Запоминает старое значение клетки (только первое за действие). Вызывать до записи нового значения.
function history:record(layers, layer, x, y)
    local p = self.pending
    if not p then
        p = {keys = {}, old = {}, seen = {}, n = 0}
        self.pending = p
    end
    local key = encode(layer, x, y)
    if p.seen[key] then return end
    p.seen[key] = true
    p.n = p.n + 1
    p.keys[p.n] = key
    local row = layers[layer] and layers[layer][y]
    p.old[p.n] = row and row[x] or 0
end

local function setCell(layers, layer, x, y, value)
    local l = layers[layer]
    if not l then return end
    if value == 0 then
        local row = l[y]
        if row then row[x] = nil end
    else
        local row = l[y]
        if not row then row = {}; l[y] = row end
        row[x] = value
    end
end

local function trim(self)
    -- старейшие шаги выбрасываем по числу шагов и по суммарному размеру (последний шаг оставляем всегда)
    while #self.undoStack > self.limit or (self.cells > self.maxCells and #self.undoStack > 1) do
        local dropped = table.remove(self.undoStack, 1)
        self.cells = self.cells - dropped.n
    end
end

--- Завершает действие. Клетки, значение которых в итоге не изменилось, отбрасываются.
--- Возвращает true, если в историю добавлен шаг.
function history:commit(layers)
    local p = self.pending
    self.pending = nil
    if not p then return false end

    local keys, old, new, n = {}, {}, {}, 0
    for i = 1, p.n do
        local layer, x, y = decode(p.keys[i])
        local row = layers[layer] and layers[layer][y]
        local value = row and row[x] or 0
        if value ~= p.old[i] then
            n = n + 1
            keys[n], old[n], new[n] = p.keys[i], p.old[i], value
        end
    end
    if n == 0 then return false end

    -- новое действие обнуляет ветку redo
    for _, step in ipairs(self.redoStack) do self.cells = self.cells - step.n end
    self.redoStack = {}

    self.undoStack[#self.undoStack + 1] = {keys = keys, old = old, new = new, n = n}
    self.cells = self.cells + n
    trim(self)
    return true
end

local function apply(step, layers, values)
    local lastLayer
    for i = step.n, 1, -1 do
        local layer, x, y = decode(step.keys[i])
        setCell(layers, layer, x, y, values[i])
        lastLayer = layer
    end
    return lastLayer
end

function history:undo(layers)
    self:commit(layers) -- действие, которое ещё записывалось, тоже считается
    local step = table.remove(self.undoStack)
    if not step then return nil end
    self.redoStack[#self.redoStack + 1] = step
    return apply(step, layers, step.old), step.n
end

function history:redo(layers)
    self:commit(layers)
    local step = table.remove(self.redoStack)
    if not step then return nil end
    self.undoStack[#self.undoStack + 1] = step
    return apply(step, layers, step.new), step.n
end

return history
