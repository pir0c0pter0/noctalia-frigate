-- Run from the repository root: lua tests/ui.lua
local function host()
    local h = { tree = nil, renders = 0, commands = {}, watchers = {},
        view = { camera = "front", cameras = { "front", "side" }, selected = { "front", "side" },
            connected = true, frame = "", message = "", problem = "", url = "https://f.example.com",
            defaultCamera = "side", credentialsReady = true }, closeButtons = true, shared = {} }
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
                get = function(key) if key == "viewer" then return h.view end return h.shared[key] end,
                set = function(key, value)
                    if key == "command" then table.insert(h.commands, value); return end
                    h.shared[key] = value
                    if h.watchers[key] then h.watchers[key](value) end
                end,
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
previous.props.onClick()
assert(h.commands[#h.commands].action == "previous")
h.env.onKey("Right", true)
assert(h.commands[#h.commands].action == "next")
local before = #h.commands
h.env.onKey("Right", false)
assert(#h.commands == before)
local gear = h:find(function(n) return n.props.glyph == "settings" end)
gear.props.onClick()
assert(h.commands[#h.commands].action == "preview" and h.commands[#h.commands].value == false)
before = #h.commands
h.env.onKey("Right", true)
assert(#h.commands == before)
local side = h:find(function(n) return n.type == "row" and n.props.key == "side" end)
side.children[1].props.onChange("true")
assert(h.commands[#h.commands].action == "toggle" and h.commands[#h.commands].value == "side")
local main = h:find(function(n) return n.type == "select" end)
assert(main.props.options[3] == "side" and main.props.selectedIndex == 2)
main.props.onChange("1")
assert(h.commands[#h.commands].action == "default" and h.commands[#h.commands].value == "front")
main.props.onChange("0")
assert(h.commands[#h.commands].value == "")
local url = h:find(function(n) return n.type == "input" end)
assert(url.props.value == "https://f.example.com")
url.props.onChange("https://g.example.com")
assert(h.commands[#h.commands].action == "url" and h.commands[#h.commands].value == "https://g.example.com")
local back = h:find(function(n) return n.props.glyph == "chevron-left" end)
back.props.onClick()
assert(h.commands[#h.commands].action == "preview" and h.commands[#h.commands].value == true)
h.view.problem = "authFailed"
h.watchers.viewer(h.view)
assert(h:find(function(n) return n.props.text == "errorTitleAuth" end))
h:find(function(n) return n.props.text == "editCredentials" end).props.onClick()
assert(h.terminal)
h.view.problem = "cannotReachServer"
h.watchers.viewer(h.view)
h:find(function(n) return n.props.text == "retry" end).props.onClick()
assert(h.commands[#h.commands].action == "retry")
h.view.problem = ""
h.view.frame = "/run/private/camera.jpg"
h.watchers.viewer(h.view)
local preview = h:find(function(n) return n.type == "image" end)
assert(preview.props.path == h.view.frame and preview.props.fit == "contain")
h:find(function(n) return n.props.glyph == "camera" end).props.onClick()
assert(h.commands[#h.commands].action == "snapshot")
h.view.savedSnapshot = "/home/u/Imagens/cameras/front.jpg"
h.watchers.viewer(h.view)
assert(h:find(function(n) return n.props.glyph == "check" end).props.tooltip == "snapshotSaved")
h.view.savedSnapshot = ""
h.env.editCredentials()
assert(h.terminal == "bash '/tmp/plugin'\\''s directory/Credentials.sh'")
h.env.onClose()
assert(h.commands[#h.commands].action == "close")
before = h.renders
h.watchers.viewer(h.view)
assert(h.renders == before)
h.closeButtons = false
h.env.onOpen()
assert(not h:find(function(n) return n.props.glyph == "x" end))
h.env.onExit()
assert(h.commands[#h.commands].action == "close")
h.closeButtons = true
h.env.onClose()
h.shared.panelPage = "settings"
h.env.onOpen()
assert(h:find(function(n) return n.type == "select" end) and h.shared.panelPage == nil)
h.watchers.panelPage("viewer")
assert(h:find(function(n) return n.type == "image" end))
print("panel lifecycle, viewer/settings pages, error actions, navigation, path quoting: passed")

local bar = host()
bar:load("BarWidget.luau")
assert(bar.glyph == "device-cctv" and bar.color == "primary" and bar.tooltip == "tooltipConnected")
bar.watchers.viewer({ connected = false })
assert(bar.color == "error" and bar.tooltip == "tooltipDisconnected")
bar.env.onClick()
assert(bar.toggled == "pir0c0pter0/frigate:viewer")
bar.toggled = nil
bar.env.onRightClick()
assert(bar.shared.panelPage == "settings" and bar.toggled == "pir0c0pter0/frigate:viewer")
bar.toggled = nil
bar.view.opened = true
bar.env.onRightClick()
assert(bar.toggled == nil)
print("bar native status, tooltip and actions: passed")
