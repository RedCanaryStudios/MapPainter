function love.conf(t)
    t.window.title = "Map Painter v"..love.filesystem.read("version.txt")
    t.window.icon = "resources/logo.png"
    t.window.width = 0
    t.window.height = 0
    t.window.fullscreentype = "exclusive"
    t.window.fullscreen = true
    t.window.msaa = 8
end