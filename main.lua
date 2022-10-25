local CreateFrame, UnitIsUnit, tinsert, sort, GetSpellBookItemName, GetSpellTabInfo, GetNumSpellTabs, GetSpellInfo, UnitAura, GetSpellCooldown, GetSpellCharges, GetSpellBaseCooldown = CreateFrame, UnitIsUnit, tinsert, sort, GetSpellBookItemName, GetSpellTabInfo, GetNumSpellTabs, GetSpellInfo, UnitAura, GetSpellCooldown, GetSpellCharges, GetSpellBaseCooldown

local backdrop = {
bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], edgeSize = 16,
insets = { left = 4, right = 3, top = 4, bottom = 3 }
}


local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
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

local specDB
local talentsInitialized = false

local function updateSpec()
  TemplateCollectorDB = TemplateCollectorDB or {}
  local classID = select(3, UnitClass("player"))
  local specIndex = GetSpecialization()
  local specId = GetSpecializationInfoForClassID(classID, specIndex)
  TemplateCollectorDB[specId] = TemplateCollectorDB[specId] or {}
  specDB = TemplateCollectorDB[specId]
  for _, field in ipairs({
    "spellsWithCd",
    "playerBuffs",
    "targetBuffs",
    "petBuffs",
    "targetDebuffs",
    "spellIdsFromTalent",
    "talentsByName",
    "SpellsWithPvpTalent",
    "spellsWithCharge",
    "spellsWithGlowOverlay",
    "spellsWithRequireTarget",
    "spellsWithTotem",
    "spellsWithUsable"
  }) do
    specDB[field] = specDB[field] or {}
  end

  talentsInitialized = true
end

local function PRINT(t)
  local text = editBox:GetText();
  text = t .. "\n" .. text;
  editBox:SetText(text);
end

local function gatherTalent()
  local talentIndex = 1
  local configId = C_ClassTalents.GetActiveConfigID()
  if configId == nil then return end
  local configInfo = C_Traits.GetConfigInfo(configId)
  if configInfo == nil then return end
  for _, treeId in ipairs(configInfo.treeIDs) do
    local nodes = C_Traits.GetTreeNodes(treeId)
    for _, nodeId in ipairs(nodes) do
      local node = C_Traits.GetNodeInfo(configId, nodeId)
      if node.ID ~= 0 then
        for idx, talentId in ipairs(node.entryIDs) do
          local entryInfo = C_Traits.GetEntryInfo(configId, talentId)
          local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
          local spellId = definitionInfo.spellID
          local spellName = GetSpellInfo(spellId)
          if spellName then
            if not specDB.spellIdsFromTalent[spellId] then
              PRINT("talent: "..GetSpellInfo(spellId))
            end
            specDB.spellIdsFromTalent[spellId] = talentIndex
            specDB.talentsByName[spellName] = spellId
            talentIndex = talentIndex + 1
          end
        end
      end
    end
  end
end

local spec_frame = CreateFrame("Frame")
spec_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
spec_frame:RegisterEvent("TRAIT_CONFIG_CREATED")
spec_frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
spec_frame:RegisterEvent("PLAYER_TALENT_UPDATE")
spec_frame:SetScript("OnEvent", function()
  updateSpec()
  gatherTalent()
end)

local spelloverlay_frame = CreateFrame("Frame")
spelloverlay_frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
spelloverlay_frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
spelloverlay_frame:SetScript("OnEvent", function(self, event, spellId)
  if not specDB.spellsWithGlowOverlay[spellId] then
    PRINT("overlayGlow: "..GetSpellInfo(spellId))
  end
  specDB.spellsWithGlowOverlay[spellId] = true
end)

local function checkTargetedSpells()
  for spellId in pairs(specDB.spellsWithCd) do
    local spellName = GetSpellInfo(spellId)
    if spellName then
      if IsSpellInRange(spellName, "target") == 0 then
        if not specDB.spellsWithRequireTarget[spellId] then
          PRINT("requiresTarget: "..GetSpellInfo(spellId))
        end
        specDB.spellsWithRequireTarget[spellId] = true
      end
    end
  end
  for spellId in pairs(specDB.spellIdsFromTalent) do
    local spellName = GetSpellInfo(spellId)
    if spellName then
      if IsSpellInRange(spellName, "target") == 0 then
        if not specDB.spellsWithRequireTarget[spellId] then
          PRINT("requiresTarget: "..GetSpellInfo(spellId))
        end
        specDB.spellsWithRequireTarget[spellId] = true
      end
    end
  end
  for actionSlot = 1, 120 do
    local actionType, spellId = GetActionInfo(actionSlot)
    if actionType == "spell"
    and spellId
    and (IsPlayerSpell(spellId) or IsSpellKnown(spellId, true))
    and IsActionInRange(actionSlot) == false
    then
      if not specDB.spellsWithRequireTarget[spellId] then
        PRINT("requiresTarget: "..GetSpellInfo(spellId))
      end
      specDB.spellsWithRequireTarget[spellId] = true
    end
  end
end

local requireTarget_frame = CreateFrame("Frame")
requireTarget_frame:RegisterEvent("PLAYER_TARGET_CHANGED")
requireTarget_frame:SetScript("OnEvent", function()
  if UnitExists("target") and UnitCanAttack("player", "target") then
    checkTargetedSpells()
  end
end)

do
  local lastSpellId, lastSpellTime
  local totems = {}
  local totem_frame = CreateFrame("Frame")
  totem_frame:RegisterEvent("PLAYER_TOTEM_UPDATE")
  totem_frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  totem_frame:SetScript("OnEvent", function(self, event, unit, castGUID, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      lastSpellId = spellId
      lastSpellTime = GetTime()
    elseif event == "PLAYER_TOTEM_UPDATE" then
      local now = GetTime()
      for index = 1, MAX_TOTEMS do
        local _, totemName = GetTotemInfo(index)
        if totemName and totemName ~= "" then
          if totems[index] == nil -- new totem
          and lastSpellTime
          and now - lastSpellTime <= 0.2
          and not specDB.spellsWithTotem[lastSpellId]
          then
            specDB.spellsWithTotem[lastSpellId] = true
            PRINT("totem: "..GetSpellInfo(lastSpellId))
          end
          totems[index] = true
        else
          totems[index] = nil
        end
      end
    end
  end)
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
    if (charges and charges > 1) or (maxCharges and maxCharges > 1) then
      if not specDB.spellsWithCharge[spellId] then
        PRINT("charge: "..GetSpellInfo(spellId))
      end
      specDB.spellsWithCharge[spellId] = true
    end
    if not specDB.spellsWithCharge[spellId] and not specDB.spellsWithCd[spellId] then
      PRINT("cd: "..GetSpellInfo(spellId))
    end
    specDB.spellsWithCd[spellId] = true;
  end
end

do
  local skipIfSpellOnCooldown = {
    [109132] = true, -- monk's roll
    [358267] = true, -- evoker's hover
   -- [205629] = true, -- dh demonic trample pvp talent
  }
  local usable_frame = CreateFrame("Frame")
  usable_frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  local isPaused = false
  usable_frame:SetScript("OnEvent", function()
    local skip = false
    for spellId in pairs(skipIfSpellOnCooldown) do
      local charges, maxCharges, startTime, duration = GetSpellCooldownUnified(spellId)
      if startTime and startTime > 0 then
        skip = true
        if not isPaused then
          PRINT("usable check paused until "..GetSpellInfo(spellId).." is ready")
          isPaused = true
          return
        end
      end
    end
    if not skip and isPaused then
      PRINT("usable check un-paused")
      isPaused = false
    end
    for actionSlot = 1, 120 do
      local actionType, spellId = GetActionInfo(actionSlot)
      if actionType == "spell"
      and spellId
      and (IsPlayerSpell(spellId) or IsSpellKnown(spellId, true))
      then
        local isUsable, notEnoughMana = IsUsableAction(actionSlot)
        if isUsable == false and not notEnoughMana then
          if not specDB.spellsWithUsable[spellId] then
            PRINT("usable: "..GetSpellInfo(spellId))
            specDB.spellsWithUsable[spellId] = true
          end
        end
      end
    end
  end)
end

local pvpTalent_frame = CreateFrame("Frame")
pvpTalent_frame:RegisterEvent("PLAYER_PVP_TALENT_UPDATE")
pvpTalent_frame:SetScript("OnEvent", function()
  local slotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo(1);
  if (slotInfo) then
     local pvpSpecTalents = slotInfo.availableTalentIDs
     for i, talentId in ipairs(pvpSpecTalents) do
        local _, _, _, _, _ , spellId = GetPvpTalentInfoByID(talentId)
        if not specDB.SpellsWithPvpTalent[spellId] then
          PRINT("pvptalent: "..GetSpellInfo(spellId))
          specDB.SpellsWithPvpTalent[spellId] = i
        end
     end
  end
end)

local bannedAuras = {
  [335149] = true, -- wotlk xp event
  [335148] = true, -- timewalking event
  [59650] = true, -- flying mount
  [282559] = true, -- xp bonus
  [225788] = true, -- wq bonus
  [7353] = true, -- Cozy Fire
  [225787] = true, -- shadowlands dungeon event
  [186406] = true, -- pet battle event
  [312370] = true, -- vulpera camp
  [335150] = true, -- cata timewalking event
  [2479] = true, -- honorless target
  [391312] = true, -- tailor buff
  [186403] = true, -- pvp event
}
local function checkForBuffs(unit, filter, output)
  local i = 1
  while true do
    local name, _, _, _, _, _, unitCaster, _, _, spellId = UnitAura(unit, i, filter) -- TODO PLAYER OR PET
    if (not name) then
      break
    end

    if (unitCaster == "player" or unitCaster == "pet") and not bannedAuras[spellId] then
      if not output[spellId] then
        PRINT(("%s %s: %s"):format(
          filter == "HELPFUL" and "buff" or "debuff",
          unit,
          name
        ))
      end
      output[spellId] = true;
    end

    i = i + 1;
  end
end

frame:SetScript("OnUpdate",
  function()
    if not talentsInitialized then return end
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

    checkForBuffs("player", "HELPFUL", specDB.playerBuffs);
    if (not UnitIsUnit("player", "target")) then
      checkForBuffs("target", "HELPFUL", specDB.targetBuffs);
    end
    checkForBuffs("pet", "HELPFUL", specDB.petBuffs);
    if (not UnitIsUnit("player", "target")) then
      checkForBuffs("target", "HARMFUL ", specDB.targetDebuffs);
    end

end);

local function formatBuffs(input, type, unit)
  local sorted = {};
  for k, _ in pairs(input) do
    tinsert(sorted, k);
  end
  table.sort(sorted)

  local output = "";
  local cacheSpellName = {}
  for _, spellId in pairs(sorted) do
    if not specDB.SpellsWithPvpTalent[spellId] and not bannedAuras[spellId] then
      local withTalent = "";
      if (specDB.spellIdsFromTalent[spellId]) then
        withTalent = (", talent = %d"):format(spellId)
      else
        local spellName = GetSpellInfo(spellId)
        if specDB.talentsByName[spellName] then
          withTalent = (", talent = %d"):format(specDB.talentsByName[spellName])
        end
      end
      local spellName = GetSpellInfo(spellId)
      if not cacheSpellName[spellName] then
        output = output .. "        { spell = " .. spellId .. ", type = \"" .. type .. "\", unit = \"" .. unit .. "\"" .. withTalent  .. " }, -- " .. spellName .. "\n";
        cacheSpellName[spellName] = true
      end
    end
  end

  return output
end


local function formatBuffsPvp(input, type, unit)
  local sorted = {};
  for k, _ in pairs(input) do
    tinsert(sorted, k);
  end
  table.sort(sorted)
  local output = "";
  local cacheSpellName = {}
  for _, spellId in pairs(sorted) do
    if specDB.SpellsWithPvpTalent[spellId] and not bannedAuras[spellId] then
      local spellName = GetSpellInfo(spellId)
      if not cacheSpellName[spellName] then
        output = output .. "        { spell = " .. spellId .. ", type = \"" .. type .. "\", unit = \"" .. unit .. "\", pvptalent = " .. specDB.SpellsWithPvpTalent[spellId]  .. ", titleSuffix = L[\""..type.."\"] }, -- " .. spellName .. "\n";
        cacheSpellName[spellName] = true
      end
    end
  end

  return output
end

function reset(field)
  if not field then return end
  if specDB[field] then
    wipe(specDB[field])
    PRINT("reset " .. field)
  end
end

local bannedCds = {
  [232633] = true, -- arcane torrent
  [312372] = true, -- camp
  [312370] = true, -- camp
}

function export()

  local buffs =
  "    [1] = {\n" ..
  "      title = L[\"Buffs\"],\n" ..
  "      args = {\n"
  buffs = buffs .. formatBuffs(specDB.playerBuffs, "buff", "player");
  buffs = buffs .. formatBuffs(specDB.targetBuffs, "buff", "target");
  buffs = buffs .. formatBuffs(specDB.petBuffs, "buff", "pet");
  buffs = buffs ..
  "      },\n" ..
  "      icon = 458972\n" ..
  "    },\n"

  local debuffs =
  "    [2] = {\n" ..
  "      title = L[\"Debuffs\"],\n" ..
  "      args = {\n"
  debuffs = debuffs .. formatBuffs(specDB.targetDebuffs, "debuff", "target");
  debuffs = debuffs ..
  "      },\n" ..
  "      icon = 458972\n" ..
  "    },\n"

  local pvpBuffs = formatBuffsPvp(specDB.playerBuffs, "buff", "player")
  pvpBuffs = pvpBuffs .. formatBuffsPvp(specDB.targetBuffs, "buff", "target")
  pvpBuffs = pvpBuffs .. formatBuffsPvp(specDB.petBuffs, "buff", "pet")
  pvpBuffs = pvpBuffs .. formatBuffsPvp(specDB.targetDebuffs, "debuff", "target")

  -- CDS
  local sortedCds = {};
  local temp = {}
  for spellId in pairs(specDB.spellsWithCd) do
    temp[spellId] = true
  end
  for spellId in pairs(specDB.spellsWithRequireTarget) do
    temp[spellId] = true
  end
  for spellId in pairs(temp) do
    if not bannedCds[spellId] then
      tinsert(sortedCds, spellId);
    end
  end
  sort(sortedCds);

  local pre_cooldowns =
  "    [3] = {\n" ..
  "      title = L[\"Cooldowns\"],\n" ..
  "      args = {\n";
  local post_cooldowns =
  "      },\n" ..
  "      icon = 136012\n" ..
  "    },\n";
  local pre_pvpTalents =
  "    [4] = {},\n"..
  "    [5] = {},\n"..
  "    [6] = {},\n"..
  "    [7] = {},\n"..
  "    [8] = {},\n"..
  "    [9] = {},\n"..
  "    [10] = {\n"..
  "      title = L[\"PvP Talents\"],\n"..
  "      args = {\n"

  local post_pvpTalents =
  "      },\n"..
  "      icon = \"Interface/Icons/Achievement_BG_winWSG\",\n"..
  "    },\n"
  local cooldowns = ""
  local pvpTalents = ""

  for _, spellId in ipairs(sortedCds) do
    local spellName = GetSpellInfo(spellId);
    local parameters = "";
    if specDB.spellsWithCharge[spellId] then
      parameters = parameters .. ", charges = true"
    end
    -- buff & debuff doesn't work if spellid is different like Death and Decay or Marrowrend
    if specDB.playerBuffs[spellId] then
      parameters = parameters .. ", buff = true"
    end
    if specDB.petBuffs[spellId] then
      parameters = parameters .. ", buff = true, unit = 'pet'"
    end
    if specDB.targetBuffs[spellId] then
      parameters = parameters .. ", debuff = true"
    end
    if specDB.spellsWithGlowOverlay[spellId] then
      parameters = parameters .. ", overlayGlow = true"
    end
    if specDB.spellsWithRequireTarget[spellId] then
      parameters = parameters .. ", requiresTarget = true"
    end
    if specDB.spellsWithTotem[spellId] then
      parameters = parameters .. ", totem = true"
    end
    if specDB.spellsWithUsable[spellId] then
      parameters = parameters .. ", usable = true"
    end
    if specDB.spellIdsFromTalent[spellId] then
      parameters = parameters .. (", talent = %s"):format(spellId)
    elseif specDB.talentsByName[spellName] then
      parameters = parameters .. (", talent = %d"):format(specDB.talentsByName[spellName])
    end

    if specDB.SpellsWithPvpTalent[spellId] then
      parameters = parameters .. (", pvptalent = %d"):format(specDB.SpellsWithPvpTalent[spellId])
      pvpTalents = pvpTalents .. "        { spell = " .. spellId ..", type = \"ability\"" .. parameters .. ", titleSuffix = L[\"cooldown\"] }, -- ".. spellName .. "\n"
    else
      cooldowns = cooldowns .. "        { spell = " .. spellId ..", type = \"ability\"" .. parameters .. " }, -- ".. spellName .. "\n"
    end
  end


  editBox:SetText(buffs .. debuffs .. pre_cooldowns .. cooldowns .. post_cooldowns .. pre_pvpTalents .. pvpBuffs .. pvpTalents .. post_pvpTalents);
  frame:Show();
end
