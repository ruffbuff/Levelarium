local settings = require("scripts.settings")
local levelLib = require("scripts.level")
local files = require("scripts.files")
local List = require("scripts.list")
local ui = require("scripts.ui")
local updater = require("scripts.updater")
local fileio = require("scripts.fileio")
local History = require("scripts.history")

local assets = {}
local assetFiles = {}  -- имена файлов, параллельно assets (нужны для экспорта TMX)
local tileSize = settings.tileSize
local gridWidth = settings.gridWidth
local gridHeight = settings.gridHeight
local canvas = {width = gridWidth * tileSize, height = gridHeight * tileSize}
local selectedTile = 1
local isErasing = false
local layers = {}
local currentLayer = 1
local maxLayers = 5  -- Максимальное количество слоев

local tileScrollOffset = 0
local visibleTilesX = 18
local visibleTilesY = 2
local tileButtonSize = 48
local paletteHeight = 120
local hudHeight = 62  -- верхняя панель с названием уровня и подсказками

local tools = {"brush", "eraser", "bucket", "line", "rectangle"}
local selectedTool = "brush"
local startX, startY = nil, nil
local previewX, previewY = nil, nil
local strokeX, strokeY = nil, nil  -- последняя клетка текущего мазка кистью/ластиком (для интерполяции)
local undoHistory = History.new(100)  -- Ctrl+Z / Ctrl+Y: до 100 шагов, шаг = мазок/заливка/линия/прямоугольник

local availableAssetPacks = {}
local selectedAssetPackIndex = 1

-- Форматы сохранения
local saveFormats = {"txt", "json", "tmx"}
local selectedSaveFormat = 1

-- Настройки холста
local canvasWidthInput = tostring(settings.gridWidth)
local canvasHeightInput = tostring(settings.gridHeight)
local activeCanvasField = 1 -- 1 для width, 2 для height

-- Состояние интерфейса
local showMenu = true       -- главное меню (поверх редактора)
local hasWork = false       -- есть открытый уровень -> в меню появляется "Continue"
local dirty = false         -- есть несохранённые изменения
local currentName = nil     -- имя уровня (без расширения) после сохранения/загрузки
local menuIndex = 1
local modal = nil           -- "assets" | "canvas" | "save" | "open" | nil
local confirmDlg = nil      -- {title, text, yes, onYes, choice}: подтверждение поверх всего
local forceQuit = false
local updateRect = nil      -- область строки "доступна новая версия" в меню (для клика)

local openList = List.new(10)
local saveList = List.new(7, true)
local assetList = List.new(9)
local openSort = "date"     -- "date" | "name"
local saveName = ""
local lastClick = {t = 0}

-- love.keypressed и love.textinput для одной и той же клавиши приходят в одном кадре.
-- Без этого флага клавиша, открывшая диалог (например P), попадала в поле ввода.
local ignoreTextInput = false

local camera = {
    x = 0, y = 0, scale = 1,
    minScale = 0.1, maxScale = 2
}

local function editorActive()
    return not showMenu and not modal and not confirmDlg
end

local function levelTitle()
    return (currentName or "Untitled") .. (dirty and "*" or "")
end

local function refreshWindowTitle()
    love.window.setTitle(settings.getWindowTitle() .. (hasWork and (" - " .. levelTitle()) or ""))
end

local function setDirty(value)
    if dirty ~= value then
        dirty = value
        refreshWindowTitle()
    end
end

local function askConfirm(title, text, yesLabel, onYes)
    confirmDlg = {title = title, text = text, yes = yesLabel, onYes = onYes, choice = 2}
end

function love.load()
    ui.load()
    availableAssetPacks = settings.getAvailableAssetPacks()

    for i, pack in ipairs(availableAssetPacks) do
        if pack == settings.currentAssetPack then
            selectedAssetPackIndex = i
            break
        end
    end

    loadAssets()
    createNewLayer()  -- Создаем первый слой при запуске
    refreshWindowTitle()

    -- Проверка обновлений (в фоне, один раз). Для проверки можно подменить адрес и "текущую" версию:
    --   LEVELARIUM_UPDATE_URL=http://localhost:8000/release.json LEVELARIUM_TEST_VERSION=1.0.0 love .
    if settings.checkUpdates then
        updater.start({
            url = os.getenv("LEVELARIUM_UPDATE_URL") or settings.updateUrl,
            currentVersion = os.getenv("LEVELARIUM_TEST_VERSION") or settings.VERSION,
            fallbackUrl = settings.releasesPage,
        })
    end
end

function love.update(dt)
    ignoreTextInput = false  -- события клавиатуры текущего кадра уже обработаны
    ui.update(dt)
    updater.poll()
    if editorActive() then
        updateCamera(dt)
    end
end

function love.quit()
    -- закрытие окна с несохранёнными изменениями: сначала спрашиваем
    if dirty and not forceQuit then
        if not confirmDlg then
            askConfirm("Quit Levelarium?", "Unsaved changes in \"" .. levelTitle() .. "\" will be lost.", "Quit without saving",
                function() forceQuit = true; love.event.quit() end)
        end
        return true
    end
    return false
end

function createNewLayer()
    if #layers < maxLayers then
        table.insert(layers, {})
        currentLayer = #layers
        return true
    end
    return false
end

function switchLayer(layerNum)
    if layerNum >= 1 and layerNum <= #layers then
        currentLayer = layerNum
    end
end

function deleteCurrentLayer()
    if #layers > 1 then
        table.remove(layers, currentLayer)
        currentLayer = math.min(currentLayer, #layers)
        undoHistory:reset()  -- номера слоёв сдвинулись, старые шаги больше не применимы
        return true
    end
    return false
end

function updateCamera(dt)
    -- Ctrl+S (и другие сочетания с Ctrl/Cmd) не должны двигать камеру
    if love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then return end
    local speed = 500 * dt / camera.scale
    if love.keyboard.isDown("w") then camera.y = camera.y - speed end
    if love.keyboard.isDown("s") then camera.y = camera.y + speed end
    if love.keyboard.isDown("a") then camera.x = camera.x - speed end
    if love.keyboard.isDown("d") then camera.x = camera.x + speed end
end

function loadAssets()
    assets = {}
    assetFiles = {}
    local packPath = settings.getAssetPackPath()
    local files = love.filesystem.getDirectoryItems(packPath)
    local imageFiles = {}
    
    for _, filename in ipairs(files) do
        if filename:match("%.png$") then
            table.insert(imageFiles, filename)
        end
    end
    
    table.sort(imageFiles, function(a, b)
        local numA = tonumber(a:match("(%d+)%.png$")) or 0
        local numB = tonumber(b:match("(%d+)%.png$")) or 0
        if numA ~= numB then return numA < numB end
        return a < b  -- стабильный порядок для файлов с одинаковым номером
    end)
    
    for _, filename in ipairs(imageFiles) do
        local path = packPath .. filename
        local success, image = pcall(love.graphics.newImage, path)
        if success then
            table.insert(assets, image)
            table.insert(assetFiles, filename)
        end
    end
    
end

function resizeCanvas(newWidth, newHeight)
    gridWidth = newWidth
    gridHeight = newHeight
    canvas.width = gridWidth * tileSize
    canvas.height = gridHeight * tileSize

    -- Если холст уменьшился, удаляем тайлы за его пределами
    -- (раньше цикл сравнивал новую ширину сама с собой и ничего не удалял)
    levelLib.trimLayers(layers, newWidth, newHeight)
    undoHistory:reset()  -- обрезанные тайлы вернуть нельзя

    canvasWidthInput = tostring(gridWidth)
    canvasHeightInput = tostring(gridHeight)
end

function switchAssetPack(packIndex)
    if packIndex >= 1 and packIndex <= #availableAssetPacks and availableAssetPacks[packIndex] ~= settings.currentAssetPack then
        selectedAssetPackIndex = packIndex
        settings.currentAssetPack = availableAssetPacks[packIndex]
        loadAssets()
        setDirty(true)  -- набор тайлов хранится в файле уровня
        selectedTile = math.max(1, math.min(selectedTile, #assets))
        local maxScroll = math.max(0, math.ceil(#assets / visibleTilesX) - visibleTilesY)
        tileScrollOffset = math.min(tileScrollOffset, maxScroll)
    end
end

-- true, если точка находится над верхней панелью, панелью инструментов (справа) или палитрой тайлов (снизу)
function isOverUi(x, y)
    return x >= love.graphics.getWidth() - 100 or y > love.graphics.getHeight() - paletteHeight or y < hudHeight
end

-- Пипетка: берёт тайл под курсором (сначала из текущего слоя, затем из верхних слоёв вниз)
function pickTile(x, y)
    if isOverUi(x, y) then return end
    local tileX = math.floor((x / camera.scale + camera.x) / tileSize) + 1
    local tileY = math.floor((y / camera.scale + camera.y) / tileSize) + 1
    if tileX < 1 or tileX > gridWidth or tileY < 1 or tileY > gridHeight then return end

    local function tileAt(layer)
        return layer and layer[tileY] and layer[tileY][tileX]
    end

    local tile = tileAt(layers[currentLayer])
    if not tile then
        for i = #layers, 1, -1 do
            tile = tileAt(layers[i])
            if tile then break end
        end
    end

    if tile and assets[tile] then
        selectedTile = tile
        selectedTool = "brush"
        -- прокручиваем палитру, чтобы выбранный тайл был виден
        local row = math.floor((tile - 1) / visibleTilesX)
        if row < tileScrollOffset or row >= tileScrollOffset + visibleTilesY then
            local maxScroll = math.max(0, math.ceil(#assets / visibleTilesX) - visibleTilesY)
            tileScrollOffset = math.min(row, maxScroll)
        end
    end
end

-- Размер тайла в пикселях в исходных PNG набора (редактор рисует их с масштабом tileSize / этот размер)
local function nativeTileSize()
    local first = assets[1]
    return first and first:getWidth() or tileSize
end

local function levelMeta()
    return {pack = settings.currentAssetPack, tileSize = nativeTileSize()}
end

function generateTxtData()
    return levelLib.toTxt(layers, gridWidth, gridHeight, levelMeta())
end

function generateJsonData()
    return levelLib.toJson(layers, gridWidth, gridHeight, nativeTileSize(), settings.currentAssetPack)
end

-- Путь к PNG набора относительно папки с .tmx: тайлы копируются в levels/tiles/<набор>/ при сохранении
local function tmxTileDir()
    return "tiles/" .. levelLib.packSlug(settings.currentAssetPack)
end

function generateTmxData()
    -- Тайлсет TMX описывает каждый PNG набора отдельным тайлом (gid = номер тайла)
    local tiles = {}
    for i, filename in ipairs(assetFiles) do
        tiles[i] = {
            source = tmxTileDir() .. "/" .. filename,
            width = assets[i]:getWidth(),
            height = assets[i]:getHeight()
        }
    end
    return levelLib.toTmx(layers, gridWidth, gridHeight, nativeTileSize(), tiles)
end

-- Папка проекта, если игра запущена как `love .` (иначе nil: .love-архив или собранный exe)
local function projectDir()
    local source = love.filesystem.getSource()
    local file = source and io.open(source .. "/main.lua", "r")
    if file then
        file:close()
        return source
    end
    return nil
end

local function ensureDirectory(path)
    -- без `mkdir -p`: на Windows такой команды нет
    if love.system.getOS() == "Windows" then
        local winPath = path:gsub("/", "\\")
        os.execute('if not exist "' .. winPath .. '" mkdir "' .. winPath .. '"')
    else
        os.execute("mkdir -p '" .. path:gsub("'", "'\\''") .. "'")
    end
end

-- Пишет файл в папку уровней (relPath - путь внутри неё, например "a.txt" или "tiles/x/1.png").
-- Возвращает true, полный путь  или  false, причину. Запись атомарная: сначала временный файл,
-- затем переименование - при сбое прежний файл остаётся целым.
-- При запуске из папки проекта уровни, как и раньше, лежат в <проект>/levels/,
-- в собранной версии (.love / exe) - в папке сохранений LÖVE.
local function writeLevelFile(relPath, data)
    local subdir = relPath:match("^(.*)/[^/]+$")
    local dir = projectDir()
    if dir then
        local base = dir .. "/" .. settings.levelsPath
        local path = base .. relPath
        local ok, err = fileio.atomicWrite(path, data)
        if not ok then
            ensureDirectory(base .. (subdir or ""))
            ok, err = fileio.atomicWrite(path, data)
        end
        if ok then return true, path end
        return false, path .. " (" .. tostring(err) .. ")"
    end

    love.filesystem.createDirectory(settings.levelsPath .. (subdir or ""))
    local path = love.filesystem.getSaveDirectory() .. "/" .. settings.levelsPath .. relPath
    local ok, err = fileio.atomicWrite(path, data)
    if ok then return true, path end
    -- запасной путь: LÖVE пишет сам (например, если в пути к профилю есть символы вне ANSI на Windows)
    local ok2, err2 = love.filesystem.write(settings.levelsPath .. relPath, data)
    if ok2 then return true, path end
    return false, path .. " (" .. tostring(err2 or err) .. ")"
end

-- Копирует PNG текущего набора рядом с TMX, чтобы Tiled нашёл картинки по относительным путям.
local function copyTmxTiles()
    local packPath = settings.getAssetPackPath()
    for _, filename in ipairs(assetFiles) do
        local data = love.filesystem.read(packPath .. filename)
        if data then
            local rel = tmxTileDir() .. "/" .. filename
            local info = love.filesystem.getInfo(settings.levelsPath .. rel)
            if not (info and info.size == #data) then
                local ok, err = writeLevelFile(rel, data)
                if not ok then return false, err end
            end
        end
    end
    return true
end

-- Список файлов уровней нужного формата: {{name, ext, size, modtime}, ...}.
-- love.filesystem видит и <проект>/levels, и папку сохранений; `ls` не нужен (его нет на Windows).
function listLevels(ext)
    local entries, seen = {}, {}
    local dirName = settings.levelsPath:gsub("/$", "")
    for _, filename in ipairs(love.filesystem.getDirectoryItems(dirName)) do
        local name, fileExt = files.splitName(filename)
        if name and (not ext or fileExt == ext) and not seen[filename] then
            seen[filename] = true
            local info = love.filesystem.getInfo(dirName .. "/" .. filename)
            if info and info.type == "file" then
                entries[#entries + 1] = {name = name, ext = fileExt, size = info.size, modtime = info.modtime}
            end
        end
    end
    return entries
end

-- Сохраняет уровень в выбранном формате. Возвращает true, размер  или  false, причину.
function saveLevel(levelName)
    local format = saveFormats[selectedSaveFormat]
    local data
    if format == "txt" then
        data = generateTxtData()
    elseif format == "json" then
        data = generateJsonData()
    elseif format == "tmx" then
        data = generateTmxData()
    end

    if format == "tmx" then
        local copied, cerr = copyTmxTiles()
        if not copied then return false, tostring(cerr) end
    end

    local ok, path = writeLevelFile(levelName .. "." .. format, data)
    if not ok then
        return false, tostring(path)
    end
    currentName = levelName
    setDirty(false)
    refreshWindowTitle()
    return true, #data
end

-- Загружает TXT-уровень. Возвращает true  или  false, причину (текущий уровень при ошибке не трогаем).
function loadLevel(levelName)
    local data = love.filesystem.read(settings.levelsPath .. levelName .. ".txt")
    if not data then
        return false, "file not found"
    end

    local newLayers, newWidth, newHeight, meta = levelLib.parseTxt(data, {
        maxSize = settings.maxGridSize,
        maxLayers = maxLayers
    })
    if not newLayers then
        -- newWidth содержит текст ошибки
        return false, tostring(newWidth)
    end

    -- набор тайлов из файла (1.2.1+); у старых файлов его нет - остаётся текущий
    local warning
    if meta and meta.pack and meta.pack ~= settings.currentAssetPack then
        local found
        for i, pack in ipairs(availableAssetPacks) do
            if pack == meta.pack then found = i break end
        end
        if found then
            switchAssetPack(found)
        else
            warning = "asset pack \"" .. meta.pack .. "\" not found, using " .. settings.currentAssetPack
        end
    end

    layers = newLayers
    undoHistory:reset()
    gridWidth, gridHeight = newWidth, newHeight
    canvas.width = gridWidth * tileSize
    canvas.height = gridHeight * tileSize
    canvasWidthInput = tostring(gridWidth)
    canvasHeightInput = tostring(gridHeight)
    currentLayer = 1
    startX, startY = nil, nil
    camera.x, camera.y, camera.scale = 0, 0, 1
    currentName = levelName
    selectedSaveFormat = 1  -- загружали TXT
    hasWork = true
    showMenu = false
    setDirty(false)
    refreshWindowTitle()
    return true, warning
end

-- ------------------------------------------------------------------ главное меню
local MENU_W, MENU_H, MENU_GAP = 340, 56, 12

local function menuItems()
    local items = {}
    if hasWork then items[#items + 1] = {id = "continue", label = "Continue", sub = levelTitle()} end
    items[#items + 1] = {id = "new", label = "New level"}
    items[#items + 1] = {id = "open", label = "Open level"}
    items[#items + 1] = {id = "quit", label = "Quit"}
    return items
end

local function menuRect(i)
    return (love.graphics.getWidth() - MENU_W) / 2, 250 + (i - 1) * (MENU_H + MENU_GAP), MENU_W, MENU_H
end

local function backToMenu()
    startX, startY = nil, nil
    showMenu = true
    menuIndex = 1
end

function drawMenu()
    local W, H = love.graphics.getDimensions()

    -- едва заметная сетка на фоне
    love.graphics.setColor(1, 1, 1, 0.035)
    for x = 0, W, 48 do love.graphics.line(x, 0, x, H) end
    for y = 0, H, 48 do love.graphics.line(0, y, W, y) end

    ui.text(settings.NAME, "title", "text", 0, 96, W, "center")
    ui.text("v" .. settings.VERSION .. "  -  tile-based level editor", "body", "dim", 0, 158, W, "center")

    local items = menuItems()
    menuIndex = math.max(1, math.min(menuIndex, #items))
    for i, item in ipairs(items) do
        local x, y, w, h = menuRect(i)
        ui.button(item.label, x, y, w, h, i == menuIndex, "h", item.sub)
    end

    updateRect = nil
    local _, lastY, _, lastH = menuRect(#items)
    if updater.available then
        local text = "Version " .. updater.available.version .. " is available - press U or click to open the page"
        local w = ui.f.body:getWidth(text) + 40
        local x, y, h = (W - w) / 2, lastY + lastH + 26, 38
        updateRect = {x = x, y = y, w = w, h = h}
        ui.color("panel")
        love.graphics.rectangle("fill", x, y, w, h, 8, 8)
        ui.color("ok")
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 8, 8)
        ui.text(text, "body", "ok", x, y + 10, w, "center")
    end

    ui.text("Up/Down - select     Enter - confirm     Esc - " .. (hasWork and "back to the editor" or "quit"),
        "small", "dim", 0, H - 58, W, "center")
    ui.text("by " .. settings.AUTHOR, "small", "dim", 0, H - 36, W, "center")
end

local function startNewLevel()
    layers = {}
    createNewLayer()
    undoHistory:reset()
    gridWidth, gridHeight = settings.gridWidth, settings.gridHeight
    canvas.width, canvas.height = gridWidth * tileSize, gridHeight * tileSize
    canvasWidthInput, canvasHeightInput = tostring(gridWidth), tostring(gridHeight)
    camera.x, camera.y, camera.scale = 0, 0, 1
    startX, startY = nil, nil
    currentName = nil
    hasWork = true
    showMenu = false
    dirty = false
    refreshWindowTitle()
    ui.toast("New level created", "info")
end

local function refreshOpenList()
    local entries = listLevels("txt")
    files.sortEntries(entries, openSort)
    openList:setItems(entries)
end

local function openOpenDialog()
    modal = "open"
    refreshOpenList()
end

local function activateMenu(id)
    if id == "continue" then
        showMenu = false
    elseif id == "new" then
        if hasWork and dirty then
            askConfirm("Start a new level?", "Unsaved changes in \"" .. levelTitle() .. "\" will be lost.",
                "Discard and start new", startNewLevel)
        else
            startNewLevel()
        end
    elseif id == "open" then
        openOpenDialog()
    elseif id == "quit" then
        love.event.quit()  -- love.quit спросит подтверждение, если есть несохранённые изменения
    end
end

local function openUpdatePage()
    if updater.available and updater.available.url then
        love.system.openURL(updater.available.url)
        ui.toast("Opening the release page in your browser...", "info")
    end
end

-- ------------------------------------------------------------------ редактор
function love.draw()
    if showMenu then
        drawMenu()
    else
        love.graphics.push()
        love.graphics.scale(camera.scale)
        love.graphics.translate(-camera.x, -camera.y)
        drawGrid()
        drawHoveredTile()
        drawPreview()
        love.graphics.pop()
        drawPalette()
        drawTools()
        drawHud()
    end

    if modal == "assets" then
        drawAssetPackSelector()
    elseif modal == "save" then
        drawSaveDialog()
    elseif modal == "open" then
        drawOpenDialog()
    elseif modal == "canvas" then
        drawCanvasSettings()
    end
    if confirmDlg then drawConfirm() end
    ui.drawToasts()
end

function drawGrid()
    local startX = math.max(0, math.floor(camera.x / tileSize))
    local startY = math.max(0, math.floor(camera.y / tileSize))
    local endX = math.min(gridWidth - 1, math.ceil((camera.x + love.graphics.getWidth() / camera.scale) / tileSize))
    local endY = math.min(gridHeight - 1, math.ceil((camera.y + love.graphics.getHeight() / camera.scale) / tileSize))

    -- фон холста: видно, где заканчивается уровень
    love.graphics.setColor(0.12, 0.13, 0.17)
    love.graphics.rectangle("fill", 0, 0, gridWidth * tileSize, gridHeight * tileSize)

    love.graphics.setColor(0.5, 0.55, 0.65, 0.35)
    for y = startY, endY do
        love.graphics.line(startX * tileSize, y * tileSize, (endX + 1) * tileSize, y * tileSize)
    end
    for x = startX, endX do
        love.graphics.line(x * tileSize, startY * tileSize, x * tileSize, (endY + 1) * tileSize)
    end

    for layerIndex, layer in ipairs(layers) do
        for y = startY, endY do
            for x = startX, endX do
                if layer[y + 1] and layer[y + 1][x + 1] and assets[layer[y + 1][x + 1]] then
                    local asset = assets[layer[y + 1][x + 1]]
                    love.graphics.setColor(1, 1, 1, layerIndex == currentLayer and 1 or 0.5)
                    love.graphics.draw(asset, x * tileSize, y * tileSize, 0, tileSize / asset:getWidth(), tileSize / asset:getHeight())
                end
            end
        end
    end
end

function drawPalette()
    local paletteWidth = love.graphics.getWidth() - 100
    local top = love.graphics.getHeight() - paletteHeight

    ui.color("panel")
    love.graphics.rectangle("fill", 0, top, paletteWidth, paletteHeight)
    ui.color("border")
    love.graphics.line(0, top + 0.5, paletteWidth, top + 0.5)

    love.graphics.setScissor(0, top, paletteWidth, paletteHeight)

    local startIndex = tileScrollOffset * visibleTilesX + 1
    for y = 0, visibleTilesY - 1 do
        for x = 0, visibleTilesX - 1 do
            local index = startIndex + y * visibleTilesX + x
            if index <= #assets then
                local asset = assets[index]
                local drawX = x * tileButtonSize + 5
                local drawY = top + y * tileButtonSize + 5

                ui.color("panel2")
                love.graphics.rectangle("fill", drawX, drawY, tileButtonSize - 2, tileButtonSize - 2, 4, 4)

                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(asset, drawX + 2, drawY + 2, 0, (tileButtonSize - 6) / asset:getWidth(), (tileButtonSize - 6) / asset:getHeight())

                if index == selectedTile and selectedTool == "brush" then
                    ui.color("accent")
                    love.graphics.setLineWidth(2)
                    love.graphics.rectangle("line", drawX, drawY, tileButtonSize - 2, tileButtonSize - 2, 4, 4)
                    love.graphics.setLineWidth(1)
                end
            end
        end
    end

    love.graphics.setScissor()

    local totalRows = math.ceil(#assets / visibleTilesX)
    local visibleRows = visibleTilesY
    if totalRows > visibleRows then
        local scrollBarHeight = (visibleRows / totalRows) * paletteHeight
        local scrollBarY = top + (tileScrollOffset / (totalRows - visibleRows)) * (paletteHeight - scrollBarHeight)
        ui.color("dim")
        love.graphics.rectangle("fill", paletteWidth - 8, scrollBarY, 6, scrollBarHeight, 3, 3)
    end
end

function drawTools()
    local x0 = love.graphics.getWidth() - 100
    ui.color("panel")
    love.graphics.rectangle("fill", x0, 0, 100, love.graphics.getHeight())
    ui.color("border")
    love.graphics.line(x0 + 0.5, 0, x0 + 0.5, love.graphics.getHeight())

    for i, tool in ipairs(tools) do
        local y = (i - 1) * 50
        local active = tool == selectedTool
        if active then
            ui.color("accent")
            love.graphics.rectangle("fill", x0 + 6, y + 5, 88, 40, 6, 6)
        end
        local label = i .. "  " .. tool:sub(1, 1):upper() .. tool:sub(2)
        ui.text(label, "body", active and "onAccent" or "text", x0 + 6, y + 16, 88, "center")
    end
end

local function coordText()
    local mouseX, mouseY = love.mouse.getPosition()
    local tileX = math.floor((mouseX / camera.scale + camera.x) / tileSize)
    local tileY = math.floor((mouseY / camera.scale + camera.y) / tileSize)
    if tileX >= 0 and tileX < gridWidth and tileY >= 0 and tileY < gridHeight and not isOverUi(mouseX, mouseY) then
        return "X " .. (tileX + 1) .. "  Y " .. (tileY + 1)
    end
    return "X -  Y -"
end

function drawHud()
    local W = love.graphics.getWidth() - 100
    love.graphics.setColor(ui.c.panel[1], ui.c.panel[2], ui.c.panel[3], 0.96)
    love.graphics.rectangle("fill", 0, 0, W, hudHeight)
    ui.color("border")
    love.graphics.line(0, hudHeight + 0.5, W, hudHeight + 0.5)

    local title = levelTitle()
    ui.text(title, "body", dirty and "warn" or "text", 12, 8)
    if dirty then
        ui.text("unsaved changes", "small", "warn", 12 + ui.f.body:getWidth(title) + 10, 11)
    end
    local info = ("%s%s   Layer %d/%d   Canvas %dx%d   Zoom %d%%   %s   Format %s"):format(
        selectedTool, selectedTool == "brush" and (" (tile " .. selectedTile .. ")") or "",
        currentLayer, #layers, gridWidth, gridHeight, math.floor(camera.scale * 100 + 0.5),
        coordText(), saveFormats[selectedSaveFormat]:upper())
    ui.text(info, "small", "dim", 0, 11, W - 12, "right")

    ui.text("Esc Menu   P Save   Ctrl+S Quick save   Ctrl+Z/Y Undo/Redo   L Open   F Format   C Canvas size   T Asset pack",
        "small", "dim", 12, 30)
    ui.text("1-5 Tools   Right click Pick tile   N New layer   PgUp/PgDn Switch layer   Del Delete layer   WASD Pan   Wheel Zoom",
        "small", "dim", 12, 44)
end

function applyBrush(x, y)
    if x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
        local row = layers[currentLayer][y] or {}
        layers[currentLayer][y] = row
        if row[x] ~= selectedTile then
            undoHistory:record(layers, currentLayer, x, y)
            row[x] = selectedTile
            setDirty(true)
        end
    end
end

function applyEraser(x, y)
    if x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
        local row = layers[currentLayer][y]
        if row and row[x] then
            undoHistory:record(layers, currentLayer, x, y)
            row[x] = nil
            setDirty(true)
        end
    end
end

function applyBucket(x, y)
    if x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
        local currentLayerData = layers[currentLayer]
        local targetTile = currentLayerData[y] and currentLayerData[y][x] or nil
        if targetTile ~= selectedTile then
            floodFill(x, y, targetTile, selectedTile)
            undoHistory:commit(layers)
            setDirty(true)
        end
    end
end

function floodFill(x, y, targetTile, replacementTile)
    local layerIndex = currentLayer
    levelLib.floodFill(layers[layerIndex], gridWidth, gridHeight, x, y, targetTile, replacementTile, function(px, py)
        undoHistory:record(layers, layerIndex, px, py)
    end)
end

function drawHoveredTile()
    local mouseX, mouseY = love.mouse.getPosition()
    local worldMouseX = mouseX / camera.scale + camera.x
    local worldMouseY = mouseY / camera.scale + camera.y
    local tileX = math.floor(worldMouseX / tileSize)
    local tileY = math.floor(worldMouseY / tileSize)
    
    if tileX >= 0 and tileX < gridWidth and tileY >= 0 and tileY < gridHeight and
       not isOverUi(mouseX, mouseY) then
        love.graphics.setColor(1, 1, 0, 0.3)
        love.graphics.rectangle("fill", 
            tileX * tileSize,
            tileY * tileSize,
            tileSize, tileSize)
    end
end

function drawPreview()
    if startX and startY and previewX and previewY then
        love.graphics.setColor(0, 1, 0, 0.5)
        
        if selectedTool == "line" then
            local positions = getLinePositions(startX, startY, previewX, previewY)
            for _, pos in ipairs(positions) do
                love.graphics.rectangle("fill", 
                    (pos.x - 1) * tileSize,
                    (pos.y - 1) * tileSize,
                    tileSize, tileSize)
            end
        elseif selectedTool == "rectangle" then
            local left = math.min(startX, previewX)
            local right = math.max(startX, previewX)
            local top = math.min(startY, previewY)
            local bottom = math.max(startY, previewY)
            
            for x = left, right do
                love.graphics.rectangle("fill", 
                    (x - 1) * tileSize,
                    (top - 1) * tileSize,
                    tileSize, tileSize)
                love.graphics.rectangle("fill", 
                    (x - 1) * tileSize,
                    (bottom - 1) * tileSize,
                    tileSize, tileSize)
            end
            for y = top, bottom do
                love.graphics.rectangle("fill", 
                    (left - 1) * tileSize,
                    (y - 1) * tileSize,
                    tileSize, tileSize)
                love.graphics.rectangle("fill", 
                    (right - 1) * tileSize,
                    (y - 1) * tileSize,
                    tileSize, tileSize)
            end
        end
    end
end

function getLinePositions(x1, y1, x2, y2)
    return levelLib.linePositions(x1, y1, x2, y2, gridWidth, gridHeight)
end

function drawLine(x1, y1, x2, y2)
    for _, pos in ipairs(getLinePositions(x1, y1, x2, y2)) do
        applyBrush(pos.x, pos.y)
    end
end

function drawRectangle(x1, y1, x2, y2)
    local left = math.max(1, math.min(math.min(x1, x2), gridWidth))
    local right = math.max(1, math.min(math.max(x1, x2), gridWidth))
    local top = math.max(1, math.min(math.min(y1, y2), gridHeight))
    local bottom = math.max(1, math.min(math.max(y1, y2), gridHeight))
    
    for x = left, right do
        applyBrush(x, top)
        applyBrush(x, bottom)
    end
    for y = top, bottom do
        applyBrush(left, y)
        applyBrush(right, y)
    end
end
-- ------------------------------------------------------------------ диалоги
local function dialogRect(w, h)
    local W, H = love.graphics.getDimensions()
    return (W - w) / 2, (H - h) / 2, w, h
end

local function isDoubleClick(which, index)
    local now = love.timer.getTime()
    local double = lastClick.which == which and lastClick.index == index and now - lastClick.t < 0.4
    lastClick = {t = now, which = which, index = index}
    return double
end

-- ---- подтверждение
local function confirmRects()
    local x, y, w, h = dialogRect(500, 190)
    local bw = (w - 24 * 2 - 16) / 2
    return {x, y, w, h}, {x + 24, y + h - 66, bw, 46}, {x + 24 + bw + 16, y + h - 66, bw, 46}
end

local function confirmAnswer(yes)
    local dlg = confirmDlg
    confirmDlg = nil
    if yes then dlg.onYes() end
end

function drawConfirm()
    ui.dim(0.65)
    local box, yes, no = confirmRects()
    ui.panel(unpack(box))
    ui.text(confirmDlg.title, "h", "text", box[1] + 24, box[2] + 20)
    ui.text(confirmDlg.text, "body", "dim", box[1] + 24, box[2] + 58, box[3] - 48)
    ui.button(confirmDlg.yes .. " (Y)", yes[1], yes[2], yes[3], yes[4], confirmDlg.choice == 1, "body")
    ui.button("Cancel (N)", no[1], no[2], no[3], no[4], confirmDlg.choice == 2, "body")
end

local function confirmKey(key)
    if key == "y" then confirmAnswer(true)
    elseif key == "n" or key == "escape" then confirmAnswer(false)
    elseif key == "left" or key == "right" or key == "tab" then confirmDlg.choice = confirmDlg.choice == 1 and 2 or 1
    elseif key == "return" or key == "kpenter" then confirmAnswer(confirmDlg.choice == 1)
    end
end

local function confirmClick(x, y, button)
    if button ~= 1 then return end
    local _, yes, no = confirmRects()
    if ui.hit(x, y, unpack(yes)) then confirmAnswer(true)
    elseif ui.hit(x, y, unpack(no)) then confirmAnswer(false)
    end
end

-- ---- открыть уровень
local OPEN_ROW_H = 30

local function openListRect()
    local x, y, w, h = dialogRect(680, 500)
    return x + 24, y + 100, w - 48
end

function drawOpenDialog()
    ui.dim(0.6)
    local x, y, w, h = dialogRect(680, 500)
    ui.panel(x, y, w, h)
    ui.text("Open level", "h", "text", x + 24, y + 18)
    ui.text(#openList.items .. " saved level" .. (#openList.items == 1 and "" or "s") .. "   -   sorted by " ..
        (openSort == "date" and "date (newest first)" or "name"), "small", "dim", x + 24, y + 52)

    local lx, ly, lw = openListRect()
    ui.text("Name", "small", "dim", lx + 10, ly - 20)
    ui.text("Size", "small", "dim", lx, ly - 20, lw - 190, "right")
    ui.text("Modified", "small", "dim", lx, ly - 20, lw - 30, "right")

    if #openList.items == 0 then
        ui.text("No saved levels yet. Press P in the editor to save one (TXT levels can be opened here).",
            "body", "dim", lx, ly + 40, lw, "center")
    else
        ui.drawList(openList, lx, ly, lw, OPEN_ROW_H, function(e, _, rx, ry, rw, rh, selected)
            local main, dim = selected and "onAccent" or "text", selected and "onAccent" or "dim"
            ui.text(e.name, "body", main, rx + 10, ry + 5, rw - 260)
            ui.text(files.formatSize(e.size), "small", dim, rx, ry + 8, rw - 178, "right")
            ui.text(files.formatDate(e.modtime), "small", dim, rx, ry + 8, rw - 8, "right")
        end)
    end

    ui.text("Up/Down, wheel - browse     Enter - open     Tab - sort by " ..
        (openSort == "date" and "name" or "date") .. "     O - open folder     Esc - cancel", "small", "dim", x + 24, y + h - 62, w - 48)
    ui.text("Folder: " .. settings.levelsPath .. "   (JSON and TMX files are exports and cannot be opened)",
        "small", "dim", x + 24, y + h - 40, w - 48)
end

-- Открывает папку с уровнями в файловом менеджере системы
local function openLevelsFolder()
    local dir = projectDir()
    local path
    if dir then
        path = dir .. "/" .. settings.levelsPath
        ensureDirectory(path)
    else
        love.filesystem.createDirectory(settings.levelsPath)
        path = love.filesystem.getSaveDirectory() .. "/" .. settings.levelsPath
    end
    path = path:gsub("\\", "/")
    if not path:match("^/") then path = "/" .. path end  -- Windows: C:/... -> file:///C:/...
    if love.system.openURL("file://" .. path) then
        ui.toast("Opened the levels folder", "info", 1.5)
    else
        ui.toast("Could not open the levels folder: " .. path, "err", 4)
    end
end

local function openSelected()
    local entry = openList:current()
    if not entry then return end
    local function go()
        local ok, err = loadLevel(entry.name)
        if ok then
            modal = nil
            ui.toast("Opened " .. entry.name .. ".txt" .. (err and (" - " .. err) or ""), err and "warn" or "ok", err and 4 or nil)
        else
            ui.toast("Could not open " .. entry.name .. ".txt: " .. tostring(err), "err", 4)
        end
    end
    if hasWork and dirty then
        askConfirm("Open \"" .. entry.name .. "\"?", "Unsaved changes in \"" .. levelTitle() .. "\" will be lost.",
            "Discard and open", go)
    else
        go()
    end
end

local function openKey(key)
    if key == "escape" then modal = nil
    elseif key == "o" then openLevelsFolder()
    elseif key == "up" then openList:move(-1)
    elseif key == "down" then openList:move(1)
    elseif key == "pageup" then openList:page(-1)
    elseif key == "pagedown" then openList:page(1)
    elseif key == "home" then openList:home()
    elseif key == "end" then openList:last()
    elseif key == "tab" then
        openSort = openSort == "date" and "name" or "date"
        local current = openList:current()
        refreshOpenList()
        if current then
            for i, e in ipairs(openList.items) do
                if e.name == current.name then openList:select(i) break end
            end
        end
    elseif key == "return" or key == "kpenter" then openSelected()
    end
end

local function openClick(x, y, button)
    if button ~= 1 then return end
    local lx, ly, lw = openListRect()
    if x >= lx and x < lx + lw then
        local index = openList:rowAt(y - ly, OPEN_ROW_H)
        if index then
            openList:select(index)
            if isDoubleClick("open", index) then openSelected() end
        end
    end
end

-- ---- сохранить уровень
local SAVE_ROW_H = 28

local function saveLayout()
    local x, y, w, h = dialogRect(680, 540)
    local tabs = {}
    for i = 1, #saveFormats do tabs[i] = {x + 24 + (i - 1) * 98, y + 152, 90, 34} end
    return x, y, w, h, tabs, x + 24, y + 238, w - 48
end

local function refreshSaveList()
    local entries = listLevels(saveFormats[selectedSaveFormat])
    files.sortEntries(entries, "date")
    saveList:setItems(entries, 0)
end

local function openSaveDialog()
    modal = "save"
    saveName = currentName or ""
    ignoreTextInput = true
    refreshSaveList()
end

local function setSaveFormat(i)
    selectedSaveFormat = (i - 1) % #saveFormats + 1
    refreshSaveList()
end

function drawSaveDialog()
    ui.dim(0.6)
    local x, y, w, h, tabs, lx, ly, lw = saveLayout()
    ui.panel(x, y, w, h)
    ui.text("Save level", "h", "text", x + 24, y + 18)

    ui.text("Name", "small", "dim", x + 24, y + 58)
    ui.color("bg")
    love.graphics.rectangle("fill", x + 24, y + 78, w - 48, 40, 6, 6)
    ui.color("accent")
    love.graphics.rectangle("line", x + 24.5, y + 78.5, w - 49, 39, 6, 6)
    local caret = (math.floor(love.timer.getTime() * 2) % 2 == 0) and "|" or ""
    local fmt = saveFormats[selectedSaveFormat]
    ui.text(saveName .. caret, "body", "text", x + 36, y + 89, w - 140)
    ui.text("." .. fmt, "body", "dim", x + 24, y + 89, w - 60, "right")

    ui.text("Format", "small", "dim", x + 24, y + 132)
    for i, name in ipairs(saveFormats) do
        local t = tabs[i]
        ui.button(name:upper(), t[1], t[2], t[3], t[4], i == selectedSaveFormat, "body")
    end
    ui.text(fmt == "txt" and "Can be opened again in Levelarium."
        or (fmt == "tmx" and "Export only - for Tiled." or "Export only."),
        "small", "dim", x + 24 + #saveFormats * 98 + 8, y + 162)

    ui.text("Existing ." .. fmt .. " files (" .. #saveList.items .. ") - pick one to overwrite it", "small", "dim", lx, ly - 22)
    if #saveList.items == 0 then
        ui.text("Nothing saved in this format yet.", "body", "dim", lx, ly + 60, lw, "center")
    else
        local typed = (files.cleanName(saveName) or ""):lower()
        ui.drawList(saveList, lx, ly, lw, SAVE_ROW_H, function(e, _, rx, ry, rw, rh, selected)
            local main, dim = selected and "onAccent" or "text", selected and "onAccent" or "dim"
            ui.text(e.name, "body", main, rx + 10, ry + 4, rw - 260)
            ui.text(files.formatSize(e.size), "small", dim, rx, ry + 7, rw - 178, "right")
            ui.text(files.formatDate(e.modtime), "small", dim, rx, ry + 7, rw - 8, "right")
        end, function(e) return e.name:lower() == typed end)
    end

    ui.text("Enter - save     Tab - format     Up/Down, wheel - pick a file     Esc - cancel",
        "small", "dim", x + 24, y + h - 40, w - 48)
end

local function commitSave(name)
    local ok, result = saveLevel(name)
    local fmt = saveFormats[selectedSaveFormat]
    if ok then
        modal = nil
        ui.toast("Saved " .. name .. "." .. fmt .. " (" .. files.formatSize(result) .. ")", "ok")
    else
        ui.toast("Could not save: " .. result, "err", 4.5)
    end
end

local function trySave()
    local name = files.cleanName(saveName)
    if not name then
        ui.toast("Enter a level name (letters, digits, space, _ and -)", "err")
        return
    end
    local fmt = saveFormats[selectedSaveFormat]
    if files.exists(listLevels(fmt), name) then
        askConfirm("Overwrite " .. name .. "." .. fmt .. "?", "A file with this name already exists and will be replaced.",
            "Overwrite", function() commitSave(name) end)
    else
        commitSave(name)
    end
end

local function saveKey(key)
    if key == "escape" then modal = nil
    elseif key == "return" or key == "kpenter" then trySave()
    elseif key == "backspace" then saveName = saveName:sub(1, -2)
    elseif key == "tab" or key == "right" then setSaveFormat(selectedSaveFormat + 1)
    elseif key == "left" then setSaveFormat(selectedSaveFormat - 1)
    elseif key == "up" or key == "down" or key == "pageup" or key == "pagedown" then
        if key == "up" then saveList:move(-1)
        elseif key == "down" then saveList:move(1)
        else saveList:page(key == "pageup" and -1 or 1) end
        local entry = saveList:current()
        if entry then saveName = entry.name end
    end
end

local function saveClick(x, y, button)
    if button ~= 1 then return end
    local _, _, _, _, tabs, lx, ly, lw = saveLayout()
    for i, t in ipairs(tabs) do
        if ui.hit(x, y, unpack(t)) then setSaveFormat(i) return end
    end
    if x >= lx and x < lx + lw then
        local index = saveList:rowAt(y - ly, SAVE_ROW_H)
        if index then
            saveList:select(index)
            saveName = saveList:current().name
            if isDoubleClick("save", index) then trySave() end
        end
    end
end

-- ---- набор тайлов
local ASSET_ROW_H = 28

local function assetLayout()
    local rows = assetList.rows
    local x, y, w, h = dialogRect(460, 120 + rows * ASSET_ROW_H + 30)
    return x, y, w, h, x + 24, y + 70, w - 48
end

local function openAssetDialog()
    modal = "assets"
    assetList.rows = math.max(1, math.min(9, #availableAssetPacks))
    assetList:setItems(availableAssetPacks, selectedAssetPackIndex)
end

function drawAssetPackSelector()
    ui.dim(0.6)
    local x, y, w, h, lx, ly, lw = assetLayout()
    ui.panel(x, y, w, h)
    ui.text("Asset pack", "h", "text", x + 24, y + 18)
    ui.text(#availableAssetPacks .. " available   -   current: " .. settings.currentAssetPack, "small", "dim", x + 24, y + 48)
    ui.drawList(assetList, lx, ly, lw, ASSET_ROW_H, function(pack, _, rx, ry, rw, rh, selected)
        ui.text(pack .. (pack == settings.currentAssetPack and "  (current)" or ""), "body",
            selected and "onAccent" or "text", rx + 10, ry + 4, rw - 20)
    end)
    ui.text("Up/Down, wheel - browse     Enter - choose     Esc - cancel",
        "small", "dim", x + 24, y + h - 36, w - 48)
end

local function assetKey(key)
    if key == "escape" then modal = nil
    elseif key == "up" then assetList:move(-1)
    elseif key == "down" then assetList:move(1)
    elseif key == "pageup" then assetList:page(-1)
    elseif key == "pagedown" then assetList:page(1)
    elseif key == "return" or key == "kpenter" then
        if assetList.selected >= 1 then
            switchAssetPack(assetList.selected)
            ui.toast("Asset pack: " .. settings.currentAssetPack, "ok")
        end
        modal = nil
    end
end

local function assetClick(x, y, button)
    if button ~= 1 then return end
    local _, _, _, _, lx, ly, lw = assetLayout()
    if x >= lx and x < lx + lw then
        local index = assetList:rowAt(y - ly, ASSET_ROW_H)
        if index then
            assetList:select(index)
            if isDoubleClick("assets", index) then assetKey("return") end
        end
    end
end

-- ---- размер холста (геометрия полей прежняя: 400x250, поля Width/Height)
function drawCanvasSettings()
    ui.dim(0.6)
    local boxX, boxY, boxWidth, boxHeight = dialogRect(400, 250)
    ui.panel(boxX, boxY, boxWidth, boxHeight)

    ui.text("Canvas size", "h", "text", boxX, boxY + 14, boxWidth, "center")
    ui.text("Current: " .. gridWidth .. "x" .. gridHeight .. "   (1-" .. settings.maxGridSize .. ")", "small", "dim", boxX, boxY + 46, boxWidth, "center")

    ui.text("Width:", "body", "text", boxX + 20, boxY + 80, 100, "left")
    ui.text("Height:", "body", "text", boxX + 20, boxY + 110, 100, "left")

    for field = 1, 2 do
        local fy = boxY + (field == 1 and 75 or 105)
        ui.color(activeCanvasField == field and "panel2" or "bg")
        love.graphics.rectangle("fill", boxX + 120, fy, 100, 26, 5, 5)
        ui.color(activeCanvasField == field and "accent" or "border")
        love.graphics.rectangle("line", boxX + 120.5, fy + 0.5, 99, 25, 5, 5)
        local value = field == 1 and canvasWidthInput or canvasHeightInput
        ui.text(value .. (activeCanvasField == field and "|" or ""), "body", "text", boxX + 128, fy + 4, 90, "left")
    end

    ui.text("Up/Down or Tab - switch field", "small", "dim", boxX, boxY + 160, boxWidth, "center")
    ui.text("Enter - apply     Esc - cancel", "small", "dim", boxX, boxY + 185, boxWidth, "center")
    ui.text("Tiles outside a smaller canvas are removed.", "small", "dim", boxX, boxY + 210, boxWidth, "center")
end

-- ------------------------------------------------------------------ ввод
function love.wheelmoved(x, y)
    if confirmDlg then return end
    if modal == "open" then openList:scroll(y)
    elseif modal == "save" then saveList:scroll(y)
    elseif modal == "assets" then assetList:scroll(y)
    elseif editorActive() then
        if love.mouse.getY() > love.graphics.getHeight() - paletteHeight then
            local totalRows = math.ceil(#assets / visibleTilesX)
            local maxScroll = math.max(0, totalRows - visibleTilesY)
            tileScrollOffset = math.max(0, math.min(tileScrollOffset - y, maxScroll))
        else
            local mouseX = love.mouse.getX() / camera.scale + camera.x
            local mouseY = love.mouse.getY() / camera.scale + camera.y

            if y > 0 then
                camera.scale = math.min(camera.scale * 1.1, camera.maxScale)
            elseif y < 0 then
                camera.scale = math.max(camera.scale / 1.1, camera.minScale)
            end

            camera.x = mouseX - love.mouse.getX() / camera.scale
            camera.y = mouseY - love.mouse.getY() / camera.scale
        end
    end
end

local function menuKey(key)
    local items = menuItems()
    if key == "up" then
        menuIndex = (menuIndex - 2) % #items + 1
    elseif key == "down" then
        menuIndex = menuIndex % #items + 1
    elseif key == "return" or key == "kpenter" or key == "space" then
        activateMenu(items[menuIndex].id)
    elseif key == "escape" then
        if hasWork then showMenu = false else love.event.quit() end
    elseif key == "u" then
        openUpdatePage()
    end
end

local function canvasKey(key)
    if key == "return" or key == "kpenter" then
        local newWidth = tonumber(canvasWidthInput)
        local newHeight = tonumber(canvasHeightInput)
        local maxSize = settings.maxGridSize
        if newWidth and newHeight and newWidth > 0 and newHeight > 0
            and newWidth <= maxSize and newHeight <= maxSize then
            if newWidth ~= gridWidth or newHeight ~= gridHeight then
                resizeCanvas(newWidth, newHeight)
                setDirty(true)
                ui.toast("Canvas size: " .. newWidth .. "x" .. newHeight, "ok")
            end
            modal = nil
            activeCanvasField = 1
        else
            ui.toast("Width and height must be numbers from 1 to " .. maxSize, "err")
        end
    elseif key == "escape" then
        modal = nil
        canvasWidthInput = tostring(gridWidth)
        canvasHeightInput = tostring(gridHeight)
        activeCanvasField = 1
    elseif key == "backspace" then
        if activeCanvasField == 1 then
            canvasWidthInput = canvasWidthInput:sub(1, -2)
        else
            canvasHeightInput = canvasHeightInput:sub(1, -2)
        end
    elseif key == "tab" or key == "up" or key == "down" then
        activeCanvasField = activeCanvasField == 1 and 2 or 1
    end
end

local function afterHistoryStep(layerIndex, verb)
    if not layerIndex then
        ui.toast("Nothing to " .. verb, "info", 1.2)
        return
    end
    if layerIndex <= #layers then currentLayer = layerIndex end
    startX, startY = nil, nil
    setDirty(true)
    ui.toast((verb == "undo" and "Undo" or "Redo") .. "  -  available: undo " .. #undoHistory.undoStack ..
        ", redo " .. #undoHistory.redoStack, "info", 1.5)
end

function doUndo()
    afterHistoryStep(undoHistory:undo(layers), "undo")
end

function doRedo()
    afterHistoryStep(undoHistory:redo(layers), "redo")
end

local function editorKey(key)
    local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
    if ctrl and key == "s" then
        ignoreTextInput = true
        if currentName then
            local ok, result = saveLevel(currentName)
            local fmt = saveFormats[selectedSaveFormat]
            if ok then
                ui.toast("Saved " .. currentName .. "." .. fmt .. " (" .. files.formatSize(result) .. ")", "ok")
            else
                ui.toast("Could not save: " .. result, "err", 4.5)
            end
        else
            openSaveDialog()
        end
    elseif ctrl and key == "z" then
        if love.keyboard.isDown("lshift", "rshift") then doRedo() else doUndo() end
    elseif ctrl and key == "y" then
        doRedo()
    elseif ctrl then
        return
    elseif key == "p" then openSaveDialog()
    elseif key == "l" then openOpenDialog()
    elseif key == "escape" then backToMenu()  -- уровень остаётся в памяти: в меню есть "Continue"
    elseif key == "t" then openAssetDialog()
    elseif key == "1" then selectedTool = "brush"
    elseif key == "2" then selectedTool = "eraser"
    elseif key == "3" then selectedTool = "bucket"
    elseif key == "4" then selectedTool = "line"
    elseif key == "5" then selectedTool = "rectangle"
    elseif key == "n" then
        if createNewLayer() then
            setDirty(true)
        else
            ui.toast("Maximum of " .. maxLayers .. " layers", "warn")
        end
    elseif key == "pageup" then switchLayer(currentLayer + 1)
    elseif key == "pagedown" then switchLayer(currentLayer - 1)
    elseif key == "delete" then
        if deleteCurrentLayer() then
            setDirty(true)
        else
            ui.toast("The only layer can't be deleted", "warn")
        end
    elseif key == "f" then
        selectedSaveFormat = selectedSaveFormat % #saveFormats + 1
        ui.toast("Save format: " .. saveFormats[selectedSaveFormat]:upper(), "info")
    elseif key == "c" then
        canvasWidthInput = tostring(gridWidth)
        canvasHeightInput = tostring(gridHeight)
        activeCanvasField = 1
        ignoreTextInput = true
        modal = "canvas"
    end
end

function love.keypressed(key)
    if confirmDlg then ignoreTextInput = true; confirmKey(key)
    elseif modal == "open" then openKey(key)
    elseif modal == "save" then saveKey(key)
    elseif modal == "assets" then assetKey(key)
    elseif modal == "canvas" then canvasKey(key)
    elseif showMenu then menuKey(key)
    else editorKey(key)
    end
end

local function editorMousePressed(x, y, button)
    if button == 2 then
        pickTile(x, y)  -- ПКМ: пипетка
        return
    elseif button ~= 1 then
        return  -- остальные кнопки мыши ничего не рисуют
    end

    if y > love.graphics.getHeight() - paletteHeight and x < love.graphics.getWidth() - 100 then
        local tileX = math.floor((x - 5) / tileButtonSize)
        local tileY = math.floor((y - (love.graphics.getHeight() - paletteHeight) - 5) / tileButtonSize)
        -- клик мимо отрисованных ячеек (отступ слева, правый край, третий "ряд") не выбирает тайл
        if tileX >= 0 and tileX < visibleTilesX and tileY >= 0 and tileY < visibleTilesY then
            local index = (tileScrollOffset + tileY) * visibleTilesX + tileX + 1
            if index >= 1 and index <= #assets then
                selectedTile = index
                selectedTool = "brush"
            end
        end
    elseif x > love.graphics.getWidth() - 100 then
        local toolIndex = math.floor(y / 50) + 1
        if toolIndex >= 1 and toolIndex <= #tools then
            selectedTool = tools[toolIndex]
        end
    elseif y < hudHeight then
        return  -- верхняя панель: сквозь неё не рисуем
    else
        local worldX = x / camera.scale + camera.x
        local worldY = y / camera.scale + camera.y
        local tileX = math.floor(worldX / tileSize) + 1
        local tileY = math.floor(worldY / tileSize) + 1

        if tileX >= 1 and tileX <= gridWidth and tileY >= 1 and tileY <= gridHeight then
            if selectedTool == "brush" then
                applyBrush(tileX, tileY)
                strokeX, strokeY = tileX, tileY
            elseif selectedTool == "eraser" then
                applyEraser(tileX, tileY)
                strokeX, strokeY = tileX, tileY
            elseif selectedTool == "bucket" then
                applyBucket(tileX, tileY)
            elseif selectedTool == "line" then
                startX, startY = tileX, tileY
            elseif selectedTool == "rectangle" then
                startX, startY = tileX, tileY
            end
        end
    end
end

function love.mousepressed(x, y, button)
    if confirmDlg then
        confirmClick(x, y, button)
    elseif modal == "open" then openClick(x, y, button)
    elseif modal == "save" then saveClick(x, y, button)
    elseif modal == "assets" then assetClick(x, y, button)
    elseif modal == "canvas" then
        -- Обработка кликов мыши в диалоге размера холста
        local boxX = love.graphics.getWidth() / 2 - 200
        local boxY = love.graphics.getHeight() / 2 - 125
        if x >= boxX + 120 and x <= boxX + 220 and y >= boxY + 75 and y <= boxY + 101 then
            activeCanvasField = 1
        elseif x >= boxX + 120 and x <= boxX + 220 and y >= boxY + 105 and y <= boxY + 131 then
            activeCanvasField = 2
        end
    elseif showMenu then
        if button ~= 1 then return end
        if updateRect and ui.hit(x, y, updateRect.x, updateRect.y, updateRect.w, updateRect.h) then
            openUpdatePage()
            return
        end
        for i, item in ipairs(menuItems()) do
            if ui.hit(x, y, menuRect(i)) then
                menuIndex = i
                activateMenu(item.id)
                return
            end
        end
    else
        editorMousePressed(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if showMenu and not modal and not confirmDlg then
        for i = 1, #menuItems() do
            if ui.hit(x, y, menuRect(i)) then menuIndex = i end
        end
    elseif editorActive() then
        local worldX = x / camera.scale + camera.x
        local worldY = y / camera.scale + camera.y
        local tileX = math.floor(worldX / tileSize) + 1
        local tileY = math.floor(worldY / tileSize) + 1

        if tileX >= 1 and tileX <= gridWidth and tileY >= 1 and tileY <= gridHeight and not isOverUi(x, y) then
            previewX, previewY = tileX, tileY

            if love.mouse.isDown(1) and (selectedTool == "brush" or selectedTool == "eraser") then
                -- между кадрами мышь перескакивает через клетки: закрашиваем всю линию от прошлой клетки мазка
                local apply = selectedTool == "brush" and applyBrush or applyEraser
                if strokeX then
                    for _, pos in ipairs(levelLib.linePositions(strokeX, strokeY, tileX, tileY, gridWidth, gridHeight)) do
                        apply(pos.x, pos.y)
                    end
                else
                    apply(tileX, tileY)
                end
                strokeX, strokeY = tileX, tileY
            end
        else
            previewX, previewY = nil, nil
            strokeX, strokeY = nil, nil
        end
    end
end

function love.mousereleased(x, y, button)
    if button ~= 1 then return end
    strokeX, strokeY = nil, nil
    if editorActive() then
        local tileX = math.floor((x / camera.scale + camera.x) / tileSize) + 1
        local tileY = math.floor((y / camera.scale + camera.y) / tileSize) + 1

        tileX = math.max(1, math.min(tileX, gridWidth))
        tileY = math.max(1, math.min(tileY, gridHeight))

        if selectedTool == "line" and startX and startY then
            drawLine(startX, startY, tileX, tileY)
            startX, startY = nil, nil
        elseif selectedTool == "rectangle" and startX and startY then
            drawRectangle(startX, startY, tileX, tileY)
            startX, startY = nil, nil
        end

        if selectedTool ~= "line" and selectedTool ~= "rectangle" then
            startX, startY = nil, nil
        end
    end
    undoHistory:commit(layers)  -- мазок / линия / прямоугольник закончены: один шаг истории
end

function love.textinput(text)
    if ignoreTextInput or confirmDlg then return end
    if modal == "save" then
        if text:match("^[%w%s_%-]+$") and #saveName + #text <= 64 then
            saveName = saveName .. text
        end
    elseif modal == "canvas" then
        if text:match("^%d+$") then
            if activeCanvasField == 1 and #canvasWidthInput + #text <= 4 then
                canvasWidthInput = canvasWidthInput .. text
            elseif activeCanvasField == 2 and #canvasHeightInput + #text <= 4 then
                canvasHeightInput = canvasHeightInput .. text
            end
        end
    end
end

