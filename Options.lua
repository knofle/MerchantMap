local _, MM = ...

-- Page under Options > AddOns: a few toggles, the share screen, and a short guide.

local C = MM.COLORS
local ACCENT, BORDER = C.accent, C.border

local HELP = [[
|cffccb084Recording|r
Vendors and service NPCs come from Classic data. Open a vendor's shop and Merchant Map records their prices, any items the Classic data is missing, and where they stand. Talking to trainers, flight masters and other service NPCs records where they stand too. For NPCs that won't talk to you, target them within 10 yards.

|cffccb084Searching|r
Open the window with |cffffffff/mm|r or the minimap button, or search straight from chat with |cffffffff/mm hunter trainer|r. Search by name, category or shorthand ("tailoring mats", "lw recipes"), by level ("food 10-20", "45", "over 30"), add "usable" for only what you can use ("usable gear 20-30"), or search for services ("hunter trainer", "repair"). Drag items onto categories to sort them, right-click to remove them.

|cffccb084Finding a vendor|r
Click an item to target the closest vendor and put a raid marker on them, show them on the minimap and point the arrow at them. Shift-click a vendor on the map for their full inventory, alt-click a pin to hide it. The MM button on the world map picks which pins show.

|cffccb084Commands|r
|cffffffff/mm|r  |cffffffff/mm <search>|r  |cffffffff/mm options|r  |cffffffff/mm arrow|r  |cffffffff/mm share|r  |cffffffff/mm auto|r  |cffffffff/mm minimap|r]]

-- The page scrolls: everything is laid out on its content frame, panel
local page = CreateFrame("Frame")
page:Hide()
local scroll = CreateFrame("ScrollFrame", nil, page)
scroll:SetPoint("TOPLEFT")
scroll:SetPoint("BOTTOMRIGHT", -14, 0)
local panel = CreateFrame("Frame", nil, scroll)
panel:SetSize(1, 1)
scroll:SetScrollChild(panel)

local bar = CreateFrame("Slider", nil, page)
bar:SetPoint("TOPRIGHT", -4, -4)
bar:SetPoint("BOTTOMRIGHT", -4, 4)
bar:SetWidth(6)
bar:SetOrientation("VERTICAL")
bar:SetMinMaxValues(0, 0)
local barTrack = bar:CreateTexture(nil, "BACKGROUND")
barTrack:SetAllPoints()
barTrack:SetColorTexture(C.inset[1], C.inset[2], C.inset[3], 1)
local barThumb = bar:CreateTexture(nil, "ARTWORK")
barThumb:SetSize(6, 40)
barThumb:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
bar:SetThumbTexture(barThumb)
bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(_, delta) bar:SetValue(bar:GetValue() - delta * 40) end)

local title = panel:CreateFontString(nil, "OVERLAY", "MM_GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Merchant Map")
title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

-- Layout runs top to bottom from here, in the column at x (colWidth nil runs to the right edge)
local y, x, colWidth = -52, 16, nil

-- Section heading with a thin rule under it
local function Section(text)
    y = y - 10
    local label = panel:CreateFontString(nil, "OVERLAY", "MM_GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(text)
    label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    local rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    if colWidth then rule:SetWidth(colWidth) else rule:SetPoint("RIGHT", panel, "RIGHT", -16, 0) end
    rule:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    y = y - 26
end

-- Checkbox in the addon's style: bordered square, filled when on
local checks = {}
local function Check(text, note, get, set)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(colWidth and colWidth - 8 or 360, 22)
    row:SetPoint("TOPLEFT", x + 8, y)
    y = y - 26

    local box = row:CreateTexture(nil, "BORDER")
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    box:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    local inner = row:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", box, 1, -1)
    inner:SetPoint("BOTTOMRIGHT", box, -1, 1)
    inner:SetColorTexture(C.inset[1], C.inset[2], C.inset[3], 1)
    local fill = row:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", box, 3, -3)
    fill:SetPoint("BOTTOMRIGHT", box, -3, 3)
    fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)

    local label = row:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(text)
    local hint = row:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
    hint:SetPoint("LEFT", label, "RIGHT", 10, 0)
    hint:SetText(note)

    row.label = label
    function row:Update()
        fill:SetShown(get())
        if self.OnUpdate then self:OnUpdate(get()) end
    end
    row:SetScript("OnClick", function(self)
        set(not get())
        self:Update()
    end)
    checks[#checks + 1] = row
    return row
end

local function Box(frame, color)
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    local fill = frame:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(color[1], color[2], color[3], 1)
end

local function Button(text, width)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(width, 22)
    Box(b, C.buttonTop)
    local hl = b:CreateTexture()
    hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
    b:SetHighlightTexture(hl)
    b:SetNormalFontObject("MM_GameFontHighlightSmall")
    b:SetText(text)
    return b
end

-- Two sections side by side: start with Columns(), switch with NextColumn(), finish with EndColumns()
local COL_W, GAP = 280, 24

local function Columns()
    colWidth = COL_W
    return y
end

local function NextColumn(top)
    local leftBottom = y
    y, x = top, 16 + COL_W + GAP
    return leftBottom
end

-- Draws the line between the columns and carries on below the taller one
local function EndColumns(top, leftBottom)
    local bottom = math.min(y, leftBottom)
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", 16 + COL_W + GAP / 2, top - 10)
    divider:SetHeight(top - 10 - bottom)
    divider:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    y, x, colWidth = bottom, 16, nil
end

-- Slider in the addon's style, its value shown as a percentage
local function Slider(text, min, max, step, onChange)
    local label = panel:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlight")
    label:SetPoint("TOPLEFT", x + 8, y - 4)
    label:SetText(text)
    y = y - 30

    local slider = CreateFrame("Slider", nil, panel)
    slider:SetSize(120, 14)
    slider:SetPoint("LEFT", label, "RIGHT", 12, 0)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, 14)
    thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    slider:SetThumbTexture(thumb)

    local shown = panel:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
    shown:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        shown:SetText(("%d%%"):format(value * 100 + 0.5))
        onChange(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    return slider
end

-- Text dropdown: choices are { value, label } pairs. With a text it gets its own labelled row;
-- with a frame instead it sits to the right of that, on the same row.
local function Dropdown(text, choices, get, set)
    local label = text
    if type(text) == "string" then
        label = panel:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlight")
        label:SetPoint("TOPLEFT", x + 8, y - 4)
        label:SetText(text)
        y = y - 30
    end

    local button = CreateFrame("Button", nil, panel)
    button:SetSize(130, 22)
    button:SetPoint("LEFT", label, "RIGHT", 12, 0)
    Box(button, C.buttonTop)
    local hl = button:CreateTexture()
    hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
    button:SetHighlightTexture(hl)
    local current = button:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
    current:SetPoint("LEFT", 8, 0)
    local arrow = button:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
    arrow:SetPoint("RIGHT", -7, 0)
    arrow:SetText("v")

    local function Update()
        for _, choice in ipairs(choices) do
            if choice[1] == get() then current:SetText(choice[2]) end
        end
    end

    local menu = CreateFrame("Frame", nil, page)
    menu:SetSize(130, #choices * 20 + 6)
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    menu:Hide()
    Box(menu, C.bg)
    for i, choice in ipairs(choices) do
        local row = CreateFrame("Button", nil, menu)
        row:SetSize(124, 20)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 20)
        local rowHl = row:CreateTexture()
        rowHl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
        row:SetHighlightTexture(rowHl)
        local rowText = row:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
        rowText:SetPoint("LEFT", 6, 0)
        rowText:SetText(choice[2])
        row:SetScript("OnClick", function()
            set(choice[1])
            Update()
            menu:Hide()
        end)
    end

    -- Closes on a click anywhere else, or when the page scrolls
    menu:SetScript("OnShow", function(self)
        arrow:SetText("^")
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    menu:SetScript("OnHide", function(self)
        arrow:SetText("v")
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    menu:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not button:IsMouseOver() then self:Hide() end
    end)
    button:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
    scroll:HookScript("OnVerticalScroll", function() menu:Hide() end)
    return Update
end

------------------------------------------------------------------------------------------------
-- When clicking on the left, Minimap on the right
local clickTop = Columns()
Section("When clicking an item or NPC in the list")

Check("Open the map", "",
    function() return not MM.db.noAutoMap end,
    function(on) MM.db.noAutoMap = not on or nil end)

Check("Set minimap marker", "When on this continent",
    function() return not MM.db.noMinimapPin end,
    function(on) MM:SetMinimapPinShown(on) end)

Check("Set waypoint", "",
    function() return MM.db.autoWaypoint end,
    function(on) MM.db.autoWaypoint = on or nil end)

-- Checkbox turns raid markers on or off; the dropdown picks which one
local MARKERS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local function MarkerIcon(i) return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i end

local markerCheck = Check("Set target marker", "",
    function() return not MM.db.noRaidMarker end,
    function(on) MM:SetRaidMarkerEnabled(on) end)
markerCheck:SetWidth(140)

local dropdown = CreateFrame("Button", nil, panel)
dropdown:SetSize(130, 22)
dropdown:SetPoint("LEFT", markerCheck.label, "RIGHT", 12, 0)
Box(dropdown, C.buttonTop)
local ddHl = dropdown:CreateTexture()
ddHl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
dropdown:SetHighlightTexture(ddHl)
local ddIcon = dropdown:CreateTexture(nil, "ARTWORK")
ddIcon:SetSize(14, 14)
ddIcon:SetPoint("LEFT", 6, 0)
local ddText = dropdown:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
ddText:SetPoint("LEFT", ddIcon, "RIGHT", 6, 0)
local ddArrow = dropdown:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
ddArrow:SetPoint("RIGHT", -7, 0)
ddArrow:SetText("v")



local function UpdateDropdown()
    local i = MM.db.raidMarker or 8
    ddIcon:SetTexture(MarkerIcon(i))
    ddText:SetText(MARKERS[i])
end

-- On the page rather than the scrolling content, so the scroll frame doesn't cut it off
local list = CreateFrame("Frame", nil, page)
list:SetSize(130, #MARKERS * 20 + 6)
list:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
list:SetFrameStrata("FULLSCREEN_DIALOG")
list:EnableMouse(true)
list:Hide()
Box(list, C.bg)

for i, markerName in ipairs(MARKERS) do
    local row = CreateFrame("Button", nil, list)
    row:SetSize(124, 20)
    row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 20)
    local hl = row:CreateTexture()
    hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
    row:SetHighlightTexture(hl)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 4, 0)
    icon:SetTexture(MarkerIcon(i))
    local text = row:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetText(markerName)
    row:SetScript("OnClick", function()
        MM:SetRaidMarker(i)
        UpdateDropdown()
        list:Hide()
    end)
end

-- Closes on a click anywhere else
list:SetScript("OnShow", function(self)
    ddArrow:SetText("^")
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
end)
list:SetScript("OnHide", function(self)
    ddArrow:SetText("v")
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end)
list:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not dropdown:IsMouseOver() then self:Hide() end
end)
dropdown:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
scroll:HookScript("OnVerticalScroll", function() list:Hide() end)

-- Dropdown is dimmed while markers are off
function markerCheck:OnUpdate(on)
    dropdown:SetEnabled(on)
    dropdown:SetAlpha(on and 1 or 0.4)
    if not on then list:Hide() end
end

local clickBottom = NextColumn(clickTop)
Section("Buttons")

Check("Minimap button", "Opens Merchant Map",
    function() return not (MM.db.minimapButton and MM.db.minimapButton.hide) end,
    function(on) MM:SetMinimapButtonShown(on) end)

local mapButtonCheck = Check("World map button", "",
    function() return not MM.db.noMapButton end,
    function(on) MM:SetMapButtonShown(on) end)
mapButtonCheck:SetWidth(140)

local UpdateMapButtonDropdown = Dropdown(mapButtonCheck.label, {
    { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" },
    { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" },
}, function() return MM.db.mapButtonCorner or "TOPRIGHT" end,
   function(value) MM:SetMapButtonCorner(value) end)

EndColumns(clickTop, clickBottom)

------------------------------------------------------------------------------------------------
-- Window on the left, Direction arrow on the right
local top = Columns()
Section("Window")

local scaleSlider = Slider("Scale", 0.75, 1.5, 0.05, function(value) MM:SetWindowScale(value) end)

local UpdateTooltipDropdown = Dropdown("Tooltip position", {
    { "top", "Top" }, { "left", "Left" }, { "right", "Right" }, { "below", "Below" }, { "mouse", "Mouse" },
}, function() return MM.db.tooltipAnchor or "below" end,
   function(value) MM.db.tooltipAnchor = value ~= "below" and value or nil end)
local leftBottom = NextColumn(top)
Section("Direction arrow")
local arrowTop = y

Check("Show", "When on this continent",
    function() return not MM.db.arrowHidden end,
    function(on) MM:SetArrowShown(on) end)

Check("Lock position", "",
    function() return MM.db.arrowLocked end,
    function(on) MM.db.arrowLocked = on or nil end)

-- Size, with a preview at the chosen size beside the options
local preview = panel:CreateTexture(nil, "ARTWORK")
preview:SetTexture(MM.ARROW_TEXTURE)
preview:SetVertexColor(0.35, 0.85, 0.35)

local slider = Slider("Size", 0.5, 2, 0.1, function(value)
    preview:SetSize(56 * value, 56 * value)
    MM:SetArrowSize(value)
end)
preview:SetPoint("CENTER", panel, "TOPLEFT", x + COL_W - 25, (arrowTop + y) / 2)

EndColumns(top, leftBottom)

------------------------------------------------------------------------------------------------
Section("Sharing")

local share = Button("Share recorded data...", 170)
share:SetPoint("TOPLEFT", 24, y)
share:SetScript("OnClick", function() MM:ToggleShare() end)
y = y - 30

local shareNote = panel:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
shareNote:SetPoint("LEFT", share, "RIGHT", 10, 0)
shareNote:SetText("Export what you've recorded, or import someone else's")

------------------------------------------------------------------------------------------------
Section("How it works")

local help = panel:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
help:SetPoint("TOPLEFT", 24, y)
help:SetPoint("RIGHT", -16, 0)
help:SetJustifyH("LEFT")
help:SetSpacing(2)
help:SetText(HELP)

-- Content is as tall as the layout plus the help text, which wraps to the page width
local function UpdateScroll()
    panel:SetWidth(scroll:GetWidth())
    local height = -y + help:GetStringHeight() + 16
    panel:SetHeight(height)
    local range = math.max(0, height - scroll:GetHeight())
    bar:SetMinMaxValues(0, range)
    bar:SetShown(range > 0)
end
scroll:SetScript("OnSizeChanged", UpdateScroll)

page:SetScript("OnShow", function()
    UpdateScroll()
    for _, row in ipairs(checks) do row:Update() end
    UpdateDropdown()
    UpdateTooltipDropdown()
    UpdateMapButtonDropdown()
    scaleSlider:SetValue(MM.db.windowScale or 1)
    slider:SetValue(MM.db.arrowScale or 1)
end)

local category = Settings.RegisterCanvasLayoutCategory(page, "Merchant Map")
Settings.RegisterAddOnCategory(category)

function MM:OpenOptions()
    Settings.OpenToCategory(category:GetID())
end