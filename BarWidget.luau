--!nonstrict
local function render(view)
    local connected = view and view.connected
    barWidget.setGlyph("device-cctv")
    barWidget.setGlyphColor(connected and "primary" or "error")
    barWidget.setTooltip(noctalia.tr(connected and "tooltipConnected" or "tooltipDisconnected"))
end

noctalia.state.watch("viewer", render)
render(noctalia.state.get("viewer"))

function onClick()
    noctalia.togglePanel("pir0c0pter0/frigate:viewer")
end

function onRightClick()
    local view = noctalia.state.get("viewer")
    noctalia.state.set("panelPage", "settings")
    if not (view and view.opened) then noctalia.togglePanel("pir0c0pter0/frigate:viewer") end
end
