-- Чистая логика уровней (без love.*): сериализация, разбор и операции над слоями.
-- Слой - разреженная таблица layer[y][x] = номер тайла (1..N); пустая клетка = nil.
-- Модуль не зависит от LÖVE, поэтому его можно проверять обычным `lua tests/run.lua`.

local level = {}

--- Склеивает значения в строку через table.concat (быстрее, чем `..` в цикле).
local function join(parts)
    return table.concat(parts)
end

local function xmlEscape(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- ---------------------------------------------------------------- TXT

--- Формат: первая строка "ширина,высота,слоёв", затем по `высота` строк на слой
--- (значения через запятую, 0 = пусто) и строка "---" после каждого слоя.
function level.toTxt(layers, width, height)
    local out = {width, ",", height, ",", #layers, "\n"}
    for _, layer in ipairs(layers) do
        for y = 1, height do
            local row = layer[y]
            for x = 1, width do
                out[#out + 1] = (row and row[x]) or 0
                if x < width then out[#out + 1] = "," end
            end
            out[#out + 1] = "\n"
        end
        out[#out + 1] = "---\n"
    end
    return join(out)
end

--- Разбор TXT. Возвращает layers, width, height либо nil, "сообщение об ошибке".
--- opts.maxSize  - максимально допустимый размер сетки (по умолчанию 1000)
--- opts.maxLayers - сколько слоёв читать максимум (по умолчанию без ограничения)
function level.parseTxt(data, opts)
    opts = opts or {}
    local maxSize = opts.maxSize or 1000
    local maxLayers = opts.maxLayers

    if type(data) ~= "string" then return nil, "no data" end

    local lines = {}
    -- "[^\r\n]+" переживает и \n, и \r\n (файл мог быть сохранён на другой ОС)
    for line in data:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
    end
    if #lines == 0 then return nil, "empty file" end

    -- заголовок "ширина,высота[,слоёв]"; число слоёв определяем по самим данным
    local headerW, headerH = lines[1]:match("^%s*(%d+)%s*,%s*(%d+)")
    local w, h = tonumber(headerW), tonumber(headerH)
    if not w or not h or w < 1 or h < 1 or w > maxSize or h > maxSize then
        return nil, "invalid header"
    end

    local layers = {}
    local layer, rows = {}, 0
    local function closeLayer()
        if not maxLayers or #layers < maxLayers then
            layers[#layers + 1] = layer
        end
        layer, rows = {}, 0
    end

    for i = 2, #lines do
        local line = lines[i]
        if line:match("^%-%-%-%s*$") then
            closeLayer()
        else
            rows = rows + 1
            if rows <= h then
                local x = 1
                for tile in line:gmatch("[^,]+") do
                    local value = tonumber(tile)
                    if not value then return nil, "invalid tile value at line " .. i end
                    value = math.floor(value)
                    if value > 0 and x <= w then
                        layer[rows] = layer[rows] or {}
                        layer[rows][x] = value
                    end
                    x = x + 1
                end
            end
        end
    end
    if rows > 0 then closeLayer() end -- файл без завершающего "---"

    if #layers == 0 then layers[1] = {} end -- всегда минимум один слой
    return layers, w, h
end

-- ---------------------------------------------------------------- JSON

--- JSON со стабильным порядком ключей:
--- {"width":W,"height":H,"tileSize":T,"layers":[{"name":"Layer 1","data":[[...],...]}]}
function level.toJson(layers, width, height, tileSize)
    local out = {'{"width":', width, ',"height":', height, ',"tileSize":', tileSize, ',"layers":['}
    for index, layer in ipairs(layers) do
        if index > 1 then out[#out + 1] = "," end
        out[#out + 1] = '{"name":"Layer ' .. index .. '","data":['
        for y = 1, height do
            if y > 1 then out[#out + 1] = "," end
            out[#out + 1] = "["
            local row = layer[y]
            for x = 1, width do
                if x > 1 then out[#out + 1] = "," end
                out[#out + 1] = (row and row[x]) or 0
            end
            out[#out + 1] = "]"
        end
        out[#out + 1] = "]}"
    end
    out[#out + 1] = "]}"
    return join(out)
end

-- ---------------------------------------------------------------- TMX

--- TMX (Tiled). Тайлсет - "коллекция изображений": каждый тайл это отдельный PNG.
--- tiles = { {source = "../assets/pack/1.png", width = 64, height = 64}, ... },
--- номер тайла в слое i соответствует gid = i (firstgid = 1), то есть tile id = i - 1.
function level.toTmx(layers, width, height, tileSize, tiles)
    tiles = tiles or {}
    local out = {
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        '<map version="1.10" tiledversion="1.10.1" orientation="orthogonal" renderorder="right-down" ',
        'compressionlevel="0" width="', width, '" height="', height, '" tilewidth="', tileSize,
        '" tileheight="', tileSize, '" infinite="0" nextlayerid="', #layers + 1, '" nextobjectid="1">\n',
        ' <tileset firstgid="1" name="tiles" tilewidth="', tileSize, '" tileheight="', tileSize,
        '" tilecount="', #tiles, '" columns="0">\n',
        '  <grid orientation="orthogonal" width="1" height="1"/>\n',
    }
    for i, tile in ipairs(tiles) do
        out[#out + 1] = '  <tile id="' .. (i - 1) .. '">\n'
        out[#out + 1] = '   <image source="' .. xmlEscape(tile.source) .. '" width="' ..
            (tile.width or tileSize) .. '" height="' .. (tile.height or tileSize) .. '"/>\n'
        out[#out + 1] = '  </tile>\n'
    end
    out[#out + 1] = ' </tileset>\n'

    for index, layer in ipairs(layers) do
        out[#out + 1] = ' <layer id="' .. index .. '" name="Layer ' .. index .. '" width="' ..
            width .. '" height="' .. height .. '">\n  <data encoding="csv">\n'
        for y = 1, height do
            local row = layer[y]
            for x = 1, width do
                out[#out + 1] = (row and row[x]) or 0
                if x < width or y < height then out[#out + 1] = "," end
            end
            if y < height then out[#out + 1] = "\n" end
        end
        out[#out + 1] = '\n  </data>\n </layer>\n'
    end
    out[#out + 1] = '</map>\n'
    return join(out)
end

-- ---------------------------------------------------------------- Операции

--- Обрезает слои по новому размеру (расширение ничего не требует: слой разреженный).
function level.trimLayers(layers, newWidth, newHeight)
    for _, layer in ipairs(layers) do
        for y, row in pairs(layer) do
            if y > newHeight then
                layer[y] = nil
            else
                for x in pairs(row) do
                    if x > newWidth then row[x] = nil end
                end
            end
        end
    end
end

--- Клетки линии Брезенхэма внутри сетки width x height.
function level.linePositions(x1, y1, x2, y2, width, height)
    local positions = {}
    x1 = math.max(1, math.min(x1, width))
    y1 = math.max(1, math.min(y1, height))
    x2 = math.max(1, math.min(x2, width))
    y2 = math.max(1, math.min(y2, height))

    local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    while true do
        positions[#positions + 1] = {x = x1, y = y1}
        if x1 == x2 and y1 == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x1 = x1 + sx
        end
        if e2 < dx then
            err = err + dx
            y1 = y1 + sy
        end
    end
    return positions
end

--- Итеративная заливка (без рекурсии: рекурсивная версия падала с stack overflow
--- на больших пустых областях). replacement == nil стирает область.
function level.floodFill(layer, width, height, x, y, target, replacement)
    if target == replacement then return end
    local stack = {{x, y}}
    while #stack > 0 do
        local pos = table.remove(stack)
        local px, py = pos[1], pos[2]
        if px >= 1 and px <= width and py >= 1 and py <= height then
            local row = layer[py]
            local current = row and row[px] or nil
            if current == target then
                if replacement then
                    if not row then
                        row = {}
                        layer[py] = row
                    end
                    row[px] = replacement
                else
                    row[px] = nil
                end
                stack[#stack + 1] = {px + 1, py}
                stack[#stack + 1] = {px - 1, py}
                stack[#stack + 1] = {px, py + 1}
                stack[#stack + 1] = {px, py - 1}
            end
        end
    end
end

return level
