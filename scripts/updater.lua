-- Проверка обновлений: один фоновый запрос к GitHub Releases при запуске.
-- HTTPS в LÖVE из коробки нет (luasocket без ssl), поэтому запрос делает системный `curl`
-- в отдельном потоке (love.thread): интерфейс не блокируется, а при отсутствии curl,
-- сети, ошибке или таймауте просто ничего не происходит.
local version = require("scripts.version")

local updater = {}

updater.available = nil  -- {version = "1.2.1", url = "https://github.com/..."} если есть новая версия

local THREAD_CODE = [[
local url, channelName = ...
require("love.system")
local channel = love.thread.getChannel(channelName)
local ok, body = pcall(function()
    local quiet = love.system.getOS() == "Windows" and " 2>nul" or " 2>/dev/null"
    local cmd = 'curl -fsSL --connect-timeout 5 --max-time 10'
        .. ' -H "User-Agent: Levelarium-update-check" -H "Accept: application/vnd.github+json" "'
        .. url .. '"' .. quiet
    local pipe = io.popen(cmd, "r")
    if not pipe then return nil end
    local out = pipe:read(262144)
    pipe:close()
    return out
end)
channel:push({body = ok and body or nil})
]]

-- Разбор ответа GitHub API releases/latest -> tag_name, html_url (nil, если ответ не похож на релиз)
function updater.parseRelease(json)
    if type(json) ~= "string" then return nil end
    local tag = json:match('"tag_name"%s*:%s*"([^"]+)"')
    if not tag or not version.parse(tag) then return nil end
    -- первый html_url в ответе - страница самого релиза (дальше идут автор и ассеты)
    local url = json:match('"html_url"%s*:%s*"(https://github%.com/[^"]+/releases/[^"]*)"')
    return tag, url
end

-- URL допускаем только http(s) и без символов, которые что-то значат для shell
function updater.isSafeUrl(url)
    return type(url) == "string" and url:match("^https?://[%w%.%-_~:/%?=&@]+$") ~= nil
end

-- Применяет ответ: заполняет updater.available, если tag новее currentVersion
function updater.handleResponse(body, currentVersion, fallbackUrl)
    local tag, url = updater.parseRelease(body)
    if tag and version.isNewer(tag, currentVersion) then
        updater.available = {version = (tag:gsub("^[vV]", "")), url = url or fallbackUrl}
        return true
    end
    return false
end

local channelName = "levelarium-update-check"
local started = false
local thread, current, fallback

-- opts: url, currentVersion, fallbackUrl. Безопасно вызывать при любом окружении.
function updater.start(opts)
    if started then return end
    started = true
    if not updater.isSafeUrl(opts.url) then return end
    if not (love.thread and love.thread.newThread) then return end
    current, fallback = opts.currentVersion, opts.fallbackUrl
    local ok, t = pcall(function()
        local th = love.thread.newThread(THREAD_CODE)
        th:start(opts.url, channelName)
        return th
    end)
    if ok then thread = t end
end

-- вызывать каждый кадр (дёшево); забирает результат потока, когда он готов
function updater.poll()
    if not thread then return end
    local result = love.thread.getChannel(channelName):pop()
    if result then
        thread = nil
        pcall(updater.handleResponse, result.body, current, fallback)
    end
end

return updater
