-- Pawn tooltip builder pipeline (extracted from Pawn.lua)

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
		Item.Stats, Item.SocketBonusStats, Item.UnknownLines = PawnGetStatsFromTooltip(TooltipName, true)
		if PawnOptions.Debug then
			PawnDebugMessage(PawnLocal.FailedToGetItemLinkMessage)
			PawnDebugMessage("Method=" .. tostring(MethodName) .. ", p1=" .. tostring(Param1) .. ", p2=" .. tostring(Param2) .. ", p3=" .. tostring(Param3))
		end
		
		-- Cache this item so we don't have to re-parse next time.
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

-- Updates a specific tooltip.
function PawnUpdateTooltip(Tooltip, MethodName, Param1, Param2, Param3, Param4)
	if not PawnOptions.Scales then return end
	local TooltipName
	if type(Tooltip) == "string" then
		TooltipName = Tooltip
		Tooltip = getglobal(TooltipName)
	elseif type(Tooltip) == "table" then
		TooltipName = Tooltip:GetName()
	end

	-- Get information for the item in this tooltip.
	local Item = PawnGetItemDataFromTooltip(TooltipName, MethodName, Param1, Param2, Param3, Param4)
	if not Item then return end
	
	-- If this is a detached or special tooltip (like AtlasLoot), we need to handle potential overwrites.
	-- We record the last item displayed in this specific tooltip to detect if it was changed or cleared.
	if Tooltip then
		if not Tooltip.PawnData then Tooltip.PawnData = {} end
		Tooltip.PawnData.LastItemLink = Item.Link
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
	end

	-- If this is the main GameTooltip, remember the item that was hovered over.
	if TooltipName == "GameTooltip" or (Tooltip == GameTooltip) then
		PawnLastHoveredItem = Item.Link
	end
	
	-- Now, just update the tooltip with the item data we got from the previous call.
	if not Tooltip then
		VgerCore.Fail("Where'd the tooltip go?  I seem to have misplaced it.")
		return
	end
	
	-- FIX: Some tooltips (like AtlasLoot) don't update properly if they've already been shown.
	-- We force a refresh if the tooltip is empty or has been modified.
	
	-- Special check for AtlasLoot/Atlas-TW:
	-- If it's the known catalog tooltip, we need to ensure the frame stays big enough.
	if (Tooltip == AtlasLootTooltip) then
		-- In Vanilla 1.12, AtlasLoot tends to finish its work after SetHyperlink.
		-- We add a check for re-entry to avoid infinite loops when we re-run PawnUpdateTooltip from OnUpdate.
		if Tooltip.UpdatingPawn then return end
		Tooltip.UpdatingPawn = true
		Tooltip:Show()
		Tooltip.UpdatingPawn = nil
	elseif (Tooltip == GameTooltip) then
		-- Ensure GameTooltip is actually showing the changes.
		-- In some cases, the layout doesn't recalculate properly when adding lines via OnUpdate.
		Tooltip:Show()
	end
	
	-- If necessary, add a blank line to the tooltip.
	local AddSpace = PawnOptions.ShowSpace
	
	-- AtlasLoot / Catalog Check:
	-- If we've already added Pawn lines to this tooltip for this exact item, don't do it again.
	if Tooltip.PawnData and Tooltip.PawnData.LastItemLink == Item.Link and Tooltip.PawnData.PawnLinesAdded then
		if not PawnTooltipHasPawnScaleLine(Tooltip) then
			Tooltip.PawnData.PawnLinesAdded = nil
		end

		-- EquipCompare tooltips are frequently redrawn/reused for the same item link.
		-- If we keep this flag set, Pawn can stop injecting values after the first pass.
		if TooltipName == "ComparisonTooltip1" or TooltipName == "ComparisonTooltip2" then
			Tooltip.PawnData.PawnLinesAdded = nil
		else
		-- Clear and re-inject ONLY if the tooltip was actually cleared by another addon
		-- but for some reason NumLines matches. Otherwise, skip.
			if Tooltip.PawnData.PawnLinesAdded then return end
		end
	end

	-- Add the scale values to the tooltip.
	if AddSpace and table.getn(Item.Values) > 0 then Tooltip:AddLine(" ") AddSpace = false end
	if PawnAddValuesToTooltip then
		PawnAddValuesToTooltip(Tooltip, Item.Values)
	end
	
	-- Record that we've added lines
	if Tooltip.PawnData then 
		Tooltip.PawnData.PawnLinesAdded = true 
		Tooltip.PawnData.LastMethod = MethodName
		Tooltip.PawnData.LastP1 = Param1
		Tooltip.PawnData.LastP2 = Param2
		Tooltip.PawnData.LastP3 = Param3
		Tooltip.PawnData.LastP4 = Param4
	end

	-- Record we've added these lines so we don't duplicate on next Patch check.
	if Tooltip and Tooltip.PawnData then
		Tooltip.PawnData.LastNumLines = Tooltip:NumLines()
	end

	-- If there were unrecognized values, annotate those lines.
	local Annotated = false
	if Item.UnknownLines then
		if (PawnOptions.ShowAsterisks == PawnShowAsterisksAlways) or ((PawnOptions.ShowAsterisks == PawnShowAsterisksNonzero or PawnOptions.ShowAsterisks == PawnShowAsterisksNonzeroNoText) and (table.getn(Item.Values) > 0)) then
			Annotated = PawnAnnotateTooltipLines(TooltipName, Item.UnknownLines)
		end
	end
	-- If we annotated the tooltip for unvalued stats, display a message.
	if (Annotated and PawnOptions.ShowAsterisks ~= PawnShowAsterisksNonzeroNoText) then
		Tooltip:AddLine(PawnLocal.AsteriskTooltipLine, VgerCore.Color.BlueR, VgerCore.Color.BlueG, VgerCore.Color.BlueB)
	end

	-- Add the item ID to the tooltip if known.
	if PawnOptions.ShowItemID and Item.Link then
		-- Only show ID if AtlasLoot ID isn't already there (to avoid duplicates)
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
	-- Add the item level to the tooltip, but don't show it for items level 1 or lower.
	if PawnOptions.ShowItemLevel and Item.Level and (Item.Level > 1) then
		if PawnOptions.AlignNumbersRight then
			Tooltip:AddDoubleLine(PawnLocal.ItemLevelTooltipLine,  Item.Level, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB)
		else
			Tooltip:AddLine(PawnLocal.ItemLevelTooltipLine .. ":  " .. Item.Level, VgerCore.Color.OrangeR, VgerCore.Color.OrangeG, VgerCore.Color.OrangeB)
		end
	end
	
	-- Record the number of lines currently in the tooltip to detect later modifications.
	if Tooltip then
		if not Tooltip.PawnData then Tooltip.PawnData = {} end
		Tooltip.PawnData.LastItemLink = Item.Link
		Tooltip.PawnData.LastMethod = MethodName
		Tooltip.PawnData.LastP1 = Param1
		Tooltip.PawnData.LastP2 = Param2
		Tooltip.PawnData.LastP3 = Param3
		Tooltip.PawnData.LastP4 = Param4
		if MethodName == "SetQuestItem" or MethodName == "SetQuestLogItem" then
			Tooltip.PawnData.LastQuestRepairLines = nil
			Tooltip.PawnData.LastQuestRepairLink = nil
		end
		-- Ensure numlines is updated AFTER all additions
		Tooltip:Show() 
		Tooltip.PawnData.LastNumLines = Tooltip:NumLines()
		
		-- If this tooltip doesn't have our update hook yet, add it.
		-- ComparisonTooltip1/2 are managed by EquipCompare and can flicker if repeatedly patched on OnUpdate.
		if not Tooltip.PawnHooked and TooltipName ~= "ComparisonTooltip1" and TooltipName ~= "ComparisonTooltip2" then
			local OriginalOnUpdate = Tooltip:GetScript("OnUpdate")
			Tooltip:SetScript("OnUpdate", function()
				if OriginalOnUpdate then OriginalOnUpdate() end
				PawnPatchTooltip(this)
			end)
			Tooltip.PawnHooked = true
		end
	end

end

-- Refresh logic for tooltips that might be modified after they are shown.
-- This ensures Pawn scales stay at the bottom regardless of which addon modifies the tooltip.
function PawnPatchTooltip(Tooltip)
	if not Tooltip or Tooltip.UpdatingPawn then return end

	local function IsQuestOwnedTooltip(TargetTooltip)
		if not TargetTooltip or not TargetTooltip.GetOwner then return false end
		if TargetTooltip == GameTooltip then
			return PawnIsQuestLikeGameTooltip(TargetTooltip)
		end
		local Owner = TargetTooltip:GetOwner()
		if not Owner or not Owner.GetName then return false end
		local OwnerName = Owner:GetName()
		return OwnerName and string.find(OwnerName, "Quest") ~= nil
	end

	local function RepatchTooltip(TargetTooltip, PreferredLink)
		if not TargetTooltip then return end

		local LastMethod = TargetTooltip.PawnData and TargetTooltip.PawnData.LastMethod
		if LastMethod == "SetQuestItem" or LastMethod == "SetQuestLogItem" then
			local P1 = TargetTooltip.PawnData and TargetTooltip.PawnData.LastP1
			local P2 = TargetTooltip.PawnData and TargetTooltip.PawnData.LastP2
			local P3 = TargetTooltip.PawnData and TargetTooltip.PawnData.LastP3
			local P4 = TargetTooltip.PawnData and TargetTooltip.PawnData.LastP4
			if P1 and P2 then
				PawnUpdateTooltip(TargetTooltip, LastMethod, P1, P2, P3, P4)
				return
			end
		end

		-- For quest-owned tooltips, avoid hyperlink fallback because it can replace
		-- quest-specific tooltip output in Atlas-TW/UIPack flows.
		if IsQuestOwnedTooltip(TargetTooltip) then return end

		if PreferredLink and PawnGetHyperlinkType(PreferredLink) == "item" then
			PawnUpdateTooltip(TargetTooltip, "SetHyperlink", PreferredLink)
			return
		end

		local LastItemLink = TargetTooltip.PawnData and TargetTooltip.PawnData.LastItemLink
		if LastItemLink and PawnGetHyperlinkType(LastItemLink) == "item" then
			PawnUpdateTooltip(TargetTooltip, "SetHyperlink", LastItemLink)
		end
	end

	local function AppendPawnValuesSafely(TargetTooltip, Item)
		if not TargetTooltip or not Item or not Item.Values then return false end
		local AddSpace = PawnOptions.ShowSpace
		if AddSpace and table.getn(Item.Values) > 0 then TargetTooltip:AddLine(" ") end

		local OriginalAlign = PawnOptions.AlignNumbersRight
		if TargetTooltip == GameTooltip then PawnOptions.AlignNumbersRight = true end
		PawnAddValuesToTooltip(TargetTooltip, Item.Values)
		PawnOptions.AlignNumbersRight = OriginalAlign

		if TargetTooltip.Show then TargetTooltip:Show() end
		return true
	end

	-- Universal non-destructive repair for GameTooltip:
	-- if Pawn lines are missing but we can resolve the visible item, append lines directly.
	-- This avoids SetHyperlink/quest-method redraw conflicts with Atlas-TW.
	if Tooltip == GameTooltip and not PawnTooltipHasPawnScaleLine(Tooltip) then
		if not Tooltip.PawnData then Tooltip.PawnData = {} end
		local CurrentLines = Tooltip:NumLines()
		local RepairLink, ItemName = PawnResolveGameTooltipItemLinkByName()
		if ItemName then
			local RepairKey = RepairLink or ("name:" .. ItemName)
			if not (Tooltip.PawnData.LastNameRepairLines == CurrentLines and Tooltip.PawnData.LastNameRepairLink == RepairKey) then
				local Item = nil
				if RepairLink then
					Item = PawnGetItemData(RepairLink)
				end

				if (not Item) or (not Item.Values) then
					Item = PawnGetCachedItem(nil, ItemName)
					if not Item then
						Item = PawnGetEmptyCachedItem(nil, ItemName)
					end
					if not Item.Values then
						PawnFixStupidTooltipFormatting("GameTooltip")
						Item.Stats, Item.SocketBonusStats, Item.UnknownLines = PawnGetStatsFromTooltip("GameTooltip", false)
						PawnRecalculateItemValuesIfNecessary(Item)
						PawnCacheItem(Item)
					end
				end

				if Item and Item.Values then
					Tooltip.UpdatingPawn = true
					Tooltip.PawnData.LastNameRepairLines = CurrentLines
					Tooltip.PawnData.LastNameRepairLink = RepairKey
					Tooltip.PawnData.PawnLinesAdded = nil
					AppendPawnValuesSafely(Tooltip, Item)
					Tooltip.PawnData.LastItemLink = Item.Link or RepairLink or Tooltip.PawnData.LastItemLink
					Tooltip.PawnData.PawnLinesAdded = true
					Tooltip.PawnData.LastNumLines = Tooltip:NumLines()
					Tooltip.UpdatingPawn = nil
					return
				end
			end
		end
	end

	-- Quest-owned tooltips are fragile under Atlas-TW redraws; keep them on a dedicated
	-- non-destructive repair path and avoid generic hyperlink/line-delta logic below.
	if IsQuestOwnedTooltip(Tooltip) then
		if not Tooltip.PawnData then return end

		if PawnTooltipHasPawnScaleLine(Tooltip) then
			Tooltip.PawnData.PawnLinesAdded = true
			Tooltip.PawnData.LastNumLines = Tooltip:NumLines()
			return
		end

		local CurrentLines = Tooltip:NumLines()
		local CurrentLink = Tooltip.PawnData.LastItemLink
		if Tooltip.PawnData.LastQuestRepairLines == CurrentLines and Tooltip.PawnData.LastQuestRepairLink == CurrentLink then
			return
		end

		local QuestLink = CurrentLink
		if (not QuestLink) or PawnGetHyperlinkType(QuestLink) ~= "item" then
			QuestLink = PawnResolveGameTooltipItemLinkByName()
		end

		if not QuestLink or PawnGetHyperlinkType(QuestLink) ~= "item" then return end
		local Item = PawnGetItemData(QuestLink)
		if not Item or not Item.Values then return end

		Tooltip.UpdatingPawn = true
		Tooltip.PawnData.LastQuestRepairLines = CurrentLines
		Tooltip.PawnData.LastQuestRepairLink = QuestLink
		Tooltip.PawnData.PawnLinesAdded = nil
		AppendPawnValuesSafely(Tooltip, Item)

		Tooltip.PawnData.LastItemLink = Item.Link or QuestLink
		Tooltip.PawnData.PawnLinesAdded = true
		Tooltip.PawnData.LastNumLines = Tooltip:NumLines()
		Tooltip.UpdatingPawn = nil
		return
	end

	local function ResolvePatchLink(TargetTooltip)
		if not TargetTooltip then return nil, nil end
		local LiveLink = nil
		if TargetTooltip.GetItem then
			_, LiveLink = TargetTooltip:GetItem()
		end
		if LiveLink and PawnGetHyperlinkType(LiveLink) == "item" then
			return LiveLink, "tooltip:GetItem"
		end

		if TargetTooltip == GameTooltip then
			local NameLink = PawnResolveGameTooltipItemLinkByName()
			if NameLink and PawnGetHyperlinkType(NameLink) == "item" then
				return NameLink, "name-fallback"
			end
		end

		return nil, nil
	end

	-- Self-heal: some tooltip flows reach here without PawnData/LastItemLink initialized.
	-- Prime from the live tooltip link so Pawn can inject instead of returning early forever.
	if (not Tooltip.PawnData) or (not Tooltip.PawnData.LastItemLink) then
		local LiveLink = ResolvePatchLink(Tooltip)
		if LiveLink and PawnGetHyperlinkType(LiveLink) == "item" then
			Tooltip.UpdatingPawn = true
			if not Tooltip.PawnData then Tooltip.PawnData = {} end
			Tooltip.PawnData.LastItemLink = LiveLink
			Tooltip.PawnData.PawnLinesAdded = nil
			RepatchTooltip(Tooltip, LiveLink)
			Tooltip.UpdatingPawn = nil
		end
	end

	if not Tooltip.PawnData or not Tooltip.PawnData.LastItemLink then return end

	local function TooltipHasPawnScaleLine(TargetTooltip)
		if not TargetTooltip or not TargetTooltip.GetName then return false end
		local TooltipName = TargetTooltip:GetName()
		if not TooltipName or not PawnOptions or not PawnOptions.Scales then return false end
		if not TargetTooltip.NumLines then return false end

		for i = 2, TargetTooltip:NumLines() do
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

	-- Universal fallback: if GameTooltip has a live item link but Pawn lines are not confirmed
	-- for that exact link, force a one-shot hyperlink update.
	if Tooltip == GameTooltip and not IsQuestOwnedTooltip(Tooltip) then
		local LiveLink = ResolvePatchLink(Tooltip)
		if LiveLink and PawnGetHyperlinkType(LiveLink) == "item" then
			local NeedsRefresh = false
			if not Tooltip.PawnData then
				NeedsRefresh = true
			elseif Tooltip.PawnData.LastItemLink ~= LiveLink then
				NeedsRefresh = true
			elseif not Tooltip.PawnData.PawnLinesAdded then
				NeedsRefresh = true
			elseif not TooltipHasPawnScaleLine(Tooltip) then
				NeedsRefresh = true
			end
			if NeedsRefresh then
				Tooltip.UpdatingPawn = true
				if not Tooltip.PawnData then Tooltip.PawnData = {} end
				Tooltip.PawnData.LastItemLink = LiveLink
				Tooltip.PawnData.PawnLinesAdded = nil
				RepatchTooltip(Tooltip, LiveLink)
				Tooltip.UpdatingPawn = nil
			end
		end
	end
	
	-- AtlasLoot and some others set NumLines to 0 or 1 while rebuilding.
	-- If that happens, we should reset our tracking rather than re-patching immediately.
	local currentLines = Tooltip:NumLines()
	
	-- If the number of lines has changed since we last updated it, a modification occurred.
	if currentLines ~= Tooltip.PawnData.LastNumLines then
		-- Only re-patch if the link still matches (sanity check)
		local _, link
		if Tooltip.GetItem then _, link = Tooltip:GetItem() end
		
		-- Some quest/UI-pack tooltips can temporarily report no link while still showing
		-- the same item. In that case, keep current item state and just sync line count.
		if not link then
			Tooltip.PawnData.LastNumLines = currentLines
			return
		end
		
		-- If it's a new item or tooltip was cleared, just update the count and stop.
		if link ~= Tooltip.PawnData.LastItemLink then
			Tooltip.PawnData.LastItemLink = link
			Tooltip.PawnData.LastNumLines = currentLines
			Tooltip.PawnData.PawnLinesAdded = nil
			return
		end

		-- If the tooltip is temporarily empty (rebuilding), don't patch yet.
		if currentLines <= 1 then
			Tooltip.PawnData.LastNumLines = currentLines
			Tooltip.PawnData.PawnLinesAdded = nil
			return
		end

		-- If lines were ADDED (currentLines > LastNumLines), re-inject.
		-- If lines were REMOVED but the item is the same, AtlasLoot probably just
		-- finished a partial draw. We should only re-inject if we are missing.
		if currentLines > Tooltip.PawnData.LastNumLines then
			-- If Pawn lines are already present, another addon simply appended content.
			-- Sync counters only; re-injecting here causes duplicate Pawn blocks.
			if TooltipHasPawnScaleLine(Tooltip) then
				Tooltip.PawnData.LastNumLines = currentLines
				Tooltip.PawnData.PawnLinesAdded = true
			else
				Tooltip.UpdatingPawn = true
				-- Reset duplication flag so UpdateTooltip can run once more.
				Tooltip.PawnData.PawnLinesAdded = nil
				RepatchTooltip(Tooltip)
				Tooltip.UpdatingPawn = nil
			end
		else
			-- Just sync the count if it somehow went down without an item change.
			Tooltip.PawnData.LastNumLines = currentLines
		end
	end
end

-- Expose tooltip pipeline through class-style namespace while retaining global API compatibility.
PawnTooltipBuilder.UpdateTooltip = PawnUpdateTooltip
PawnTooltipBuilder.PatchTooltip = PawnPatchTooltip
PawnTooltipBuilder.HasPawnScaleLine = PawnTooltipHasPawnScaleLine
