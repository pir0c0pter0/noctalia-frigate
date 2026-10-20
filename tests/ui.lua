-- Run from the repository root: lua tests/ui.lua
local function host()
    local h = { tree = nil, renders = 0, commands = {}, watchers = {},
        view = { camera = "front", cameras = { "front", "side" }, selected = { "front", "side" },
            connected = true, frame = "", message = "" }, closeButtons = true }
    local function node(kind)
        return function(props, children) return { type = kind, props = props or {}, children = children or {} } end
    end
    local env = {
        ui = setmetatable({}, { __index = function(_, key) return node(key) end }),
        panel = {
            render = function(tree) h.tree = tree; h.renders = h.renders + 1 end,
            close = function() h.closed = true end,
        },
        barWidget = {
            setGlyph = function(value) h.glyph = value end,
            setGlyphColor = function(value) h.color = value end,
            setTooltip = function(value) h.tooltip = value end,
        },
        noctalia = {
            tr = function(key) return key end,
            getSetting = function(key) assert(key == "shell.show_close_buttons"); return h.closeButtons end,
            pluginDir = function() return "/tmp/plugin's directory" end,
            runInTerminal = function(cmd) h.terminal = cmd; return true end,
            openSettings = function() h.settingsOpened = true end,
            togglePanel = function(id) h.toggled = id end,
            notifyError = function() error("unexpected notification") end,
            state = {
                get = function(key) assert(key == "viewer"); return h.view end,
                set = function(key, value) assert(key == "command"); table.insert(h.commands, value) end,
                watch = function(key, cb) h.watchers[key] = cb end,
            },
        },
    }
    h.env = setmetatable(env, { __index = _G })
    function h:load(path) assert(loadfile(path, "t", self.env))() end
    function h:find(predicate, tree)
        tree = tree or self.tree
        if predicate(tree) then return tree end
        for _, child in ipairs(tree.children) do
            local found = self:find(predicate, child)
            if found then return found end
        end
    end
    return h
end

local h = host()
h:load("Panel.luau")
assert(h.renders == 0)
h.env.onOpen()
assert(h.commands[#h.commands].action == "open")
local previous = h:find(function(n) return n.props.glyph == "chevron-left" end)
assert(previous.props.enabled)
previous.props.onClick()
assert(h.commands[#h.commands].action == "previous")
h.env.onKey("Right", true)
assert(h.commands[#h.commands].action == "next")
local before = #h.commands
h.env.onKey("Right", false)
assert(#h.commands == before)
local picker = h:find(function(n) return n.props.text == "cameraSelection" end)
picker.props.onClick()
assert(h.commands[#h.commands].action == "preview" and h.commands[#h.commands].value == false)
before = #h.commands
h.env.onKey("Right", true)
assert(#h.commands == before)
local side = h:find(function(n) return n.type == "row" and n.props.key == "side" end)
side.children[1].props.onChange("true")
assert(h.commands[#h.commands].action == "toggle" and h.commands[#h.commands].value == "side")
local back = h:find(function(n) return n.props.text == "backToViewer" end)
back.props.onClick()
assert(h.commands[#h.commands].value == true)
h.view.frame = "/run/private/camera.jpg"
h.watchers.viewer(h.view)
local preview = h:find(function(n) return n.type == "image" end)
assert(preview.props.path == h.view.frame and preview.props.fit == "contain")
h.env.editCredentials()
assert(h.terminal == "bash '/tmp/plugin'\\''s directory/Credentials.sh'")
h.env.onClose()
assert(h.commands[#h.commands].action == "close")
before = h.renders
h.watchers.viewer(h.view)
assert(h.renders == before)
h.closeButtons = false
h.env.onOpen()
assert(not h:find(function(n) return n.props.glyph == "close" end))
h.env.onExit()
assert(h.commands[#h.commands].action == "close")
print("panel lifecycle, native controls, navigation, selection pause, path quoting: passed")

local bar = host()
bar:load("BarWidget.luau")
assert(bar.glyph == "camera-video" and bar.color == "primary" and bar.tooltip == "tooltipConnected")
bar.watchers.viewer({ connected = false })
assert(bar.color == "error" and bar.tooltip == "tooltipDisconnected")
bar.env.onClick()
assert(bar.toggled == "pir0c0pter0/frigate:viewer")
bar.env.onRightClick()
assert(bar.settingsOpened)
print("bar native status, tooltip and actions: passed")
