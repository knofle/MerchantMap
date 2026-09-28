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
Click an item to target and skull the closest vendor, mark it on the minimap and point the arrow at it. Shift-click a map pin for a waypoint, alt-click to hide it. The VA button on the world map picks which pins show.

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

Check("Open the map automatically", "When you click an item or service",
    function() return not VA.db.noAutoMap end,
    function(on) VA.db.noAutoMap = not on or nil end, -76)

local share = CreateFrame("Button", nil, panel)
share:SetSize(170, 22)
share:SetPoint("TOPLEFT", 16, -108)
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
help:SetPoint("TOPLEFT", 16, -146)
help:SetPoint("RIGHT", -16, 0)
help:SetJustifyH("LEFT")
help:SetSpacing(2)
help:SetText(HELP)

panel:SetScript("OnShow", function()
    for _, row in ipairs(checks) do row:Update() end
end)

local category = Settings.RegisterCanvasLayoutCategory(panel, "Vendor Atlas")
Settings.RegisterAddOnCategory(category)