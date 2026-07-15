-- || AutoMarker 3.3.5a (Wrath) - mouseover-driven port || --
--
-- Vanilla SuperWoW lets you pass a raw GUID anywhere a unit token is expected.
-- 3.3.5a does not, so "mark the whole pack from a single click" is impossible
-- without a client mod. This build leans on the one mechanism that does work
-- reliably: when UPDATE_MOUSEOVER_UNIT fires, "mouseover" is a valid unit
-- token, so SetRaidTarget("mouseover", n) works. We check the mouseover GUID
-- against the loaded packs and apply the assigned mark if matched.
-- User sweeps cursor over the pull; each mob snaps to its assigned mark.

local L = AutoMarkerLocale

local color = {
  white = "|cffffffff", red = "|cffff0000", green = "|cff00ff00",
  blue = "|cff0000ff", yellow = "|cffffff00", orange = "|cffff8000",
}
local function c(text, col) return col..text.."|r" end

local UnitExists         = UnitExists
local UnitName           = UnitName
local UnitGUID           = UnitGUID
local SetRaidTarget      = SetRaidTarget
local GetRaidTargetIndex = GetRaidTargetIndex
local GetRealZoneText    = GetRealZoneText
local IsPartyLeader      = IsPartyLeader
local GetNumPartyMembers = GetNumPartyMembers
local GetNumRaidMembers  = GetNumRaidMembers
local GetRaidRosterInfo  = GetRaidRosterInfo
local sgmatch            = string.gmatch
local ssub               = string.sub
local slen               = string.len
local supper             = string.upper
local tinsert            = table.insert
local tremove            = table.remove
local tonumber           = tonumber
local pairs, ipairs      = pairs, ipairs

local function auto_print(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) end
end

local function InGroup()
  return (GetNumPartyMembers() + GetNumRaidMembers()) > 0
end

local function PlayerCanMark()
  if not InGroup() then return true end  -- solo: server allows it on this client
  if GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers() do
      local name, rank = GetRaidRosterInfo(i)
      if name == UnitName("player") then return (rank or 0) >= 1 end
    end
    return false
  end
  local pl = IsPartyLeader()
  return pl == 1 or pl == true
end

local raidMarks = { L["Unmarked"], L["Star"], L["Circle"], L["Diamond"], L["Triangle"], L["Moon"], L["Square"], L["Cross"], L["Skull"] }

local defaultSettings = { enabled = true, debug = false }

local sweep_on = false
local sweepPackName = nil
local currentNpcsToMark = {}
local currentEntryPacks = {}
local entrySlots = {}

local autoMarker = CreateFrame("Frame", "AutoMarkerFrame")

-- GUID -> entry --------------------------------------------------------------
--
-- A WotLK ObjectGuid prints as "0x" plus 16 hex digits: high(4) entry(6)
-- counter(6). The entry field holds the creature_template entry and is stable
-- forever; the counter is the spawn id, which for script-summoned mobs is
-- handed out by the runtime generator and differs every pull. Only Creature and
-- Vehicle carry a real entry: Pet (0xF140) reuses those bits for pet_number.
-- The value exceeds 2^53 so it cannot survive tonumber() as a whole; slice the
-- field out as a string instead.
local ENTRY_HIGH = { ["F130"] = true, ["F150"] = true }

local function guidEntry(guid)
  if not guid or slen(guid) ~= 18 then return nil end
  if not ENTRY_HIGH[supper(ssub(guid, 3, 6))] then return nil end
  return tonumber(ssub(guid, 7, 12), 16)
end

local function entryToPack(entry, zone)
  for packName, pools in pairs(currentEntryPacks[zone] or {}) do
    if pools[entry] then return packName, pools[entry] end
  end
end

-- Marks are unique in WoW: an icon can only sit on one mob at a time, so an
-- entry pack hands each distinct GUID its own slot from the pool. A GUID
-- already holding a slot keeps it, which makes re-sweeping idempotent. When the
-- pool is full and a GUID we have never seen turns up, the bound cohort cannot
-- still be alive (the pool is sized to the real add count), so those bindings
-- are stale: flush and let the newcomer start a fresh assignment.
local function assignEntryMark(guid, zone, packName, entry, pool)
  entrySlots[zone] = entrySlots[zone] or {}
  entrySlots[zone][packName] = entrySlots[zone][packName] or {}
  local slots = entrySlots[zone][packName][entry]
  if not slots then
    slots = {}
    for i, mark in ipairs(pool) do slots[i] = { mark = mark } end
    entrySlots[zone][packName][entry] = slots
  end

  for _, slot in ipairs(slots) do
    if slot.guid == guid then return slot.mark, false end
  end
  for _, slot in ipairs(slots) do
    if not slot.guid then slot.guid = guid; return slot.mark, false end
  end

  for _, slot in ipairs(slots) do slot.guid = nil end
  slots[1].guid = guid
  return slots[1].mark, true
end

local function guidToPack(id, zone)
  if not currentNpcsToMark or not currentNpcsToMark[zone] then return end
  for packName, packInfo in pairs(currentNpcsToMark[zone] or {}) do
    for guid, _ in pairs(packInfo) do
      if guid == id then return packName, currentNpcsToMark[zone][packName] end
    end
  end
  for packName, packInfo in pairs(AutoMarkerDB.customNpcsToMark[zone] or {}) do
    for guid, _ in pairs(packInfo) do
      if guid == id then return packName, AutoMarkerDB.customNpcsToMark[zone][packName] end
    end
  end
end

-- Every way this function declines to mark looks the same from in front of the
-- screen: nothing happens. Trace names the reason instead. Repeats are dropped
-- because UPDATE_MOUSEOVER_UNIT fires constantly.
local lastTrace
local function trace(msg)
  if not (AutoMarkerDB and AutoMarkerDB.settings and AutoMarkerDB.settings.debug) then return end
  if lastTrace == msg then return end
  lastTrace = msg
  auto_print(c("AM: ", color.orange) .. msg)
end

-- The core mechanism: on mouseover, if the GUID is in a known pack,
-- apply the pack's assigned mark using the "mouseover" token directly.
local function OnMouseover()
  if not AutoMarkerDB.settings.enabled then
    trace("addon is disabled, /am enable")
    return
  end
  local guid = UnitGUID("mouseover")
  if not guid then return end

  local name  = UnitName("mouseover") or "?"
  local zone  = GetRealZoneText()
  local entry = guidEntry(guid)

  if not (IsShiftKeyDown() and IsControlKeyDown()) then
    trace(name .. " entry=" .. tostring(entry) .. " zone=[" .. tostring(zone) .. "] (hold ctrl+shift to mark)")
    return
  end
  if not PlayerCanMark() then
    trace("cannot mark " .. name .. ": needs party leader, or raid leader/assist")
    return
  end

  local desired, source

  local pn, pack = guidToPack(guid, zone)
  if pn and pack and pack[guid] then
    desired, source = pack[guid], "pack: "..pn
  elseif entry then
    local epn, pool = entryToPack(entry, zone)
    if epn then
      local recycled
      desired, recycled = assignEntryMark(guid, zone, epn, entry, pool)
      source = "entry "..entry..", pack: "..epn..(recycled and ", cohort reset" or "")
    else
      trace("no pack holds " .. name .. " (entry " .. entry .. ") in zone [" .. tostring(zone) .. "]")
      return
    end
  else
    trace(name .. " guid " .. guid .. " carries no creature entry")
    return
  end

  local current = GetRaidTargetIndex("mouseover") or 0
  if current == desired then
    trace(name .. " already wears " .. raidMarks[desired+1] .. " [" .. source .. "]")
    return
  end
  SetRaidTarget("mouseover", desired)
  trace(name.." ("..guid..") "..raidMarks[current+1].." -> "..raidMarks[desired+1].." ["..source.."]")
end

-- Called from sweep: stores the mouseover's GUID and its current raid mark in `pack`.
local function AddToPack(guid, pack)
  if not guid or not pack then return end

  local unitName = UnitName("mouseover") or "<unknown>"
  local raidmark = GetRaidTargetIndex("mouseover") or 0
  local zoneName = GetRealZoneText()

  AutoMarkerDB.customNpcsToMark[zoneName] = AutoMarkerDB.customNpcsToMark[zoneName] or {}
  AutoMarkerDB.customNpcsToMark[zoneName][pack] = AutoMarkerDB.customNpcsToMark[zoneName][pack] or {}
  currentNpcsToMark[zoneName] = currentNpcsToMark[zoneName] or {}
  currentNpcsToMark[zoneName][pack] = currentNpcsToMark[zoneName][pack] or {}

  local existing = AutoMarkerDB.customNpcsToMark[zoneName][pack][guid]
  if existing ~= raidmark then
    auto_print((existing and L["Updating "] or L["Adding "]) .. unitName .. "(" .. guid .. L[") in pack: "] .. pack .. L[" with new mark: "] .. raidMarks[raidmark + 1] .. L[" in zone: "] .. zoneName)
    AutoMarkerDB.customNpcsToMark[zoneName][pack][guid] = raidmark
    currentNpcsToMark[zoneName][pack][guid] = raidmark
  end
end

-- EVENTS ---------------------------------------------------------------

autoMarker:RegisterEvent("ADDON_LOADED")
autoMarker:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
autoMarker:RegisterEvent("PLAYER_REGEN_ENABLED")

function autoMarker:Initialize()
  if not AutoMarkerDB then AutoMarkerDB = {} end
  if not AutoMarkerDB.customNpcsToMark then AutoMarkerDB.customNpcsToMark = {} end

  if not AutoMarkerDB.settings then
    AutoMarkerDB.settings = {}
    for k, v in pairs(defaultSettings) do AutoMarkerDB.settings[k] = v end
  else
    for k, v in pairs(defaultSettings) do
      if AutoMarkerDB.settings[k] == nil then AutoMarkerDB.settings[k] = v end
    end
  end

  for raid_name, packs in pairs(defaultNpcsToMark) do
    if not currentNpcsToMark[raid_name] then currentNpcsToMark[raid_name] = {} end
    for pack_name, _ in pairs(packs) do
      if not currentNpcsToMark[raid_name][pack_name] then
        currentNpcsToMark[raid_name][pack_name] = defaultNpcsToMark[raid_name][pack_name]
      end
    end
  end
  for raid_name, packs in pairs(AutoMarkerDB.customNpcsToMark) do
    if not currentNpcsToMark[raid_name] then currentNpcsToMark[raid_name] = {} end
    for pack_name, _ in pairs(packs) do
      currentNpcsToMark[raid_name][pack_name] = AutoMarkerDB.customNpcsToMark[raid_name][pack_name]
    end
  end

  -- Entry packs are static source data: an entry is knowable up front, so there
  -- is nothing to capture in-game and nothing to persist.
  for raid_name, packs in pairs(defaultEntryPacks or {}) do
    currentEntryPacks[raid_name] = currentEntryPacks[raid_name] or {}
    for pack_name, pools in pairs(packs) do
      currentEntryPacks[raid_name][pack_name] = pools
    end
  end

  auto_print(c(L["AutoMarker loaded!"], color.yellow) .. L[" Type "] .. c("/am", color.green) .. L[" to see commands."])
  auto_print(c("AutoMarker: ", color.orange).."mouseover-driven mode. Sweep cursor over mobs to mark.")
end

local function HandleEvent(self, event, ...)
  if event == "ADDON_LOADED" then
    if (...) == "AutoMarker" then self:Initialize() end
    return
  end
  if not (AutoMarkerDB and AutoMarkerDB.settings and AutoMarkerDB.settings.enabled) then return end

  -- Pools are pull-scoped. Leaving combat is the only signal that a pull is
  -- over: nothing about a mouseover can tell "still marking this pull" apart
  -- from "same mob type, next pull". Flushing here means the next pull always
  -- starts at the top of the pool however few mobs you swept in the last one,
  -- and a wipe re-summon is covered for free since a wipe ends combat too.
  if event == "PLAYER_REGEN_ENABLED" then
    entrySlots = {}
    return
  end

  if event == "UPDATE_MOUSEOVER_UNIT" then
    OnMouseover()
    if sweep_on then
      local g = UnitGUID("mouseover")
      if g then AddToPack(g, sweepPackName) end
    end
  end
end
autoMarker:SetScript("OnEvent", HandleEvent)

-- Slash commands -----------------------------------------------------------

local function tsize(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local function handleCommands(msg)
  local args = {}
  for word in sgmatch(msg or "", "%S+") do tinsert(args, word) end
  local command, packName = args[1], args[2]
  local zoneName = GetRealZoneText()

  if sweep_on and command ~= "sweep" then
    sweep_on = false
    auto_print(L["Sweep mode [ "] .. c(L["off"], color.red) .. " ]")
    return
  end

  if command == "enabled" or command == "enable" then
    AutoMarkerDB.settings.enabled = not AutoMarkerDB.settings.enabled
    auto_print(L["AutoMarker is now ["] ..
      (AutoMarkerDB.settings.enabled and c(L["enabled"], color.green) or c(L["disabled"], color.red)) .. "]")
  elseif command == "clear" or command == "c" then
    if not packName then auto_print("Usage: /am clear <packname>"); return end
    if AutoMarkerDB.customNpcsToMark[zoneName] and AutoMarkerDB.customNpcsToMark[zoneName][packName] then
      AutoMarkerDB.customNpcsToMark[zoneName][packName] = nil
      if currentNpcsToMark[zoneName] then currentNpcsToMark[zoneName][packName] = nil end
      auto_print(L["Mobs in "] .. packName .. L[" have been cleared."])
    else
      auto_print("No custom pack named '"..packName.."' in this zone.")
    end
  elseif command == "sweep" then
    local off_aliases = { off = true, stop = true, cancel = true, ["false"] = true }
    if sweep_on and (not packName or packName == sweepPackName or off_aliases[packName]) then
      sweep_on = false
      auto_print(L["Sweep mode [ "] .. c(L["off"], color.red) .. " ]")
      return
    end
    if off_aliases[packName] then return end
    if not packName then auto_print("Usage: /am sweep <packname>"); return end
    sweep_on = true; sweepPackName = packName
    auto_print(L["Sweep mode [ "] .. c(L["on"], color.green) .. L[" ] sweep your mouse over enemies to add them to pack: "] .. c(sweepPackName, color.orange))
  elseif command == "reset" then
    entrySlots = {}
    auto_print("AutoMarker: entry-pack assignments cleared.")
  elseif command == "debug" then
    AutoMarkerDB.settings.debug = not AutoMarkerDB.settings.debug
    auto_print(L["Debug mode set to: "] .. (AutoMarkerDB.settings.debug and c(L["on"], color.green) or c(L["off"], color.red)))
  else
    auto_print(L["Commands:"])
    auto_print("/am " .. c("e", color.green) .. "nable - toggle the addon")
    auto_print("/am " .. c("sweep", color.green) .. " <packname> - sweep mouse over mobs to add them; repeat or '/am sweep off' to cancel")
    auto_print("/am " .. c("c", color.green) .. "lear <packname> - delete a custom pack in this zone")
    auto_print("/am " .. c("reset", color.green) .. " - forget entry-pack mark assignments")
    auto_print("/am debug - toggle debug print on each automark")
  end
end

SLASH_AUTOMARKER1 = "/automarker"
SLASH_AUTOMARKER2 = "/am"
SlashCmdList["AUTOMARKER"] = handleCommands
