-- Pawn bootstrap and hook helpers (extracted from Pawn.lua)

-- Hooks a private item tooltip at its completed Show lifecycle. Safe to call repeatedly.
-- This is for addon-owned frames only; shadowing GameTooltip.Show breaks some 1.12 clients.
function PawnHookVisibleItemTooltipShow(Tooltip)
	if not Tooltip or Tooltip.PawnVisibleShowHooked then return end
	local OriginalShow = Tooltip.Show
	Tooltip.Show = function(self)
		OriginalShow(self)
		if self.PawnVisibleShowUpdating then return end
		self.PawnVisibleShowUpdating = true
		local OldNumLines = self:NumLines()
		local Finalized = PawnFinalizeVisibleItemTooltip(self)
		if Finalized and self:NumLines() ~= OldNumLines then OriginalShow(self) end
		self.PawnVisibleShowUpdating = nil
	end
	Tooltip.PawnVisibleShowHooked = true
end

-- Hooks EquipCompare tooltips if available. Safe to call multiple times and after late loads.
function PawnHookEquipCompareTooltips()
	PawnHookVisibleItemTooltipShow(getglobal("ComparisonTooltip1"))
	PawnHookVisibleItemTooltipShow(getglobal("ComparisonTooltip2"))
end

-- Sets a keybinding to its default value if it's not already assigned to something else.  Returns true if anything was changed.
function PawnSetKeybindingIfAvailable(Key, Binding)
	local ExistingBinding = GetBindingAction(Key)
	if not ExistingBinding or ExistingBinding == "" then
		SetBinding(Key, Binding)
		return true
	else
		return false
	end
end

-- Returns an empty Pawn scale table.
function PawnGetEmptyScale()
	return { Values = {} }
end

-- Returns the default Pawn scale table.
function PawnGetDefaultScale()
	return 
	{
		["SmartGemSocketing"] = true,
		["Values"] =
		{
			["Strength"] = 1,
			["Agility"] = 1,
			["Stamina"] = 2/3,
			["Intellect"] = 1,
			["Spirit"] = 1,
			["Armor"] = 0.1,
			["Dps"] = 3.4,
			["ExpertiseRating"] = 0,
			["Hit"] = 1,
			["Crit"] = 1,
			["ArmorPenetration"] = 0,
			["SpellHit"] = 1,
			["SpellCrit"] = 1,
			["ResilienceRating"] = 0,
			["Haste"] = 0,
			["SpellHaste"] = 0,
			["Ap"] = 0.5,
			["FeralAp"] = 0.4,
			["Rap"] = 0.4,
			["Mp5"] = 2.5,
			["Hp5"] = 2.5,
			["Mana"] = 1/15,
			["Health"] = 1/15,
			["BlockValue"] = 0.65,
			["Block"] = 1,
			["Defense"] = 1,
			["Dodge"] = 1,
			["Parry"] = 1,
			["SpellPower"] = 6/7,
			["SpellDamage"] = 0.4,
			["Healing"] = 0.455,
			["SpellPenetration"] = 0.8,
			["FireSpellDamage"] = 0.7,
			["ShadowSpellDamage"] = 0.7,
			["NatureSpellDamage"] = 0.7,
			["ArcaneSpellDamage"] = 0.7,
			["FrostSpellDamage"] = 0.7,
			["HolySpellDamage"] = 0.7,
			["AllResist"] = 2.5,
			["FireResist"] = 1,
			["ShadowResist"] = 1,
			["NatureResist"] = 1,
			["ArcaneResist"] = 1,
			["FrostResist"] = 1,
			["RedSocket"] = 0,
			["YellowSocket"] = 0,
			["BlueSocket"] = 0,
			["MetaSocket"] = 0,
		},
	}
end

-- LinkWrangler compatibility
function PawnLinkWranglerOnTooltip(Tooltip, ItemLink)
	if not Tooltip then return end
	PawnUpdateTooltip(Tooltip:GetName(), "SetHyperlink", ItemLink)
	PawnAttachIconToTooltip(Tooltip, false, ItemLink)
end

-- Hooks known additional item tooltips discovered at runtime.
-- Do not scan every global containing "Tooltip": many UI addons use shared tooltip-like
-- frames for menus, and attaching Pawn's repair loop to those frames leaks stale item data.
function PawnTryHookAdditionalTooltips()
	-- Known late-created item tooltips are hooked explicitly by their Show lifecycle in
	-- PawnBootstrap_SetDefaultKeybindings. Broad runtime discovery caused menu pollution.
end

-- If debugging is enabled, show a message; otherwise, do nothing.
function PawnDebugMessage(Message)
	if PawnOptions.Debug then
		VgerCore.Message(Message)
	end
end

-- Processes a Pawn slash command.
function PawnCommand(Command)
	if Command == "" then
		PawnUIShow()
	elseif Command == PawnLocal.DebugOnCommand or Command == PawnLocal.CheckOnCommand then
		PawnOptions.Debug = true
		VgerCore.Message(PawnLocal.CheckOnMessage)
		PawnResetTooltips()
		if PawnUIFrame_DebugCheck then PawnUIFrame_DebugCheck:SetChecked(PawnOptions.Debug) end
	elseif Command == PawnLocal.DebugOffCommand or Command == PawnLocal.CheckOffCommand then
		PawnOptions.Debug = false
		VgerCore.Message(PawnLocal.CheckOffMessage)
		PawnResetTooltips()
		if PawnUIFrame_DebugCheck then PawnUIFrame_DebugCheck:SetChecked(PawnOptions.Debug) end
	else
		PawnUsage()
	end
end

-- Displays Pawn usage information.
function PawnUsage()
	VgerCore.Message(" ")
	VgerCore.MultilineMessage(PawnLocal.Usage)
	VgerCore.Message(" ")
end

-- Returns an empty item for use in the item cache.
function PawnGetEmptyCachedItem(NewItemLink, NewItemName)
	return { Name = NewItemName, UnknownLines = {}, Link = NewItemLink }
end

-- Searches the item cache for an item, and either returns the correct cached item, or nil.
function PawnGetCachedItem(ItemLink, ItemName, NumLines)
	local ItemCache = PawnInternal and PawnInternal.GetItemCache and PawnInternal.GetItemCache() or nil
	if (not ItemCache) or (table.getn(ItemCache) == 0) then return end
	if PawnOptions.Debug then return end

	for _, CachedItem in pairs(ItemCache) do
		if ItemLink and CachedItem.Link then
			if ItemLink == CachedItem.Link then return CachedItem end
		elseif ItemName and CachedItem.Name then
			if ItemName == CachedItem.Name then return CachedItem end
		end
	end
end

-- Once per new version of Pawn that adds keybindings, bind the new actions to default keys.
function PawnBootstrap_SetDefaultKeybindings()
	-- On some clients/UI packs, UPDATE_BINDINGS can fire before saved variables load.
	if not PawnOptions then return false end

	if PawnOptions.LastKeybindingsSet == nil  then PawnOptions.LastKeybindingsSet = 0 end
	local BindingSet = false

	-- Keybindings for opening the Pawn UI and setting comparison items.
	if PawnOptions.LastKeybindingsSet < 1 then
		BindingSet = PawnSetKeybindingIfAvailable(PAWN_TOGGLE_UI_DEFAULT_KEY, "PAWN_TOGGLE_UI") or BindingSet
		BindingSet = PawnSetKeybindingIfAvailable(PAWN_COMPARE_LEFT_DEFAULT_KEY, "PAWN_COMPARE_LEFT") or BindingSet
		BindingSet = PawnSetKeybindingIfAvailable(PAWN_COMPARE_RIGHT_DEFAULT_KEY, "PAWN_COMPARE_RIGHT") or BindingSet
	end

	-- If any keybindings were changed, save the user's bindings.
	if BindingSet and SaveBindings then
		if GetCurrentBindingSet then
			local Current = GetCurrentBindingSet()
			if Current == 1 or Current == 2 then
				SaveBindings(Current)
			end
		end
	end

	-- Record that we've set those keybindings, so we don't try to set them again in the future, even if
	-- the user clears them.
	PawnOptions.LastKeybindingsSet = 1

	-- Tooltip Tracking Mechanism:
	-- We hook the standard tooltips so that whenever they are shown/updated, they
	-- gain the Pawn "OnUpdate" watcher that ensures our lines stay at the bottom.
	local tooltipsToHook = {
		ShoppingTooltip1, ShoppingTooltip2
	}
	for _, tooltip in pairs(tooltipsToHook) do
		if tooltip and not tooltip.PawnHooked then
			local originalOnUpdate = tooltip:GetScript("OnUpdate")
			tooltip:SetScript("OnUpdate", function()
				if originalOnUpdate then originalOnUpdate() end
				PawnPatchTooltip(this)
			end)
			tooltip.PawnHooked = true
		end
	end
	PawnTryHookAdditionalTooltips()

	-- GameTooltip uses OnShow because shadowing its C Show method breaks some 1.12 clients.
	local function HookVisibleItemTooltipOnShow(Tooltip)
		if not Tooltip or not Tooltip.GetScript or not Tooltip.SetScript then return end
		if Tooltip:GetScript("OnShow") == Tooltip.PawnOnShowWrapper then return end
		local OriginalOnShow = Tooltip:GetScript("OnShow")
		local OnShowWrapper = function()
			if this.PawnOnShowUpdating then return end
			if OriginalOnShow then OriginalOnShow() end
			local OldNumLines = this:NumLines()
			this.PawnOnShowUpdating = true
			local Finalized = PawnFinalizeVisibleItemTooltip(this)
			if Finalized and this:NumLines() ~= OldNumLines then this:Show() end
			this.PawnOnShowUpdating = nil
		end
		Tooltip:SetScript("OnShow", OnShowWrapper)
		Tooltip.PawnOnShowWrapper = OnShowWrapper
	end
	HookVisibleItemTooltipOnShow(GameTooltip)

	-- Atlas and chat-link frames can remain visible while their contents change.
	PawnHookVisibleItemTooltipShow(getglobal("AtlasLootTooltip"))
	PawnHookVisibleItemTooltipShow(getglobal("AtlasLootTooltip2"))
	PawnHookVisibleItemTooltipShow(getglobal("AtlasCFMLootTooltip"))
	PawnHookVisibleItemTooltipShow(ItemRefTooltip)
	PawnHookVisibleItemTooltipShow(getglobal("ItemRefTooltip2"))
	PawnHookVisibleItemTooltipShow(getglobal("ItemRefTooltip3"))
	PawnHookVisibleItemTooltipShow(getglobal("ItemRefTooltip4"))
	PawnHookVisibleItemTooltipShow(getglobal("ItemRefTooltip5"))

	local StaticHooksInstalled = PawnInternal and PawnInternal.GetStaticTooltipHooksInstalled and PawnInternal.GetStaticTooltipHooksInstalled()
	if not StaticHooksInstalled then
		-- The item link tooltip
		hooksecurefunc(ItemRefTooltip, "SetHyperlink",
			function(ItemLink)
				PawnAttachIconToTooltip(ItemRefTooltip, false, ItemLink)
				if PawnGetHyperlinkType(ItemLink) ~= "item" then return end
				PawnUpdateTooltip(ItemRefTooltip, "SetHyperlink", ItemLink)
			end)
		local ItemRefOriginalOnEnter = ItemRefTooltip:GetScript("OnEnter")
		local ItemRefOriginalOnLeave = ItemRefTooltip:GetScript("OnLeave")
		local ItemRefOriginalOnMouseUp = ItemRefTooltip:GetScript("OnMouseUp")
		ItemRefTooltip:SetScript("OnEnter", function()
			if ItemRefOriginalOnEnter then ItemRefOriginalOnEnter() end
			PawnLastHoveredItem = nil
			if ItemRefTooltip.GetItem then _, PawnLastHoveredItem = ItemRefTooltip:GetItem() end
		end)
		ItemRefTooltip:SetScript("OnLeave", function()
			if ItemRefOriginalOnLeave then ItemRefOriginalOnLeave() end
			PawnLastHoveredItem = nil
		end)
		ItemRefTooltip:SetScript("OnMouseUp",
			function()
				if ItemRefOriginalOnMouseUp then ItemRefOriginalOnMouseUp() end
				if arg1 == "RightButton" then
					local ItemLink = nil
					if ItemRefTooltip.GetItem then _, ItemLink = ItemRefTooltip:GetItem() end
					PawnUI_SetCompareItemAndShow(2, ItemLink)
				end
			end)

		-- The loot roll window
		local LootRollClickHandler =
			function()
				if arg1 == "RightButton" then
					local ItemLink = GetLootRollItemLink(this:GetParent().rollID)
					PawnUI_SetCompareItemAndShow(2, ItemLink)
				end
			end
		local function HookLootRollMouseUp(Frame)
			if not Frame or Frame.PawnLootRollMouseUpHooked then return end
			local OriginalOnMouseUp = Frame:GetScript("OnMouseUp")
			Frame:SetScript("OnMouseUp", function()
				if OriginalOnMouseUp then OriginalOnMouseUp() end
				LootRollClickHandler()
			end)
			Frame.PawnLootRollMouseUpHooked = true
		end
		HookLootRollMouseUp(GroupLootFrame1IconFrame)
		HookLootRollMouseUp(GroupLootFrame2IconFrame)
		HookLootRollMouseUp(GroupLootFrame3IconFrame)
		HookLootRollMouseUp(GroupLootFrame4IconFrame)

		local function HookLootRollTooltipOnEnter(Frame)
			if not Frame or Frame.PawnLootRollOnEnterHooked then return end
			local OriginalOnEnter = Frame:GetScript("OnEnter")
			Frame:SetScript("OnEnter", function()
				if OriginalOnEnter then OriginalOnEnter() end
				if this and this:GetParent() and this:GetParent().rollID then
					PawnUpdateTooltip(GameTooltip, "SetLootRollItem", this:GetParent().rollID)
				end
			end)
			Frame.PawnLootRollOnEnterHooked = true
		end
		HookLootRollTooltipOnEnter(GroupLootFrame1IconFrame)
		HookLootRollTooltipOnEnter(GroupLootFrame2IconFrame)
		HookLootRollTooltipOnEnter(GroupLootFrame3IconFrame)
		HookLootRollTooltipOnEnter(GroupLootFrame4IconFrame)

		-- ShaguTweaks equip-compare support.
		-- ShaguTweaks calls SetInventoryItem → Show → AddHeader → Show on ShoppingTooltip1/2 every frame.
		-- OnUpdate ordering is unreliable, so instead we shadow the Show method in the Lua table.
		-- Lua calls like ShoppingTooltip1:Show() look up Show in the Lua table first, finding our wrapper.
		-- We inject Pawn lines synchronously inside the second Show() call (after AddHeader has run),
		-- detected by line 1 being gray (0.5,0.5,0.5 = "Currently Equipped" header color).
		local function PawnHookShaguTooltipShow(Tooltip)
			if not Tooltip or Tooltip.PawnShaguShowHooked then return end
			local tooltipName = Tooltip:GetName()

			-- Capture the C-level Show via metamethod before we shadow it in the Lua table.
			local cShow = Tooltip.Show

			Tooltip.Show = function(self)
				cShow(self)  -- call the real C Show first so the tooltip visually updates

				if Tooltip.PawnShaguUpdating then return end

				local line1 = getglobal(tooltipName .. "TextLeft1")
				if not line1 then return end
				local r, g, b = line1:GetTextColor()
				-- AddHeader sets line 1 to gray (0.5,0.5,0.5). Skip the pre-AddHeader Show call.
				if not r or r > 0.55 or g > 0.55 or b > 0.55 then return end

				local line2 = getglobal(tooltipName .. "TextLeft2")
				local itemName = line2 and line2:GetText()
				if not itemName or itemName == "" then return end

				-- Cache item link by name; rescan inventory only when the item changes.
				if itemName ~= Tooltip.PawnShaguLastName then
					Tooltip.PawnShaguLastName = itemName
					Tooltip.PawnShaguLastLink = nil
					for slotID = 1, 19 do
						local link = GetInventoryItemLink("player", slotID)
						if link then
							local _, _, name = string.find(link, "%[(.-)%]")
							if name == itemName then
								Tooltip.PawnShaguLastLink = link
								break
							end
						end
					end
				end

				local itemLink = Tooltip.PawnShaguLastLink
				if not itemLink then return end

				-- Finalize after Shagu has populated the complete comparison tooltip.
				Tooltip.PawnShaguUpdating = true
				PawnFinalizeItemTooltip(Tooltip, itemLink)
				-- Re-render so the backdrop resizes to include the Pawn lines we just added.
				-- Call cShow directly to avoid recursing through this Lua shadow.
				cShow(self)
				Tooltip.PawnShaguUpdating = nil
			end

			Tooltip.PawnShaguShowHooked = true
		end
		PawnHookShaguTooltipShow(ShoppingTooltip1)
		PawnHookShaguTooltipShow(ShoppingTooltip2)
	end

	PawnTryHookAdditionalTooltips()

	if MultiTips then
		if ItemRefTooltip2 and not ItemRefTooltip2.PawnHyperlinkHooked then VgerCore.HookInsecureFunction(ItemRefTooltip2, "SetHyperlink", function(self, ItemLink) PawnUpdateTooltip(ItemRefTooltip2, "SetHyperlink", ItemLink) PawnAttachIconToTooltip(ItemRefTooltip2, false, ItemLink) end) ItemRefTooltip2.PawnHyperlinkHooked = true end
		if ItemRefTooltip3 and not ItemRefTooltip3.PawnHyperlinkHooked then VgerCore.HookInsecureFunction(ItemRefTooltip3, "SetHyperlink", function(self, ItemLink) PawnUpdateTooltip(ItemRefTooltip3, "SetHyperlink", ItemLink) PawnAttachIconToTooltip(ItemRefTooltip3, false, ItemLink) end) ItemRefTooltip3.PawnHyperlinkHooked = true end
		if ItemRefTooltip4 and not ItemRefTooltip4.PawnHyperlinkHooked then VgerCore.HookInsecureFunction(ItemRefTooltip4, "SetHyperlink", function(self, ItemLink) PawnUpdateTooltip(ItemRefTooltip4, "SetHyperlink", ItemLink) PawnAttachIconToTooltip(ItemRefTooltip4, false, ItemLink) end) ItemRefTooltip4.PawnHyperlinkHooked = true end
		if ItemRefTooltip5 and not ItemRefTooltip5.PawnHyperlinkHooked then VgerCore.HookInsecureFunction(ItemRefTooltip5, "SetHyperlink", function(self, ItemLink) PawnUpdateTooltip(ItemRefTooltip5, "SetHyperlink", ItemLink) PawnAttachIconToTooltip(ItemRefTooltip5, false, ItemLink) end) ItemRefTooltip5.PawnHyperlinkHooked = true end
	end

	if PawnInternal and PawnInternal.SetStaticTooltipHooksInstalled then PawnInternal.SetStaticTooltipHooksInstalled(true) end
	PawnHookEquipCompareTooltips()
end
