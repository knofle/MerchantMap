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

local function Continent(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.mapType > Enum.UIMapType.Continent and info.parentMapID and info.parentMapID ~= 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return info and info.mapType == Enum.UIMapType.Continent and info.mapID
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
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    VA.db.arrowPoint = { point, relPoint, x, y }
end)
-- While verifying (/va unverified), left-click finds the nearest NPC from where you are now,
-- and right-click skips to the next one instead of clearing the marker
frame:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then
        VA:PointToNextUnverified()
    elseif VA.verifyMode then
        VA:SkipUnverified()
    else
        VA:ClearMinimapVendor()
    end
end)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(target and target.name or "Vendor Atlas", 1, 1, 1)
    GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
    if VA.verifyMode then
        GameTooltip:AddLine("Click to find the nearest from where you are", 0.35, 0.85, 0.35)
        GameTooltip:AddLine("Right-click to skip to the next one", 0.35, 0.85, 0.35)
    else
        GameTooltip:AddLine("Right-click to remove the marker", 0.35, 0.85, 0.35)
    end
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", GameTooltip_Hide)

-- Called by the minimap marker; nil hides the arrow
function VA:SetArrowTarget(vendor)
    target, continent, tx = vendor, nil, nil
    if vendor and not self.db.arrowHidden then
        name:SetText(vendor.name)
        elapsed = INTERVAL
        frame:Show()
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