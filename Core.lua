local addonName, MM = ...

-- Fonts ------------------------------------------------------------------
-- Copies of the Blizzard font objects we use, switched to the addon's font.

local FONT = "Interface\\AddOns\\" .. addonName .. "\\fonts\\Expressway.ttf"

-- Earthy palette shared by the window and the map widgets
MM.COLORS = {
    accent = { 0.80, 0.69, 0.52 },   -- sand: titles, selection, highlights
    text = { 0.86, 0.80, 0.70 },     -- warm off-white for "Normal" fonts
    border = { 0.36, 0.31, 0.25 },   -- muted bronze
    bg = { 0.105, 0.095, 0.085 },    -- warm charcoal
    header = { 0.17, 0.15, 0.125 },  -- lighter band behind the title
    inset = { 0.065, 0.06, 0.055 },  -- list and tree wells
    button = { 0.17, 0.15, 0.125 },
    buttonTop = { 0.235, 0.205, 0.17 },
}
-- Tiled grain laid over flat backgrounds
MM.GRAIN = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"

for _, name in ipairs({
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge",
    "GameFontHighlight", "GameFontHighlightSmall",
    "GameFontDisable", "GameFontDisableSmall", "GameFontDisableLarge",
    "ChatFontNormal",
}) do
    local font = CreateFont("MM_" .. name)
    font:CopyFontObject(_G[name])
    local _, size, flags = font:GetFont()
    font:SetFont(FONT, size, flags)
    -- Blizzard's "Normal" fonts are gold; use the warm off-white instead
    if name:find("Normal", 1, true) and name ~= "ChatFontNormal" then
        font:SetTextColor(unpack(MM.COLORS.text))
    end
end

local db
local scanPending, scanIncomplete, scanAttempts = false, false, 0

-- Helpers ---------------------------------------------------------------

local function VendorKey()
    local name = UnitName("npc")
    if not name then return end
    local guid = UnitGUID("npc")
    if guid and not (issecretvalue and issecretvalue(guid)) then
        local unitType, _, _, _, _, npcID = strsplit("-", guid)
        if unitType == "Creature" or unitType == "Vehicle" or unitType == "GameObject" then
            return tonumber(npcID), name
        end
    end
    return name, name
end

local function MerchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then
            return info.name, info.texture, info.price, info.numAvailable, info.hasExtendedCost
        end
    elseif GetMerchantItemInfo then
        local name, texture, price, _, numAvailable, _, _, extendedCost = GetMerchantItemInfo(i)
        return name, texture, price, numAvailable, extendedCost
    end
end

-- Returns cost text, and whether it is paid in honor or battleground marks
local function ExtendedCost(i)
    local parts, pvp = {}, false
    for c = 1, GetMerchantItemCostInfo(i) or 0 do
        local texture, amount, link, currencyName = GetMerchantItemCostItem(i, c)
        if texture and amount then
            parts[#parts + 1] = amount .. " |T" .. texture .. ":0|t"
        end
        if strlower(currencyName or link or ""):find("honor", 1, true) then pvp = true end
    end
    return #parts > 0 and table.concat(parts, " ") or nil, pvp
end

local function ZoneOf(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.mapType > Enum.UIMapType.Zone and info.parentMapID and info.parentMapID ~= 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return info and info.mapID
end

-- Takes over the Classic vendor when the in-game ID differs from the Classic one,
-- matching by name in the same zone. Its offers move to the new key.
local function AdoptSeed(key, name, zone)
    for seedID, seed in pairs(db.vendors) do
        if seedID ~= key and seed.classic and seed.name == name and (not seed.mapID or seed.mapID == zone) then
            db.vendors[seedID] = nil
            for itemID in pairs(seed.items) do
                local item = db.items[itemID]
                if item and item.vendors[seedID] then
                    item.vendors[key] = item.vendors[key] or item.vendors[seedID]
                    item.vendors[seedID] = nil
                end
            end
            seed.seedID = seedID
            return seed
        end
    end
end

function MM:ZoneOf(mapID)
    return ZoneOf(mapID)
end

-- Drops the Classic seed that stands for this vendor when Forever's ID differs (used by imports)
function MM:RemoveSeedFor(key, name, mapID)
    local zone = ZoneOf(mapID)
    for seedID, seed in pairs(db.vendors) do
        if seedID ~= key and seed.classic and seed.name == name and (not seed.mapID or seed.mapID == zone) then
            for itemID in pairs(seed.items) do
                local item = db.items[itemID]
                if item then
                    item.vendors[seedID] = nil
                    if not next(item.vendors) then db.items[itemID] = nil end
                end
            end
            db.vendors[seedID] = nil
            return seedID
        end
    end
end

-- Scanning --------------------------------------------------------------

-- Vendors give a discount from Friendly upward; prices are stored without it
local DISCOUNTS = { [5] = 0.05, [6] = 0.10, [7] = 0.15, [8] = 0.20 }

local function BasePrice(price, discount)
    if not (price and discount) then return price end
    return math.floor(price / (1 - discount) + 0.5)
end

function MM:ScanMerchant()
    scanPending = false
    local key, vendorName = VendorKey()
    if not key then return end

    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    key = MM:VendorSpotKey(key, mapID)
    local reaction = UnitReaction("npc", "player")
    local discount = reaction and not (issecretvalue and issecretvalue(reaction)) and DISCOUNTS[reaction]

    local vendor = db.vendors[key]
    local seed = AdoptSeed(key, vendorName, ZoneOf(mapID))
    if not vendor then
        vendor = seed or { items = {} }
    elseif seed then
        vendor.seedID = seed.seedID
        for itemID in pairs(seed.items) do vendor.items[itemID] = true end
    end
    -- Shipped prices for items not seen this time become yours
    if vendor.shipped then
        for itemID in pairs(vendor.items) do
            local offer = db.items[itemID] and db.items[itemID].vendors[key]
            if offer then offer.shipped = nil end
        end
    end
    db.vendors[key] = vendor
    vendor.name = vendorName
    vendor.lastSeen = time()
    vendor.classic, vendor.shipped, vendor.located = nil, nil, nil
    -- A confirmed position for the Classic vendor isn't needed once you've seen the shop
    db.verifiedServices[key] = nil
    if vendor.seedID then db.verifiedServices[vendor.seedID] = nil end

    if pos then
        vendor.mapID, vendor.x, vendor.y = mapID, pos:GetXY()
    end

    -- Class filter hides items from the merchant list, so scan unfiltered
    local oldFilter
    if GetMerchantFilter and SetMerchantFilter and LE_LOOT_FILTER_ALL then
        oldFilter = GetMerchantFilter()
        if oldFilter ~= LE_LOOT_FILTER_ALL then
            SetMerchantFilter(LE_LOOT_FILTER_ALL)
        else
            oldFilter = nil
        end
    end

    -- Items you can't see (class, race, rank, sold out) are kept: only what you see is updated
    local complete = true
    for i = 1, GetMerchantNumItems() do
        local itemID = GetMerchantItemID(i)
        local name, icon, price, numAvailable, hasCost = MerchantItem(i)
        if itemID and name then
            local item = db.items[itemID] or { vendors = {} }
            db.items[itemID] = item
            item.name, item.icon = name, icon
            item.link = GetMerchantItemLink(i) or item.link
            item.quality = item.quality or C_Item.GetItemQualityByID(itemID)
            local cost, pvp
            if hasCost then cost, pvp = ExtendedCost(i) end
            item.vendors[key] = {
                price = BasePrice(price, discount),
                cost = cost,
                pvp = pvp or nil,
                limited = (numAvailable and numAvailable >= 0) or nil,
            }
            vendor.items[itemID] = true
            MM:QueueAutoCategorize(itemID)
        else
            complete = false
        end
    end

    if oldFilter then SetMerchantFilter(oldFilter) end

    scanIncomplete = not complete
    self:RefreshItemHolidays()
    self:OnDataChanged()
end

local function QueueScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.3, function()
        if MerchantFrame and MerchantFrame:IsShown() then MM:ScanMerchant() end
        scanPending = false
    end)
end

-- Shared formatting -------------------------------------------------------

function MM:MoneyText(copper)
    if GetMoneyString then return GetMoneyString(copper, true) end
    return C_CurrencyInfo.GetCoinTextureString(copper)
end

-- Classic items no one has bought yet have no price
function MM:PriceText(offer)
    if not (offer.price or offer.cost) then return "|cff8a8a8aNo price data|r" end
    local text = offer.cost
    if offer.price and offer.price > 0 then
        text = text and (self:MoneyText(offer.price) .. " " .. text) or self:MoneyText(offer.price)
    end
    text = text or "Free"
    if offer.limited then text = text .. " |cffff8040(limited)|r" end
    return text
end

function MM:LocationText(vendor)
    local info = vendor.mapID and C_Map.GetMapInfo(vendor.mapID)
    if not info then return "Unknown location" end
    return ("%s %.1f, %.1f"):format(info.name, vendor.x * 100, vendor.y * 100)
end

function MM:ZoneName(vendor)
    local info = vendor.mapID and C_Map.GetMapInfo(vendor.mapID)
    return info and info.name or "Unknown"
end

-- Events ------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        -- Data saved under the old name, Vendor Atlas, carries over
        MerchantMapDB = MerchantMapDB or VendorAtlasDB or {}
        VendorAtlasDB = nil
        db = MerchantMapDB
        db.vendors = db.vendors or {}
        db.items = db.items or {}
        db.hiddenVendors = db.hiddenVendors or {}
        db.verifiedServices = db.verifiedServices or {}
        db.holidays = db.holidays or {}
        MM.db = db
        MM:InitCategories()
        events:UnregisterEvent("ADDON_LOADED")
    elseif event == "MERCHANT_SHOW" then
        scanAttempts = 0
        MM:ScanMerchant()
    elseif scanIncomplete and not scanPending and scanAttempts < 5 then
        -- Retry only while item data is still loading
        scanAttempts = scanAttempts + 1
        QueueScan()
    end
end)
