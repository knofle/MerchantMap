local _, VA = ...

-- Direction arrow to the marked vendor, like TomTom's. Shown while a vendor is marked.
-- Drag to move, right-click to clear the marker, /va arrow to turn it off or on.

local ARROW = "Interface\\Minimap\\MinimapArrow"
local INTERVAL = 0.05
local ARRIVED = 5 -- yards

local target, continent, tx, ty, width, height

local frame = CreateFrame("Button", "VendorAtlasArrow", UIParent)
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

local name = frame:CreateFontString(nil, "OVERLAY", "VA_GameFontHighlightSmall")
name:SetPoint("TOP", frame, "BOTTOM", 0, -2)

local distance = frame:CreateFontString(nil, "OVERLAY", "VA_GameFontDisableSmall")
distance:SetPoint("TOP", name, "BOTTOM", 0, -1)

local continents = {}
local function Continent(mapID)
    if not mapID then return end
    local found = continents[mapID]
    if found == nil then
        local info = C_Map.GetMapInfo(mapID)
        while info and info.mapType > Enum.UIMapType.Continent and info.parentMapID and info.parentMapID ~= 0 do
            info = C_Map.GetMapInfo(info.parentMapID)
        end
        found = info and info.mapType == Enum.UIMapType.Continent and info.mapID or false
        continents[mapID] = found
    end
    return found or nil
end

-- Green when facing the vendor, turning red as it falls behind you
local function Tint(angle)
    local off = math.abs((angle + math.pi) % (2 * math.pi) - math.pi) / math.pi
    arrow:SetVertexColor(0.35 + 0.55 * off, 0.85 - 0.65 * off, 0.35 - 0.25 * off)
end

local elapsed = 0
local function Update(_, dt)
    elapsed = elapsed + dt
    if elapsed < INTERVAL then return end
    elapsed = 0

    local here = Continent(C_Map.GetBestMapForUnit("player"))
    if here ~= continent then
        -- Changed continent: find the vendor on the new one
        continent, tx = here, nil
        if here then
            tx, ty = VA:PosOnMap(target, here)
            width, height = C_Map.GetMapWorldSize(here)
        end
    end
    local pos = continent and tx and C_Map.GetPlayerMapPosition(continent, "player")
    local facing = GetPlayerFacing()
    if not (pos and width and width > 0) then
        arrow:Hide()
        distance:SetText("Not on this continent")
        return
    end

    local px, py = pos:GetXY()
    local dx, dy = (tx - px) * width, (ty - py) * height
    local yards = math.sqrt(dx * dx + dy * dy)
    if yards < ARRIVED then
        arrow:Hide()
        distance:SetText("Arrived")
        return
    end
    distance:SetText(("%d yd"):format(yards))
    if not facing then
        arrow:Hide()
        return
    end
    local angle = math.atan2(-dx, -dy) - facing
    arrow:SetRotation(angle)
    Tint(angle)
    arrow:Show()
end

frame:SetScript("OnUpdate", Update)

local function StartMoving() frame:StartMoving() end
local function StopMoving()
    frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = frame:GetPoint()
    VA.db.arrowPoint = { point, relPoint, x, y }
end
frame:SetScript("OnDragStart", StartMoving)
frame:SetScript("OnDragStop", StopMoving)

-- Left-click targets and skulls the NPC (through the targeting button). While verifying
-- (/va unverified), shift-click finds the nearest from where you are and right-click skips one;
-- otherwise right-click clears the marker.
local function OnClick(_, button)
    if button == "LeftButton" then
        if VA.verifyMode and IsShiftKeyDown() then VA:PointToNextUnverified() end
    elseif VA.verifyMode then
        VA:SkipUnverified()
    else
        VA:ClearMinimapVendor()
    end
end
frame:SetScript("OnClick", OnClick)

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(target and target.name or "Vendor Atlas", 1, 1, 1)
    GameTooltip:AddLine("Click to target and mark with a skull (when nearby)", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
    if VA.verifyMode then
        GameTooltip:AddLine("Shift-click to find the nearest from where you are", 0.35, 0.85, 0.35)
        GameTooltip:AddLine("Right-click to skip to the next one", 0.35, 0.85, 0.35)
    else
        GameTooltip:AddLine("Right-click to remove the marker", 0.35, 0.85, 0.35)
    end
    GameTooltip:Show()
end

local function AttachTargeting()
    if not target then return end
    VA:AttachTargetButton(frame, {
        name = target.name,
        unmarkName = target.name,
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
    if not VA:IsTargetOwner(self) then GameTooltip:Hide() end
end)

-- Called by the minimap marker; nil hides the arrow
function VA:SetArrowTarget(vendor)
    target, continent, tx = vendor, nil, nil
    if vendor and not self.db.arrowHidden then
        name:SetText(vendor.name)
        elapsed = INTERVAL
        frame:Show()
        -- Still under the cursor after skipping: aim the targeting at the new NPC
        if self:IsTargetOwner(frame) then
            AttachTargeting()
            ShowTooltip(frame)
        end
    else
        frame:Hide()
    end
end

function VA:SetArrowShown(show)
    self.db.arrowHidden = not show or nil
    self:SetArrowTarget(target)
end

function VA:ToggleArrow()
    self:SetArrowShown(self.db.arrowHidden)
    print(("|cffccb084Vendor Atlas:|r arrow %s."):format(self.db.arrowHidden and "off" or "on"))
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local p = VA.db.arrowPoint
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    end
end)