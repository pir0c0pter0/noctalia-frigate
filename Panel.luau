--!nonstrict
local tr = noctalia.tr
local view = noctalia.state.get("viewer") or {}
local opened = false
local page = "viewer"
local render

local function command(action, value)
    noctalia.state.set("command", { action = action, value = value })
end

local function showPage(name)
    page = name
    command("preview", name == "viewer")
    render()
end

function editCredentials()
    local dir = noctalia.pluginDir()
    if not dir then return end
    -- runInTerminal accepts a shell string; quote the path, never interpolate secrets.
    local script = (dir .. "/Credentials.sh"):gsub("'", "'\\''")
    if not noctalia.runInTerminal("bash '" .. script .. "'") then
        noctalia.notifyError(tr("title"), tr("terminalFailed"))
    end
end

local function hasProblem()
    return view.problem ~= nil and view.problem ~= ""
end

local function statusRow()
    local color, text = "on_surface_variant", tr("connecting")
    if hasProblem() then
        color, text = "error", tr(view.problem, view.problemParams)
    elseif view.connected then
        color = "primary"
        text = view.version and view.version ~= "" and tr("connectedVersion", { version = view.version }) or tr("connected")
    end
    return ui.row({ gap = 8, align = "center" }, {
        ui.box({ width = 8, height = 8, radius = 4, fill = color }),
        ui.label({ text = text, color = "on_surface_variant", maxLines = 2, flexGrow = 1 }),
    })
end

local function headerButtons(row)
    table.insert(row, ui.button({ glyph = "settings", variant = "ghost", tooltip = tr("settings"), selected = page == "settings",
        onClick = function() showPage(page == "settings" and "viewer" or "settings") end }))
    if noctalia.getSetting("shell.show_close_buttons") ~= false then
        table.insert(row, ui.button({ glyph = "x", variant = "ghost", tooltip = tr("close"), onClick = function() panel.close() end }))
    end
    return ui.row({ gap = 4, align = "center" }, row)
end

-- Full-area state for errors and empty states, with the one action that fixes it.
local function notice(glyph, color, title, detail, action)
    local children = {
        ui.glyph({ name = glyph, size = 40, color = color }),
        ui.label({ text = title, fontWeight = "bold", textAlign = "center" }),
    }
    if detail then
        table.insert(children, ui.label({ text = detail, textAlign = "center", maxLines = 4, maxWidth = 460, color = "on_surface_variant" }))
    end
    if action then table.insert(children, action) end
    return ui.column({ key = "notice", flexGrow = 1, gap = 10, justify = "center", align = "center",
        fill = "surface_variant/0.35", radius = 12, padding = 24 }, children)
end

local function settingsButton()
    return ui.button({ glyph = "settings", text = tr("openSettings"), variant = "primary", onClick = function() showPage("settings") end })
end

local function retryButton()
    return ui.button({ glyph = "refresh", text = tr("retry"), variant = "primary", onClick = function() command("retry") end })
end

local function problemNotice()
    local detail = tr(view.problem, view.problemParams)
    if view.problem == "noUrlConfigured" or view.problem == "invalidUrl" then
        return notice("settings", "primary", tr("errorTitleSetup"), detail, settingsButton())
    elseif view.problem == "authFailed" then
        return notice("lock", "error", tr("errorTitleAuth"), detail,
            ui.button({ glyph = "key", text = tr("editCredentials"), variant = "primary", onClick = function() editCredentials() end }))
    elseif view.problem == "keyringFailed" then
        return notice("key", "error", tr("errorTitleKeyring"), detail, retryButton())
    end
    return notice("plug-connected-x", "error", tr("errorTitleConnection"), detail, retryButton())
end

local function viewerPage()
    local selected = view.selected or {}
    local title = view.camera and view.camera ~= "" and view.camera or tr("title")
    local header = {
        ui.glyph({ name = "device-cctv", color = view.connected and "primary" or "on_surface_variant" }),
        ui.label({ text = title, fontWeight = "bold", maxLines = 1, flexGrow = 1 }),
    }
    if #selected > 1 then
        table.insert(header, ui.label({ text = tostring(view.index or 1) .. " / " .. tostring(#selected), color = "on_surface_variant" }))
        table.insert(header, ui.button({ glyph = "chevron-left", variant = "ghost", tooltip = tr("previousCamera"),
            onClick = function() command("previous") end }))
        table.insert(header, ui.button({ glyph = "chevron-right", variant = "ghost", tooltip = tr("nextCamera"),
            onClick = function() command("next") end }))
    end
    local content = { headerButtons(header) }
    if view.frame and view.frame ~= "" then
        table.insert(content, ui.image({ key = "preview", path = view.frame, height = 400, flexGrow = 1, fit = "contain", radius = 12 }))
    elseif hasProblem() then
        table.insert(content, problemNotice())
    elseif #selected == 0 and view.connected and #(view.cameras or {}) == 0 then
        table.insert(content, notice("camera-off", "on_surface_variant", tr("noCamerasFound"), nil,
            ui.button({ glyph = "refresh", text = tr("listCameras"), variant = "primary", onClick = function() command("discover") end })))
    elseif #selected == 0 and view.connected then
        table.insert(content, notice("camera-off", "on_surface_variant", tr("noCamerasSelected"), nil, settingsButton()))
    else
        table.insert(content, notice("device-cctv", "on_surface_variant",
            tr(view.connected and "loadingStream" or "connecting"), nil, nil))
    end
    table.insert(content, statusRow())
    if view.message and view.message ~= "" then
        table.insert(content, ui.label({ text = tr(view.message), maxLines = 2, color = "error" }))
    end
    return content
end

local function section(title, children)
    table.insert(children, 1, ui.label({ text = title, fontWeight = "bold", color = "primary" }))
    return ui.column({ gap = 8 }, children)
end

local function settingsPage()
    local selected = view.selected or {}
    local header = {
        ui.button({ glyph = "chevron-left", variant = "ghost", tooltip = tr("back"), onClick = function() showPage("viewer") end }),
        ui.label({ text = tr("settings"), fontWeight = "bold", flexGrow = 1 }),
    }

    local server = section(tr("frigateServerUrl"), {
        ui.input({ key = "url", value = view.url or "", placeholder = "https://frigate.local:5000",
            onChange = function(text) command("url", text) end }),
        ui.label({ text = tr("serverUrlHint"), maxLines = 2, color = "on_surface_variant" }),
        statusRow(),
        ui.row({ gap = 8, align = "center" }, {
            ui.button({ glyph = "key", text = tr("editCredentials"), onClick = function() editCredentials() end }),
            ui.label({ text = tr(view.hasCredentials and "credentialsSet" or "credentialsNone"), color = "on_surface_variant", flexGrow = 1 }),
        }),
    })

    -- Index 0 means "first visible camera"; the select reports zero-based indexes.
    local options, current = { tr("firstCamera") }, 0
    for i, name in ipairs(selected) do
        table.insert(options, name)
        if name == view.defaultCamera then current = i end
    end
    local main = section(tr("defaultCamera"), {
        ui.select({ key = "default", options = options, selectedIndex = current, enabled = #selected > 0,
            onChange = function(value)
                local i = tonumber(value)
                if i then command("default", i > 0 and selected[i] or "") end
            end }),
        ui.label({ text = tr("defaultCameraHint"), maxLines = 2, color = "on_surface_variant" }),
    })

    local list = {
        ui.row({ gap = 8, align = "center" }, {
            ui.label({ text = tr("camerasSelected", { count = #selected }), color = "on_surface_variant", flexGrow = 1 }),
            ui.button({ glyph = "refresh", variant = "ghost", tooltip = tr("listCameras"), enabled = view.credentialsReady == true,
                onClick = function() command("discover") end }),
        }),
    }
    for _, name in ipairs(view.cameras or {}) do
        local checked = false
        for _, camera in ipairs(selected) do if camera == name then checked = true; break end end
        table.insert(list, ui.row({ key = name, gap = 12, align = "center" }, {
            ui.toggle({ checked = checked, onChange = function() command("toggle", name) end }),
            ui.label({ text = name, flexGrow = 1 }),
        }))
    end
    if #(view.cameras or {}) == 0 then
        table.insert(list, ui.label({ text = tr(view.connected and "noCamerasFound" or "camerasAfterConnect"), color = "on_surface_variant", maxLines = 2 }))
    end

    return {
        headerButtons(header),
        ui.scroll({ key = "settings", flexGrow = 1, gap = 20 }, {
            server, main, section(tr("visibleCameras"), list),
        }),
    }
end

render = function()
    if not opened then return end
    local content = page == "settings" and settingsPage() or viewerPage()
    panel.render(ui.column({ gap = 12, flexGrow = 1 }, content))
end

noctalia.state.watch("viewer", function(value)
    view = value or {}
    render()
end)

-- The bar's right click asks for the settings page, even while already open.
noctalia.state.watch("panelPage", function(value)
    -- While closed, leave the request for onOpen to read.
    if value == nil or not opened then return end
    noctalia.state.set("panelPage", nil)
    showPage(value == "settings" and "settings" or "viewer")
end)

function onOpen()
    opened = true
    page = noctalia.state.get("panelPage") == "settings" and "settings" or "viewer"
    noctalia.state.set("panelPage", nil)
    command("open")
    if page == "settings" then command("preview", false) end
    render()
end

function onClose()
    opened = false
    command("close")
end

function onKey(chord, pressed)
    if not pressed or page ~= "viewer" then return end
    if chord == "Left" then command("previous") end
    if chord == "Right" then command("next") end
end

function onExit()
    if opened then command("close") end
end
