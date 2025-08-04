local settings = {
    NAME = "Levelarium",
    VERSION = "1.0.3",
    AUTHOR = "ruffbuff",
    tileSize = 64,
    gridWidth = 50,
    gridHeight = 50,
    assetsPath = "assets/",
    iconFile = "app-image.png",
    currentAssetPack = "itach/v1",
    levelsPath = "levels/"
}

function settings.getFullTitle()
    return settings.NAME .. " v" .. settings.VERSION
end

function settings.getWindowTitle()
    return settings.NAME .. " - v" .. settings.VERSION
end

function settings.getAssetPackPath()
    return settings.assetsPath .. settings.currentAssetPack .. "/"
end

function settings.getAvailableAssetPacks()
    local packs = {}
    local function scanFolder(path, prefix)
        prefix = prefix or ""
        local items = love.filesystem.getDirectoryItems(path)
        for _, item in ipairs(items) do
            local fullPath = path .. "/" .. item
            local info = love.filesystem.getInfo(fullPath)
            if info and info.type == "directory" then
                local packPath = prefix .. item
                local packFiles = love.filesystem.getDirectoryItems(fullPath)
                local hasPngFiles = false
                for _, file in ipairs(packFiles) do
                    if file:match("%.png$") then
                        hasPngFiles = true
                        break
                    end
                end
                if hasPngFiles then
                    table.insert(packs, packPath)
                else
                    scanFolder(fullPath, packPath .. "/")
                end
            end
        end
    end
    
    scanFolder(settings.assetsPath)
    return packs
end

return settings