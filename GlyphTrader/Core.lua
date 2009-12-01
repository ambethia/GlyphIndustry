GlyphTrader = CreateFrame("Frame");
GlyphTrader:SetScript("OnEvent", function(self, event, ...) if self[event] then return self[event](self, event, ...) end end);
GlyphTrader:RegisterEvent("ADDON_LOADED");
GlyphTrader.Scanner = CreateFrame("Frame");
GlyphTrader:Hide();

local IDLE = 0; local SCANNING = 1;

local DEFAULTS = {
  maxAuctionCount = 13,
  minAuctionPrice = 30000 -- 3g
}

function GlyphTrader:ADDON_LOADED(event, addon)
  self.maxAuctionCount = DEFAULTS.maxAuctionCount;
  self.minAuctionPrice = DEFAULTS.minAuctionPrice;
  self.Scanner:Reset();
  
  self:CreateAuctionPanel();
  self.tabIndex = self:CreateAuctionFrameTab();
  hooksecurefunc("AuctionFrameTab_OnClick", self.AuctionFrameTab_OnClick_Hook);

  self:RegisterEvent("PLAYER_LOGOUT");
  self:UnregisterEvent("ADDON_LOADED");
  self.ADDON_LOADED = nil;
end

function GlyphTrader:ProcessAuctions()
  local glyphs = {};
  self.Scanner:Reset();

  for name, _ in pairs(self:GetCurrentGlyphInventory()) do glyphs[name] = true end
  if GlyphTrader.AuctionPanel.cancelCb:GetChecked() then
    for name, _ in pairs(self:GetCurrentGlyphAuctions()) do glyphs[name] = true end
  end
  for name, _ in pairs(glyphs) do table.insert(self.Scanner.queue, name) end
  
  table.sort(self.Scanner.queue);
  self.Scanner:Start();
end

function GlyphTrader:GetCurrentGlyphAuctions()
  local glyphs = {}
  for i = 1, GetNumAuctionItems("owner") do
    if GlyphCrafter.GLYPHS[tonumber(GetAuctionItemLink("owner", i):match("item:(%d+)"))] then
      local name, _, stack, _, _, _, _, _, _, _, _, _, saleStatus = GetAuctionItemInfo("owner", i);
      if saleStatus == 0 then
        if glyphs[name] then
          glyphs[name] = glyphs[name] + stack;
        else
          glyphs[name] = stack;
        end
      end
    end
  end

  return glyphs;
end

function GlyphTrader:GetCurrentGlyphInventory()
  local glyphs = {}
  for bagID = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bagID) do
      local link = GetContainerItemLink(bagID, slot)
      local _, stack = GetContainerItemInfo(bagID, slot);
      if link then
        if GlyphCrafter.GLYPHS[tonumber(link:match("item:(%d+)"))] then
          local name = GetItemInfo(link);
          if glyphs[name] then
            glyphs[name] = glyphs[name] + stack;
          else
            glyphs[name] = stack;
          end
        end
      end
    end
  end

  return glyphs;
end

function GlyphTrader.Scanner:Start()
  GlyphTrader.ToggleButtons();
  self:SetScript("OnUpdate", self.OnUpdate);
end

function GlyphTrader.Scanner:Stop()
  self:SetScript("OnUpdate", nil);
  GlyphTrader.ToggleButtons();
  GlyphTrader:UpdateStatus("Ready")
end

function GlyphTrader.Scanner:Reset()
  self.queue = {};         -- [name]
  self.currentQuery = nil; -- name
  self.lastUpdate = 0
  self.state = IDLE;
  self.callback = nil;
end

function GlyphTrader.Scanner:OnUpdate(elapsed)
  self.lastUpdate = self.lastUpdate + elapsed;
  local delay = GlyphTrader.AuctionPanel.loopCb:GetChecked() and 5 or 1;

  -- Wait a couple seconds
  if (self.lastUpdate > delay) then
    self.lastUpdate = 0;

    if self.state == IDLE then
      self.state = SCANNING;
      self.currentQuery = self.queue[1];
      if self.currentQuery then
        table.remove(self.queue, 1);
        self:TryCurrentQuery();
      else
        -- the queue must be empty
        if GlyphTrader.AuctionPanel.loopCb:GetChecked() then
          self:Stop();
          GlyphTrader:ProcessAuctions(); -- Start over
        else
          self:Stop();
        end
      end
    elseif self.state == SCANNING then
      self:TryCurrentQuery();
    end
  end
end

function GlyphTrader.Scanner:TryCurrentQuery()
  if CanSendAuctionQuery() then
    GlyphTrader:RegisterEvent("AUCTION_ITEM_LIST_UPDATE");
    AucAdvanced.Scan.Private.Hook.QueryAuctionItems(self.currentQuery, 0, 0, 0, 5, 0, 0, 0, 0, 0);
    GlyphTrader:UpdateStatus("Searching for %s", (self.currentQuery or ""))
  end
end

function GlyphTrader:AUCTION_ITEM_LIST_UPDATE()
  local lowest;
  -- look for the lowest competing price
  for i = 1, GetNumAuctionItems("list") do
    local name, _, count, _, _, _, _, _, buyoutPrice, _, highBidder, owner = GetAuctionItemInfo("list", i)
    if buyoutPrice > 0 then -- ignore non-buyout auctions
      local price = buyoutPrice / count;
      if not lowest then
        lowest = { price = price, name = name, owner = owner };
      elseif price < lowest.price then
        lowest = { price = price, name = name, owner = owner };
      end
    end
  end
  if lowest then
    -- Cancel auctions if we've been undercut
    for i = 1, GetNumAuctionItems("owner") do
      local name, _, stack, _, _, _, _, _, buyout, _, _, _, saleStatus = GetAuctionItemInfo("owner", i);
      if lowest.name == name and saleStatus == 0 and lowest.owner ~= UnitName("player") and lowest.price <= (buyout/stack) then
        local logMsg = ""
        if GlyphTrader.AuctionPanel.cancelCb:GetChecked() then
          logMsg = "Cancelled"
          if CanCancelAuction(i) then CancelAuction(i) end
        else
          logMsg = "Skipped cancel of"
        end
        self:Log("%s %s %s (-%s) %s", logMsg, name, self.FormatCurrency(buyout/stack), self.FormatCurrency((buyout/stack) - lowest.price), (lowest.owner or "??"));
      end
    end
  end

  for bagID = 0, NUM_BAG_SLOTS do
    for slot = 1, GetContainerNumSlots(bagID) do
      local link = GetContainerItemLink(bagID, slot)
      local _, stack = GetContainerItemInfo(bagID, slot);
      if link then
        if GlyphCrafter.GLYPHS[tonumber(link:match("item:(%d+)"))] then
          local name = GetItemInfo(link);
          if self.Scanner.currentQuery == name then
            local count;
            local posted = self:GetCurrentGlyphAuctions()[name];
            if posted then
              -- we already have some posted
              count = self.maxAuctionCount - posted;
            else
              -- we don't have any posted            
              count = self.maxAuctionCount;
            end
            -- if we have some to auction
            if count > 0 then
              -- determine the selling price
              -- local price = 0;
              -- if lowest then
              --   -- undercut the lowest price by 2.5s
              --   price = lowest.price - 250;
              -- else
              --   -- guess the price
              --   if AucAdvanced and AucAdvanced.Modules and AucAdvanced.Modules.Util.Appraiser and AucAdvanced.Modules.Util.Appraiser.GetPrice then
              --     price = AucAdvanced.Modules.Util.Appraiser.GetPrice(link, nil, true)
              --   end
              -- end

              -- CRAZY LOW LIQUIDATION PRICES
              local price = 66600;
              if lowest then
                price = math.min(lowest.price - 250, price);
              end

              -- don't get totally ripped off
              if price >= self.minAuctionPrice then
                -- finally post them
                count = math.min(count, stack)
                sig = AucAdvanced.API.GetSigFromLink(link);
                AucAdvanced.Post.PostAuction(sig, 1, price*0.90, price, 12*60, count);
                local sap = lowest and (lowest.owner or "??") or "None";
                self:Log("Posting %s %s %s", name, self.FormatCurrency(price), sap);
              end
            end
          end
        end
      end
    end
  end

  -- self.currentQuery = nil;
  self.Scanner.state = IDLE;
  GlyphTrader:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE");
end

-- Create a tab on the AuctionHouse UI
function GlyphTrader:CreateAuctionFrameTab()
  local tabIndex = 1;
  while getglobal("AuctionFrameTab" .. tabIndex) ~= nil do tabIndex = tabIndex + 1; end
  local tab = CreateFrame("Button", "AuctionFrameTab" .. tabIndex,
    AuctionFrame, "AuctionTabTemplate");
  tab:SetID(tabIndex);
  tab:SetText("Glyphs");
  tab:SetPoint("LEFT", "AuctionFrameTab" .. (tabIndex - 1), "RIGHT", -8, 0);
  PanelTemplates_DeselectTab(tab);
  PanelTemplates_SetNumTabs(AuctionFrame, tabIndex);
  return tabIndex;
end

function GlyphTrader:CreateAuctionPanel()
  self.AuctionPanel = CreateFrame("Frame", nil, AuctionFrame);
  local frame = self.AuctionPanel; frame:Hide();

  frame:SetPoint("TOPLEFT",     AuctionFrame, "TOPLEFT",     0, 0);
  frame:SetPoint("BOTTOMRIGHT", AuctionFrame, "BOTTOMRIGHT", 0, 0);

  frame.cancelBtn = CreateFrame("BUTTON", nil, frame, "UIPanelButtonTemplate")
  frame.cancelBtn:SetWidth(80); frame.cancelBtn:SetHeight(22);
  frame.cancelBtn:SetText("Stop");
  frame.cancelBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 14);
  frame.cancelBtn:SetScript("OnClick", function() self.Scanner:Stop(self.Scanner); end);
  frame.cancelBtn:Disable();

  frame.beginBtn = CreateFrame("BUTTON", nil, frame, "UIPanelButtonTemplate")
  frame.beginBtn:SetWidth(126); frame.beginBtn:SetHeight(22);
  frame.beginBtn:SetText("Start");
  frame.beginBtn:SetPoint("RIGHT", frame.cancelBtn, "LEFT", 2, 0);
  frame.beginBtn:SetScript("OnClick", function() self.ProcessAuctions(self); end);

  frame.btnsEnabled = true;

  frame.loopCb = CreateFrame("CheckButton", "AuctionPanelLoopCB", frame, "OptionsCheckButtonTemplate");
  frame.loopCb:SetPoint("LEFT", AuctionFrameMoneyFrame, "RIGHT", 3, -1);
  frame.loopCb.text = getglobal("AuctionPanelLoopCBText")
  frame.loopCb.text:SetText("Loop?")
  frame.loopCb:SetChecked(0);

  frame.cancelCb = CreateFrame("CheckButton", "AuctionPanelCancelCB", frame, "OptionsCheckButtonTemplate");
  frame.cancelCb:SetPoint("LEFT", frame.loopCb, "RIGHT", 100, 0);
  frame.cancelCb.text = getglobal("AuctionPanelCancelCBText")
  frame.cancelCb.text:SetText("Cancel?");
  frame.cancelCb:SetChecked(1);

  frame.statusLbl = frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall");
  frame.statusLbl:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -20, -50);
  frame.statusLbl:SetText("Ready");
  frame.statusLbl:SetJustifyH("RIGHT");

  frame.LogFrame = CreateFrame("ScrollingMessageFrame", nil, frame);
  frame.LogFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -76);
  frame.LogFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -100, 42);
  frame.LogFrame:SetFontObject(ChatFontSmall);
  frame.LogFrame:SetJustifyH("LEFT");
  frame.LogFrame:SetJustifyV("TOP");
  frame.LogFrame:SetMaxLines(1000);
  frame.LogFrame:SetFadeDuration(120);
  frame.LogFrame:EnableMouseWheel(1);
  frame.LogFrame:SetScript("OnMouseWheel", function(log, delta)
    if delta > 0 then
      if IsShiftKeyDown() then log:ScrollToTop()
      else log:ScrollUp() end
    elseif delta < 0 then
      if IsShiftKeyDown() then log:ScrollToBottom()
      else log:ScrollDown() end
    end
  end)
end

function GlyphTrader:Log(msg, ...)
  self.AuctionPanel.LogFrame:AddMessage(date("|cff9d9d9d%H:%M|r ") .. (format(msg, ...) or ""));
end

function GlyphTrader:UpdateStatus(msg, ...)
  self.AuctionPanel.statusLbl:SetText(format(msg, ...) or "");
end

function GlyphTrader.ToggleButtons()
  local panel = GlyphTrader.AuctionPanel;
  if panel.btnsEnabled then
    panel.btnsEnabled = false;
    panel.beginBtn:SetText("Scanning...");
    panel.beginBtn:Disable();
    panel.cancelBtn:Enable();
  else
    panel.btnsEnabled = true;
    panel.beginBtn:SetText("Start");
    panel.beginBtn:Enable();
    panel.cancelBtn:Disable();
  end
end

function GlyphTrader.AuctionFrameTab_OnClick_Hook(index)
  GlyphTrader.AuctionPanel:Hide();  
  if (index and index:GetID()) == GlyphTrader.tabIndex then
    AuctionFrameTopLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopLeft");
    AuctionFrameTop:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Top");
    AuctionFrameTopRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-TopRight");
    AuctionFrameBotLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotLeft");
    AuctionFrameBot:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-Bot");
    AuctionFrameBotRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Auction-BotRight");
    GlyphTrader.AuctionPanel:Show();
  end
end

function GlyphTrader.FormatCurrency(amount)
  if not amount then return end
  local silver = floor((amount/100)%100)
  local gold   = floor((amount/100)/100)
  if gold > 0 then
    return string.format("|cffffd700%d.|cffc7c7cf%02d", gold, silver)
  else
    return string.format("|cffc7c7cf%d", silver)
  end
end

function GlyphTrader:PLAYER_LOGOUT()
  -- Do stuff on logout.
end
