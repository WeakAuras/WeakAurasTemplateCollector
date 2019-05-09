local CreateFrame, UnitIsUnit, tinsert, sort, GetSpellBookItemName, GetSpellTabInfo, GetNumSpellTabs, GetSpellInfo, UnitAura, GetSpellCooldown, GetSpellCharges, GetSpellBaseCooldown = CreateFrame, UnitIsUnit, tinsert, sort, GetSpellBookItemName, GetSpellTabInfo, GetNumSpellTabs, GetSpellInfo, UnitAura, GetSpellCooldown, GetSpellCharges, GetSpellBaseCooldown

local backdrop = {
bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], edgeSize = 16,
insets = { left = 4, right = 3, top = 4, bottom = 3 }
}


local frame = CreateFrame("Frame", nil, UIParent)
frame:SetBackdrop(backdrop)
frame:SetBackdropColor(0, 0, 0)
frame:SetBackdropBorderColor(0.4, 0.4, 0.4)
--frame:Hide();

local scrollFrame = CreateFrame("ScrollFrame", "1ScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetAllPoints();

local editBox = CreateFrame("EditBox", "1Edit", frame)
editBox:SetFontObject(ChatFontNormal)
editBox:SetMultiLine(true)
editBox:SetAutoFocus(false);
editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

scrollFrame:SetScrollChild(editBox)

frame:SetPoint("RIGHT",0,0)
frame:SetWidth(300)
frame:SetHeight(715)
editBox:SetWidth(500);

--- OUTPUT
local spellsWithCd = {};
local playerBuffs = {};
local targetBuffs = {};
local petBuffs = {};
local targetDebuffs = {};
local spellIdsFromTalent = {};
local spellsWithCharge = {};

---

local gatheringTalent = false;

local function PRINT(t)
  local text = editBox:GetText();
  text = text .. "\n" .. t;
  editBox:SetText(text);
end

local function GetSpellCooldownUnified(id)
  local gcdStart, gcdDuration = GetSpellCooldown(61304);
  local charges, maxCharges, startTime, duration = GetSpellCharges(id);
  local cooldownBecauseRune = false;
   -- charges is nil if the spell has no charges. Or in other words GetSpellCharges is the wrong api
  if (charges == nil) then
    local basecd = GetSpellBaseCooldown(id);
    local enabled;
    startTime, duration, enabled = GetSpellCooldown(id);
    if (enabled == 0) then
      startTime, duration = 0, 0
    end

    local spellcount = GetSpellCount(id);
    -- GetSpellCount returns 0 for all spells that have no spell counts, so we only use that information if
    -- either the spell count is greater than 0
    -- or we have a ability without a base cooldown
    -- Checking the base cooldown is not enough though, since some abilities have no base cooldown,
    -- but can still be on cooldown
    -- e.g. Raging Blow that gains a cooldown with a talent
    if (spellcount > 0) then
      charges = spellcount;
    end

    local onNonGCDCD = duration and startTime and duration > 0 and (duration ~= gcdDuration or startTime ~= gcdStart);

    if ((basecd and basecd > 0) or onNonGCDCD) then

    else
      charges = spellcount;
      startTime = 0;
      duration = 0;
    end
  elseif (charges == maxCharges) then
    startTime, duration = 0, 0;
  elseif (charges == 0 and duration == 0) then
    -- Lavaburst while under Ascendance can return 0 charges even if the spell is useable
    charges = 1;
  end

  startTime = startTime or 0;
  duration = duration or 0;
  -- WORKAROUND Sometimes the API returns very high bogus numbers causing client freeezes,
  -- discard them here. WowAce issue #1008
  if (duration > 604800) then
    duration = 0;
    startTime = 0;
  end

--  print(" => ", charges, maxCharges, duration);

  return charges, maxCharges, startTime, duration;
end

local function checkForCd(spellId)
  local charges, maxCharges, startTime, duration = GetSpellCooldownUnified(spellId);
  if (charges and charges > 1) or (maxCharges and maxCharges > 1) or duration > 0 then
    if (not spellsWithCd[spellId]) then
      PRINT("Adding "  .. GetSpellInfo(spellId) .. " " .. duration);
      if (gatheringTalent) then
        spellIdsFromTalent[spellId] = true;
      end
    end
    if (charges and charges > 1) or (maxCharges and maxCharges > 1) then
      spellsWithCharge[spellId] = true
    end
    spellsWithCd[spellId] = true;
  end
end

local function checkForBuffs(unit, filter, output)
  local i = 1
  while true do
    local name, _, _, _, _, _, unitCaster, _, _, spellId = UnitAura(unit, i, filter) -- TODO PLAYER OR PET
    if (not name) then
      break
    end

    if (unitCaster == "player" or unitCaster == "pet") then
      if (not output[spellId]) then
        PRINT("Adding "  .. GetSpellInfo(spellId));
        if (gatheringTalent) then
          spellIdsFromTalent[spellId] = true;
        end
      end
      output[spellId] = true;
    end

    i = i + 1;
  end
end

function talents()
  gatheringTalent = true;
  PRINT("Gathering Talent information...");
end


frame:SetScript("OnUpdate",
  function()
    for spellTab = 1, GetNumSpellTabs() do
      local _, _, offset, numSpells, _, offspecID = GetSpellTabInfo(spellTab)
      if (offspecID  == 0) then
        for i = (offset + 1), (offset + numSpells - 1) do
          local name, _, spellId = GetSpellBookItemName(i, BOOKTYPE_SPELL)
          if not name then
            break;
          end
          if (spellId) then
            checkForCd(spellId);
          end
        end
      end
    end
    local i = 1;
    while true do
      local name, _, spellId = GetSpellBookItemName(i, BOOKTYPE_PET)
      if not name then
        break;
      end
      if (spellId) then
        checkForCd(spellId);
      end
      i = i + 1
    end

    checkForBuffs("player", "HELPFUL", playerBuffs);
    if (not UnitIsUnit("player", "target")) then
      checkForBuffs("target", "HELPFUL", targetBuffs);
    end
    checkForBuffs("pet", "HELPFUL", petBuffs);
    if (not UnitIsUnit("player", "target")) then
      checkForBuffs("target", "HARMFUL ", targetDebuffs);
    end

end);

local function formatBuffs(input, type, unit)
  local sorted = {};
  for k, _ in pairs(input) do
    tinsert(sorted, k);
  end

  local output = "";
  for _, spellId in pairs(sorted) do
    local withTalent = "";
    if (spellIdsFromTalent[spellId]) then
      withTalent = ", talent = 0 "
    end
    output = output .. "        { spell = " .. spellId .. ", type = \"" .. type .. "\", unit = \"" .. unit .. "\"" .. withTalent  .. "}, -- " .. GetSpellInfo(spellId) .. "\n";
  end

  return output;
end

function export()

  local buffs =
  "    [1] = {\n" ..
  "      title = L[\"Buffs\"],\n" ..
  "      args = {\n"
  buffs = buffs .. formatBuffs(playerBuffs, "buff", "player");
  buffs = buffs .. formatBuffs(targetBuffs, "buff", "target");
  buffs = buffs .. formatBuffs(petBuffs, "buff", "pet");
  buffs = buffs ..
  "      },\n" ..
  "      icon = 458972\n" ..
  "    },\n"

  local debuffs =
  "    [2] = {\n" ..
  "      title = L[\"Debuffs\"],\n" ..
  "      args = {\n"
  debuffs = debuffs .. formatBuffs(targetDebuffs, "debuff", "target");
  debuffs = debuffs ..
  "      },\n" ..
  "      icon = 458972\n" ..
  "    },\n"



  -- CDS
  local sortedCds = {};
  for spellId, _ in pairs(spellsWithCd) do
    tinsert(sortedCds, spellId);
  end
  sort(sortedCds);

  local cooldowns =
  "    [3] = {\n" ..
  "      title = L[\"Cooldowns\"],\n" ..
  "      args = {\n";

  for _, spellId in ipairs(sortedCds) do
    local spellName = GetSpellInfo(spellId);
    local parameters = "";
    if spellIdsFromTalent[spellId] then
      parameters = parameters .. ", talent = 0 "
    end
    if spellsWithCharge[spellId] then
      parameters = parameters .. ", charges = true "
    end
    -- buff & debuff doesn't work if spellid is different like Death and Decay or Marrowrend
    if playerBuffs[spellId] then
      parameters = parameters .. ", buff = true "
    end
    if petBuffs[spellId] then
      parameters = parameters .. ", buff = true, unit = 'pet' "
    end
    if targetBuffs[spellId] then
      parameters = parameters .. ", debuff = true "
    end
    -- TODO handle if possible: requiresTarget, totem, overlayGlow, usable

    cooldowns = cooldowns .. "        { spell = " .. spellId ..", type = \"ability\"" .. parameters .. "}, -- ".. spellName .. "\n"
  end

  cooldowns = cooldowns ..
  "      },\n" ..
  "      icon = 136012\n" ..
  "    },\n";

  editBox:SetText(buffs .. debuffs .. cooldowns);
  frame:Show();
end

-- Encounter ids are saved in Prototypes.lua, WeakAuras.encounter_table
-- key = encounterJournalID
-- value = encounterID
--
-- Script to get encounterJournalID:

--Alternative way to get them:
--<https://wow.tools/dbc/?dbc=journalencounter.db2>
--How to get encounterID:
--<https://wow.tools/dbc/?dbc=dungeonencounter.db2>

function WeakAuras.PrintEncounters()
  local encounter_list = ""
  EJ_SelectTier(EJ_GetNumTiers())
  for _,inRaid in ipairs({false, true}) do
     local instance_index = 1
     local instance_id
     local dungeon_name
     local title = inRaid and "Raids" or "Dungeons"
     encounter_list = ("%s|cffffd200%s|r\n"):format(encounter_list, title)
     repeat
        instance_id, dungeon_name = EJ_GetInstanceByIndex(instance_index, inRaid)
        instance_index = instance_index + 1
        if instance_id then
           EJ_SelectInstance(instance_id)
           local encounter_index = 1
           encounter_list = ("%s|cffffd200%s|r\n"):format(encounter_list, dungeon_name)
           repeat
              local encounter_name,_, encounter_id = EJ_GetEncounterInfoByIndex(encounter_index)
              encounter_index = encounter_index + 1
              if encounter_id then
                 encounter_list = ("%s%s: %d\n"):format(encounter_list, encounter_name, encounter_id)
              end
           until not encounter_id
        end
     until not instance_id
     encounter_list = encounter_list .. "\n"
  end
  print(string.format("%s\n%s", encounter_list, "Supports multiple entries, separated by commas\n"))
end
