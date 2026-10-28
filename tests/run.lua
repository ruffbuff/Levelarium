-- Тесты чистой логики уровней (scripts/level.lua).
-- Запуск из корня проекта:  lua tests/run.lua   (или luajit tests/run.lua)
package.path = "./?.lua;" .. package.path
local level = require("scripts.level")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("ok     " .. name)
    else
        failed = failed + 1
        print("FAIL   " .. name .. "\n         " .. tostring(err))
    end
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "values differ") .. ": expected <" .. tostring(expected) .. ">, got <" .. tostring(actual) .. ">", 2)
    end
end

local function sampleLayers()
    return {
        {[1] = {[1] = 5, [3] = 2}, [3] = {[2] = 64}},
        {[2] = {[2] = 7}},
    }
end

local function sameLayers(a, b, w, h)
    for i = 1, math.max(#a, #b) do
        for y = 1, h do
            for x = 1, w do
                local va = a[i] and a[i][y] and a[i][y][x] or 0
                local vb = b[i] and b[i][y] and b[i][y][x] or 0
                if va ~= vb then return false, ("layer %d (%d,%d): %s vs %s"):format(i, x, y, va, vb) end
            end
        end
        if (a[i] == nil) ~= (b[i] == nil) then return false, "layer count differs" end
    end
    return true
end

-- ------------------------------------------------------------ TXT
test("toTxt: заголовок, строки и разделители слоёв", function()
    eq(level.toTxt(sampleLayers(), 3, 3),
        "3,3,2\n5,0,2\n0,0,0\n0,64,0\n---\n0,0,0\n0,7,0\n0,0,0\n---\n")
end)

test("TXT: сохранение -> загрузка возвращает тот же уровень", function()
    local layers = sampleLayers()
    local back, w, h = level.parseTxt(level.toTxt(layers, 3, 3))
    eq(w, 3); eq(h, 3); eq(#back, 2)
    local ok, why = sameLayers(layers, back, 3, 3)
    assert(ok, why)
end)

test("TXT: нестандартный размер 7x2 и три слоя", function()
    local layers = {{[2] = {[7] = 1}}, {}, {[1] = {[1] = 9}}}
    local back, w, h = level.parseTxt(level.toTxt(layers, 7, 2))
    eq(w, 7); eq(h, 2); eq(#back, 3)
    assert(sameLayers(layers, back, 7, 2))
end)

test("parseTxt: файл с \\r\\n (другая ОС) читается так же", function()
    local data = level.toTxt(sampleLayers(), 3, 3):gsub("\n", "\r\n")
    local back = level.parseTxt(data)
    eq(#back, 2, "число слоёв")
    assert(sameLayers(sampleLayers(), back, 3, 3))
end)

test("parseTxt: файл без завершающего '---' даёт последний слой", function()
    local back = level.parseTxt("2,1,1\n3,0\n")
    eq(#back, 1)
    eq(back[1][1][1], 3)
end)

test("parseTxt: пустой файл, мусор и неверный заголовок -> nil, ошибка (без падения)", function()
    for _, bad in ipairs({"", "\n\n", "abc", "0,5,1\n", "5,0,1\n", "99999,5,1\n", "-3,4,1\n"}) do
        local layers, err = level.parseTxt(bad)
        eq(layers, nil, "должен быть nil для " .. string.format("%q", bad))
        assert(type(err) == "string")
    end
    eq(level.parseTxt(nil), nil)
end)

test("parseTxt: нечисловой тайл -> ошибка", function()
    local layers, err = level.parseTxt("2,1,1\n1,x\n---\n")
    eq(layers, nil)
    assert(err:find("line 2"))
end)

test("parseTxt: заголовок без слоёв всё равно даёт один пустой слой", function()
    local layers = level.parseTxt("4,4,1\n")
    eq(#layers, 1)
end)

test("parseTxt: maxLayers обрезает лишние слои", function()
    local data = level.toTxt({{}, {}, {}, {}}, 2, 2)
    eq(#level.parseTxt(data, {maxLayers = 3}), 3)
end)

test("parseTxt: тайлы вне заявленной сетки отбрасываются", function()
    local layers = level.parseTxt("2,1,1\n1,2,3\n4,5\n---\n")
    eq(layers[1][1][2], 2)
    eq(layers[1][1][3], nil)
    eq(layers[1][2], nil)
end)

-- ------------------------------------------------------------ JSON
test("toJson: точная структура", function()
    eq(level.toJson(sampleLayers(), 3, 3, 64),
        '{"width":3,"height":3,"tileSize":64,"layers":[' ..
        '{"name":"Layer 1","data":[[5,0,2],[0,0,0],[0,64,0]]},' ..
        '{"name":"Layer 2","data":[[0,0,0],[0,7,0],[0,0,0]]}]}')
end)

test("toJson: скобки и кавычки сбалансированы на большом уровне", function()
    local json = level.toJson({{}, {}, {}}, 50, 50, 64)
    local _, open = json:gsub("%[", "")
    local _, close = json:gsub("%]", "")
    eq(open, close)
    eq(open, 1 + 3 * 51)
end)

-- ------------------------------------------------------------ TMX
test("toTmx: тайлсет - коллекция изображений, а не один спрайтлист", function()
    local tiles = {
        {source = "../assets/p/1.png", width = 64, height = 64},
        {source = "../assets/p/2.png", width = 64, height = 64},
    }
    local tmx = level.toTmx(sampleLayers(), 3, 3, 64, tiles)
    assert(tmx:find('tilecount="2" columns="0"', 1, true), "tilecount/columns")
    assert(tmx:find('<tile id="0">', 1, true) and tmx:find('<tile id="1">', 1, true))
    assert(tmx:find('source="../assets/p/2.png"', 1, true))
    assert(tmx:find('<layer id="2" name="Layer 2" width="3" height="3">', 1, true))
    assert(tmx:find("5,0,2,\n0,0,0,\n0,64,0\n", 1, true), "csv данные слоя 1")
    assert(tmx:sub(-7) == "</map>\n")
end)

test("toTmx: спецсимволы в пути экранируются", function()
    local tmx = level.toTmx({{}}, 1, 1, 64, {{source = 'a&b"<.png', width = 1, height = 1}})
    assert(tmx:find('source="a&amp;b&quot;&lt;.png"', 1, true))
end)

-- ------------------------------------------------------------ Операции
test("trimLayers: уменьшение холста удаляет тайлы за границей", function()
    local layers = {{[1] = {[1] = 1, [5] = 2}, [4] = {[1] = 3}, [9] = {[9] = 4}}}
    level.trimLayers(layers, 3, 4)
    eq(layers[1][1][1], 1)
    eq(layers[1][1][5], nil, "колонка за шириной")
    eq(layers[1][4][1], 3)
    eq(layers[1][9], nil, "строка за высотой")
end)

test("linePositions: горизонталь, диагональ, точка, обратное направление", function()
    eq(#level.linePositions(1, 1, 5, 1, 10, 10), 5)
    local d = level.linePositions(1, 1, 4, 4, 10, 10)
    eq(#d, 4); eq(d[4].x, 4); eq(d[4].y, 4)
    eq(#level.linePositions(3, 3, 3, 3, 10, 10), 1)
    local r = level.linePositions(5, 5, 1, 2, 10, 10)
    eq(r[1].x, 5); eq(r[#r].x, 1); eq(r[#r].y, 2)
end)

test("linePositions: координаты прижимаются к сетке", function()
    for _, p in ipairs(level.linePositions(-5, -5, 99, 99, 10, 10)) do
        assert(p.x >= 1 and p.x <= 10 and p.y >= 1 and p.y <= 10)
    end
end)

test("floodFill: заливает связную область и не выходит за стены", function()
    local layer = {[2] = {[1] = 9, [2] = 9, [3] = 9}, [1] = {}, [3] = {}}
    level.floodFill(layer, 3, 3, 1, 1, nil, 4) -- верхняя строка отделена стеной из 9
    for x = 1, 3 do eq(layer[1][x], 4) end
    eq(layer[3][1], nil, "нижняя строка не тронута")
end)

test("floodFill: replacement == nil стирает область", function()
    local layer = {[1] = {[1] = 2, [2] = 2, [3] = 5}}
    level.floodFill(layer, 3, 1, 1, 1, 2, nil)
    eq(layer[1][1], nil); eq(layer[1][2], nil); eq(layer[1][3], 5)
end)

test("floodFill: 400x400 пустая область без stack overflow", function()
    local layer = {}
    level.floodFill(layer, 400, 400, 1, 1, nil, 3)
    local count = 0
    for y = 1, 400 do for x = 1, 400 do if layer[y][x] == 3 then count = count + 1 end end end
    eq(count, 160000)
end)

test("floodFill: target == replacement ничего не делает", function()
    local layer = {[1] = {[1] = 2}}
    level.floodFill(layer, 2, 2, 1, 1, 2, 2)
    eq(layer[1][2], nil)
end)

test("toTxt: уровень 500x500x5 сериализуется быстро", function()
    local start = os.clock()
    local layers = {{}, {}, {}, {}, {}}
    local txt = level.toTxt(layers, 500, 500)
    assert(#txt > 500 * 500 * 5)
    assert(os.clock() - start < 5, "слишком медленно")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
