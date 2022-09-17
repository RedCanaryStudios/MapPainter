local binser = require("deps.binser")
local nativefs = require("deps.nativefs")
local ffi = require("ffi")
local imgui
local hover = false

local canvas

local fps = 0
local fpslast = 0

local debug = {
    scale = 3;
}

local brush = {
    color = {0, 0, 0, 1};
    size = 20;
}

local camera = {
    offset = {0, 0};
    speed = 500;
    zoom = 1;
}

local clock = 0

local overlay = love.graphics.newImage("resources/map.png")
local canvas = love.graphics.newCanvas(overlay:getWidth()*debug.scale, overlay:getHeight()*debug.scale)

local function hex2rgb(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

local function getMouseGlobal()
    return love.mouse.getX(), love.mouse.getY()
end

local function getMouseLocal()
    return love.graphics.inverseTransformPoint(getMouseGlobal())
end

local function getMouseCanvas()
    return love.graphics.transformPoint(getMouseGlobal())
end

local function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else
        copy = orig
    end
    return copy
end

function love.run()
	if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then love.timer.step() end

	local dt = 0

	-- Main loop time.
	return function()
		-- Process events.
		if love.event then
			love.event.pump()
			for name, a,b,c,d,e,f in love.event.poll() do
				if name == "quit" then
					if not love.quit or not love.quit() then
                        local imgdata = canvas:newImageData():getString()
                        nativefs.write("save/dat", binser.serialize(brush, camera, imgdata))
						return a or 0
					end
				end
				love.handlers[name](a,b,c,d,e,f)
			end
		end

		-- Update dt, as we'll be passing it to update
		if love.timer then dt = love.timer.step() end

		-- Call update and draw
		if love.update then love.update(dt) end -- will pass 0 if love.timer is disabled

		if love.graphics and love.graphics.isActive() then
			love.graphics.origin()
			love.graphics.clear(love.graphics.getBackgroundColor())

			if love.draw then love.draw() end

			love.graphics.present()
		end

		if love.timer then love.timer.sleep(0.001) end
	end
end

function love.load(args)
    local lib_folder = string.format("libs/%s-%s", jit.os, jit.arch)
    assert(
        love.filesystem.getRealDirectory(lib_folder),
        "The precompiled cimgui shared library is not available for your os/architecture. You can try compiling it yourself."
    )
    love.filesystem.remove(lib_folder)
    love.filesystem.createDirectory(lib_folder)
    for _, v in ipairs(love.filesystem.getDirectoryItems(lib_folder)) do
        local filename = string.format("%s/%s", lib_folder, v)
        assert(love.filesystem.write(filename, love.filesystem.read(filename)))
    end
    local extension = jit.os == "Windows" and "dll" or jit.os == "Linux" and "so" or jit.os == "OSX" and "dylib"
    package.cpath = string.format("%s;%s/%s/?.%s", package.cpath, love.filesystem.getSaveDirectory(), lib_folder, extension)

    imgui = require "cimgui"
    imgui.Init()

    local flags = {}
    flags.fullscreentype = "desktop"
    flags.fullscreen = true
    love.window.setMode(100, 100, flags)

    if not nativefs.getInfo("save") then
        nativefs.createDirectory("save")
    end

    if not nativefs.getInfo("save/dat") then
        nativefs.write("save/dat", "")
    end
    local contents = nativefs.read("save/dat")

    if contents ~= "" and args[1] ~= "-ns" then
        brush, camera, imgdata = binser.deserializeN(contents, 3)
        local loaded = love.image.newImageData(overlay:getWidth()*debug.scale, overlay:getHeight()*debug.scale, "rgba8", imgdata)
        canvas:renderTo(function()
            local img = love.graphics.newImage(loaded)
            love.graphics.draw(img)
        end)
    end
end

function love.update(dt)
    clock = clock + dt
    
    if clock - 0.5 > fpslast then
        fps = math.floor(1/dt)
        fpslast = clock
    end

    local isDown = love.keyboard.isDown

    local speed = camera.speed
    local offset = camera.offset

    offset[1] = offset[1] + dt*speed*(isDown("d") and 1 or 0)/camera.zoom
    offset[1] = offset[1] + dt*speed*(isDown("a") and -1 or 0)/camera.zoom

    offset[2] = offset[2] + dt*speed*(isDown("s") and 1 or 0)/camera.zoom
    offset[2] = offset[2] + dt*speed*(isDown("w") and -1 or 0)/camera.zoom

    brush.size = math.max(brush.size + dt*(50/camera.zoom)*(isDown("q") and -1 or 0), 1)
    brush.size = math.max(brush.size + dt*(50/camera.zoom)*(isDown("e") and 1 or 0), 1)

    local dx = (love.graphics.getWidth() / 2) - (love.graphics.getWidth() / 2) / camera.zoom
    local dy = (love.graphics.getHeight() / 2) - (love.graphics.getHeight() / 2) / camera.zoom

    if dy + camera.offset[2] < 0 then
        camera.offset[2] = -dy
    end

    if dy + camera.offset[2] + love.graphics.getHeight()/camera.zoom > overlay:getHeight() then
        camera.offset[2] = camera.offset[2] + (overlay:getHeight() - (dy + camera.offset[2] + love.graphics.getHeight()/camera.zoom))
    end

    camera.offset[1] = camera.offset[1] % overlay:getWidth()

    imgui.Update(dt)
    imgui.NewFrame()
end

local mask_shader = love.graphics.newShader[[
   vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
      if (Texel(texture, texture_coords).rgb == vec3(0.0)) {
         // a discarded pixel wont be applied as the stencil.
         discard;
      }
      return vec4(1.0);
   }
]]

local ox, oy = 0, 0
local function SF()
    love.graphics.setShader(mask_shader)
    love.graphics.draw(overlay, ox, oy)
    love.graphics.setShader()
end

local function doGraphics()
    local dx = (love.graphics.getWidth() / 2) - (love.graphics.getWidth() / 2) / camera.zoom
    local dy = (love.graphics.getHeight() / 2) - (love.graphics.getHeight() / 2) / camera.zoom

    love.graphics.push()
    love.graphics.scale(camera.zoom)
    love.graphics.translate(-camera.offset[1] - dx, -camera.offset[2] - dy)
    
    love.graphics.setColor(50/255, 71/255, 140/255)
    love.graphics.rectangle("fill", ox, oy, overlay:getWidth(), overlay:getHeight())
    
    love.graphics.stencil(SF, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    love.graphics.setColor(77/255, 140/255, 50/255)
    love.graphics.rectangle("fill", ox, oy, overlay:getWidth(), overlay:getHeight())

    local mx, my = getMouseLocal()

    if not hover then
        love.graphics.setColor(unpack(brush.color))
        love.graphics.circle("fill", mx, my, brush.size)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, ox, oy, 0, 1/debug.scale, 1/debug.scale)

    love.graphics.setStencilTest()

    love.graphics.pop()

    if love.mouse.isDown(1) and not hover then
        canvas:renderTo(function()
            love.graphics.setColor(unpack(brush.color))
            love.graphics.circle("fill", (mx % overlay:getWidth())*debug.scale, my*debug.scale, brush.size*debug.scale)
        end)
    end

    if not hover then
        love.graphics.setColor(unpack(brush.color))
        local mx, my = getMouseGlobal()
        love.graphics.circle("line", mx, my, brush.size*camera.zoom)
    end
end

function love.draw()
    hover = false
    imgui.SetNextWindowSize(imgui.ImVec2_Float(280, 280))
    if imgui.Begin("Edit", nil, imgui.ImGuiWindowFlags_MenuBar) then
        hover = imgui.IsWindowHovered() or hover
        hover = imgui.IsWindowFocused() or hover

        local red = ffi.new("float[1]",brush.color[1])
        local green = ffi.new("float[1]",brush.color[2])
        local blue = ffi.new("float[1]",brush.color[3])
        if imgui.BeginMenuBar("Config") then

            if imgui.BeginMenu("Colors") then
                imgui.SliderFloat("RED", red, 0, 1)
                brush.color[1] = red[0]

                imgui.SliderFloat("green", green, 0, 1)
                brush.color[2] = green[0]

                imgui.SliderFloat("BLUE", blue, 0, 1)
                brush.color[3] = blue[0]

                hover = imgui.IsAnyItemHovered() or hover
                hover = imgui.IsAnyItemFocused() or hover
                hover = imgui.IsAnyMouseDown() or hover
                imgui.EndMenu()
            end


            imgui.EndMenuBar()
        end
    end
    imgui.End()

    local dx = (love.graphics.getWidth() / 2) - (love.graphics.getWidth() / 2) / camera.zoom
    local dy = (love.graphics.getHeight() / 2) - (love.graphics.getHeight() / 2) / camera.zoom

    ox, oy = 0, 0
    doGraphics()
    if dx + camera.offset[1] > 0 then
        ox, oy = overlay:getWidth(), 0
        doGraphics()
    else
        ox, oy = -overlay:getWidth(), 0
        doGraphics()
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(fps)

    imgui.Render()
    imgui.RenderDrawLists()
end

function love.wheelmoved(x, y)
    if love.mouse.isDown(2) then
        brush.size = math.max(brush.size + (5/camera.zoom)*(y), 1)
    else
        camera.zoom = math.max(math.min(camera.zoom*(1 + y/20), 8), love.graphics.getHeight()/overlay:getHeight())
    end

    imgui.WheelMoved(x, y)
    if not imgui.GetWantCaptureMouse() then
         
    end
end

function love.keypressed(k)
    if k == 'escape' then
        love.event.quit()
    elseif k == 'f' then
        local dx = (love.graphics.getWidth() / 2) - (love.graphics.getWidth() / 2) / camera.zoom
        local dy = (love.graphics.getHeight() / 2) - (love.graphics.getHeight() / 2) / camera.zoom

        brush.color = {canvas:newImageData():getPixel(dx + camera.offset[1] + love.mouse.getX()/camera.zoom, dy + camera.offset[2] + love.mouse.getY()/camera.zoom)}
        brush.color[4] = 1
    end

    imgui.KeyPressed(k)
    if not imgui.GetWantCaptureKeyboard() then
         
    end
end

function love.mousemoved(x, y, dx, dy)
    if love.mouse.isDown(3) then
        camera.offset[1] = camera.offset[1] - dx/camera.zoom
        camera.offset[2] = camera.offset[2] - dy/camera.zoom
    end

    imgui.MouseMoved(x, y)
    if not imgui.GetWantCaptureMouse() then
        
    end
end

function love.mousepressed(x, y, button)
    imgui.MousePressed(button)
    if not imgui.GetWantCaptureMouse() then
         
    end
end

function love.mousereleased(x, y, button)
    imgui.MouseReleased(button)
    if not imgui.GetWantCaptureMouse() then
        
    end
end

function love.textinput(t)
    imgui.TextInput(t)
    if not imgui.GetWantCaptureKeyboard() then
        
    end
end

function love.quit()
    return imgui.Shutdown()
end

function love.resize(w, h)
    local io = imgui.GetIO()
    io.DisplaySize.x, io.DisplaySize.y = w, h
end