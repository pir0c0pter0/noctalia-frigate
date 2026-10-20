--!nonstrict
local tr = noctalia.tr
local view = noctalia.state.get("viewer") or {}
local opened = false
local showCameras = false
local function command(action, value)
    noctalia.state.set("command", { action = action, value = value })
end

local function render()
    if not opened then return end
    local selected = view.selected or {}
    local header = {
        ui.glyph({ name = "camera-video", color = view.connected and "primary" or "error" }),
        ui.label({ text = view.camera and view.camera ~= "" and view.camera or tr("title"), flexGrow = 1, fontWeight = "bold" }),
        ui.button({ glyph = "chevron-left", tooltip = tr("previousCamera"), enabled = #selected > 1,
            onClick = function() command("previous") end }),
        ui.button({ glyph = "chevron-right", tooltip = tr("nextCamera"), enabled = #selected > 1,
            onClick = function() command("next") end }),
    }
    if noctalia.getSetting("shell.show_close_buttons") ~= false then
        table.insert(header, ui.button({ glyph = "close", tooltip = tr("close"), onClick = function() panel.close() end }))
    end
    local content = { ui.row({ gap = 8, align = "center" }, header) }
    if showCameras then
        local rows = { ui.label({ text = tr("selectCamerasHint"), maxLines = 3 }) }
        for _, name in ipairs(view.cameras or {}) do
            local checked = false
            for _, camera in ipairs(selected) do if camera == name then checked = true; break end end
            table.insert(rows, ui.row({ key = name, gap = 12, align = "center" }, {
                ui.toggle({ checked = checked, onChange = function() command("toggle", name) end }),
                ui.label({ text = name, flexGrow = 1 }),
            }))
        end
        table.insert(rows, ui.label({ text = tr("camerasSelected", { count = #selected }), color = "on_surface_variant" }))
        table.insert(content, ui.scroll({ key = "selection", flexGrow = 1, gap = 12 }, rows))
    elseif view.frame and view.frame ~= "" then
        table.insert(content, ui.image({ key = "preview", path = view.frame, height = view.message and view.message ~= "" and 260 or 320, fit = "contain", flexGrow = 1 }))
    else
        local key = #selected == 0 and "noCamerasConfigured" or "loadingStream"
        table.insert(content, ui.column({ flexGrow = 1, justify = "center", align = "center" }, {
            ui.label({ text = tr(key), textAlign = "center", maxLines = 4, color = "on_surface_variant" }),
        }))
    end
    if view.message and view.message ~= "" then
        table.insert(content, ui.label({ text = tr(view.message, view.messageParams), maxLines = 3, color = "on_surface_variant" }))
    end
    table.insert(content, ui.row({ gap = 8 }, {
        ui.button({ glyph = "list-check", text = tr(showCameras and "backToViewer" or "cameraSelection"),
            onClick = function()
                showCameras = not showCameras
                command("preview", not showCameras)
                render()
            end }),
        ui.button({ glyph = "refresh", text = tr("listCameras"), enabled = view.credentialsReady == true, onClick = function() command("discover") end }),
        ui.button({ glyph = "plug-connected", tooltip = tr("testConnection"), enabled = view.credentialsReady == true, onClick = function() command("test") end }),
        ui.button({ glyph = "settings", tooltip = tr("settings"), onClick = function() noctalia.openSettings() end }),
    }))
    table.insert(content, ui.row({ gap = 8 }, {
        ui.button({ glyph = "key", text = tr("editCredentials"), onClick = "editCredentials" }),
        ui.button({ glyph = "reload", text = tr("reloadCredentials"), onClick = function() command("reloadCredentials") end }),
    }))
    panel.render(ui.column({ gap = 12, flexGrow = 1 }, content))
end

noctalia.state.watch("viewer", function(value)
    view = value or {}
    render()
end)

function editCredentials()
    local dir = noctalia.pluginDir()
    if not dir then return end
    -- runInTerminal accepts a shell string; quote the path, never interpolate secrets.
    local script = (dir .. "/Credentials.sh"):gsub("'", "'\\''")
    if not noctalia.runInTerminal("bash '" .. script .. "'") then
        noctalia.notifyError(tr("title"), tr("terminalFailed"))
    end
end

function onOpen()
    opened = true
    showCameras = false
    command("open")
    render()
end

function onClose()
    opened = false
    command("close")
end

function onKey(chord, pressed)
    if not pressed or showCameras then return end
    if chord == "Left" then command("previous") end
    if chord == "Right" then command("next") end
end

function onExit()
    if opened then command("close") end
end
