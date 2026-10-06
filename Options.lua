local _, VA = ...

-- Page under Options > AddOns: a few toggles, the share screen, and a short guide.

local C = VA.COLORS
local ACCENT, BORDER = C.accent, C.border

local HELP = [[
|cffccb084Recording|r
Open a vendor's shop and Vendor Atlas records what they sell and where they stand. Talking to trainers, flight masters and other service NPCs records them too. For NPCs that won't talk to you, target them within 10 yards.

|cffccb084Searching|r
Open the window with |cffffffff/va|r or the minimap button. Search by name, category or shorthand ("tailoring mats", "lw recipes"), by level ("food 10-20", "45", "over 30") or for services ("hunter trainer", "repair"). Drag items onto categories to sort them, right-click to remove them.

|cffccb084Finding a vendor|r
Click an item to target the closest vendor and put a raid marker on them, show them on the minimap and point the arrow at them. Shift-click a map pin for a waypoint, alt-click to hide it. The VA button on the world map picks which pins show.

|cffccb084Verifying|r
Red pins are Classic data that hasn't been confirmed in Forever. Visit or talk to them to confirm.

|cffccb084Commands|r
|cffffffff/va|r  |cffffffff/va arrow|r  |cffffffff/va share|r  |cffffffff/va auto|r  |cffffffff/va minimap|r]]

local panel = CreateFrame("Frame")
panel:Hide()

local title = panel:CreateFontString(nil, "OVERLAY", "VA_GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Vendor Atlas")
title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])

-- Checkbox in the addon's style: bordered square, filled when on
local checks = {}
local function Check(text, note, get, set, y)
    local row = CreateFrame("Button", nil, panel)
    row:SetSize(360, 22)
    row:SetPoint("TOPLEFT", 16, y)

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

    local label = row:CreateFontString(nil, "OVERLAY", "VA_GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(text)
    local hint = row:CreateFontString(nil, "OVERLAY", "VA_GameFontDisableSmall")
    hint:SetPoint("LEFT", label, "RIGHT", 10, 0)
    hint:SetText(note)

    function row:Update() fill:SetShown(get()) end
    row:SetScript("OnClick", function(self)
        set(not get())
        self:Update()
    end)
    checks[#checks + 1] = row
end

Check("Direction arrow", "Points to the marked vendor",
    function() return not VA.db.arrowHidden end,
    function(on) VA:SetArrowShown(on) end, -50)

Check("Lock arrow position", "So it can't be dragged by accident",
    function() return VA.db.arrowLocked end,
    function(on) VA.db.arrowLocked = on or nil end, -76)

-- Arrow size slider, 50% to 200%
local sizeLabel = panel:CreateFontString(nil, "OVERLAY", "VA_GameFontHighlight")
sizeLabel:SetPoint("TOPLEFT", 16, -108)
sizeLabel:SetText("Arrow size")

local slider = CreateFrame("Slider", nil, panel)
slider:SetSize(160, 14)
slider:SetPoint("LEFT", sizeLabel, "RIGHT", 12, 0)
slider:SetOrientation("HORIZONTAL")
slider:SetMinMaxValues(0.5, 2)
slider:SetValueStep(0.1)
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

local sizeValue = panel:CreateFontString(nil, "OVERLAY", "VA_GameFontDisableSmall")
sizeValue:SetPoint("LEFT", slider, "RIGHT", 10, 0)

-- Preview at the chosen size, off to the right so the largest size doesn't cover other options
local preview = panel:CreateTexture(nil, "ARTWORK")
preview:SetPoint("CENTER", panel, "TOPLEFT", 520, -115)
preview:SetTexture(VA.ARROW_TEXTURE)
preview:SetVertexColor(0.35, 0.85, 0.35)

slider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value * 10 + 0.5) / 10
    sizeValue:SetText(("%d%%"):format(value * 100))
    preview:SetSize(56 * value, 56 * value)
    VA:SetArrowSize(value)
end)
slider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(self:GetValue() + delta * 0.1)
end)

Check("Open the map automatically", "When you click an item or service",
    function() return not VA.db.noAutoMap end,
    function(on) VA.db.noAutoMap = not on or nil end, -134)

Check("Minimap button", "Left-click opens Vendor Atlas",
    function() return not (VA.db.minimapButton and VA.db.minimapButton.hide) end,
    function(on) VA:SetMinimapButtonShown(on) end, -160)

-- Raid marker dropdown
local MARKERS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local function MarkerIcon(i) return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i end

local function Box(frame, color)
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    local fill = frame:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(color[1], color[2], color[3], 1)
end

local markerLabel = panel:CreateFontString(nil, "OVERLAY", "VA_GameFontHighlight")
markerLabel:SetPoint("TOPLEFT", 16, -192)
markerLabel:SetText("Target marker")

local dropdown = CreateFrame("Button", nil, panel)
dropdown:SetSize(130, 22)
dropdown:SetPoint("LEFT", markerLabel, "RIGHT", 12, 0)
Box(dropdown, C.buttonTop)
local ddHl = dropdown:CreateTexture()
ddHl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
dropdown:SetHighlightTexture(ddHl)
local ddIcon = dropdown:CreateTexture(nil, "ARTWORK")
ddIcon:SetSize(14, 14)
ddIcon:SetPoint("LEFT", 6, 0)
local ddText = dropdown:CreateFontString(nil, "OVERLAY", "VA_GameFontHighlightSmall")
ddText:SetPoint("LEFT", ddIcon, "RIGHT", 6, 0)
local ddArrow = dropdown:CreateFontString(nil, "OVERLAY", "VA_GameFontDisableSmall")
ddArrow:SetPoint("RIGHT", -7, 0)
ddArrow:SetText("v")

local markerNote = panel:CreateFontString(nil, "OVERLAY", "VA_GameFontDisableSmall")
markerNote:SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
markerNote:SetText("Put on the vendor you click")

local function UpdateDropdown()
    local i = VA.db.raidMarker or 8
    ddIcon:SetTexture(MarkerIcon(i))
    ddText:SetText(MARKERS[i])
end

local list = CreateFrame("Frame", nil, dropdown)
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
    local text = row:CreateFontString(nil, "OVERLAY", "VA_GameFontHighlightSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetText(markerName)
    row:SetScript("OnClick", function()
        VA:SetRaidMarker(i)
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

local share = CreateFrame("Button", nil, panel)
share:SetSize(170, 22)
share:SetPoint("TOPLEFT", 16, -224)
local border = share:CreateTexture(nil, "BACKGROUND")
border:SetAllPoints()
border:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
local bg = share:CreateTexture(nil, "BORDER")
bg:SetPoint("TOPLEFT", 1, -1)
bg:SetPoint("BOTTOMRIGHT", -1, 1)
bg:SetColorTexture(C.buttonTop[1], C.buttonTop[2], C.buttonTop[3], 1)
local hl = share:CreateTexture()
hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
share:SetHighlightTexture(hl)
share:SetNormalFontObject("VA_GameFontHighlightSmall")
share:SetText("Share verified data...")
share:SetScript("OnClick", function() VA:ToggleShare() end)

local shareNote = panel:CreateFontString(nil, "OVERLAY", "VA_GameFontDisableSmall")
shareNote:SetPoint("LEFT", share, "RIGHT", 10, 0)
shareNote:SetText("Export what you've verified, or import someone else's")

local help = panel:CreateFontString(nil, "OVERLAY", "VA_GameFontHighlightSmall")
help:SetPoint("TOPLEFT", 16, -262)
help:SetPoint("RIGHT", -16, 0)
help:SetJustifyH("LEFT")
help:SetSpacing(2)
help:SetText(HELP)

panel:SetScript("OnShow", function()
    for _, row in ipairs(checks) do row:Update() end
    UpdateDropdown()
    slider:SetValue(VA.db.arrowScale or 1)
end)

local category = Settings.RegisterCanvasLayoutCategory(panel, "Vendor Atlas")
Settings.RegisterAddOnCategory(category)

function VA:OpenOptions()
    Settings.OpenToCategory(category:GetID())
end