-- Сравнение версий по semver (без зависимостей от love.*).
local version = {}

-- "v1.2.3", "1.2", "1.2.3-beta.1" -> {major, minor, patch, pre = {...}|nil}; nil, если не версия
function version.parse(s)
    if type(s) ~= "string" then return nil end
    s = s:match("^%s*[vV]?(.-)%s*$")
    s = s:gsub("%+.*$", "")  -- метаданные сборки не участвуют в сравнении
    local core, pre = s:match("^([%d%.]+)%-?(.*)$")
    if not core or core == "" then return nil end
    local nums = {}
    for part in core:gmatch("[^%.]+") do
        if not part:match("^%d+$") then return nil end
        nums[#nums + 1] = tonumber(part)
    end
    if #nums == 0 or #nums > 3 then return nil end
    while #nums < 3 do nums[#nums + 1] = 0 end
    local v = {nums[1], nums[2], nums[3]}
    if pre ~= "" then
        v.pre = {}
        for part in pre:gmatch("[^%.]+") do v.pre[#v.pre + 1] = part end
    end
    return v
end

local function comparePre(a, b)
    -- версия без суффикса новее версии с суффиксом (1.0.0 > 1.0.0-rc.1)
    if not a and not b then return 0 end
    if not a then return 1 end
    if not b then return -1 end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i], b[i]
        if x == nil then return -1 end
        if y == nil then return 1 end
        local nx, ny = tonumber(x), tonumber(y)
        if nx and ny then
            if nx ~= ny then return nx < ny and -1 or 1 end
        elseif nx then
            return -1  -- числовые идентификаторы младше буквенных
        elseif ny then
            return 1
        elseif x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

-- -1, если a < b; 0, если равны; 1, если a > b; nil, если одна из строк не версия
function version.compare(a, b)
    local va, vb = version.parse(a), version.parse(b)
    if not va or not vb then return nil end
    for i = 1, 3 do
        if va[i] ~= vb[i] then return va[i] < vb[i] and -1 or 1 end
    end
    return comparePre(va.pre, vb.pre)
end

-- true, если remote строго новее current (при нераспознанной версии - false)
function version.isNewer(remote, current)
    return version.compare(remote, current) == 1
end

return version
