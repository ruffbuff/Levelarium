-- Список с выбором и прокруткой (логика без отрисовки и без love.*).
local List = {}
List.__index = List

-- allowNone: выбор может быть пустым (selected = 0), например в диалоге сохранения
function List.new(rows, allowNone)
    return setmetatable({items = {}, selected = 0, top = 0, rows = rows or 10, allowNone = allowNone or false}, List)
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function List:maxTop()
    return math.max(0, #self.items - self.rows)
end

function List:setItems(items, selected)
    self.items = items
    self.top = 0
    self:select(selected or (#items > 0 and 1 or 0))
end

function List:select(i)
    if #self.items == 0 then
        self.selected, self.top = 0, 0
        return
    end
    self.selected = clamp(i, self.allowNone and 0 or 1, #self.items)
    if self.selected >= 1 then
        if self.selected <= self.top then self.top = self.selected - 1 end
        if self.selected > self.top + self.rows then self.top = self.selected - self.rows end
    end
    self.top = clamp(self.top, 0, self:maxTop())
end

function List:move(delta) self:select(self.selected + delta) end
function List:page(dir) self:select(math.max(1, self.selected) + dir * self.rows) end
function List:home() self:select(1) end
function List:last() self:select(#self.items) end

-- колесо мыши: dy > 0 - вверх; выбор не меняется
function List:scroll(dy)
    self.top = clamp(self.top - dy * 3, 0, self:maxTop())
end

-- индекс элемента по смещению от верха списка в пикселях или nil
function List:rowAt(relY, rowH)
    if relY < 0 then return nil end
    local row = math.floor(relY / rowH)
    if row >= self.rows then return nil end
    local index = self.top + row + 1
    return index <= #self.items and index or nil
end

function List:current() return self.items[self.selected] end

return List
