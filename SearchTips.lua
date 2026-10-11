local _, MM = ...

local W, C = MM.W, MM.COLORS
local ACCENT, BORDER = C.accent, C.border
local Fill, Outline, Grain, Gradient = W.Fill, W.Outline, W.Grain, W.Gradient
local panel = MM.panel

-- Search tips window ----------------------------------------------------------

local function Tip(text) return "|cffffffff" .. text .. "|r" end

local TIPS = table.concat({
    "|cffccb084Searching|r",
    "Type all or part of a name. Every word has to match.",
    "Words also match categories: " .. Tip("tailoring materials") .. ", " .. Tip("food") .. ".",
    "Shorthands: " .. Tip("lw bs alch ench engi") .. ", " .. Tip("mats") .. " for materials.",
    "",
    "|cffccb084Gear|r",
    "Armor or weapon type and slot: " .. Tip("mail gloves") .. ", " .. Tip("2h sword") .. ".",
    "",
    "|cffccb084Levels|r",
    Tip("20-30") .. ", " .. Tip("45") .. ", " .. Tip("over 30") .. " or " .. Tip("under 30") .. ", with or without words: "
        .. Tip("food 10-20") .. ". For recipes it's the skill they need.",
    "",
    "|cffccb084Only what you can use|r",
    "Add " .. Tip("usable") .. " to hide anything with red text in its tooltip: " .. Tip("usable mail 20-30") .. ".",
    "",
    "|cffccb084Trainers and other NPCs|r",
    Tip("hunter trainer") .. ", " .. Tip("repair") .. ", " .. Tip("flight master") .. ", " .. Tip("mailbox") .. "...",
    "Nearest goes to the closest one, All shows every one on the map.",
    "",
    "|cffccb084Categories and holidays|r",
    "Click a category to search inside it. Holiday items show once that holiday is turned on.",
    "",
    "|cffccb084From chat|r",
    Tip("/mm hunter trainer") .. ". A single match goes straight to the nearest one.",
    "",
    "|cffccb084Once you've found it|r",
    "Click an item to mark its nearest vendor, and target them when close enough. "
        .. "Shift-click to link it in chat.",
    "Or click " .. Tip("Nearest vendor for") .. " at the top for the closest vendor selling anything in your results.",
}, "\n")

local tips = CreateFrame("Frame", "MerchantMapSearchTips", UIParent)
tips:SetSize(380, 330)
tips:SetPoint("CENTER", -240, 0)
tips:SetFrameStrata("FULLSCREEN_DIALOG")
tips:SetClampedToScreen(true)
tips:SetMovable(true)
tips:EnableMouse(true)
tips:RegisterForDrag("LeftButton")
tips:SetScript("OnDragStart", tips.StartMoving)
tips:SetScript("OnDragStop", tips.StopMovingOrSizing)
tips:Hide()
Fill(tips, C.bg, 0.97)
Grain(tips, 0.35)
Outline(tips, BORDER)
tinsert(UISpecialFrames, "MerchantMapSearchTips")
-- Closes when combat starts
tips:RegisterEvent("PLAYER_REGEN_DISABLED")
tips:SetScript("OnEvent", tips.Hide)

local tipsHeader = CreateFrame("Frame", nil, tips)
tipsHeader:SetPoint("TOPLEFT", 1, -1)
tipsHeader:SetPoint("TOPRIGHT", -1, -1)
tipsHeader:SetHeight(25)
Gradient(tipsHeader, C.bg, C.header)
local tipsTitle = tipsHeader:CreateFontString(nil, "OVERLAY", "MM_GameFontNormal")
tipsTitle:SetPoint("TOPLEFT", 10, -7)
tipsTitle:SetText("Search tips")
tipsTitle:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
local tipsClose = CreateFrame("Button", nil, tipsHeader)
tipsClose:SetSize(20, 20)
tipsClose:SetPoint("TOPRIGHT", -4, -2)
tipsClose:SetNormalFontObject("MM_GameFontHighlight")
tipsClose:SetHighlightFontObject("MM_GameFontNormal")
tipsClose:SetText("x")
tipsClose:SetScript("OnClick", function() tips:Hide() end)

-- The text scrolls with the mouse wheel or the thin bar on the right
local tipsScroll = CreateFrame("ScrollFrame", nil, tips)
tipsScroll:SetPoint("TOPLEFT", 12, -34)
tipsScroll:SetPoint("BOTTOMRIGHT", -22, 10)
local tipsContent = CreateFrame("Frame", nil, tipsScroll)
tipsContent:SetSize(1, 1)
tipsScroll:SetScrollChild(tipsContent)
local tipsText = tipsContent:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
tipsText:SetPoint("TOPLEFT")
tipsText:SetJustifyH("LEFT")
tipsText:SetSpacing(3)
tipsText:SetTextColor(unpack(C.text))
tipsText:SetText(TIPS)

local tipsBar = CreateFrame("Slider", nil, tips)
tipsBar:SetPoint("TOPRIGHT", -8, -34)
tipsBar:SetPoint("BOTTOMRIGHT", -8, 10)
tipsBar:SetWidth(6)
tipsBar:SetOrientation("VERTICAL")
tipsBar:SetMinMaxValues(0, 0)
local tipsTrack = tipsBar:CreateTexture(nil, "BACKGROUND")
tipsTrack:SetAllPoints()
tipsTrack:SetColorTexture(1, 1, 1, 0.05)
local tipsThumb = tipsBar:CreateTexture(nil, "ARTWORK")
tipsThumb:SetSize(6, 40)
tipsThumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
tipsBar:SetThumbTexture(tipsThumb)
tipsBar:SetScript("OnValueChanged", function(_, value) tipsScroll:SetVerticalScroll(value) end)
tipsScroll:EnableMouseWheel(true)
tipsScroll:SetScript("OnMouseWheel", function(_, delta) tipsBar:SetValue(tipsBar:GetValue() - delta * 40) end)

local function LayoutTips()
    local width = tipsScroll:GetWidth()
    tipsText:SetWidth(width)
    tipsContent:SetSize(width, tipsText:GetStringHeight() + 4)
    local range = math.max(0, tipsContent:GetHeight() - tipsScroll:GetHeight())
    tipsBar:SetMinMaxValues(0, range)
    tipsBar:SetShown(range > 0)
end
-- Same strata as the main window, so it needs a frame level above everything in it
tips:SetScript("OnShow", function()
    tips:SetScale(MM.db.windowScale or 1)
    tips:SetFrameLevel(panel:GetFrameLevel() + 100)
    LayoutTips()
end)
tinsert(W.scaled, tips)
tipsScroll:SetScript("OnSizeChanged", LayoutTips)

function MM:ToggleSearchTips()
    tips:SetShown(not tips:IsShown())
end
