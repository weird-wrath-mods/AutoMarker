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
local GetInstanceInfo    = GetInstanceInfo
local time               = time
local sformat            = string.format
local GetTime            = GetTime
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

-- A mark takes a server round-trip to show, and until it does the mob still
-- reads as unmarked, so a sweep that crosses it again would ask twice. The
-- server answers a repeat by clearing the icon and setting it again, which
-- flickers. Hold each request for a short window instead of resending.
-- ponytail: fixed window, raise it if flicker returns on laggy nights
local PENDING_WINDOW = 0.3
local pendingMarks = {}

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

local function guidCounter(guid)
  return tonumber(ssub(guid, 13, 18), 16)
end

local function withCounter(guid, counter)
  return ssub(guid, 1, 12) .. sformat("%06X", counter)
end

-- Shifts --------------------------------------------------------------------
--
-- A pinned counter is the mob's place in the order the instance map created
-- units at load. A map rebuilt after kills (restart, or left empty past the
-- unload delay) skips the load-time summons of dead vehicles and bosses, and a
-- server update can add or drop spawns; either moves every later counter by the
-- same amount. Shifts are saved, since the next night on the same lockout loads
-- the same way.

local function shiftGroups(zone)
  local _, _, _, _, maxPlayers = GetInstanceInfo()
  local out = {}
  for _, g in ipairs(defaultShiftGroups and defaultShiftGroups[zone] or {}) do
    if g.raidSize == maxPlayers then out[#out + 1] = g end
  end
  return out
end

local function shiftKey(zone, g) return zone .. "/" .. g.name .. "/" .. g.raidSize end

local function groupShift(zone, g)
  local rec = AutoMarkerDB.shifts[shiftKey(zone, g)]
  return rec and rec.shift or 0
end

local function groupPins(g, zone, entry)
  local out = {}
  for packName in pairs(g.packs) do
    for pin in pairs(currentNpcsToMark[zone] and currentNpcsToMark[zone][packName] or {}) do
      if guidEntry(pin) == entry then out[#out + 1] = guidCounter(pin) end
    end
  end
  return out
end

-- Votes describe the instance map loaded now, so they live for the session and
-- clear when the zone changes.
local votes = {}
local votesZone

local trace

-- Every pinned mob votes, once per GUID, for each shift that would put it on a
-- pin of its type. The shift with the most votes wins: a type with one pin in
-- the group settles it alone, and a single wrong pin cannot outvote the rest.
-- Pins of one type often sit at consecutive counters (the 10-man Adherents are
-- 388-38B), so one mob can leave a tie. A tie keeps the stored shift if it leads,
-- else takes the one pack 1's anchor implies, since pack 1 is pulled first. A
-- tie neither breaks leaves the group unsettled, and its packs mark nothing
-- until another mob decides it, rather than risk duplicate icons in a pack.
local function learnShift(guid, zone, entry)
  for _, g in ipairs(shiftGroups(zone)) do
    local key = shiftKey(zone, g)
    local v = votes[key]
    if not v then v = { seen = {}, count = {}, anchor = {} }; votes[key] = v end
    local pins = groupPins(g, zone, entry)
    if #pins > 0 and not v.seen[guid] then
      v.seen[guid] = true
      local counter = guidCounter(guid)
      for _, p in ipairs(pins) do
        v.count[counter - p] = (v.count[counter - p] or 0) + 1
      end
      if entry == guidEntry(g.anchor) then v.anchor[counter - guidCounter(g.anchor)] = true end

      local best = 0
      for _, n in pairs(v.count) do if n > best then best = n end end
      local cur, pick = groupShift(zone, g)
      if v.count[cur] == best then
        pick = cur
      else
        local leaders, anchored = {}, {}
        for s, n in pairs(v.count) do
          if n == best then
            leaders[#leaders + 1] = s
            if v.anchor[s] then anchored[#anchored + 1] = s end
          end
        end
        pick = (#leaders == 1 and leaders[1]) or (#anchored == 1 and anchored[1]) or nil
      end

      v.unsettled = pick == nil
      if pick and pick ~= cur then
        AutoMarkerDB.shifts[key] = { shift = pick, t = time() }
        trace(g.name .. " (" .. g.raidSize .. ") counters shifted by " .. pick)
      end
      if v.unsettled then
        trace(g.name .. " shift undecided, hover another of its mobs")
      else
        local fits
        for _, p in ipairs(pins) do if counter - p == pick then fits = true end end
        if not fits then trace(guid .. " fits no " .. g.name .. " pin at shift " .. pick .. ", pin data may be wrong") end
      end
    end
  end
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
  -- Slots hang off the pool table, not the entry, so entries listed with the
  -- same table draw from one pool in sweep order.
  local slots = entrySlots[zone][packName][pool]
  if not slots then
    slots = {}
    for i, mark in ipairs(pool) do slots[i] = { mark = mark } end
    entrySlots[zone][packName][pool] = slots
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

-- Returns the pack and the pinned GUID the mouseover stands for, which differs
-- from the mouseover's own GUID when its shift group has moved.
local function guidToPack(id, zone)
  if not currentNpcsToMark or not currentNpcsToMark[zone] then return end
  local sizes = defaultPackRaidSize and defaultPackRaidSize[zone] or {}
  local _, _, _, _, maxPlayers = GetInstanceInfo()
  local shifted = {}
  for _, g in ipairs(shiftGroups(zone)) do
    local v = votes[shiftKey(zone, g)]
    local s = groupShift(zone, g)
    if (v and v.unsettled) or s ~= 0 then
      -- false: unsettled, so this group's packs match nothing
      local pin = not (v and v.unsettled) and withCounter(id, guidCounter(id) - s)
      for packName in pairs(g.packs) do shifted[packName] = pin end
    end
  end
  for packName, packInfo in pairs(currentNpcsToMark[zone] or {}) do
    if not sizes[packName] or sizes[packName] == maxPlayers then
      local pin = shifted[packName]
      if pin == nil then pin = id end
      if pin and packInfo[pin] then return packName, packInfo, pin end
    end
  end
  for packName, packInfo in pairs(AutoMarkerDB.customNpcsToMark[zone] or {}) do
    if packInfo[id] then return packName, packInfo, id end
  end
end

-- Every way this function declines to mark looks the same from in front of the
-- screen: nothing happens. Trace names the reason instead. Repeats are dropped
-- because UPDATE_MOUSEOVER_UNIT fires constantly.
local lastTrace
function trace(msg)
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
  if entry then learnShift(guid, zone, entry) end

  if not (IsShiftKeyDown() and IsControlKeyDown()) then
    trace(name .. " entry=" .. tostring(entry) .. " zone=[" .. tostring(zone) .. "] (hold ctrl+shift to mark)")
    return
  end
  if not PlayerCanMark() then
    trace("cannot mark " .. name .. ": needs party leader, or raid leader/assist")
    return
  end

  local desired, source

  local pn, pack, pin = guidToPack(guid, zone)
  if pn then
    desired, source = pack[pin], "pack: "..pn..(pin ~= guid and ", as "..pin or "")
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
    pendingMarks[guid] = nil
    trace(name .. " already wears " .. raidMarks[desired+1] .. " [" .. source .. "]")
    return
  end
  local pending = pendingMarks[guid]
  if pending and pending.mark == desired and GetTime() - pending.t < PENDING_WINDOW then
    trace(name .. " " .. raidMarks[desired+1] .. " already requested, waiting on server")
    return
  end
  SetRaidTarget("mouseover", desired)
  pendingMarks[guid] = { mark = desired, t = GetTime() }
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
autoMarker:RegisterEvent("ZONE_CHANGED_NEW_AREA")

function autoMarker:Initialize()
  if not AutoMarkerDB then AutoMarkerDB = {} end
  if not AutoMarkerDB.customNpcsToMark then AutoMarkerDB.customNpcsToMark = {} end
  if not AutoMarkerDB.shifts then AutoMarkerDB.shifts = {} end

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
    pendingMarks = {}
    return
  end

  -- Compared by name because the event can also fire without leaving the zone.
  if event == "ZONE_CHANGED_NEW_AREA" then
    local zone = GetRealZoneText()
    if zone ~= votesZone then votes = {}; votesZone = zone end
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
  elseif command == "shift" then
    if packName == "reset" then
      AutoMarkerDB.shifts = {}
      votes = {}
      auto_print("AutoMarker: shifts cleared.")
    else
      local any
      for key, rec in pairs(AutoMarkerDB.shifts) do
        any = true
        auto_print(key .. ": " .. rec.shift .. " (set " .. date("%Y-%m-%d %H:%M", rec.t) .. ")")
      end
      if not any then auto_print("AutoMarker: no shifts stored.") end
    end
  elseif command == "debug" then
    AutoMarkerDB.settings.debug = not AutoMarkerDB.settings.debug
    auto_print(L["Debug mode set to: "] .. (AutoMarkerDB.settings.debug and c(L["on"], color.green) or c(L["off"], color.red)))
  else
    auto_print(L["Commands:"])
    auto_print("/am " .. c("e", color.green) .. "nable - toggle the addon")
    auto_print("/am " .. c("sweep", color.green) .. " <packname> - sweep mouse over mobs to add them; repeat or '/am sweep off' to cancel")
    auto_print("/am " .. c("c", color.green) .. "lear <packname> - delete a custom pack in this zone")
    auto_print("/am " .. c("reset", color.green) .. " - forget entry-pack mark assignments")
    auto_print("/am shift [reset] - show or clear learned GUID shifts")
    auto_print("/am debug - toggle debug print on each automark")
  end
end

SLASH_AUTOMARKER1 = "/automarker"
SLASH_AUTOMARKER2 = "/am"
SlashCmdList["AUTOMARKER"] = handleCommands
