local _, MM = ...

-- Minimap pin for the last vendor you clicked on the world map.
-- Cleared by right-clicking it, or by opening that vendor's shop.

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"

-- Minimap diameter in yards per zoom level
local SIZES = {
    outdoor = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
    indoor = { 300, 240, 180, 120, 80, 50 },
}

local target

local pin = CreateFrame("Button", nil, Minimap)
pin:SetSize(16, 16)
pin:SetFrameLevel(Minimap:GetFrameLevel() + 10)
pin:RegisterForClicks("RightButtonUp")
pin:Hide()

-- Green ring over the normal ring, matching the marked pin on the world map
local outline = pin:CreateTexture(nil, "BACKGROUND", nil, 1)
outline:SetSize(16, 16)
outline:SetPoint("CENTER")
outline:SetTexture(CIRCLE)
outline:SetVertexColor(0.35, 0.85, 0.35)
local ring = pin:CreateTexture(nil, "BACKGROUND")
ring:SetAllPoints()
ring:SetTexture(CIRCLE)
ring:SetVertexColor(0.85, 0.68, 0.2)
local disc = pin:CreateTexture(nil, "BORDER")
disc:SetSize(13, 13)
disc:SetPoint("CENTER")
disc:SetTexture(CIRCLE)
disc:SetVertexColor(0.05, 0.05, 0.07, 0.9)
local icon = pin:CreateTexture(nil, "ARTWORK")
icon:SetSize(9, 9)
icon:SetPoint("CENTER")
icon:SetTexture(COIN)

-- Yards east and south from the player to the vendor
local function Offset()
    local north, west = MM:VectorTo(target)
    if north then return -west, -north end
end

-- Minimap settings, refreshed when they can change rather than every update
local rotate, square, indoors

-- The minimap's own indoor mode, which IsIndoors() doesn't always match (towns, buildings, caves).
-- Indoor and outdoor zoom are stored separately, so whichever matches the current zoom is in use;
-- when both are equal, nudge the zoom for a moment to tell them apart.
-- canNudge is only set on zone changes: the nudge fires zoom events itself, so doing it on
-- those would keep retriggering
local function ReadIndoors(canNudge)
    local outdoorZoom, insideZoom = GetCVar("minimapZoom"), GetCVar("minimapInsideZoom")
    if not (outdoorZoom and insideZoom) then
        indoors = IsIndoors()
        return
    end
    local zoom = Minimap:GetZoom()
    if outdoorZoom ~= insideZoom then
        indoors = tonumber(outdoorZoom) ~= zoom
    elseif canNudge then
        Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
        indoors = tonumber(GetCVar("minimapZoom")) ~= Minimap:GetZoom()
        Minimap:SetZoom(zoom)
    end
end

local function ReadSettings()
    rotate = GetCVar("rotateMinimap") == "1"
    square = GetMinimapShape and GetMinimapShape() == "SQUARE"
end

-- Patrol route or spawn spots of the marked vendor, as on the world map (Routes.lua), clipped to
-- the minimap's edge. Points are turned into world yards once, when the vendor is marked.
local ROUTE_DOT, ROUTE_LINE, ROUTE_RIM = 5, 2.5, 1.5 -- on screen; ROUTE_RIM is the black edge
local ROUTE_COLOR = { 0.90, 0.30, 0.22, 0.95 }
local ROUTE_MASK = "Interface\\AddOns\\MerchantMap\\routedot"
local ROUTE_TEX = "Interface\\AddOns\\MerchantMap\\routeline"
local routeLayer = CreateFrame("Frame", nil, Minimap)
routeLayer:SetAllPoints()
routeLayer:SetFrameLevel(Minimap:GetFrameLevel() + 9) -- just under the pin
routeLayer:Hide()
local routeDots, routeLines = {}, {}
local route, routeDrawn -- routeDrawn: what the route was last drawn for, so it's redrawn only on change

local function BuildRoute(key)
    route, routeDrawn = nil, nil
    routeLayer:Hide()
    local id = key and MM:VendorDataID(key)
    local data = id and MM.vendorRoutes and MM.vendorRoutes[id]
    local spawns = id and not data and MM.vendorSpawns and MM.vendorSpawns[id]
    local mapID = (data or spawns) and MM:AreaMap((data or spawns)[1])
    if not mapID then return end
    route = { spawns = spawns and true }
    local function Add(path, from)
        local points = {}
        for i = from, #path - 1, 2 do
            local instance, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(path[i] / 100, path[i + 1] / 100))
            if pos then
                route.instance = instance
                points[#points + 1], points[#points + 2] = pos:GetXY()
            end
        end
        route[#route + 1] = points
    end
    if spawns then Add(spawns, 2) else for p = 2, #data do Add(data[p], 1) end end
end

local function RouteDot(i, x, y, size)
    local dot = routeDots[i]
    if not dot then
        dot = routeLayer:CreateTexture(nil, "OVERLAY", nil, 1)
        dot:SetTexture(ROUTE_MASK)
        dot:SetVertexColor(unpack(ROUTE_COLOR))
        dot.outline = routeLayer:CreateTexture(nil, "OVERLAY", nil, 0)
        dot.outline:SetTexture(ROUTE_MASK)
        dot.outline:SetVertexColor(0, 0, 0, 0.9)
        dot.outline:SetPoint("CENTER", dot)
        routeDots[i] = dot
    end
    dot:SetSize(size, size)
    dot:SetPoint("CENTER", Minimap, "CENTER", x, y)
    dot.outline:SetSize(size + ROUTE_RIM * 2, size + ROUTE_RIM * 2)
    dot:Show()
    dot.outline:Show()
end

local function RouteLine(i, x1, y1, x2, y2)
    local line = routeLines[i]
    if not line then
        line = routeLayer:CreateLine(nil, "OVERLAY", nil, 1)
        line:SetTexture(ROUTE_TEX)
        line:SetVertexColor(unpack(ROUTE_COLOR))
        line:SetThickness(ROUTE_LINE)
        line.outline = routeLayer:CreateLine(nil, "OVERLAY", nil, 0)
        line.outline:SetTexture(ROUTE_TEX)
        line.outline:SetVertexColor(0, 0, 0, 0.9)
        line.outline:SetThickness(ROUTE_LINE + ROUTE_RIM * 2)
        routeLines[i] = line
    end
    for _, l in ipairs({ line, line.outline }) do
        l:SetStartPoint("CENTER", Minimap, x1, y1)
        l:SetEndPoint("CENTER", Minimap, x2, y2)
        l:Show()
    end
end

-- Set per draw: player position, yards to pixels, rotation and the minimap's edge
local playerN, playerW, routeScale, rotSin, rotCos, edge

local function ToMinimap(north, west)
    local x, y = (playerW - west) * routeScale, (north - playerN) * routeScale
    if rotSin then x, y = x * rotCos - y * rotSin, x * rotSin + y * rotCos end
    return x, y
end

local function Inside(x, y)
    if square then return math.abs(x) <= edge and math.abs(y) <= edge end
    return x * x + y * y <= edge * edge
end

-- Where a segment from an inside point to an outside one crosses the edge (bisection works for
-- round and square minimaps alike)
local function Clip(ax, ay, bx, by)
    local lo, hi = 0, 1
    for _ = 1, 10 do
        local mid = (lo + hi) / 2
        if Inside(ax + (bx - ax) * mid, ay + (by - ay) * mid) then lo = mid else hi = mid end
    end
    return ax + (bx - ax) * lo, ay + (by - ay) * lo
end

local function DrawRoute(scale, sin, cos)
    local py, px, _, instance = UnitPosition("player")
    if not py or (issecretvalue and issecretvalue(py)) or instance ~= route.instance then
        routeLayer:Hide()
        routeDrawn = nil
        return
    end
    local radius = Minimap:GetWidth() / 2 - 2
    if routeDrawn and py == playerN and px == playerW and scale == routeScale and sin == rotSin
        and radius == edge and square == routeDrawn.square then return end
    routeDrawn = { square = square }
    playerN, playerW, routeScale, rotSin, rotCos, edge = py, px, scale, sin, cos, radius

    local dots, lines = 0, 0
    for _, path in ipairs(route) do
        local lastX, lastY, lastIn
        for i = 1, #path - 1, 2 do
            local x, y = ToMinimap(path[i], path[i + 1])
            local inside = Inside(x, y)
            if inside then
                dots = dots + 1
                RouteDot(dots, x, y, route.spawns and ROUTE_DOT or ROUTE_LINE)
            end
            if not route.spawns and lastX and (inside or lastIn) then
                local x1, y1, x2, y2 = lastX, lastY, x, y
                if not lastIn then x1, y1 = Clip(x, y, lastX, lastY) end
                if not inside then x2, y2 = Clip(lastX, lastY, x, y) end
                lines = lines + 1
                RouteLine(lines, x1, y1, x2, y2)
            end
            lastX, lastY, lastIn = x, y, inside
        end
    end
    for i = dots + 1, #routeDots do
        routeDots[i]:Hide()
        routeDots[i].outline:Hide()
    end
    for i = lines + 1, #routeLines do
        routeLines[i]:Hide()
        routeLines[i].outline:Hide()
    end
    routeLayer:Show()
end

-- Only touches the pin when where or how it shows changes, as this runs every frame
local lastX, lastY, lastAlpha
local function Place(x, y, alpha)
    if alpha ~= lastAlpha then
        lastAlpha = alpha
        pin:SetAlpha(alpha)
        pin:EnableMouse(alpha > 0)
    end
    if x and (x ~= lastX or y ~= lastY) then
        lastX, lastY = x, y
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
end

local function Update()
    local east, south = Offset()
    -- Different continent: keep the target but show nothing
    if not east then
        routeLayer:Hide()
        routeDrawn = nil
        return Place(nil, nil, 0)
    end

    local zoom = Minimap:GetZoom()
    local diameter = SIZES[indoors and "indoor" or "outdoor"][zoom + 1] or SIZES.outdoor[1]
    local scale = Minimap:GetWidth() / diameter
    local x, y = east * scale, -south * scale

    -- Rotating minimaps turn the world so your facing points up
    local s, c
    if rotate then
        local facing = GetPlayerFacing()
        if facing and not (issecretvalue and issecretvalue(facing)) then
            s, c = math.sin(-facing), math.cos(-facing)
            x, y = x * c - y * s, x * s + y * c
        end
    end
    if route then DrawRoute(scale, s, c) end

    -- Beyond minimap range: park on the edge, dimmed
    local radius = Minimap:GetWidth() / 2 - 6
    local outside
    if square then
        outside = math.abs(x) > radius or math.abs(y) > radius
        x, y = math.max(-radius, math.min(radius, x)), math.max(-radius, math.min(radius, y))
    else
        local dist = math.sqrt(x * x + y * y)
        outside = dist > radius
        if outside then x, y = x / dist * radius, y / dist * radius end
    end

    Place(x, y, outside and 0.6 or 1)
end

-- Every frame, so the pin moves with the minimap instead of trailing it
pin:SetScript("OnUpdate", Update)

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(target.name, 1, 0.82, 0)
    if target.title then GameTooltip:AddLine("<" .. target.title .. ">", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(MM:LocationText(target), 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click to remove", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- Removing the marker also takes the skull off the vendor, which needs the secure targeting
-- button laid over the pin while it's hovered
pin:SetScript("OnEnter", function(self)
    ShowTooltip(self)
    MM:AttachTargetButton(self, {
        rightClick = true,
        unmarkName = MM:TargetName(target),
        onEnter = ShowTooltip,
        onLeave = GameTooltip_Hide,
        onClick = function(_, button)
            if button == "RightButton" then MM:ClearMinimapVendor() end
        end,
    })
end)
pin:SetScript("OnLeave", function(self)
    if not MM:IsTargetOwner(self) then GameTooltip:Hide() end
end)

-- Set when the waypoint option placed a waypoint, so clearing the marker can take it away again
local placedWaypoint

function MM:ClearMinimapVendor()
    target, MM.minimapKey = nil, nil
    pin:Hide()
    BuildRoute(nil)
    if placedWaypoint then
        placedWaypoint = nil
        MM:ClearWaypoint()
    end
    MM:SetArrowTarget(nil)
    MM:RefreshMap()
end

-- Option: the marked vendor can be left off the minimap; the arrow and world map still show it
function MM:SetMinimapPinShown(show)
    self.db.noMinimapPin = not show or nil
    pin:SetShown(show and target ~= nil)
    -- The route goes with the pin (drawn from its updates)
    if not show then routeLayer:Hide() end
    routeDrawn = nil
end

pin:SetScript("OnClick", function() MM:ClearMinimapVendor() end)

-- label names the waypoint (the item you clicked); defaults to the vendor's name.
-- limited flags the item as limited stock at this vendor, for the arrow.
function MM:SetMinimapVendor(vendor, key, label, limited)
    if not (vendor and vendor.mapID) then return end
    target, MM.minimapKey = vendor, key
    lastX, lastY, lastAlpha = nil, nil, nil
    ReadSettings()
    ReadIndoors(true)
    icon:SetTexture(vendor.icon or COIN)
    BuildRoute(key)
    pin:SetShown(not MM.db.noMinimapPin)
    Update()
    -- Option: a map waypoint on the vendor too
    if MM.db.autoWaypoint then
        MM:SetWaypoint(vendor, label)
        placedWaypoint = true
    end
    MM:SetArrowTarget(vendor, label, limited)
    MM:RefreshMap()
end

-- Reaching the vendor clears the pin
local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("CVAR_UPDATE")
-- The minimap switches between indoor and outdoor zoom on these
for _, event in ipairs({ "MINIMAP_UPDATE_ZOOM", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "CVAR_UPDATE" then
        ReadSettings()
    elseif event ~= "MERCHANT_SHOW" then
        if target then ReadIndoors(event ~= "MINIMAP_UPDATE_ZOOM") end
    elseif target and UnitName("npc") == target.name then
        MM:ClearMinimapVendor()
    end
end)
