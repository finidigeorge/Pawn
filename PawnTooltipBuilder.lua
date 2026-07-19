-- Pawn tooltip builder pipeline (extracted from Pawn.lua)

-- Keyed by item link. Stores computed set bonus values from the last visible tooltip scan.
-- Separate from the item cache so the character-context data (which pieces are worn) never
-- pollutes the static-item cache that is populated from the hidden PawnPrivateTooltip.
local PawnSetBonusCache = {}

-- Item links can differ by color, enchant, or normalization path. Set membership is tied
-- to the base item, so use its item ID as the stable cache key whenever possible.
local function PawnGetSetBonusCacheKey(ItemLink)
	if not ItemLink then return nil end
	local ItemID = PawnGetItemIDFromLink(ItemLink)
	if ItemID then return tostring(ItemID) end
	return ItemLink
end

-- Returns true when GameTooltip is currently showing quest-context content.
function PawnTooltipBuilder:IsQuestLikeGameTooltip(Tooltip)
	if Tooltip ~= GameTooltip then return false end
	if Tooltip.PawnData and Tooltip.PawnData.IsQuestTooltip then return true end

	if Tooltip.GetOwner and Tooltip:GetOwner() and Tooltip:GetOwner().GetName then
		local OwnerName = Tooltip:GetOwner():GetName()
		if OwnerName and string.find(OwnerName, "Quest") then
			return true
		end
	end

	local QuestNameLink = PawnResolveGameTooltipItemLinkByName()
	if QuestNameLink and PawnGetHyperlinkType(QuestNameLink) == "item" then return true end

	return false
end

function PawnIsQuestLikeGameTooltip(Tooltip)
	return PawnTooltipBuilder:IsQuestLikeGameTooltip(Tooltip)
end

-- Resolves an item link from GameTooltip text, preferring stable item hyperlinks.
function PawnTooltipBuilder:ResolveGameTooltipItemLinkByName()
	local ItemName = PawnGetItemNameFromTooltip("GameTooltip")
	if not ItemName then return nil, nil end

	if GetItemInfo then
		local _, NameLink = GetItemInfo(ItemName)
		if NameLink and PawnGetHyperlinkType(NameLink) == "item" then
			return NameLink, ItemName
		end
	end

	if PawnGetQuestItemLinkByName then
		local QuestNameLink = PawnGetQuestItemLinkByName(ItemName)
		if QuestNameLink and PawnGetHyperlinkType(QuestNameLink) == "item" then
			return QuestNameLink, ItemName
		end
	end

	return nil, ItemName
end

function PawnResolveGameTooltipItemLinkByName()
	return PawnTooltipBuilder:ResolveGameTooltipItemLinkByName()
end

-- Gets the item data for a specific item.  Retrieves the information from the cache when possible; otherwise, gets it from the tooltip specified.
-- Return value type is the same as PawnGetCachedItem.
function PawnGetItemDataFromTooltip(TooltipName, MethodName, Param1, Param2, Param3, Param4)
	VgerCore.Assert(TooltipName, "TooltipName must be non-null!")
	VgerCore.Assert(MethodName, "MethodName must be non-null!")
	if (not TooltipName) or (not MethodName) then return end
	
	-- First, find the tooltip.
	local Tooltip = getglobal(TooltipName)
	if not Tooltip then return end
	
	-- If we have a tooltip, try to get an item link from it.
	local ItemLink, ItemID, ItemLevel
	if (MethodName == "SetHyperlink") and Param1 then
		-- Special case: if the method is SetHyperlink, then we already have an item link.
		-- (Normally, GetItem will work, but SetHyperlink is used by some mod compatibility code.)
		ItemLink = Param1
	elseif (MethodName == "SetQuestItem") then
		-- Quest dialog item tooltips may not expose links via Tooltip:GetItem() on older clients.
		local ItemType = Param1
		local ItemIndex = Param2
		if type(Param1) == "table" then
			ItemType = Param2
			ItemIndex = Param3
		end
		if ItemType and ItemIndex and GetQuestItemLink then
			ItemLink = GetQuestItemLink(ItemType, ItemIndex)
		end
		if (not ItemLink) and Tooltip.GetItem then
			_, ItemLink = Tooltip:GetItem()
		end
	elseif (MethodName == "SetQuestLogItem") then
		-- Quest log tooltips may pass through here without exposing links via Tooltip:GetItem().
		local ItemType = Param1
		local ItemIndex = Param2
		if type(Param1) == "table" then
			ItemType = Param2
			ItemIndex = Param3
		end
		if ItemType and ItemIndex and GetQuestLogItemLink then
			ItemLink = GetQuestLogItemLink(ItemType, ItemIndex)
		end
		if (not ItemLink) and Tooltip.GetItem then
			_, ItemLink = Tooltip:GetItem()
		end
	elseif (MethodName == "SetLootRollItem") then
		-- Party/raid roll tooltips often don't return a link from Tooltip:GetItem() in older clients.
		-- For hooksecurefunc(self, ...), Param1 may be the tooltip itself and roll ID is Param2.
		local RollID = Param1
		if type(Param1) == "table" and Param2 then RollID = Param2 end
		if RollID and GetLootRollItemLink then
			ItemLink = GetLootRollItemLink(RollID)
		end
	elseif (MethodName == "SetLootItem") then
		-- Loot window tooltips can similarly fail to expose links through GetItem.
		local LootSlot = Param1
		if type(Param1) == "table" and Param2 then LootSlot = Param2 end
		if LootSlot and GetLootSlotLink then
			ItemLink = GetLootSlotLink(LootSlot)
		end
	elseif Tooltip.GetItem then
		_, ItemLink = Tooltip:GetItem()
	end
	
	-- If we got an item link from the tooltip (or it was passed in), we can go through the simpler and more effective code that specifically
	-- uses item links, and skip the rest of this function.
	if ItemLink then
		return PawnGetItemData(ItemLink)
	end
	
	-- If we made it this far, then we're in the degenerate case where the tooltip doesn't have item information.  Let's look for the item's name,
	-- and maybe we'll get lucky and find that in our item cache.
	local ItemName, ItemNameLineNumber = PawnGetItemNameFromTooltip(TooltipName)
	if (not ItemName) or (not ItemNameLineNumber) then return end

	-- Extra fallback for quest-tooltip flows on older clients/UIPacks:
	-- If GameTooltip has no link, try to resolve by item name via quest APIs.
	-- Some UI packs use non-Blizzard owner names and no global Quest* OnEnter handlers.
	if TooltipName == "GameTooltip" then
		local OwnerName = nil
		if Tooltip.GetOwner and Tooltip:GetOwner() and Tooltip:GetOwner().GetName then
			OwnerName = Tooltip:GetOwner():GetName()
		end

		-- Turtle-friendly fallback: resolve link from item name via GetItemInfo, which is often
		-- available even when quest-specific tooltip APIs/functions are missing or replaced.
		if GetItemInfo then
			local _, NameLink = GetItemInfo(ItemName)
			if NameLink and PawnGetHyperlinkType(NameLink) == "item" then
				return PawnGetItemData(NameLink)
			end
		end

		local QuestItemLink = PawnGetQuestItemLinkByName(ItemName)
		if QuestItemLink then
			return PawnGetItemData(QuestItemLink)
		end
	end

	local Item = PawnGetCachedItem(nil, ItemName)
	if Item and Item.Values then
		return Item
	end
	-- If Item is non-null but Item.Values is null, we're not done yet!
	
	-- Ugh, the tooltip doesn't have item information and this item isn't in the Pawn item cache, so we'll have to try to parse this tooltip.	
	if not Item then
		Item = PawnGetEmptyCachedItem(nil, ItemName)
		if PawnOptions.Debug then
			PawnDebugMessage(" ")
			PawnDebugMessage("====================")
			PawnDebugMessage(VgerCore.Color.Green .. ItemName)
		end
		
		-- Since we don't have an item link, we have to just read stats from the original tooltip, so we only get enchanted values.
		PawnFixStupidTooltipFormatting(TooltipName)
		Item.Stats, Item.SocketBonusStats, Item.UnknownLines, _, Item.SetBonusStats = PawnGetStatsFromTooltip(TooltipName, true)
		if PawnOptions.Debug then
			PawnDebugMessage(PawnLocal.FailedToGetItemLinkMessage)
			PawnDebugMessage("Method=" .. tostring(MethodName) .. ", p1=" .. tostring(Param1) .. ", p2=" .. tostring(Param2) .. ", p3=" .. tostring(Param3))
		end
		
		-- Cache this item so we don't have to re-parse next time.
		-- Only cache if we found recognizable stats; otherwise this is a non-item tooltip (e.g. a spell).
		if not Item.Stats or not next(Item.Stats) then return nil end
		PawnCacheItem(Item)
	end
	
	-- Recalculate the scale values for the item only if necessary.
	PawnRecalculateItemValuesIfNecessary(Item)
	
	return Item
end

-- Returns the same information as PawnGetItemData, but based on an inventory slot index instead of an item link.
-- If requested, data for the base unenchanted item can be returned instead; otherwise, the actual item is returned.
function PawnGetItemDataForInventorySlot(Slot, Unenchanted)
	local ItemLink = GetInventoryItemLink("player", Slot)
	if not ItemLink then return end
	if Unenchanted then
		local UnenchantedItem = PawnUnenchantItemLink(ItemLink)
		if UnenchantedItem then ItemLink = UnenchantedItem end
	end
	return PawnGetItemData(ItemLink)
end

-- Recalculates the scale values for a cached item if necessary, and returns them.
function PawnRecalculateItemValuesIfNecessary(Item)
	-- We now have stats for the item.  If values aren't already calculated for the item, calculate those.  This happens when we have
	-- just retrieved the stats for the item, and also when the item values were cleared from the cache but not the stats.
	if not Item.Values then
		-- Calculate each of the values for which there are scales.
		Item.Values = PawnGetAllItemValues(Item.Stats, Item.SocketBonusStats, Item.UnenchantedStats, Item.UnenchantedSocketBonusStats, PawnOptions.Debug)
		if PawnOptions.Debug then PawnDebugMessage(" ") end
	end
	return Item.Values
end

-- Returns a single scale value (in both its enchanted and unenchanted forms) for a cached item.  Returns nil for any values that are not present.
function PawnGetSingleValueFromItem(Item, ScaleName)
	local ValuesTable = PawnRecalculateItemValuesIfNecessary(Item)
	if not ValuesTable then return end
	
	-- The scale values are sorted alphabetically, so we need to go through the list.
	local Count = table.getn(ValuesTable)
	for i = 1, Count do
		local Value = ValuesTable[i]
		if Value[1] == ScaleName then
			return Value[2], Value[3]
		end
	end
	
	-- It's not here; return nil.
end

-- Returns true if a tooltip currently contains at least one visible Pawn scale line.
function PawnTooltipHasPawnScaleLine(Tooltip)
	if not Tooltip or not Tooltip.GetName then return false end
	if not Tooltip.NumLines then return false end
	if not PawnOptions or not PawnOptions.Scales then return false end

	local TooltipName = Tooltip:GetName()
	if not TooltipName then return false end

	for i = 2, Tooltip:NumLines() do
		local LeftLine = getglobal(TooltipName .. "TextLeft" .. i)
		if LeftLine and LeftLine.GetText then
			local Text = LeftLine:GetText()
			if Text and Text ~= "" then
				for ScaleName, Scale in pairs(PawnOptions.Scales) do
					if not Scale.Hidden and string.find(Text, ScaleName, 1, true) then
						return true
					end
				end
			end
		end
	end

	return false
end

-- Scans a visible tooltip for active Set: bonus lines and stores the result in PawnSetBonusCache[ItemLink].
-- ItemLink is used as the cache key. Call once per PawnUpdateTooltip, before adding any Pawn lines.
local function PawnCacheSetBonusFromTooltip(TooltipName, ItemLink)
	if not TooltipName or TooltipName == "PawnPrivateTooltip" then return end
	if not ItemLink then
		if PawnOptions.Debug then PawnDebugMessage("SBC: skip - no ItemLink (tooltip=" .. tostring(TooltipName) .. ")") end
		return
	end
	local TooltipObj = getglobal(TooltipName)
	local numLines = TooltipObj and TooltipObj.NumLines and TooltipObj:NumLines() or 0
	if PawnOptions.Debug then PawnDebugMessage("SBC: " .. TooltipName .. " lines=" .. numLines .. " link=" .. tostring(ItemLink)) end
	if numLines == 0 then return end
	local _, ItemNameLineNumber = PawnGetItemNameFromTooltip(TooltipName)
	if not ItemNameLineNumber then return end
	local foundSet = false
	local Stats = {}
	for i = ItemNameLineNumber + 1, numLines do
		local LeftLine = getglobal(TooltipName .. "TextLeft" .. i)
		if LeftLine then
			local LineText = LeftLine:GetText()
			if LineText then
				local s = string.sub(LineText, 1, 4)
				if s == "Set:" or s == "set:" then
					foundSet = true
					if PawnOptions.Debug then PawnDebugMessage("SBC: found [" .. LineText .. "]") end
					local Understood = PawnLookForSingleStat(PawnRegexes, Stats, LineText, false)
					-- Some 1.12 clients expose a visually wrapped bonus as multiple tooltip
					-- font strings. Join continuation lines until the complete bonus parses.
					if not Understood then
						local JoinedText = LineText
						for j = i + 1, math.min(i + 3, numLines) do
							local ContinuationLine = getglobal(TooltipName .. "TextLeft" .. j)
							local ContinuationText = ContinuationLine and ContinuationLine:GetText()
							if not ContinuationText or ContinuationText == "" or string.sub(ContinuationText, 1, 4) == "Set:"
								or string.sub(ContinuationText, 1, 1) == "(" then break end
							JoinedText = JoinedText .. " " .. ContinuationText
							if PawnLookForSingleStat(PawnRegexes, Stats, JoinedText, false) then break end
						end
					end
				end
			end
		end
	end
	if PawnOptions.Debug then PawnDebugMessage("SBC: foundSet=" .. tostring(foundSet) .. " statsHit=" .. tostring(next(Stats) ~= nil)) end
	if next(Stats) then
		local Values = PawnGetAllItemValues(Stats, nil, nil, nil, false)
		if Values and type(Values) == "table" and table.getn(Values) > 0 then
			PawnSetBonusCache[PawnGetSetBonusCacheKey(ItemLink)] = Values
			if PawnOptions.Debug then PawnDebugMessage("SBC: wrote " .. tostring(table.getn(Values)) .. " values") end
		end
	end
end

local PawnAddExtraLinesToTooltip

-- Appends Pawn scale values and set bonus values (from PawnSetBonusCache) to a tooltip.
function PawnAppendValuesToTooltip(TargetTooltip, Item)
	if not TargetTooltip or not Item or not Item.Values then return false end
	local SetBonusCacheKey = PawnGetSetBonusCacheKey(Item.Link)
	if PawnOptions.Debug then PawnDebugMessage("APV: link=" .. tostring(Item.Link) .. " cacheHit=" .. tostring(SetBonusCacheKey and PawnSetBonusCache[SetBonusCacheKey] ~= nil)) end
	local AddSpace = PawnOptions.ShowSpace
	if AddSpace and table.getn(Item.Values) > 0 then TargetTooltip:AddLine(" ") end
	local OriginalAlign = PawnOptions.AlignNumbersRight
	if TargetTooltip == GameTooltip then PawnOptions.AlignNumbersRight = true end
	PawnAddValuesToTooltip(TargetTooltip, Item.Values)
	PawnOptions.AlignNumbersRight = OriginalAlign
	local SetBonusValues = SetBonusCacheKey and PawnSetBonusCache[SetBonusCacheKey]
	if SetBonusValues and type(SetBonusValues) == "table" and table.getn(SetBonusValues) > 0 then
		if PawnOptions.Debug then PawnDebugMessage("APV: appending " .. tostring(table.getn(SetBonusValues)) .. " set bonus lines") end
		PawnAddSetBonusValuesToTooltip(TargetTooltip, SetBonusValues)
	end
	-- No Show() here — caller owns the Show() lifecycle.
	return true
end

-- Finalizes a tooltip that has already been populated by the game or another addon.
-- Character slots, bags, and Shagu comparison frames all use this path so set-bonus
-- scanning and duplicate handling stay identical. The caller owns the final Show().
function PawnFinalizeItemTooltip(Tooltip, ItemLink)
	if not Tooltip or not ItemLink or PawnGetHyperlinkType(ItemLink) ~= "item" then return false end
	if not PawnOptions or not PawnOptions.Scales then return false end
	local TooltipName = Tooltip.GetName and Tooltip:GetName()
	if not TooltipName then return false end

	local Item = PawnGetItemData(ItemLink)
	if not Item or not Item.Values or table.getn(Item.Values) == 0 then return false end

	PawnCacheSetBonusFromTooltip(TooltipName, Item.Link or ItemLink)

	if not Tooltip.PawnData then Tooltip.PawnData = {} end
	Tooltip.PawnData.LastItemLink = Item.Link or ItemLink
	Tooltip.UpdatingPawn = true

	if PawnTooltipHasPawnScaleLine(Tooltip) then
		local SetBonusValues = PawnSetBonusCache[PawnGetSetBonusCacheKey(Item.Link or ItemLink)]
		if SetBonusValues and table.getn(SetBonusValues) > 0 then
			local OriginalAlign = PawnOptions.AlignNumbersRight
			if Tooltip == GameTooltip then PawnOptions.AlignNumbersRight = true end
			PawnAddSetBonusValuesToTooltip(Tooltip, SetBonusValues)
			PawnOptions.AlignNumbersRight = OriginalAlign
		end
	else
		PawnAppendValuesToTooltip(Tooltip, Item)
		PawnAddExtraLinesToTooltip(Tooltip, TooltipName, Item)
	end

	Tooltip.PawnData.PawnLinesAdded = true
	Tooltip.PawnData.LastNumLines = Tooltip:NumLines()
	Tooltip.UpdatingPawn = nil
	return true
end

-- Finalizes a visible item tooltip when this 1.12 client exposes no reliable item link.
-- Pawn's existing tooltip parser is the authority here: arbitrary UI menus are ignored
-- unless their visible text contains actual recognized item stats.
function PawnFinalizeVisibleItemTooltip(Tooltip)
	if not Tooltip or not Tooltip.GetName then return false end
	if not PawnOptions or not PawnOptions.Scales then return false end
	local TooltipName = Tooltip:GetName()
	if not TooltipName then return false end

	PawnFixStupidTooltipFormatting(TooltipName)
	local Stats, SocketBonusStats, _, _, SetBonusStats = PawnGetStatsFromTooltip(TooltipName, false)
	if not Stats or not next(Stats) then return false end

	local Values = PawnGetAllItemValues(Stats, SocketBonusStats, nil, nil, false)
	if not Values or table.getn(Values) == 0 then return false end

	Tooltip.UpdatingPawn = true
	local OriginalAlign = PawnOptions.AlignNumbersRight
	if Tooltip == GameTooltip then PawnOptions.AlignNumbersRight = true end
	if not PawnTooltipHasPawnScaleLine(Tooltip) then PawnAddValuesToTooltip(Tooltip, Values) end

	if SetBonusStats and next(SetBonusStats) then
		local SetBonusValues = PawnGetAllItemValues(SetBonusStats, nil, nil, nil, false)
		if SetBonusValues and table.getn(SetBonusValues) > 0 then
			PawnAddSetBonusValuesToTooltip(Tooltip, SetBonusValues)
		end
	end
	PawnOptions.AlignNumbersRight = OriginalAlign

	if not Tooltip.PawnData then Tooltip.PawnData = {} end
	Tooltip.PawnData.PawnLinesAdded = true
	Tooltip.PawnData.LastNumLines = Tooltip:NumLines()
	Tooltip.UpdatingPawn = nil
	return true
end

-- Appends asterisk annotation, Item ID, and Item Level lines if configured.
-- Shared between PawnUpdateTooltip and PawnPatchTooltip to avoid duplication.
PawnAddExtraLinesToTooltip = function(Tooltip, TooltipName, Item)
	if Item.UnknownLines then
		if (PawnOptions.ShowAsterisks == PawnShowAsterisksAlways) or
		   ((PawnOptions.ShowAsterisks == PawnShowAsterisksNonzero or PawnOptions.ShowAsterisks == PawnShowAsterisksNonzeroNoText)
		    and table.getn(Item.Values) > 0) then
			local Annotated = PawnAnnotateTooltipLines(TooltipName, Item.UnknownLines)
			if Annotated and PawnOptions.ShowAsterisks ~= PawnShowAsterisksNonzeroNoText then
				Tooltip:AddLine(PawnLocal.AsteriskTooltipLine, VgerCore.Color.BlueR, VgerCore.Color.BlueG, VgerCore.Color.BlueB)
			end
		end
	end
	if PawnOptions.ShowItemID and Item.Link then
		if not PawnIsAddOnLoaded("AtlasLoot") or not AtlasLootOptions or not AtlasLootOptions.ShowItemID then
			local IDs = PawnGetItemIDsForDisplay(Item.Link)
			if IDs then
				if PawnOptions.AlignNumbersRight then
					Tooltip:AddDoubleLine(PawnLocal.ItemIDTooltipLine, IDs, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB)
				else
					Tooltip:AddLine(PawnLocal.ItemIDTooltipLine .. ":  " .. IDs, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB)
				end
			end
		end
	end
	if PawnOptions.ShowItemLevel and Item.Level and Item.Level > 1 then
		if PawnOptions.AlignNumbersRight then
			Tooltip:AddDoubleLine(PawnLocal.ItemLevelTooltipLine, Item.Level, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB)
		else
			Tooltip:AddLine(PawnLocal.ItemLevelTooltipLine .. ":  " .. Item.Level, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB)
		end
	end
end

-- Resolves item data, caches set bonuses, injects Pawn lines, and records PawnData.
-- Called from Set* hooks (runs BEFORE the game calls Show), so lines are committed
-- by the game's own Show() without us ever needing to call Show() ourselves.
function PawnUpdateTooltip(Tooltip, MethodName, Param1, Param2, Param3, Param4)
	if not PawnOptions or not PawnOptions.Scales then return end
	local TooltipName
	if type(Tooltip) == "string" then
		TooltipName = Tooltip
		Tooltip = getglobal(TooltipName)
	elseif type(Tooltip) == "table" then
		TooltipName = Tooltip:GetName()
	end

	local Item = PawnGetItemDataFromTooltip(TooltipName, MethodName, Param1, Param2, Param3, Param4)
	if not Item then return end

	if not Tooltip then return end
	if not Tooltip.PawnData then Tooltip.PawnData = {} end
	Tooltip.PawnData.LastItemLink = Item.Link
	Tooltip.PawnData.LastMethod = MethodName
	Tooltip.PawnData.LastP1 = Param1
	Tooltip.PawnData.LastP2 = Param2
	Tooltip.PawnData.LastP3 = Param3
	Tooltip.PawnData.LastP4 = Param4
	if MethodName == "SetQuestItem" or MethodName == "SetQuestLogItem" then
		Tooltip.PawnData.IsQuestTooltip = true
	elseif Tooltip == GameTooltip then
		if Tooltip.GetOwner and Tooltip:GetOwner() and Tooltip:GetOwner().GetName then
			local OwnerName = Tooltip:GetOwner():GetName()
			if not OwnerName or not string.find(OwnerName, "Quest") then
				Tooltip.PawnData.IsQuestTooltip = nil
			end
		else
			Tooltip.PawnData.IsQuestTooltip = nil
		end
	end

	if TooltipName == "GameTooltip" or Tooltip == GameTooltip then
		PawnLastHoveredItem = Item.Link
	end

	-- All tooltip sources use one idempotent finalization path. If another hook already
	-- added base values, this adds only missing set values; otherwise it adds everything.
	PawnFinalizeItemTooltip(Tooltip, Item.Link)

	-- DO NOT call Show() here. The game calls Show() naturally after Set* methods.
	-- Our hooksecurefunc runs between Set* and Show, so lines are already in the buffer
	-- when the game's Show() fires and commits them.

	-- Install OnUpdate repair hook if not already present.
	if Tooltip ~= GameTooltip and not Tooltip.PawnHooked and TooltipName ~= "ComparisonTooltip1" and TooltipName ~= "ComparisonTooltip2" then
		local OriginalOnUpdate = Tooltip:GetScript("OnUpdate")
		Tooltip:SetScript("OnUpdate", function()
			if OriginalOnUpdate then OriginalOnUpdate() end
			PawnPatchTooltip(this)
		end)
		Tooltip.PawnHooked = true
	end
end

-- Repair path. Called from the Show hook and OnUpdate.
-- If Pawn lines are already present, returns immediately (fast path).
-- If lines are missing (e.g. another addon cleared the tooltip after PawnUpdateTooltip ran),
-- resolves the item and appends lines non-destructively, then calls Show() to commit.
-- Never calls SetHyperlink — no full tooltip rebuild.
function PawnPatchTooltip(Tooltip)
	if not Tooltip or Tooltip.UpdatingPawn then return end
	if not PawnOptions or not PawnOptions.Scales then return end

	-- Resolve the item link from the live tooltip state. Never fall back to a stale
	-- PawnData.LastItemLink when GetItem() is available — that causes spurious Pawn
	-- lines on non-item tooltips (e.g. UI buttons) that happen to share GameTooltip.
	local ItemLink = nil
	if Tooltip.GetItem then
		-- Require that PawnUpdateTooltip previously ran for this tooltip (LastItemLink is set).
		-- If LastItemLink is nil the tooltip was hidden since the last item hover, meaning
		-- GetItem() may return a stale link (pfUI reuses GameTooltip for menus without Hide()).
		if not Tooltip.PawnData or not Tooltip.PawnData.LastItemLink then return end
		local LiveName, LiveLink = Tooltip:GetItem()
		if LiveLink and PawnGetHyperlinkType(LiveLink) == "item" then
			-- GetItem() can retain the previous item when shared GameTooltip content is
			-- replaced with a menu tooltip. Verify that the visible title is still the item.
			local VisibleName = Tooltip:GetName() and PawnGetItemNameFromTooltip(Tooltip:GetName())
			local ExpectedName = LiveName
			if not ExpectedName and GetItemInfo then ExpectedName = GetItemInfo(LiveLink) end
			if not ExpectedName or not VisibleName or ExpectedName ~= VisibleName then
				Tooltip.PawnData.LastItemLink = nil
				Tooltip.PawnData.PawnLinesAdded = nil
			else
				ItemLink = LiveLink
				if LiveLink ~= Tooltip.PawnData.LastItemLink then
					Tooltip.PawnData.LastItemLink = LiveLink
					Tooltip.PawnData.PawnLinesAdded = nil
				end
			end
		end

		-- Turtle WoW's character-sheet GameTooltip can return no item from GetItem()
		-- even though SetInventoryItem populated it correctly. Resolve only from an
		-- actual Character*Slot owner; this remains safe for shared menu tooltips.
		if not ItemLink and Tooltip == GameTooltip and Tooltip.GetOwner then
			local Owner = Tooltip:GetOwner()
			local OwnerName = Owner and Owner.GetName and Owner:GetName()
			if OwnerName and string.find(OwnerName, "^Character.*Slot$") and Owner.GetID then
				local SlotID = Owner:GetID()
				local InventoryLink = SlotID and GetInventoryItemLink("player", SlotID)
				if InventoryLink and PawnGetHyperlinkType(InventoryLink) == "item" then
					local ExpectedName = nil
					if GetItemInfo then ExpectedName = GetItemInfo(InventoryLink) end
					if not ExpectedName then
						local _, _, LinkName = string.find(InventoryLink, "%[(.-)%]")
						ExpectedName = LinkName
					end
					local VisibleName = PawnGetItemNameFromTooltip("GameTooltip")
					if ExpectedName and VisibleName and ExpectedName == VisibleName then
						ItemLink = InventoryLink
						Tooltip.PawnData.LastItemLink = InventoryLink
					end
				end
			end
		end
		if not ItemLink then return end
	end

	-- For frames without GetItem() (e.g. AtlasLootTooltip), fall back to PawnData.
	if not ItemLink and not Tooltip.GetItem then
		ItemLink = Tooltip.PawnData and Tooltip.PawnData.LastItemLink
	end

	if not ItemLink or PawnGetHyperlinkType(ItemLink) ~= "item" then return end

	-- Existing Pawn lines belong to the verified live item. Set bonuses can render a
	-- frame later than the Set* hook, so rescan and append only missing set scale lines.
	if PawnTooltipHasPawnScaleLine(Tooltip) then
		local OldNumLines = Tooltip:NumLines()
		PawnFinalizeItemTooltip(Tooltip, ItemLink)
		if Tooltip:NumLines() ~= OldNumLines then Tooltip:Show() end
		return
	end

	if PawnFinalizeItemTooltip(Tooltip, ItemLink) then Tooltip:Show() end
end

-- DEAD CODE TOMBSTONE: IsQuestOwnedTooltip, RepatchTooltip, ResolvePatchLink, and the
-- line-delta patrol loop were removed in the architectural redesign. PawnPatchTooltip is
-- now the single injection point and no longer calls PawnUpdateTooltip internally.
-- The old quest repair path and name-repair path are consolidated above.

-- Expose tooltip pipeline through class-style namespace while retaining global API compatibility.
PawnTooltipBuilder.UpdateTooltip = PawnUpdateTooltip
PawnTooltipBuilder.PatchTooltip = PawnPatchTooltip
PawnTooltipBuilder.HasPawnScaleLine = PawnTooltipHasPawnScaleLine
PawnTooltipBuilder.FinalizeItemTooltip = PawnFinalizeItemTooltip
PawnTooltipBuilder.FinalizeVisibleItemTooltip = PawnFinalizeVisibleItemTooltip
