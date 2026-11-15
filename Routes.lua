local _, MM = ...

-- Patrol routes from VendorData, drawn on the world map while a patroller's pin is hovered: a line along
-- each path, or dots on the spawn spots of vendors found at one of several places.
-- Lines and dots are plain textures on the map canvas, so nothing here moves or zooms the map.

local DOT_SIZE = 7 -- on screen, kept steady by undoing the canvas zoom
local LINE_WIDTH = 3.5
local OUTLINE = 2 -- black rim around dots and lines, on screen
local COLOR = { 0.90, 0.30, 0.22, 0.95 } -- muted red, to stand out on the map's greens and browns
-- Soft-edged textures (solid middle, fading edges) stand in for anti-aliasing, which lines don't have.
-- Sizes are a little over the look wanted, as the outer edge fades out.
local MASK = "Interface\\AddOns\\MerchantMap\\routedot"
local LINE = "Interface\\AddOns\\MerchantMap\\routeline"
local dots, lines, joints = {}, {}, {}
local layer

local function Layer(canvas)
    if not layer then
        layer = CreateFrame("Frame", nil, canvas)
        layer:SetAllPoints(canvas)
    end
    return layer
end

-- Just under the hovered pin, but above OpenMap's stitched map art, which is drawn as frames on the
-- canvas and would hide the trail otherwise (its API gives the level the art reaches)
local function LayerLevel(pin)
    local level = math.max(pin:GetFrameLevel() - 1, 1)
    local artTop = OpenMapAPI and OpenMapAPI.ArtTopLevel and OpenMapAPI.ArtTopLevel()
    if type(artTop) == "number" and level <= artTop then level = artTop + 1 end
    return level
end

-- Dots for spawn spots, and round joints between line segments (whose square ends leave notches)
local function Dot(i, pool)
    pool = pool or dots
    local dot = pool[i]
    if not dot then
        dot = layer:CreateTexture(nil, "OVERLAY", nil, 1)
        dot:SetTexture(MASK)
        dot:SetVertexColor(unpack(COLOR))
        dot.outline = layer:CreateTexture(nil, "OVERLAY", nil, 0)
        dot.outline:SetTexture(MASK)
        dot.outline:SetVertexColor(0, 0, 0, 0.9)
        dot.outline:SetPoint("CENTER", dot)
        pool[i] = dot
    end
    return dot
end

local function PlaceDot(dot, canvas, x, y, size, rim)
    dot:SetSize(size, size)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", canvas, "TOPLEFT", x, y)
    dot:Show()
    dot.outline:SetSize(rim, rim)
    dot.outline:Show()
end

local function Segment(i)
    local line = lines[i]
    if not line then
        line = layer:CreateLine(nil, "OVERLAY", nil, 1)
        line:SetTexture(LINE)
        line:SetVertexColor(unpack(COLOR))
        line.outline = layer:CreateLine(nil, "OVERLAY", nil, 0)
        line.outline:SetTexture(LINE)
        line.outline:SetVertexColor(0, 0, 0, 0.9)
        lines[i] = line
    end
    return line
end

-- What the route is drawn for, so the hover tracker can redraw it when any of it changes
local shownPin, shownKey, shownMap, shownScale

function MM:HideVendorRoute()
    shownPin, shownKey, shownMap, shownScale = nil, nil, nil, nil
    for _, pool in ipairs({ dots, joints }) do
        for _, dot in ipairs(pool) do
            dot:Hide()
            dot.outline:Hide()
        end
    end
    for _, line in ipairs(lines) do
        line:Hide()
        line.outline:Hide()
    end
end

function MM:ShowVendorRoute(pin)
    self:HideVendorRoute()
    local mapID, scale = WorldMapFrame:GetMapID(), WorldMapFrame:GetCanvasScale()
    shownPin, shownKey, shownMap, shownScale = pin, pin.key, mapID, scale
    local id = pin.key and self:VendorDataID(pin.key)
    local route = id and self.vendorRoutes and self.vendorRoutes[id]
    local spawns = id and not route and self.vendorSpawns and self.vendorSpawns[id]
    local routeMap = (route or spawns) and self:AreaMap((route or spawns)[1])
    if not (routeMap and mapID) then return end

    local canvas = WorldMapFrame:GetCanvas()
    local width, height = canvas:GetSize()
    -- (frame levels on the map can be restricted in combat; the layer keeps its last level then)
    if not InCombatLockdown() then Layer(canvas):SetFrameLevel(LayerLevel(pin)) else Layer(canvas) end
    local spot = { mapID = routeMap }
    local stitched = OpenMapAPI and OpenMapAPI.IsStitched and OpenMapAPI.IsStitched() and OpenMapAPI.WorldFromMap
        and OpenMapAPI.MapFromWorld
    -- A route point (0-100 on its zone) in canvas offsets, or nil when it isn't on this map
    local function Place(px, py)
        spot.x, spot.y = px / 100, py / 100
        local x, y = self:PosOnMap(spot, mapID)
        -- On OpenMap's stitched map the map underneath follows the view, so the route may be in a
        -- neighbouring zone: placed through the stitched world instead (the canvas reaches past 0..1 there)
        if stitched then
            local u, v = OpenMapAPI.WorldFromMap(routeMap, spot.x, spot.y)
            if u then x, y = OpenMapAPI.MapFromWorld(mapID, u, v) end
        end
        if x then return x * width, -y * height end
    end

    if spawns then
        local size, rim = DOT_SIZE / scale, (DOT_SIZE + OUTLINE * 2) / scale
        local n = 0
        for i = 2, #spawns - 1, 2 do
            local x, y = Place(spawns[i], spawns[i + 1])
            if x then
                n = n + 1
                PlaceDot(Dot(n), canvas, x, y, size, rim)
            end
        end
        return
    end

    local thick, rim = LINE_WIDTH / scale, (LINE_WIDTH + OUTLINE * 2) / scale
    local n, j = 0, 0
    for p = 2, #route do
        local path = route[p]
        local lastX, lastY = Place(path[1], path[2])
        for i = 1, #path - 1, 2 do
            local x, y = Place(path[i], path[i + 1])
            if x then
                j = j + 1
                PlaceDot(Dot(j, joints), canvas, x, y, thick, rim)
            end
        end
        for i = 3, #path - 1, 2 do
            local x, y = Place(path[i], path[i + 1])
            if x and lastX then
                n = n + 1
                local line = Segment(n)
                line:SetThickness(thick)
                line:SetStartPoint("TOPLEFT", canvas, lastX, lastY)
                line:SetEndPoint("TOPLEFT", canvas, x, y)
                line:Show()
                line.outline:SetThickness(rim)
                line.outline:SetStartPoint("TOPLEFT", canvas, lastX, lastY)
                line.outline:SetEndPoint("TOPLEFT", canvas, x, y)
                line.outline:Show()
            end
            lastX, lastY = x, y
        end
    end
end

-- /mm patrols (left out of the help): the map shows every vendor with a patrol note, both factions,
-- keyed "p" .. npcID. Positions are your own or shipped where there are any, else the Classic spot.
function MM:TogglePatrols()
    self.patrolMode = not self.patrolMode or nil
    self.patrolNPCs = nil
    local count = 0
    if self.patrolMode then
        self.patrolNPCs = {}
        for id, note in pairs(self.vendorNotes or {}) do
            local v = self.knownVendors[id]
            local mine, shipped = self.db.vendors[id], self.shippedVendors[id]
            local mapID, x, y
            if mine and mine.mapID then
                mapID, x, y = mine.mapID, mine.x, mine.y
            elseif shipped then
                mapID, x, y = shipped[2], shipped[3], shipped[4]
            elseif v then
                mapID, x, y = self:AreaMap(v[4]), v[5] / 100, v[6] / 100
            end
            if v and mapID then
                self.patrolNPCs["p" .. id] = {
                    name = v[1], title = v[2], faction = v[3], note = note, mapID = mapID, x = x, y = y, service = true,
                }
                count = count + 1
            end
        end
    end
    self:RefreshMap()
    print(self.patrolMode and ("|cffccb084Merchant Map:|r map shows all %d patrolling vendors, both factions."):format(count)
        or "|cffccb084Merchant Map:|r map shows your usual pins again.")
end

local FACTIONS = { A = "Alliance", H = "Horde", AH = "Both factions" }

function MM:ShowPatrolTooltip(owner, key)
    local npc = self.patrolNPCs[key]
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(npc.name, 1, 0.82, 0)
    if npc.title then GameTooltip:AddLine("<" .. npc.title .. ">", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(self:LocationText(npc), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(FACTIONS[npc.faction] or npc.faction, 0.6, 0.6, 0.6)
    GameTooltip:AddLine(npc.note, 1, 0.6, 0.3, true)
    local id = tonumber(key:sub(2))
    if self.vendorRoutes and self.vendorRoutes[id] then
        GameTooltip:AddLine("Patrol route", 0.6, 0.6, 0.6)
    elseif self.vendorSpawns and self.vendorSpawns[id] then
        GameTooltip:AddLine(("%d spawn spots"):format((#self.vendorSpawns[id] - 1) / 2), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("No route data", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Called by the hover tracker. Map refreshes, zooms and map changes can drop or stale the dots
-- without the hovered pin changing, so redraw whenever what they were drawn for has moved on.
function MM:SyncVendorRoute(pin)
    if not pin then
        if shownPin then self:HideVendorRoute() end
        return
    end
    if pin ~= shownPin or pin.key ~= shownKey or WorldMapFrame:GetMapID() ~= shownMap
        or WorldMapFrame:GetCanvasScale() ~= shownScale
        or (layer and not InCombatLockdown() and layer:GetFrameLevel() ~= LayerLevel(pin)) then
        self:ShowVendorRoute(pin)
    end
end
