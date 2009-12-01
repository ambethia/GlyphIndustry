GlyphCrafter = CreateFrame("Frame");
GlyphCrafter:SetScript("OnEvent", function(self, event, ...) if self[event] then return self[event](self, event, ...) end end);
GlyphCrafter:RegisterEvent("ADDON_LOADED");
GlyphCrafter:Hide();

local ids = LibStub("tekIDmemo")
local auc = LibStub("tekAucQuery")

function GlyphCrafter:ADDON_LOADED(event, addon)
  self:UnregisterEvent("ADDON_LOADED");
  self.ADDON_LOADED = nil;
end

function GlyphCrafter.getProfitInfo(id)
  id = ids[id];
  local results = BeanCounter.API.search(id, {
    ["selectbox"]     = { "1", "server" },
    ["auction"]       = true,
    ["failedauction"] = true
  }, true, nil);

  local soldCount = 0;
  local failCount = 0
  
  for idx, auction in next, results do
    if auction[2] == "Auc Successful" then
      soldCount = soldCount + 1;
    elseif auction[2] == "Auc Expired" then
      failCount = failCount + 1;
    end
  end

  local totalTrys  = soldCount + failCount;
  local inkMod     = GlyphCrafter.twoInks:match(id) and 2 or 1
  local sellPrice  = auc[id] or 0
  local sellRate   = totalTrys > 0 and (soldCount / totalTrys) or 0
  local failFactor = failCount > 0 and (soldCount / failCount) or 0
  
  local profitability = (sellRate + failFactor + 0.05) * (sellPrice / inkMod)
  
  return profitability, totalTrys, soldCount, failCount, sellRate
end

-- GlyphCrafter.Panda_orig_ButtonFactory = Panda.ButtonFactory
-- 
-- function Panda.ButtonFactory(...)
--   local f = GlyphCrafter.Panda_orig_ButtonFactory(...)
--   return f
-- end

function GlyphCrafter.list()
  -- table.sort(t, function(a,b) return a<b end)
  local glyphs = {}

  for id, shortName in next, GlyphCrafter.GLYPHS do
    local ahCount = ForSaleByOwnerDB[GetRealmName().." "..UnitFactionGroup("player")][UnitName("player")][GetItemInfo(id)] or 0  
    local profitability = GlyphCrafter.getProfitInfo(id)
    table.insert(glyphs, {
      ["id"]            = id,
      ["shortName"]     = shortName,
      ["profitability"] = profitability,
      ["count"]         = ahCount + GetItemCount(id)
    })
    print(id, shortName)
  end
  
  return glyphs
end

function GlyphCrafter.CG(perc, ...)
	if perc >= 1 then
		local r, g, b = select(select('#', ...) - 2, ...)
		return r, g, b
	elseif perc <= 0 then
		local r, g, b = ...
		return r, g, b
	end
	
	local num = select('#', ...) / 3

	local segment, relperc = math.modf(perc*(num-1))
	local r1, g1, b1, r2, g2, b2 = select((segment*3)+1, ...)

	return r1 + (r2-r1)*relperc, g1 + (g2-g1)*relperc, b1 + (b2-b1)*relperc
end

function debug(...) DevTools_Dump(...); end


-- PANDA PANEL

-- ripped out of Panda/Glyphs.lua
local panel = Panda.panel.panels[3]

local name = GetSpellInfo(45357)

local auc = LibStub("tekAucQuery")

local function glyphcolorer(id, frame)
  if GlyphCrafter.GLYPHS[id] then
    local p = frame:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmall")
    local _, _, sold, _, rate = GlyphCrafter.getProfitInfo(id)
    local auc_price = auc[id]
    local craft_price = GetReagentCost and GetReagentCost(id)
    local price = auc_price and craft_price and (auc_price - craft_price) or auc_price
    local min_price = 50000 -- 5g
    p:SetPoint("LEFT", frame.icon, "LEFT", -1, 1)
    p:SetText(sold)
    p:SetTextColor(GlyphCrafter.CG(rate, 1,0,0, 1,1,0, 0,1,0), 0.5)
    p:SetShadowColor(0,0,0,0.25)
    p:SetShadowOffset(1, 1)    
    if GlyphCrafter.twoInks:match(id) then
      min_price = min_price*2
      local fs = frame:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmall")
      fs:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 0, -2)
      fs:SetText("*")
    end
    frame.icon:SetAlpha(.80)
    if sold and sold < 20 then frame.icon:SetAlpha(0.25) end
    if price and price < min_price then frame.icon:SetAlpha(0); frame:SetAlpha(0.25) end
  end
end

panel:RegisterFrame("Glyph Crafter", Panda.PanelFactory(45357,
[[
43544 43331 43350 43364 43367 43370 43379 43386 43390 43396
43673 43332 43351 43361 43340 43374 43380 43388 43389 43397
43672 43335 43338 43339 43368 43371 43378 43385 43394 43395
43535 43316 43356 43360 43365 43342 43376 43344 43391 43399
43539 43674 43355 43357 43369 43372 43343 43381 43393 43400
43671 43334 43354 43359 43366 43373 43377 43725   0   43398
  0   44922   0   44920   0     0     0   44923   0     0  
  0     0     0     0     0     0     0     0     0     0  
43549 40906 42914 42751 41092 42400 42969 41517 42464 43425
43547 40908 42912 42747 41106 42407 42972 41541 42455 43416
43551 40913 45731 42738 41105 42411 42971 41531 42454 43432
45804 40897 42907 44684 41103 42396 45768 41535 45785 43418
43542 40916 42909 44955 41109 42406 42961 41536 42453 43421
43827 40919 45732 42735 41099 42409 42973 41524 42459 43415
43546 40912 42902 45737 41110 45756 45761 41539 42456 43424
43543 40900 42911 42739 43867 42402 42954 41542 45779 43414
43548 40923 42904 42750 41094 42397 45762 45775 42467 43427
43536 40896 42901 42749 43869 45760 45769 45776 42469 43423
45805 40902 42898 42754 41100 42417 42968 41532 42465 43413
43553 40901 42915 42736 41098 45755 42960 41527 42472 43412
43545 40915 42905 45740 41096 42401 42964 41534 45789 43417
43825 45603 42910 42741 41108 42398 42967 41540 42462 43422
43550 45602 42917 42746 45745 42405 42955 41537 42458 43426
43826 40921 42916 42745 41095 42404 42956 45778 42463 43428
45806 40922 42906 42737 45746 42410 42974 41526 45780 45790
45799 40909 42908 42743 45742 42416 42957 45771 42468 43431
43554 45604 42913 42752 41102 42403 42970 41518 42460 43430
43541 44928 42903 42742 41097 42399 45767 41533 45781 45793
43538 40914 45734 42744 41107 42412 42966 41552 42466 45797
43537 46372   0   42734 45741   0   42958 41547 42470 43429
45800 45601   0   42740 41104   0   42965 41529 42473 43420
45803 40920   0   42748 43868   0   42962 45777 42457 45794
43533 40903   0   42753 41101   0   42959 41530 42461 43419
43552 40924   0     0     0     0   45908   0   42471   0  
  0   45622   0     0     0     0     0     0     0     0  
]], glyphcolorer))
