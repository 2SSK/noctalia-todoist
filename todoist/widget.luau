--!nonstrict
-- Todoist bar widget -- shows the active todo count, opens the panel.

local PANEL_ID = "2SSK/todoist:panel"

local function render()
  barWidget.setGlyph("clipboard-check")
  barWidget.setTooltip(noctalia.tr("panel.title"))
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end

noctalia.state.watch("count", function(_value)
  render()
end)

render()
