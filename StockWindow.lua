local _, MM = ...

local W, C = MM.W, MM.COLORS
local ACCENT, BORDER = C.accent, C.border
local ROW_H, SCROLL_W = W.ROW_H, W.SCROLL_W
local Fill, Outline, Grain, Gradient = W.Fill, W.Outline, W.Grain, W.Gradient
local AddScrollbar, UpdateScrollbar = W.AddScrollbar, W.UpdateScrollbar
local panel = MM.panel

-- Vendor stock window: everything one vendor sells, opened by shift-clicking them on the map

local STOCK_ROWS, STOCK_W = 18, 320
local stock = CreateFrame("Frame", "MerchantMapStockFrame", UIParent)
stock:SetSize(STOCK_W, 64 + STOCK_ROWS * ROW_H + 10)
stock:SetPoint("CENTER", 220, 0)
stock:SetFrameStrata("FULLSCREEN_DIALOG")
stock:SetClampedToScreen(true)
stock:SetMovable(true)
stock:EnableMouse(true)
stock:RegisterForDrag("LeftButton")
stock:SetScript("OnDragStart", stock.StartMoving)
stock:SetScript("OnDragStop", stock.StopMovingOrSizing)
stock:Hide()
Fill(stock, C.bg, 0.97)
Grain(stock, 0.35)
Outline(stock, BORDER)
tinsert(UISpecialFrames, "MerchantMapStockFrame")
-- Closes when combat starts
stock:RegisterEvent("PLAYER_REGEN_DISABLED")
stock:SetScript("OnEvent", stock.Hide)

local stockHeader = CreateFrame("Frame", nil, stock)
stockHeader:SetPoint("TOPLEFT", 1, -1)
stockHeader:SetPoint("TOPRIGHT", -1, -1)
stockHeader:SetHeight(52)
Gradient(stockHeader, C.bg, C.header)

local stockName = stockHeader:CreateFontString(nil, "OVERLAY", "MM_GameFontNormal")
stockName:SetPoint("TOPLEFT", 10, -8)
stockName:SetPoint("RIGHT", -28, 0)
stockName:SetJustifyH("LEFT")
stockName:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
local stockInfo = stockHeader:CreateFontString(nil, "OVERLAY", "MM_GameFontDisableSmall")
stockInfo:SetPoint("TOPLEFT", stockName, "BOTTOMLEFT", 0, -4)
stockInfo:SetPoint("RIGHT", -10, 0)
stockInfo:SetJustifyH("LEFT")

local stockClose = CreateFrame("Button", nil, stockHeader)
stockClose:SetSize(20, 20)
stockClose:SetPoint("TOPRIGHT", -4, -4)
stockClose:SetNormalFontObject("MM_GameFontHighlight")
stockClose:SetHighlightFontObject("MM_GameFontNormal")
stockClose:SetText("x")
stockClose:SetScript("OnClick", function() stock:Hide() end)

local stockList = CreateFrame("Frame", nil, stock)
stockList:SetPoint("TOPLEFT", 8, -60)
stockList:SetPoint("BOTTOMRIGHT", -8, 8)
Fill(stockList, C.inset, 0.95)
AddScrollbar(stockList)

local stockKey, stockItems, stockOffset = nil, {}, 0
local stockRows = {}

local function DrawStock()
    stockOffset = math.max(0, math.min(stockOffset, #stockItems - STOCK_ROWS))
    for i, row in ipairs(stockRows) do
        local itemID = stockItems[stockOffset + i]
        local item = itemID and MM.db.items[itemID]
        local offer = item and item.vendors[stockKey]
        row.itemID = item and itemID
        row.rule:SetShown(itemID == "late")
        if itemID == "late" then
            row.icon:SetTexture(nil)
            row.name:SetText("Not in stock at last visit")
            row.name:SetTextColor(0.6, 0.6, 0.6)
            row.price:SetText("")
            row:Show()
        elseif offer then
            local color = ITEM_QUALITY_COLORS[item.quality or 1] or ITEM_QUALITY_COLORS[1]
            row.icon:SetTexture(item.icon or 134400)
            row.name:SetText(item.name or "?")
            row.name:SetTextColor(color.r, color.g, color.b)
            row.price:SetText(offer.notSeen and "" or MM:PriceText(offer))
            row:Show()
        else
            row:Hide()
        end
    end
    UpdateScrollbar(stockList, stockOffset, #stockItems, STOCK_ROWS)
end
stockList.onScroll = function(pos)
    stockOffset = pos
    DrawStock()
end
stockList:EnableMouseWheel(true)
stockList:SetScript("OnMouseWheel", function(_, delta)
    stockOffset = stockOffset - delta * 3
    DrawStock()
end)

for i = 1, STOCK_ROWS do
    local row = CreateFrame("Button", nil, stockList)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", -(SCROLL_W + 4), 0)
    local hl = row:CreateTexture()
    hl:SetColorTexture(1, 1, 1, 0.06)
    row:SetHighlightTexture(hl)
    -- Thin line above the "Not in stock at last visit" heading, setting it apart from what's in stock
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetHeight(1)
    row.rule:SetPoint("TOPLEFT", 4, 0)
    row.rule:SetPoint("TOPRIGHT", -4, 0)
    row.rule:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
    row.rule:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.price = row:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
    row.price:SetPoint("RIGHT", -4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "MM_GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(stock, "ANCHOR_NONE")
        GameTooltip:SetPoint("TOPLEFT", stock, "TOPRIGHT", 4, 0)
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    -- Shift-click links the item in chat, like anywhere else
    row:SetScript("OnClick", function(self)
        if not (self.itemID and IsModifiedClick()) then return end
        local item = MM.db.items[self.itemID]
        local link = item.link or select(2, C_Item.GetItemInfo(self.itemID))
        if link then HandleModifiedItemClick(link) end
    end)
    stockRows[i] = row
end

function MM:ShowVendorStock(key)
    local vendor = self.db.vendors[key]
    if not vendor or W.InCombat() then return end
    stockKey, stockItems, stockOffset = key, self:VendorItems(key), 0
    -- Those not in stock at the last visit are sorted last, under their own heading
    local count = #stockItems
    for i, itemID in ipairs(stockItems) do
        if self.db.items[itemID].vendors[key].notSeen then
            table.insert(stockItems, i, "late")
            break
        end
    end
    stockName:SetText(vendor.name .. (vendor.title and (" |cff8a8a8a<" .. vendor.title .. ">|r") or ""))
    stockInfo:SetText(("%s   %d items"):format(self:LocationText(vendor), count))
    stock:Show()
    stock:SetFrameLevel(panel:GetFrameLevel() + 100)
    DrawStock()
end

-- Prices and names that load later show up while it's open
stock:SetScript("OnShow", function()
    stock:SetScale(MM.db.windowScale or 1)
    stock:SetFrameLevel(panel:GetFrameLevel() + 100)
    DrawStock()
end)
tinsert(W.scaled, stock)
