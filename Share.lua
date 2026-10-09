local _, MM = ...

-- Share verified data: export what you've confirmed in-game as a text string others can import.
-- Vendors (position and stock with prices) and service NPCs you've talked to are included,
-- but only when newer than the data shipped with the addon. Needs LibSerialize and LibDeflate.

local PREFIX = "!MM1!"
local OLD_PREFIX = "!VA1!" -- exports made before the rename from Vendor Atlas
local C = MM.COLORS

local function Libs()
    local serialize = LibStub and LibStub("LibSerialize", true)
    local deflate = LibStub and LibStub("LibDeflate", true)
    return serialize, deflate
end

-- Export ----------------------------------------------------------------------

-- LibSerialize checks for -0 with 1 / num, which errors in WoW, so zeros are sent as nil
local function NZ(n)
    if n ~= 0 then return n end
end

function MM:ExportData()
    local LibSerialize, LibDeflate = Libs()
    if not (LibSerialize and LibDeflate) then return nil, "LibSerialize and LibDeflate are needed." end

    local db = self.db
    local data = { vendors = {}, items = {}, services = {} }
    local vendorCount, serviceCount = 0, 0

    -- Only what's newer than the data shipped with the addon
    for key, vendor in pairs(db.vendors) do
        local shipped = self.shippedVendors[key]
        if not vendor.classic and not vendor.shipped and vendor.mapID
            and (not shipped or (vendor.lastSeen or 0) > shipped[5]) then
            local stock = {}
            for itemID in pairs(vendor.items) do
                local item = db.items[itemID]
                local offer = item and item.vendors[key]
                if offer and not offer.classic and not offer.shipped then
                    stock[itemID] = { NZ(offer.price), offer.cost, offer.limited, offer.pvp }
                    data.items[itemID] = data.items[itemID] or { item.name, NZ(item.icon) }
                end
            end
            local notSeen = {}
            for itemID in pairs(vendor.notSeen or {}) do notSeen[#notSeen + 1] = itemID end
            data.vendors[key] = {
                vendor.name, vendor.mapID, NZ(vendor.x), NZ(vendor.y), NZ(vendor.lastSeen), stock, vendor.seedID,
                next(notSeen) and notSeen or nil,
            }
            vendorCount = vendorCount + 1
        end
    end
    for key, seen in pairs(db.verifiedServices) do
        local shipped = self.shippedServices[key]
        if not shipped or (seen.t or 0) > shipped[5] then
            data.services[key] = {
                name = seen.name, mapID = seen.mapID, x = NZ(seen.x), y = NZ(seen.y), t = NZ(seen.t),
                paths = seen.paths, faction = seen.faction, title = seen.title,
            }
            serviceCount = serviceCount + 1
        end
    end
    if vendorCount + serviceCount == 0 then return nil, "Nothing new since the data shipped with the addon." end

    local packed = LibDeflate:CompressDeflate(LibSerialize:Serialize(data), { level = 9 })
    return PREFIX .. LibDeflate:EncodeForPrint(packed), vendorCount, serviceCount
end

-- Import ----------------------------------------------------------------------

-- Takes an imported vendor's position and prices, unless yours are as new.
-- Items the import doesn't have keep what you had for them.
local function ImportVendor(db, key, rec, items)
    local name, mapID, x, y, seen, stock, seedID, notSeen = unpack(rec, 1, 8)
    x, y, seen = x or 0, y or 0, seen or 0
    local current = db.vendors[key]
    if current and not current.classic and (current.lastSeen or 0) >= seen then return false end

    local vendor = current or { items = {} }
    vendor.name, vendor.mapID, vendor.x, vendor.y, vendor.lastSeen = name, mapID, x, y, seen
    vendor.classic, vendor.shipped, vendor.located = nil, nil, nil
    vendor.seedID = MM:RemoveSeedFor(key, name, mapID) or seedID or vendor.seedID
    db.vendors[key] = vendor
    -- Classic items their visit didn't see in the shop
    for _, itemID in ipairs(notSeen or {}) do
        if not stock[itemID] then
            vendor.notSeen = vendor.notSeen or {}
            vendor.notSeen[itemID] = true
            local offer = db.items[itemID] and db.items[itemID].vendors[key]
            if offer and offer.classic then offer.notSeen = true end
        end
    end

    for itemID, offer in pairs(stock) do
        local item = db.items[itemID]
        if not item then
            local info = items[itemID]
            item = { name = info and info[1], icon = info and info[2], vendors = {} }
            if item.name then db.items[itemID] = item end
        end
        if item.name then
            item.vendors[key] = { price = offer[1] or 0, cost = offer[2], limited = offer[3], pvp = offer[4] }
            vendor.items[itemID] = true
            MM:QueueAutoCategorize(itemID)
        end
    end
    return true
end

-- Returns vendors and services taken, or nil and an error message
function MM:ImportData(text)
    local LibSerialize, LibDeflate = Libs()
    if not (LibSerialize and LibDeflate) then return nil, "LibSerialize and LibDeflate are needed." end

    text = strtrim(text or "")
    if text:sub(1, #OLD_PREFIX) == OLD_PREFIX then text = PREFIX .. text:sub(#OLD_PREFIX + 1) end
    if text:sub(1, #PREFIX) ~= PREFIX then return nil, "That isn't Merchant Map data." end
    local packed = LibDeflate:DecodeForPrint(text:sub(#PREFIX + 1))
    local serialized = packed and LibDeflate:DecompressDeflate(packed)
    local ok, data = false, nil
    if serialized then ok, data = LibSerialize:Deserialize(serialized) end
    if not (ok and type(data) == "table" and data.vendors) then return nil, "The data is damaged or incomplete." end

    local db = self.db
    local vendors, services = 0, 0
    for key, rec in pairs(data.vendors) do
        if ImportVendor(db, key, rec, data.items or {}) then vendors = vendors + 1 end
    end
    for key, seen in pairs(data.services or {}) do
        local mine = db.verifiedServices[key]
        if not mine or (mine.t or 0) < (seen.t or 0) then
            seen.x, seen.y, seen.t = seen.x or 0, seen.y or 0, seen.t or 0
            db.verifiedServices[key] = seen
            services = services + 1
        end
    end

    self:RefreshServices()
    self:OnDataChanged()
    return vendors, services
end

-- Dialog ----------------------------------------------------------------------

local dialog

local function Skin(frame, color, alpha)
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    local bg = frame:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end

local function Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 20)
    Skin(b, C.buttonTop)
    local hl = b:CreateTexture()
    hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
    b:SetHighlightTexture(hl)
    b:SetNormalFontObject("MM_GameFontHighlightSmall")
    b:SetText(text)
    return b
end

local function CreateDialog()
    dialog = CreateFrame("Frame", "MerchantMapShareFrame", UIParent)
    dialog:SetSize(460, 300)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    dialog:SetClampedToScreen(true)
    Skin(dialog, C.bg, 0.97)
    -- New frames start shown; start hidden so the first toggle opens it
    dialog:Hide()
    tinsert(UISpecialFrames, "MerchantMapShareFrame")

    local title = dialog:CreateFontString(nil, "OVERLAY", "MM_GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Share verified data")
    title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    local close = CreateFrame("Button", nil, dialog)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetNormalFontObject("MM_GameFontHighlight")
    close:SetText("x")
    close:SetScript("OnClick", function() dialog:Hide() end)

    local help = dialog:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 10, -30)
    help:SetPoint("RIGHT", -10, 0)
    help:SetJustifyH("LEFT")
    help:SetText("Export, then copy with Ctrl+C. To import, paste someone's text here and press Import.")

    -- Scrolling text box for the export string
    local well = CreateFrame("Frame", nil, dialog)
    well:SetPoint("TOPLEFT", 10, -48)
    well:SetPoint("BOTTOMRIGHT", -10, 58)
    Skin(well, C.inset, 0.95)

    local scroll = CreateFrame("ScrollFrame", nil, well)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    scroll:EnableMouseWheel(true)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFontObject("MM_GameFontHighlightSmall")
    box:SetWidth(420)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, box:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 30)))
    end)
    well:SetScript("OnMouseDown", function() box:SetFocus() end)

    local status = dialog:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
    status:SetPoint("BOTTOMLEFT", 10, 38)
    status:SetPoint("RIGHT", -10, 0)
    status:SetJustifyH("LEFT")

    local export = Button(dialog, "Export", 90)
    export:SetPoint("BOTTOMLEFT", 10, 10)
    export:SetScript("OnClick", function()
        local text, vendors, services = MM:ExportData()
        if not text then
            status:SetText("|cffff5a4d" .. vendors .. "|r")
            return
        end
        box:SetText(text)
        box:HighlightText()
        box:SetFocus()
        status:SetText(("Exported %d vendors and %d service NPCs."):format(vendors, services))
    end)

    local import = Button(dialog, "Import", 90)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    import:SetScript("OnClick", function()
        local vendors, services = MM:ImportData(box:GetText())
        if not vendors then
            status:SetText("|cffff5a4d" .. services .. "|r")
            return
        end
        status:SetText(("Imported %d vendors and %d service NPCs. Newer entries you had were kept."):format(vendors, services))
    end)

    local clear = Button(dialog, "Clear", 70)
    clear:SetPoint("BOTTOMRIGHT", -10, 10)
    clear:SetScript("OnClick", function()
        box:SetText("")
        status:SetText("")
    end)
end

function MM:ToggleShare()
    if not dialog then CreateDialog() end
    dialog:SetShown(not dialog:IsShown())
end
