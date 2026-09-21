--------------------------------------------------------------------------
-- Pawn <-> wowsims-turtle bridge: in-game half.
--
-- Exports the current character (equipped items, enchants, talents) as a
-- compact JSON string into the PawnSimDump saved variable, and applies
-- simulated stat weights (written by sim.ps1 into sim\SimResults.lua) back
-- into a Pawn scale.
--
-- Workflow:
--   1. Pawn window -> Sim tab -> "1. Export character" (or /psim dump)
--   2. /reload  (flushes the saved variable to disk)
--   3. Run sim.ps1 from the Pawn folder on your PC
--   4. /reload, then Sim tab -> "2. Apply sim results" (or /psim apply)
--------------------------------------------------------------------------

PawnSimExportVersion = 1

-- Equipped slots in the order wowsims expects in player.equipment.items.
PawnSimExportSlotOrder = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

PawnSimExportRaceTokens = {
	["Human"] = "RaceHuman",
	["Dwarf"] = "RaceDwarf",
	["Night Elf"] = "RaceNightElf",
	["Gnome"] = "RaceGnome",
	["Orc"] = "RaceOrc",
	["Undead"] = "RaceUndead",
	["Scourge"] = "RaceUndead",
	["Tauren"] = "RaceTauren",
	["Troll"] = "RaceTroll",
	["Goblin"] = "RaceGoblin",
	["High Elf"] = "RaceHighElf",
}

PawnSimExportClassTokens = {
	["Warrior"] = "ClassWarrior",
	["Paladin"] = "ClassPaladin",
	["Hunter"] = "ClassHunter",
	["Rogue"] = "ClassRogue",
	["Priest"] = "ClassPriest",
	["Shaman"] = "ClassShaman",
	["Mage"] = "ClassMage",
	["Warlock"] = "ClassWarlock",
	["Druid"] = "ClassDruid",
}

-- Prints a prefixed message to the chat frame.
function PawnSimExportPrint(Message)
	DEFAULT_CHAT_FRAME:AddMessage(tostring(PawnSimExportChatPrefix) .. tostring(Message))
end

-- Escapes a string so that it can be embedded in the JSON blob.
function PawnSimExportEscape(Value)
	if Value == nil then return "" end
	local Result = tostring(Value)
	Result = string.gsub(Result, "\\", "\\\\")
	Result = string.gsub(Result, "\"", "\\\"")
	Result = string.gsub(Result, "\r", "")
	Result = string.gsub(Result, "\n", "\\n")
	return Result
end

-- Returns the equipped items as a JSON array in wowsims slot order:
-- [slot, itemID, enchantID, "name", ...]. Empty slots have itemID 0.
function PawnSimExportCollectItems()
	local Items = {}
	for i = 1, table.getn(PawnSimExportSlotOrder) do
		local Slot = PawnSimExportSlotOrder[i]
		local ItemID, EnchantID, ItemName = 0, 0, ""
		local Link = GetInventoryItemLink("player", Slot)
		if Link then
			local _, _, ID, Enchant = string.find(Link, "item:(%d+):(%d*)")
			ItemID = tonumber(ID) or 0
			EnchantID = tonumber(Enchant) or 0
			local _, _, Name = string.find(Link, "%[(.-)%]")
			ItemName = Name or ""
		end
		table.insert(Items, string.format("[%d,%d,%d,\"%s\"]", Slot, ItemID, EnchantID, PawnSimExportEscape(ItemName)))
	end
	return "[" .. table.concat(Items, ",") .. "]"
end

-- Returns two JSON arrays: talent ranks per tab, and max ranks per tab.
function PawnSimExportCollectTalents()
	local Ranks, Maxes = {}, {}
	for Tab = 1, GetNumTalentTabs() do
		local TabRanks, TabMax = {}, {}
		for Index = 1, GetNumTalents(Tab) do
			local Name, Icon, Tier, Column, Rank, MaxRank = GetTalentInfo(Tab, Index)
			table.insert(TabRanks, Rank or 0)
			table.insert(TabMax, MaxRank or 0)
		end
		table.insert(Ranks, "[" .. table.concat(TabRanks, ",") .. "]")
		table.insert(Maxes, "[" .. table.concat(TabMax, ",") .. "]")
	end
	return table.concat(Ranks, ","), table.concat(Maxes, ",")
end

-- Builds the JSON blob for the current character.
function PawnSimExportBuildJson(ScaleName)
	local Race = UnitRace("player") or ""
	local Class = UnitClass("player") or ""
	local CharacterName = UnitName("player") or "Player"
	local Level = UnitLevel("player") or 60
	local TalentGroup = 1
	if GetActiveTalentGroup then TalentGroup = GetActiveTalentGroup() or 1 end

	local TalentsJson, TalentMaxJson = PawnSimExportCollectTalents()

	local Parts = {}
	table.insert(Parts, string.format('{"version":%d', PawnSimExportVersion))
	table.insert(Parts, string.format(',"time":%d', time()))
	table.insert(Parts, string.format(',"scale":"%s"', PawnSimExportEscape(ScaleName or "")))
	table.insert(Parts, string.format(',"char":{"name":"%s","race":"%s","raceToken":"%s","class":"%s","classToken":"%s","level":%d,"talentGroup":%d}',
		PawnSimExportEscape(CharacterName),
		PawnSimExportEscape(Race), PawnSimExportEscape(PawnSimExportRaceTokens[Race] or ""),
		PawnSimExportEscape(Class), PawnSimExportEscape(PawnSimExportClassTokens[Class] or ""),
		Level, TalentGroup))
	table.insert(Parts, ',"items":' .. PawnSimExportCollectItems())
	table.insert(Parts, ',"talents":[' .. TalentsJson .. ']')
	table.insert(Parts, ',"talentMax":[' .. TalentMaxJson .. ']}')
	return table.concat(Parts)
end

-- Exports the character into the PawnSimDump saved variable.
function PawnSimDumpCharacter(ScaleName)
	if (not ScaleName) or ScaleName == "" then ScaleName = PawnDefaultScaleName end
	if (not ScaleName) or ScaleName == "" then
		PawnSimExportPrint(PawnSimExportNoScaleMessage)
		return
	end

	-- pcall so a hidden error shows up in chat instead of silently doing nothing.
	local Ok, Result = pcall(PawnSimExportBuildJson, ScaleName)
	if not Ok then
		PawnSimExportPrint("Export FAILED: " .. tostring(Result))
		return
	end

	PawnSimDump = Result
	PawnSimDumpTime = time()

	PawnSimExportPrint(string.format("%s (scale: %s, %d bytes)", PawnSimExportDumpedMessage, ScaleName, string.len(PawnSimDump or "")))
end

-- Applies the generated sim results (sim\SimResults.lua) to a scale.
function PawnSimApplyResults(ScaleName)
	if (not ScaleName) or ScaleName == "" then ScaleName = PawnDefaultScaleName end
	if (not ScaleName) or ScaleName == "" then
		PawnSimExportPrint(PawnSimExportNoScaleMessage)
		return
	end
	if (not PawnSimResults) or (not PawnSimResults.stats) then
		PawnSimExportPrint(PawnSimExportNoResultsMessage)
		return
	end

	PawnSimExportPrint(string.format(PawnSimExportResultsStampMessage,
		tostring(PawnSimResults.generatedAt), tostring(PawnSimResults.source)))

	local Applied, Zeroed = 0, 0
	for Stat, Value in pairs(PawnSimResults.stats) do
		if type(Value) == "number" then
			PawnSetStatValue(ScaleName, Stat, Value)
			if Value == 0 then
				Zeroed = Zeroed + 1
			else
				Applied = Applied + 1
			end
		end
	end

	PawnSimExportPrint(string.format(PawnSimExportAppliedMessage, Applied, ScaleName))
	if Zeroed > 0 then
		PawnSimExportPrint(string.format("%d stats were zeroed/removed by the sim (e.g. stats you are capped on).", Zeroed))
	end

	local Tag = PawnGetScaleTag(ScaleName)
	if Tag then
		PawnSimExportPrint("Scale tag: " .. Tag)
	end
end

-- Prints the current bridge status.
function PawnSimExportStatus()
	local ScaleName = PawnUICurrentScale or PawnDefaultScaleName or "?"
	PawnSimExportPrint(string.format("Target scale: %s", tostring(ScaleName)))
	if PawnSimDumpTime then
		local Stamp = tostring(PawnSimDumpTime)
		if date then Stamp = date("%Y-%m-%d %H:%M:%S", PawnSimDumpTime) end
		PawnSimExportPrint(string.format("Last character export: %s", Stamp))
	else
		PawnSimExportPrint("Last character export: never")
	end
	if PawnSimResults and PawnSimResults.stats then
		local Count = 0
		for _ in pairs(PawnSimResults.stats) do Count = Count + 1 end
		PawnSimExportPrint(string.format("Sim results: %s, %d stats (source: %s)",
			tostring(PawnSimResults.generatedAt), Count, tostring(PawnSimResults.source)))
	else
		PawnSimExportPrint("Sim results: none loaded (run sim.ps1, then /reload)")
	end
end

SLASH_PAWNSIM1 = "/psim"
SlashCmdList["PAWNSIM"] = function(Message)
	local _, _, Command, Rest = string.find(Message or "", "^(%S+)%s*(.*)$")
	Command = string.lower(Command or "")
	if Command == "dump" then
		PawnSimDumpCharacter(Rest ~= "" and Rest or PawnUICurrentScale)
	elseif Command == "apply" then
		PawnSimApplyResults(Rest ~= "" and Rest or PawnUICurrentScale)
	elseif Command == "status" then
		PawnSimExportStatus()
	else
		PawnSimExportPrint("Usage: /psim dump [scale] | /psim apply [scale] | /psim status")
	end
end
