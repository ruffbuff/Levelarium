local settings = require("scripts.settings")

local assets = {}
local tileSize = settings.tileSize
local gridWidth = settings.gridWidth
local gridHeight = settings.gridHeight
local canvas = {width = gridWidth * tileSize, height = gridHeight * tileSize}
local selectedTile = 1
local showMenu = true
local isErasing = false
local layers = {}
local currentLayer = 1
local maxLayers = 5  -- Максимальное количество слоев

local tileScrollOffset = 0
local visibleTilesX = 18
local visibleTilesY = 2
local tileButtonSize = 48
local paletteHeight = 120

local tools = {"brush", "eraser", "bucket", "line", "rectangle"}
local selectedTool = "brush"
local startX, startY = nil, nil
local previewX, previewY = nil, nil

local availableAssetPacks = {}
local selectedAssetPackIndex = 1
local showAssetPackSelector = false

local showLevelNameInput = false
local showLevelSelector = false
local levelNameInput = ""
local availableLevels = {}
local selectedLevelIndex = 1

local camera = {
    x = 0, y = 0, scale = 1,
    minScale = 0.1, maxScale = 2
}

function love.load()
    love.window.setMode(1024, 768, {resizable=false, vsync=true})
    love.window.setTitle(settings.getWindowTitle())
    availableAssetPacks = settings.getAvailableAssetPacks()
    
    for i, pack in ipairs(availableAssetPacks) do
        if pack == settings.currentAssetPack then
            selectedAssetPackIndex = i
            break
        end
    end
    
    loadAssets()
    createNewLayer()  -- Создаем первый слой при запуске
end

function love.update(dt)
    if not showMenu and not showAssetPackSelector and not showLevelNameInput and not showLevelSelector then
        updateCamera(dt)
    end
end

function updateCamera(dt)
    local speed = 500 * dt / camera.scale
    if love.keyboard.isDown("w") then camera.y = camera.y - speed end
    if love.keyboard.isDown("s") then camera.y = camera.y + speed end
    if love.keyboard.isDown("a") then camera.x = camera.x - speed end
    if love.keyboard.isDown("d") then camera.x = camera.x + speed end
end

function loadAssets()
    assets = {}
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
        return numA < numB
    end)
    
    for _, filename in ipairs(imageFiles) do
        local path = packPath .. filename
        local success, image = pcall(love.graphics.newImage, path)
        if success then
            table.insert(assets, image)
            print("Loaded asset: " .. filename .. " from pack: " .. settings.currentAssetPack)
        else
            print("Failed to load asset: " .. filename)
        end
    end
    
    print("Total assets loaded: " .. #assets .. " from pack: " .. settings.currentAssetPack)
end

function createNewLayer()
    if #layers < maxLayers then
        table.insert(layers, {})
        currentLayer = #layers
        print("Создан новый слой " .. currentLayer)
    else
        print("Достигнуто максимальное количество слоев")
    end
end

function switchLayer(layerNum)
    if layerNum >= 1 and layerNum <= #layers then
        currentLayer = layerNum
        print("Переключено на слой " .. currentLayer)
    else
        print("Неверный номер слоя")
    end
end

function deleteCurrentLayer()
    if #layers > 1 then
        table.remove(layers, currentLayer)
        currentLayer = math.min(currentLayer, #layers)
        print("Удален слой. Текущий слой: " .. currentLayer)
    else
        print("Нельзя удалить единственный слой")
    end
end

function switchAssetPack(packIndex)
    if packIndex >= 1 and packIndex <= #availableAssetPacks then
        selectedAssetPackIndex = packIndex
        settings.currentAssetPack = availableAssetPacks[packIndex]
        print("Switched to asset pack: " .. settings.currentAssetPack)
        loadAssets()
        selectedTile = math.min(selectedTile, #assets)
    end
end

function isInsidePaletteArea(x, y)
    local paletteHeight = 100
    local paletteWidth = love.graphics.getWidth() - 100
    return y > love.graphics.getHeight() - paletteHeight and x < paletteWidth
end

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
        drawInfo()
        drawCoordinates()
        
        if showAssetPackSelector then
            drawAssetPackSelector()
        elseif showLevelNameInput then
            drawLevelNameInput()
        elseif showLevelSelector then
            drawLevelSelector()
        end
    end
end

function drawMenu()
    love.graphics.printf(settings.getFullTitle(), 0, 300, love.graphics.getWidth(), "center")
    love.graphics.printf("Press Enter to start", 0, 350, love.graphics.getWidth(), "center")
    love.graphics.printf("by " .. settings.AUTHOR, 0, 380, love.graphics.getWidth(), "center")
end

function drawGrid()
    local startX = math.max(0, math.floor(camera.x / tileSize))
    local startY = math.max(0, math.floor(camera.y / tileSize))
    local endX = math.min(gridWidth - 1, math.ceil((camera.x + love.graphics.getWidth() / camera.scale) / tileSize))
    local endY = math.min(gridHeight - 1, math.ceil((camera.y + love.graphics.getHeight() / camera.scale) / tileSize))

    love.graphics.setColor(0.8, 0.8, 0.8, 0.5)
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
    
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", 0, love.graphics.getHeight() - paletteHeight, paletteWidth, paletteHeight)
    
    love.graphics.setScissor(0, love.graphics.getHeight() - paletteHeight, paletteWidth, paletteHeight)
    
    local startIndex = tileScrollOffset * visibleTilesX + 1
    for y = 0, visibleTilesY - 1 do
        for x = 0, visibleTilesX - 1 do
            local index = startIndex + y * visibleTilesX + x
            if index <= #assets then
                local asset = assets[index]
                local drawX = x * tileButtonSize + 5
                local drawY = love.graphics.getHeight() - paletteHeight + y * tileButtonSize + 5
                
                love.graphics.setColor(0.3, 0.3, 0.3)
                love.graphics.rectangle("fill", drawX, drawY, tileButtonSize, tileButtonSize)
                
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(asset, drawX + 2, drawY + 2, 0, (tileButtonSize - 4) / asset:getWidth(), (tileButtonSize - 4) / asset:getHeight())
                
                if index == selectedTile and selectedTool == "brush" then
                    love.graphics.setColor(1, 1, 0)
                    love.graphics.rectangle("line", drawX, drawY, tileButtonSize, tileButtonSize)
                end
            end
        end
    end

    love.graphics.setScissor()

    local totalRows = math.ceil(#assets / visibleTilesX)
    local visibleRows = visibleTilesY
    if totalRows > visibleRows then
        local scrollBarHeight = (visibleRows / totalRows) * paletteHeight
        local scrollBarY = love.graphics.getHeight() - paletteHeight + (tileScrollOffset / (totalRows - visibleRows)) * (paletteHeight - scrollBarHeight)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.rectangle("fill", paletteWidth - 10, scrollBarY, 10, scrollBarHeight)
    end
end

function drawTools()
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", love.graphics.getWidth() - 100, 0, 100, love.graphics.getHeight())

    for i, tool in ipairs(tools) do
        local y = (i - 1) * 50 + 10
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(tool, love.graphics.getWidth() - 90, y)
        if tool == selectedTool then
            love.graphics.setColor(1, 1, 0)
            love.graphics.rectangle("line", love.graphics.getWidth() - 100, y - 5, 100, 45)
        end
    end
end

function drawInfo()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Current tool: " .. selectedTool .. (selectedTool == "brush" and " (Tile " .. selectedTile .. ")" or ""), 10, 10)
    love.graphics.print("P - Save, L - Load", 10, 30)
    love.graphics.print("ESC - Back to menu", 10, 50)
    love.graphics.print("Current Layer: " .. currentLayer .. "/" .. #layers, 10, 90)
    love.graphics.print("N - New Layer, PgUp/PgDn - Switch Layer, Del - Delete Layer", 10, 110)
    love.graphics.print("Asset Pack: " .. settings.currentAssetPack .. " (T - Toggle)", 10, 130)
    love.graphics.print("Assets: " .. #assets, 10, 150)
end

function love.wheelmoved(x, y)
    if not showMenu and not showAssetPackSelector and not showLevelNameInput and not showLevelSelector then
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

function love.keypressed(key)
    if showMenu and key == "return" then
        showMenu = false
        layers = {}
        createNewLayer()
    elseif not showMenu then
        if showAssetPackSelector then
            if key == "up" then
                selectedAssetPackIndex = math.max(1, selectedAssetPackIndex - 1)
            elseif key == "down" then
                selectedAssetPackIndex = math.min(#availableAssetPacks, selectedAssetPackIndex + 1)
            elseif key == "return" then
                switchAssetPack(selectedAssetPackIndex)
                showAssetPackSelector = false
            elseif key == "escape" then
                showAssetPackSelector = false
            end
        elseif showLevelNameInput then
            if key == "return" then
                if levelNameInput ~= "" then
                    saveLevel(levelNameInput)
                    showLevelNameInput = false
                    levelNameInput = ""
                end
            elseif key == "escape" then
                showLevelNameInput = false
                levelNameInput = ""
            elseif key == "backspace" then
                levelNameInput = levelNameInput:sub(1, -2)
            end
        elseif showLevelSelector then
            if key == "up" then
                selectedLevelIndex = math.max(1, selectedLevelIndex - 1)
            elseif key == "down" then
                selectedLevelIndex = math.min(#availableLevels, selectedLevelIndex + 1)
            elseif key == "return" then
                if #availableLevels > 0 then
                    loadLevel(availableLevels[selectedLevelIndex])
                    showLevelSelector = false
                end
            elseif key == "escape" then
                showLevelSelector = false
            end
        else
            if key == "p" then saveLevel()
            elseif key == "l" then loadLevel()
            elseif key == "escape" then showMenu = true
            elseif key == "t" then showAssetPackSelector = true
            elseif key == "1" then selectedTool = "brush"
            elseif key == "2" then selectedTool = "eraser"
            elseif key == "3" then selectedTool = "bucket"
            elseif key == "4" then selectedTool = "line"
            elseif key == "5" then selectedTool = "rectangle"
            elseif key == "n" then createNewLayer()
            elseif key == "pageup" then switchLayer(currentLayer + 1)
            elseif key == "pagedown" then switchLayer(currentLayer - 1)
            elseif key == "delete" then deleteCurrentLayer()
            end
        end
    end
end

function love.mousepressed(x, y, button)
    if not showMenu and not showAssetPackSelector and not showLevelNameInput and not showLevelSelector then
        if y > love.graphics.getHeight() - paletteHeight and x < love.graphics.getWidth() - 100 then
            local tileX = math.floor((x - 5) / tileButtonSize)
            local tileY = math.floor((y - (love.graphics.getHeight() - paletteHeight) - 5) / tileButtonSize)
            local index = (tileScrollOffset + tileY) * visibleTilesX + tileX + 1
            if index <= #assets then
                selectedTile = index
                selectedTool = "brush"
            end
        elseif x > love.graphics.getWidth() - 100 then
            local toolIndex = math.floor(y / 50) + 1
            if toolIndex >= 1 and toolIndex <= #tools then
                selectedTool = tools[toolIndex]
            end
        else
            local worldX = x / camera.scale + camera.x
            local worldY = y / camera.scale + camera.y
            local tileX = math.floor(worldX / tileSize) + 1
            local tileY = math.floor(worldY / tileSize) + 1

            if tileX >= 1 and tileX <= gridWidth and tileY >= 1 and tileY <= gridHeight then
                if selectedTool == "brush" then
                    applyBrush(tileX, tileY)
                elseif selectedTool == "eraser" then
                    applyEraser(tileX, tileY)
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
end

function love.mousemoved(x, y, dx, dy, istouch)
    if not showMenu and not showAssetPackSelector and not showLevelNameInput and not showLevelSelector then
        local worldX = x / camera.scale + camera.x
        local worldY = y / camera.scale + camera.y
        local tileX = math.floor(worldX / tileSize) + 1
        local tileY = math.floor(worldY / tileSize) + 1
        
        if tileX >= 1 and tileX <= gridWidth and tileY >= 1 and tileY <= gridHeight then
            previewX, previewY = tileX, tileY
            
            if love.mouse.isDown(1) then
                if selectedTool == "brush" then
                    applyBrush(tileX, tileY)
                elseif selectedTool == "eraser" then
                    applyEraser(tileX, tileY)
                end
            end
        else
            previewX, previewY = nil, nil
        end
    end
end

function love.mousereleased(x, y, button)
    if not showMenu and not showAssetPackSelector and not showLevelNameInput and not showLevelSelector then
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
end

function love.textinput(text)
    if showLevelNameInput then
        if text:match("[%w%s_%-]") then
            levelNameInput = levelNameInput .. text
        end
    end
end

function saveLevel(levelName)
    if not levelName or levelName == "" then
        showLevelNameInput = true
        levelNameInput = ""
        return
    end
    
    if not love.filesystem.getInfo(settings.levelsPath) then
        love.filesystem.createDirectory(settings.levelsPath)
    end
    
    local data = gridWidth .. "," .. gridHeight .. "," .. #layers .. "\n"
    for layerIndex, layer in ipairs(layers) do
        for y = 1, gridHeight do
            for x = 1, gridWidth do
                local tileValue = layer[y] and layer[y][x] or 0
                data = data .. tileValue
                if x < gridWidth then
                    data = data .. ","
                end
            end
            data = data .. "\n"
        end
        data = data .. "---\n"
    end
    
    local filename = settings.levelsPath .. levelName .. ".txt"
    local success = love.filesystem.write(filename, data)
    if success then
        print("Level saved as: " .. levelName)
    else
        print("Failed to save level: " .. levelName)
    end
end

function loadLevel(levelName)
    if not levelName then
        showLevelSelector = true
        updateAvailableLevels()
        return
    end
    
    local filename = settings.levelsPath .. levelName .. ".txt"
    local data = love.filesystem.read(filename)
    
    if data then
        local lines = {}
        for line in data:gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        
        local dimensions = lines[1]:gmatch("[^,]+")
        gridWidth = tonumber(dimensions())
        gridHeight = tonumber(dimensions())
        local layerCount = tonumber(dimensions())
        canvas.width = gridWidth * tileSize
        canvas.height = gridHeight * tileSize
        
        layers = {}
        local currentLayerData = {}
        local layerIndex = 1
        
        for i = 2, #lines do
            if lines[i] == "---" then
                table.insert(layers, currentLayerData)
                currentLayerData = {}
                layerIndex = layerIndex + 1
            else
                local row = {}
                local x = 1
                for tile in lines[i]:gmatch("[^,]+") do
                    local tileValue = tonumber(tile)
                    if tileValue ~= 0 then
                        row[x] = tileValue
                    end
                    x = x + 1
                end
                table.insert(currentLayerData, row)
            end
        end
        
        if #currentLayerData > 0 then
            table.insert(layers, currentLayerData)
        end
        
        currentLayer = 1
        print("Level loaded: " .. levelName)
    else
        print("Failed to load level: " .. levelName)
    end
end

function updateAvailableLevels()
    availableLevels = {}
    local files = love.filesystem.getDirectoryItems(settings.levelsPath)
    
    for _, filename in ipairs(files) do
        if filename:match("%.txt$") then
            local levelName = filename:gsub("%.txt$", "")
            table.insert(availableLevels, levelName)
        end
    end
    
    table.sort(availableLevels)
    selectedLevelIndex = 1
end

function applyBrush(x, y)
    if x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
        layers[currentLayer][y] = layers[currentLayer][y] or {}
        layers[currentLayer][y][x] = selectedTile
    end
end

function applyEraser(x, y)
    if x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
        if layers[currentLayer][y] then
            layers[currentLayer][y][x] = nil
        end
    end
end

function applyBucket(x, y)
    if x >= 1 and x <= gridWidth and y >= 1 and y <= gridHeight then
        local currentLayerData = layers[currentLayer]
        local targetTile = currentLayerData[y] and currentLayerData[y][x] or nil
        if targetTile ~= selectedTile then
            floodFill(x, y, targetTile, selectedTile)
        end
    end
end

function floodFill(x, y, targetTile, replacementTile)
    if x < 1 or x > gridWidth or y < 1 or y > gridHeight then return end
    
    local currentLayerData = layers[currentLayer]
    local currentTile = currentLayerData[y] and currentLayerData[y][x] or nil
    
    if currentTile == targetTile then
        if replacementTile then
            currentLayerData[y] = currentLayerData[y] or {}
            currentLayerData[y][x] = replacementTile
        else
            if currentLayerData[y] then
                currentLayerData[y][x] = nil
            end
        end
        
        floodFill(x + 1, y, targetTile, replacementTile)
        floodFill(x - 1, y, targetTile, replacementTile)
        floodFill(x, y + 1, targetTile, replacementTile)
        floodFill(x, y - 1, targetTile, replacementTile)
    end
end

function drawHoveredTile()
    local mouseX, mouseY = love.mouse.getPosition()
    local worldMouseX = mouseX / camera.scale + camera.x
    local worldMouseY = mouseY / camera.scale + camera.y
    local tileX = math.floor(worldMouseX / tileSize)
    local tileY = math.floor(worldMouseY / tileSize)
    
    if tileX >= 0 and tileX < gridWidth and tileY >= 0 and tileY < gridHeight and
       mouseX < love.graphics.getWidth() - 100 and mouseY < love.graphics.getHeight() - 100 then
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
    local positions = {}
    x1 = math.max(1, math.min(x1, gridWidth))
    y1 = math.max(1, math.min(y1, gridHeight))
    x2 = math.max(1, math.min(x2, gridWidth))
    y2 = math.max(1, math.min(y2, gridHeight))

    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    while true do
        table.insert(positions, {x = x1, y = y1})
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

function drawCoordinates()
    local mouseX, mouseY = love.mouse.getPosition()
    local worldMouseX = mouseX / camera.scale + camera.x
    local worldMouseY = mouseY / camera.scale + camera.y
    local tileX = math.floor(worldMouseX / tileSize)
    local tileY = math.floor(worldMouseY / tileSize)
    
    if tileX >= 0 and tileX < gridWidth and tileY >= 0 and tileY < gridHeight and
       mouseX < love.graphics.getWidth() - 100 and mouseY < love.graphics.getHeight() - 100 then
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("X: " .. (tileX + 1) .. ", Y: " .. (tileY + 1), 10, 70)
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("X: -, Y: -", 10, 70)
    end
end

function drawAssetPackSelector()
    local centerX = love.graphics.getWidth() / 2
    local centerY = love.graphics.getHeight() / 2
    local boxWidth = 400
    local boxHeight = math.min(300, #availableAssetPacks * 25 + 80)
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2
    
    love.graphics.setColor(0.2, 0.2, 0.2, 0.9)
    love.graphics.rectangle("fill", boxX, boxY, boxWidth, boxHeight)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", boxX, boxY, boxWidth, boxHeight)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Select Asset Pack", boxX, boxY + 10, boxWidth, "center")
    
    for i, pack in ipairs(availableAssetPacks) do
        local y = boxY + 40 + (i - 1) * 25
        if i == selectedAssetPackIndex then
            love.graphics.setColor(1, 1, 0)
            love.graphics.rectangle("fill", boxX + 10, y - 2, boxWidth - 20, 20)
            love.graphics.setColor(0, 0, 0)
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.print(pack, boxX + 15, y)
    end
    
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.printf("Use UP/DOWN arrows to select, ENTER to confirm, ESC to cancel", 
                        boxX, boxY + boxHeight - 30, boxWidth, "center")
end

function drawLevelNameInput()
    local centerX = love.graphics.getWidth() / 2
    local centerY = love.graphics.getHeight() / 2
    local boxWidth = 400
    local boxHeight = 120
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2
    
    love.graphics.setColor(0.2, 0.2, 0.2, 0.9)
    love.graphics.rectangle("fill", boxX, boxY, boxWidth, boxHeight)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", boxX, boxY, boxWidth, boxHeight)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Enter Level Name", boxX, boxY + 10, boxWidth, "center")
    
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.rectangle("fill", boxX + 20, boxY + 40, boxWidth - 40, 25)
    
    love.graphics.setColor(0, 0, 0)
    love.graphics.print(levelNameInput .. "|", boxX + 25, boxY + 45)
    
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.printf("Type name and press ENTER to save, ESC to cancel", 
                        boxX, boxY + 80, boxWidth, "center")
end

function drawLevelSelector()
    local centerX = love.graphics.getWidth() / 2
    local centerY = love.graphics.getHeight() / 2
    local boxWidth = 400
    local boxHeight = math.min(300, #availableLevels * 25 + 80)
    local boxX = centerX - boxWidth / 2
    local boxY = centerY - boxHeight / 2
    
    love.graphics.setColor(0.2, 0.2, 0.2, 0.9)
    love.graphics.rectangle("fill", boxX, boxY, boxWidth, boxHeight)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", boxX, boxY, boxWidth, boxHeight)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Select Level to Load", boxX, boxY + 10, boxWidth, "center")
    
    if #availableLevels == 0 then
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.printf("No saved levels found", boxX, boxY + 50, boxWidth, "center")
    else
        for i, levelName in ipairs(availableLevels) do
            local y = boxY + 40 + (i - 1) * 25
            if i == selectedLevelIndex then
                love.graphics.setColor(1, 1, 0)
                love.graphics.rectangle("fill", boxX + 10, y - 2, boxWidth - 20, 20)
                love.graphics.setColor(0, 0, 0)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.print(levelName, boxX + 15, y)
        end
    end
    
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.printf("Use UP/DOWN arrows to select, ENTER to load, ESC to cancel", 
                        boxX, boxY + boxHeight - 30, boxWidth, "center")
end

function drawLine(x1, y1, x2, y2)
    x1 = math.max(1, math.min(x1, gridWidth))
    y1 = math.max(1, math.min(y1, gridHeight))
    x2 = math.max(1, math.min(x2, gridWidth))
    y2 = math.max(1, math.min(y2, gridHeight))

    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    while true do
        applyBrush(x1, y1)
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
