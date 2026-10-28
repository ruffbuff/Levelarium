-- Конфигурация LÖVE. Читается только из корня проекта (раньше лежала в scripts/ и игнорировалась).
function love.conf(t)
    t.identity = "Levelarium"
    t.version = "11.5"
    t.console = false

    local settings = require("scripts.settings")

    t.window.title = settings.getWindowTitle()
    t.window.icon = settings.assetsPath .. settings.iconFile
    t.window.width = 1024  -- размер окна редактора (не зависит от размера сетки)
    t.window.height = 768
    t.window.borderless = false
    t.window.resizable = false
    t.window.minwidth = 800
    t.window.minheight = 600
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.display = 1
    t.window.highdpi = false
    t.window.x = nil
    t.window.y = nil

    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = false
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false
    t.modules.sound = false
    t.modules.system = true
    t.modules.timer = true
    t.modules.touch = false
    t.modules.video = false
    t.modules.window = true
    t.modules.thread = true  -- фоновая проверка обновлений (scripts/updater.lua)
end