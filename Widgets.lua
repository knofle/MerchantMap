local _, MM = ...

-- Shared frame helpers for the window and the frames it opens. Other files take them from MM.W.

local C = MM.COLORS
local ACCENT, BORDER = C.accent, C.border
local W = {}
MM.W = W

local function Border(frame, r, g, b, a)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a or 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
            t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
            t:SetWidth(1)
        end
    end
end

local function Background(frame, r, g, b, a)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

local function Fill(frame, color, alpha)
    return Background(frame, color[1], color[2], color[3], alpha or 1)
end

local function Outline(frame, color, alpha)
    Border(frame, color[1], color[2], color[3], alpha or 1)
end

-- Subtle tiled grain over a flat fill
local function Grain(frame, alpha)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    t:SetAllPoints()
    t:SetTexture(MM.GRAIN, "REPEAT", "REPEAT")
    t:SetHorizTile(true)
    t:SetVertTile(true)
    t:SetAlpha(alpha)
end

-- Vertical gradient between two colors, lighter at the top
local function Gradient(frame, bottom, top, layer, sublevel)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 2)
    t:SetAllPoints()
    t:SetColorTexture(1, 1, 1, 1)
    if t.SetGradient and CreateColor then
        t:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1),
            CreateColor(top[1], top[2], top[3], 1))
    else
        t:SetColorTexture(bottom[1], bottom[2], bottom[3], 1)
    end
    return t
end

-- Raised button look: gradient face, bronze edge, soft hover
local function SkinButton(b)
    Gradient(b, C.button, C.buttonTop)
    Outline(b, BORDER)
    local hl = b:CreateTexture()
    hl:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.12)
    b:SetHighlightTexture(hl)
end

local function EditBox(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetFontObject("MM_ChatFontNormal")
    box:SetAutoFocus(false)
    box:SetTextInsets(6, 6, 0, 0)
    Fill(box, C.inset, 0.95)
    Outline(box, BORDER)
    return box
end

local function TextButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 20)
    SkinButton(b)
    b:SetNormalFontObject("MM_GameFontHighlightSmall")
    b:SetHighlightFontObject("MM_GameFontNormalSmall")
    b:SetDisabledFontObject("MM_GameFontDisableSmall")
    b:SetText(text)
    return b
end

local function SetTooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local SCROLL_W = 8

-- Thin track with a draggable thumb. frame.onScroll(pos) is set once the frame's draw function exists.
local function AddScrollbar(frame)
    frame.track = frame:CreateTexture(nil, "ARTWORK")
    frame.track:SetPoint("TOPRIGHT")
    frame.track:SetPoint("BOTTOMRIGHT")
    frame.track:SetWidth(SCROLL_W)
    frame.track:SetColorTexture(1, 1, 1, 0.05)

    local thumb = CreateFrame("Frame", nil, frame)
    thumb:SetWidth(SCROLL_W)
    thumb:EnableMouse(true)
    local tex = thumb:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)

    thumb:SetScript("OnEnter", function() tex:SetAlpha(1) end)
    thumb:SetScript("OnLeave", function(self)
        if not self.dragY then tex:SetAlpha(0.7) end
    end)
    -- OnUpdate only runs while dragging
    local function Drag(self)
        local _, y = GetCursorPosition()
        local travel = frame:GetHeight() - self:GetHeight()
        if travel > 0 then
            local moved = (self.dragY - y / self:GetEffectiveScale()) / travel
            frame.onScroll(math.floor(self.dragPos + moved * (frame.scrollTotal - frame.scrollVisible) + 0.5))
        end
    end
    thumb:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        self.dragY, self.dragPos = y / self:GetEffectiveScale(), frame.scrollPos
        self:SetScript("OnUpdate", Drag)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragY = nil
        self:SetScript("OnUpdate", nil)
        if not self:IsMouseOver() then tex:SetAlpha(0.7) end
    end)
    frame.thumb = thumb
end

local function UpdateScrollbar(frame, pos, total, visible)
    frame.scrollPos, frame.scrollTotal, frame.scrollVisible = pos, total, visible
    local scrolls = total > visible
    frame.track:SetShown(scrolls)
    frame.thumb:SetShown(scrolls)
    if scrolls then
        local h = frame:GetHeight()
        local size = math.max(20, h * visible / total)
        frame.thumb:SetHeight(size)
        frame.thumb:ClearAllPoints()
        frame.thumb:SetPoint("TOPRIGHT", 0, -(h - size) * pos / (total - visible))
    end
end

-- Row height shared by the item list and the stock window
W.ROW_H, W.SCROLL_W = 20, SCROLL_W

-- Windows that follow the scale option
W.scaled = {}

-- Merchant Map is locked during combat: its windows close and won't open until it ends
function W.InCombat()
    if not InCombatLockdown() then return false end
    print("|cffccb084Merchant Map:|r not available in combat.")
    return true
end

W.Fill, W.Outline, W.Grain, W.Gradient, W.SkinButton = Fill, Outline, Grain, Gradient, SkinButton
W.EditBox, W.TextButton, W.SetTooltip = EditBox, TextButton, SetTooltip
W.AddScrollbar, W.UpdateScrollbar = AddScrollbar, UpdateScrollbar
