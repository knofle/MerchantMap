local _, MM = ...

-- Direction arrow to the marked vendor, like TomTom's. Shown while a vendor is marked.
-- Drag to move, right-click to clear the marker, /mm arrow to turn it off or on.

local ARROW = "Interface\\AddOns\\MerchantMap\\arrow"
MM.ARROW_TEXTURE = ARROW
-- Shown instead of the arrow when there's no direction to point in
local STATUS_ICONS = {
    arrived = { "Interface\\AddOns\\MerchantMap\\arrived", 0.35, 0.85, 0.35 },
    elsewhere = { "Interface\\AddOns\\MerchantMap\\elsewhere", 0.7, 0.7, 0.7 },
}
local INTERVAL = 0.05
local ARRIVED = 5 -- yards

local target, label, limited

local frame = CreateFrame("Button", "MerchantMapArrow", UIParent)
frame:SetSize(56, 56)
frame:SetPoint("CENTER", 0, 180)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
frame:Hide()

local arrow = frame:CreateTexture(nil, "ARTWORK")
arrow:SetAllPoints()
arrow:SetTexture(ARROW)

local name = frame:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
name:SetPoint("TOP", frame, "BOTTOM", 0, -2)

-- The item you're going to buy, when you clicked one
local item = frame:CreateFontString(nil, "OVERLAY", "MM_GameFontNormalSmall")
item:SetPoint("TOP", name, "BOTTOM", 0, -1)

local distance = frame:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")

-- Green when facing the vendor, turning red as it falls behind you
local function Tint(angle)
    local off = math.abs((angle + math.pi) % (2 * math.pi) - math.pi) / math.pi
    arrow:SetVertexColor(0.35 + 0.55 * off, 0.85 - 0.65 * off, 0.35 - 0.25 * off)
end

-- Direction to the vendor (radians from north), refreshed every INTERVAL; nil hides the arrow
local bearing, lastAngle

-- Where the vendor is, and how far: changes slowly, so only every INTERVAL.
-- The distance text only changes when the shown value does.
local shown
local function SetDistance(value)
    if value == shown then return end
    shown = value
    distance:SetText(type(value) == "number" and value .. " yd" or value)
end

-- "arrived" or "elsewhere" (another continent) while there's nothing to point at
local status, shownStatus

local function Locate()
    bearing, status = nil, nil
    local north, west = MM:VectorTo(target)
    if not north then
        status = "elsewhere"
        return SetDistance("Not on this continent")
    end
    local yards = math.floor(math.sqrt(north * north + west * west))
    if yards < ARRIVED then
        status = "arrived"
        return SetDistance("Arrived")
    end
    SetDistance(yards)
    bearing = math.atan2(west, north)
end

-- Turning is read every frame so the arrow follows smoothly; it only redraws when the angle changes
local elapsed = INTERVAL
local function Update(_, dt)
    elapsed = elapsed + dt
    if elapsed >= INTERVAL then
        elapsed = 0
        Locate()
    end

    -- Arrived or on another continent: a still icon instead of the arrow
    if status then
        if status ~= shownStatus then
            shownStatus = status
            local icon = STATUS_ICONS[status]
            arrow:SetTexture(icon[1])
            arrow:SetRotation(0)
            arrow:SetVertexColor(icon[2], icon[3], icon[4])
            lastAngle = nil
        end
        arrow:Show()
        return
    elseif shownStatus then
        shownStatus = nil
        arrow:SetTexture(ARROW)
    end

    local facing = bearing and GetPlayerFacing()
    if not facing or (issecretvalue and issecretvalue(facing)) then
        arrow:Hide()
        lastAngle = nil
        return
    end
    local angle = bearing - facing
    if angle ~= lastAngle then
        lastAngle = angle
        arrow:SetRotation(angle)
        Tint(angle)
    end
    arrow:Show()
end

frame:SetScript("OnUpdate", Update)

-- Locking (in the options) stops dragging
local moving
local function StartMoving()
    if MM.db.arrowLocked then return end
    moving = true
    frame:StartMoving()
end
local function StopMoving()
    if not moving then return end
    moving = nil
    frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = frame:GetPoint()
    MM.db.arrowPoint = { point, relPoint, x, y }
end
frame:SetScript("OnDragStart", StartMoving)
frame:SetScript("OnDragStop", StopMoving)

-- Left-click targets and marks the NPC (through the targeting button), right-click clears the marker
local function OnClick(_, button)
    if button == "RightButton" then MM:ClearMinimapVendor() end
end
frame:SetScript("OnClick", OnClick)

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(target and target.name or "Merchant Map", 1, 1, 1)
    if not MM.db.arrowLocked then GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5) end
    GameTooltip:AddLine("Right-click to remove the marker", 0.35, 0.85, 0.35)
    GameTooltip:Show()
end

local function AttachTargeting()
    if not target then return end
    MM:AttachTargetButton(frame, {
        name = MM:TargetName(target) or false,
        unmarkName = MM:TargetName(target),
        rightClick = true,
        onEnter = ShowTooltip,
        onLeave = GameTooltip_Hide,
        onClick = OnClick,
        onDragStart = StartMoving,
        onDragStop = StopMoving,
    })
end

frame:SetScript("OnEnter", function(self)
    ShowTooltip(self)
    AttachTargeting()
end)
frame:SetScript("OnLeave", function(self)
    if not MM:IsTargetOwner(self) then GameTooltip:Hide() end
end)

-- Called by the minimap marker; nil hides the arrow. itemName is shown under the vendor's name,
-- with a red note when they only have it in limited stock.
function MM:SetArrowTarget(vendor, itemName, limitedStock)
    target, label, limited, shown = vendor, itemName, limitedStock, nil
    if vendor and not self.db.arrowHidden then
        name:SetText(vendor.name)
        item:SetText((itemName or "") .. (itemName and limitedStock and " |cffff4d4d(limited stock)|r" or ""))
        distance:ClearAllPoints()
        distance:SetPoint("TOP", itemName and item or name, "BOTTOM", 0, -1)
        elapsed = INTERVAL
        frame:Show()
        -- Still under the cursor when the target changes: aim the targeting at the new NPC
        if self:IsTargetOwner(frame) then
            AttachTargeting()
            ShowTooltip(frame)
        end
    else
        frame:Hide()
    end
end

function MM:SetArrowShown(show)
    self.db.arrowHidden = not show or nil
    self:SetArrowTarget(target, label, limited)
end

-- Arrow size as a scale of its normal 56 pixels; the text below it keeps its size
local SIZE = 56
function MM:SetArrowSize(scale)
    self.db.arrowScale = scale ~= 1 and scale or nil
    frame:SetSize(SIZE * scale, SIZE * scale)
end

function MM:ToggleArrow()
    self:SetArrowShown(self.db.arrowHidden)
    print(("|cffccb084Merchant Map:|r arrow %s."):format(self.db.arrowHidden and "off" or "on"))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local p = MM.db.arrowPoint
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
    MM:SetArrowSize(MM.db.arrowScale or 1)
end)
