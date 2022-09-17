function love.conf(t)
    t.window.title = "Map Painter v"..love.filesystem.read("version.txt")
    t.window.icon = "resources/logo.png"
end