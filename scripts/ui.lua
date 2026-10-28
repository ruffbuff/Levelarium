-- Общий внешний вид: палитра, шрифты, панели, кнопки, уведомления (тосты).
local ui = {}

ui.c = {
    bg      = {0.09, 0.10, 0.13},
    panel   = {0.15, 0.16, 0.20},
    panel2  = {0.20, 0.22, 0.27},
    border  = {0.30, 0.33, 0.40},
    text    = {0.91, 0.93, 0.96},
    dim     = {0.62, 0.66, 0.73},
    accent  = {0.33, 0.60, 1.00},
    onAccent = {0.05, 0.08, 0.14},
    ok      = {0.30, 0.78, 0.46},
    warn    = {1.00, 0.76, 0.28},
    err     = {0.93, 0.36, 0.36},
}

ui.f = {}

function ui.load()
    ui.f.title = love.graphics.newFont(46)
    ui.f.h     = love.graphics.newFont(22)
    ui.f.body  = love.graphics.newFont(16)
    ui.f.small = love.graphics.newFont(13)
    love.graphics.setBackgroundColor(ui.c.bg)
end

function ui.color(name, alpha)
    local c = ui.c[name]
    love.graphics.setColor(c[1], c[2], c[3], alpha or 1)
end

function ui.hit(px, py, x, y, w, h)
    return px >= x and px < x + w and py >= y and py < y + h
end

-- text(строка, шрифт, цвет, x, y [, ширина, выравнивание])
function ui.text(str, font, color, x, y, w, align)
    love.graphics.setFont(ui.f[font])
    ui.color(color)
    if w then
        love.graphics.printf(str, x, y, w, align or "left")
    else
        love.graphics.print(str, x, y)
    end
end

function ui.dim(alpha)
    love.graphics.setColor(0, 0, 0, alpha or 0.6)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
end

function ui.panel(x, y, w, h, fill)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x + 4, y + 6, w, h, 8, 8)
    ui.color(fill or "panel")
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    ui.color("border")
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 8, 8)
end

-- Кнопка/пункт меню: active - выделенный пункт
function ui.button(label, x, y, w, h, active, font, sub)
    if active then
        ui.color("accent")
        love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    else
        ui.color("panel")
        love.graphics.rectangle("fill", x, y, w, h, 8, 8)
        ui.color("border")
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 8, 8)
    end
    local f = ui.f[font or "h"]
    love.graphics.setFont(f)
    local textColor = active and "onAccent" or "text"
    if sub then
        ui.text(label, font or "h", textColor, x + 18, y + (h - f:getHeight()) / 2 - 8)
        ui.text(sub, "small", active and "onAccent" or "dim", x + 18, y + h / 2 + 6)
    else
        ui.text(label, font or "h", textColor, x, y + (h - f:getHeight()) / 2, w, "center")
    end
end

-- Список с прокруткой (см. scripts/list.lua). drawRow(item, index, x, y, w, h, selected)
function ui.drawList(list, x, y, w, rowH, drawRow, isSelected)
    local h = list.rows * rowH
    love.graphics.setScissor(x, y, w, h)
    for row = 0, list.rows - 1 do
        local index = list.top + row + 1
        local item = list.items[index]
        if not item then break end
        local ry = y + row * rowH
        local selected = isSelected and isSelected(item, index) or (index == list.selected)
        if selected then
            ui.color("accent", 0.9)
            love.graphics.rectangle("fill", x, ry, w - 12, rowH - 2, 5, 5)
        elseif row % 2 == 1 then
            ui.color("panel2", 0.45)
            love.graphics.rectangle("fill", x, ry, w - 12, rowH - 2, 5, 5)
        end
        drawRow(item, index, x, ry, w - 12, rowH - 2, selected)
    end
    love.graphics.setScissor()
    if #list.items > list.rows then
        local trackH = h
        local barH = math.max(24, trackH * list.rows / #list.items)
        local barY = y + (trackH - barH) * (list.top / list:maxTop())
        ui.color("border", 0.6)
        love.graphics.rectangle("fill", x + w - 8, y, 6, trackH, 3, 3)
        ui.color("dim")
        love.graphics.rectangle("fill", x + w - 8, barY, 6, barH, 3, 3)
    end
end

-- ------------------------------------------------------------------ тосты
local toasts = {}

function ui.toast(message, kind, seconds)
    toasts = {{message = message, kind = kind or "info", left = seconds or 2.8}}  -- один тост, новый заменяет старый
end

function ui.update(dt)
    for i = #toasts, 1, -1 do
        toasts[i].left = toasts[i].left - dt
        if toasts[i].left <= 0 then table.remove(toasts, i) end
    end
end

function ui.drawToasts()
    local t = toasts[1]
    if not t then return end
    local f = ui.f.body
    local maxW = 640
    local _, lines = f:getWrap(t.message, maxW)
    local w = math.min(maxW, f:getWidth(t.message)) + 40
    local h = #lines * f:getHeight() + 22
    local x = (love.graphics.getWidth() - w) / 2
    local y = 74
    local alpha = math.min(1, t.left / 0.4)
    love.graphics.setColor(0, 0, 0, 0.4 * alpha)
    love.graphics.rectangle("fill", x + 3, y + 4, w, h, 8, 8)
    ui.color("panel2", alpha)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    local kindColor = ({ok = "ok", err = "err", warn = "warn"})[t.kind] or "accent"
    ui.color(kindColor, alpha)
    love.graphics.rectangle("fill", x, y, 5, h, 3, 3)
    love.graphics.setFont(f)
    ui.color("text", alpha)
    love.graphics.printf(t.message, x + 20, y + 11, w - 30, "left")
end

return ui
