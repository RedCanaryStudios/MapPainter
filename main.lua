local binser = require("deps.binser")
local nativefs = require("deps.nativefs")
local ffi = require("ffi")

local imgui
local hover = false
local hoverdb = 0

local canvas
local clock = 0
local registerDrawClick = 0

local fps = 0
local fpslast = 0

local debug = {
    scale = 3;
    hoverdb = 0.22;
    print = function()
        return fps
    end
}

local function isUI()
    return (clock - hoverdb < debug.hoverdb)
end

local brush = {
    color = {1, 1, 1, 1};
    size = 20;
    structsize = 10;
}

local camera = {
    offset = {0, 0};
    speed = 500;
    zoom = 1;
}

local items = {
    stationary = {};
    moveable = {};
    pending = nil;
}

local function starPoints(a, r, ox, oy)
    local vertices = {}

    for i = 0, (2*a)+1 do
        table.insert(vertices, (r/(((i + 1) % 2)+1))*math.sin(i/(2*a)*2*math.pi) + ox)
        table.insert(vertices, (r/(((i + 1) % 2)+1))*math.cos(i/(2*a)*2*math.pi) + oy)
    end

    return vertices
end

local stationaryTemplates = {
    City = {
        Render = function(mydat, ofx, ofy)
            love.graphics.setColor(unpack(mydat.color))
            love.graphics.polygon("fill", starPoints(3, mydat.size, mydat.x + ofx, mydat.y + ofy))
        end;
    };

    Capital = {
        Render = function(mydat, ofx, ofy)
            love.graphics.setColor(unpack(mydat.color))
            love.graphics.polygon("fill", starPoints(5, mydat.size, mydat.x + ofx, mydat.y + ofy))
        end;
    };

    Dock = {
        Render = function(mydat, ofx, ofy)
            love.graphics.setColor(unpack(mydat.color))
            love.graphics.polygon("fill", starPoints(4, mydat.size, mydat.x + ofx, mydat.y + ofy))
        end;
    };
}

local stationaryMoveable = {}

local overlay = love.graphics.newImage("resources/map.png")
local canvas = love.graphics.newCanvas(overlay:getWidth()*debug.scale, overlay:getHeight()*debug.scale)

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

local function savedata()
    local imgdata = canvas:newImageData():getString()
    nativefs.write("save/dat", binser.serialize(items, brush, camera, imgdata))
end

function love.run()
	if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

	
	if love.timer then love.timer.step() end

	local dt = 0

	
	return function()
		
		if love.event then
			love.event.pump()
			for name, a,b,c,d,e,f in love.event.poll() do
				if name == "quit" then
					if not love.quit or not love.quit() then
                        savedata()
						return a or 0
					end
				end
				love.handlers[name](a,b,c,d,e,f)
			end
		end

		if love.timer then dt = love.timer.step() end

		if love.update then love.update(dt) end

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
    imgui.GetStyle().WindowRounding = 5
    imgui.GetStyle().FrameRounding = 4
    imgui.GetStyle().GrabRounding = 4;

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

    canvas:renderTo(function()
        love.graphics.setColor(77/255, 140/255, 50/255)
        love.graphics.rectangle("fill", 0, 0, overlay:getWidth()*debug.scale, overlay:getHeight()*debug.scale)
    end)

    if contents ~= "" and args[1] ~= "-ns" then
        items, brush, camera, imgdata = binser.deserializeN(contents, 4)
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

    local mx, my = getMouseLocal()

    if not isUI() then
        love.graphics.setColor(unpack(brush.color))
        love.graphics.circle("fill", mx, my, brush.size)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, ox, oy, 0, 1/debug.scale, 1/debug.scale)

    love.graphics.setStencilTest()

    for _, v in ipairs(items.stationary) do
        stationaryTemplates[v.type].Render(v, ox, oy)
    end

    if items.pending and registerDrawClick > 0 then
        registerDrawClick = registerDrawClick - 1
        hoverdb = clock

        local dat = {
            type = items.pending;
            size = brush.structsize;
            x = mx;
            y = my;
            color = shallowcopy(brush.color)
        }
        
        table.insert(items.stationary, dat)

        if not love.keyboard.isDown("lctrl") then
            items.pending = nil
        end
     end

    if items.pending then
        local fakeDat = {
            size = brush.structsize;
            x = mx;
            y = my;
            color = brush.color;
        }
        stationaryTemplates[items.pending].Render(fakeDat, 0, 0)
    end

    love.graphics.pop()

    if love.mouse.isDown(1) and not isUI() and not items.pending then
        canvas:renderTo(function()
            love.graphics.setColor(unpack(brush.color))
            love.graphics.circle("fill", (mx % overlay:getWidth())*debug.scale, my*debug.scale, brush.size*debug.scale)
        end)
    end

    if not isUI() and not items.pending then
        love.graphics.setColor(unpack(brush.color))
        local mx, my = getMouseGlobal()
        love.graphics.circle("line", mx, my, brush.size*camera.zoom)
    end
end

function love.draw()
    hover = false
    imgui.SetNextWindowSize(imgui.ImVec2_Float(280, 120))

    if imgui.Begin("PaintBrush") then
        local red = ffi.new("float[1]",brush.color[1])
        local green = ffi.new("float[1]",brush.color[2])
        local blue = ffi.new("float[1]",brush.color[3])

        imgui.SliderFloat("RED", red, 0, 1)
        brush.color[1] = red[0]

        imgui.SliderFloat("GREEN", green, 0, 1)
        brush.color[2] = green[0]

        imgui.SliderFloat("BLUE", blue, 0, 1)
        brush.color[3] = blue[0]
    end

    imgui.End()

    imgui.SetNextWindowSize(imgui.ImVec2_Float(280, 750))

    if imgui.Begin("Placement") then
        if imgui.TreeNode_Str("Structures") then
            local scale = ffi.new("float[1]", brush.structsize)

            for k in pairs(stationaryTemplates) do
                if imgui.Button("Place "..k) then
                    if items.pending == k then
                        items.pending = nil
                    else
                        items.pending = k
                    end
                end
            end

            imgui.Spacing()

            imgui.SliderFloat("Size", scale, 2, 20)
            brush.structsize = scale[0]

            imgui.TreePop()
        end

        if imgui.TreeNode_Str("Units") then
            if imgui.Button("Army") then

            end

            if imgui.Button("Heavy Army") then

            end

            if imgui.Button("Boat") then

            end
            imgui.TreePop()
        end

        imgui.Spacing()

        local db = ffi.new("float[1]", debug.hoverdb)
        imgui.SliderFloat("Debounce", db, 0.05, 1)
        debug.hoverdb = db[0]
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

    if debug.print then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(debug.print())
    end

    imgui.Render()
    imgui.RenderDrawLists()

    hover = imgui.GetWantCaptureMouse()

    if hover == true then
        hoverdb = clock
    end
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
        love.graphics.captureScreenshot(function(imgd)
            local r, g, b = imgd:getPixel(getMouseGlobal())
            brush.color[1] = r
            brush.color[2] = g
            brush.color[3] = b
            brush.color[4] = 1
        end)
    end

    imgui.KeyPressed(k)
    if not imgui.GetWantCaptureKeyboard() then

    end
end

function love.keyreleased(k)
    imgui.KeyReleased(k)
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
         registerDrawClick = registerDrawClick + 1
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