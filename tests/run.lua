-- Тесты чистой логики уровней (scripts/level.lua).
-- Запуск из корня проекта:  lua tests/run.lua   (или luajit tests/run.lua)
package.path = "./?.lua;" .. package.path
local level = require("scripts.level")
local version = require("scripts.version")
local files = require("scripts.files")
local List = require("scripts.list")
local updater = require("scripts.updater")

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

-- ---------------------------------------------------------------- версии
test("version.compare: порядок по major/minor/patch", function()
    eq(version.compare("1.2.0", "1.1.9"), 1)
    eq(version.compare("1.2.0", "1.2.0"), 0)
    eq(version.compare("1.2.0", "1.10.0"), -1, "1.2 младше 1.10 (числовое сравнение)")
    eq(version.compare("2.0.0", "1.99.99"), 1)
end)

test("version.compare: префикс v, короткие версии, пре-релизы", function()
    eq(version.compare("v1.2.0", "1.2.0"), 0)
    eq(version.compare("1.2", "1.2.0"), 0)
    eq(version.compare("1.2.0-rc.1", "1.2.0"), -1, "пре-релиз младше релиза")
    eq(version.compare("1.2.0-rc.2", "1.2.0-rc.10"), -1)
    eq(version.compare("1.2.0+build5", "1.2.0"), 0)
end)

test("version: мусор не версия и никогда не 'новее'", function()
    eq(version.parse("latest"), nil)
    eq(version.parse(""), nil)
    eq(version.parse(nil), nil)
    eq(version.compare("abc", "1.0.0"), nil)
    eq(version.isNewer("abc", "1.0.0"), false)
    eq(version.isNewer("v1.3.0", "1.2.0"), true)
    eq(version.isNewer("1.2.0", "1.2.0"), false)
    eq(version.isNewer("1.1.0", "1.2.0"), false)
end)

-- ---------------------------------------------------------------- updater (без сети)
local release = '{"url":"https://api.github.com/x","html_url":"https://github.com/ruffbuff/Levelarium/releases/tag/v1.3.0",'
    .. '"tag_name":"v1.3.0","author":{"html_url":"https://github.com/ruffbuff"}}'

test("updater.parseRelease: tag и страница релиза", function()
    local tag, url = updater.parseRelease(release)
    eq(tag, "v1.3.0")
    eq(url, "https://github.com/ruffbuff/Levelarium/releases/tag/v1.3.0")
    eq(updater.parseRelease("<html>rate limit</html>"), nil)
    eq(updater.parseRelease('{"message":"Not Found"}'), nil)
    eq(updater.parseRelease(nil), nil)
end)

test("updater.handleResponse: новая версия / та же / мусор", function()
    updater.available = nil
    eq(updater.handleResponse(release, "1.3.0"), false)
    eq(updater.available, nil)
    eq(updater.handleResponse("oops", "1.2.0"), false)
    eq(updater.available, nil)
    eq(updater.handleResponse(release, "1.2.0"), true)
    eq(updater.available.version, "1.3.0")
    eq(updater.available.url, "https://github.com/ruffbuff/Levelarium/releases/tag/v1.3.0")
    updater.available = nil
end)

test("updater.isSafeUrl: только http(s) без символов shell", function()
    eq(updater.isSafeUrl("https://api.github.com/repos/ruffbuff/Levelarium/releases/latest"), true)
    eq(updater.isSafeUrl("http://127.0.0.1:8765/release.json"), true)
    eq(updater.isSafeUrl("file:///etc/passwd"), false)
    eq(updater.isSafeUrl('https://x.io/a"; rm -rf ~ #'), false)
    eq(updater.isSafeUrl("https://x.io/a`id`"), false)
    eq(updater.isSafeUrl("https://x.io/a b"), false)
    eq(updater.isSafeUrl(nil), false)
end)

-- ---------------------------------------------------------------- список файлов
test("files.splitName / cleanName", function()
    local name, ext = files.splitName("My Level.TXT")
    eq(name, "My Level"); eq(ext, "txt")
    eq(files.splitName("noext"), nil)
    eq(files.cleanName("  level_1-b  "), "level_1-b")
    eq(files.cleanName(""), nil)
    eq(files.cleanName("   "), nil)
    eq(files.cleanName("../hack"), nil)
    eq(files.cleanName("a/b"), nil)
    eq(files.cleanName(("x"):rep(65)), nil)
end)

test("files.sortEntries: по дате (новые сверху) и по имени", function()
    local function sample()
        return {
            {name = "beta", ext = "txt", modtime = 100},
            {name = "Alpha", ext = "txt", modtime = 300},
            {name = "gamma", ext = "txt", modtime = 200},
            {name = "alpha2", ext = "txt", modtime = 300},
        }
    end
    local byDate = files.sortEntries(sample(), "date")
    eq(byDate[1].name, "Alpha"); eq(byDate[2].name, "alpha2", "при равной дате - по имени")
    eq(byDate[3].name, "gamma"); eq(byDate[4].name, "beta")
    local byName = files.sortEntries(sample(), "name")
    eq(byName[1].name, "Alpha"); eq(byName[2].name, "alpha2"); eq(byName[3].name, "beta"); eq(byName[4].name, "gamma")
end)

test("files.formatSize / formatDate / exists", function()
    eq(files.formatSize(0), "0 B")
    eq(files.formatSize(1023), "1023 B")
    eq(files.formatSize(1536), "1.5 KB")
    eq(files.formatSize(5 * 1024 * 1024), "5.0 MB")
    eq(files.formatSize(nil), "-")
    eq(files.formatDate(nil), "-")
    assert(files.formatDate(0):match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$"))
    local list = {{name = "Forest"}, {name = "cave"}}
    eq((files.exists(list, "forest")), true, "без учёта регистра")
    eq((files.exists(list, "castle")), false)
end)

-- ---------------------------------------------------------------- список с прокруткой
local function numbered(n)
    local t = {}
    for i = 1, n do t[i] = {name = "l" .. i} end
    return t
end

test("List: выбор, страницы и границы", function()
    local l = List.new(10)
    l:setItems(numbered(30))
    eq(l.selected, 1); eq(l.top, 0)
    l:move(-1); eq(l.selected, 1, "выше первого не уйти")
    l:page(1); eq(l.selected, 11); eq(l.top, 1, "окно следует за выбором")
    l:last(); eq(l.selected, 30); eq(l.top, 20)
    l:move(5); eq(l.selected, 30)
    l:home(); eq(l.selected, 1); eq(l.top, 0)
end)

test("List: колесо двигает окно, но не выбор; пустой список безопасен", function()
    local l = List.new(10)
    l:setItems(numbered(30))
    l:scroll(-2); eq(l.top, 6); eq(l.selected, 1)
    l:scroll(-100); eq(l.top, 20, "не дальше конца")
    l:scroll(100); eq(l.top, 0)
    local e = List.new(10)
    e:setItems({})
    e:move(1); e:page(1); e:scroll(-1)
    eq(e.selected, 0); eq(e.top, 0); eq(e:current(), nil)
end)

test("List: rowAt и режим allowNone", function()
    local l = List.new(10)
    l:setItems(numbered(30)); l:scroll(-1)
    eq(l.top, 3)
    eq(l:rowAt(0, 30), 4)
    eq(l:rowAt(65, 30), 6)
    eq(l:rowAt(-1, 30), nil)
    eq(l:rowAt(10 * 30, 30), nil, "за пределами окна")
    local short = List.new(10); short:setItems(numbered(2))
    eq(short:rowAt(3 * 30, 30), nil, "ниже последнего элемента")
    local open = List.new(5); open:setItems(numbered(3)); open:select(0)
    eq(open.selected, 1, "в обычном списке выбор не бывает пустым")
    local save = List.new(5, true); save:setItems(numbered(3), 0)
    eq(save.selected, 0); eq(save:current(), nil)
    save:move(1); eq(save.selected, 1)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
