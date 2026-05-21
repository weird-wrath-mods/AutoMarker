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
BINDING_HEADER_AUTOMARK   = L["|cff22CC00 - AutoMark Bindings -"]
BINDING_NAME_MOUSEOVERKEY = L["Keys to hold to activate mouseover mark"]
BINDING_NAME_RUNKEY       = L["Mark mouseover or target"]
BINDING_NAME_NEXTKEY      = L["Mark next group based on default order"]

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
local ssub               = string.sub
local sgmatch            = string.gmatch
local tinsert            = table.insert
local tremove            = table.remove
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

local defaultSettings = { enabled = true, debug = false, automark = true }

local sweep_on = false
local sweepPackName = nil
local currentPackName = nil
local currentNpcsToMark = {}

local autoMarker = CreateFrame("Frame", "AutoMarkerFrame")

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

local function rememberGuid(guid, name)
  if not guid or not name then return end
  if ssub(guid, 3, 3) ~= "F" then return end
  AutoMarkerDB.unitCache[guid] = name
end

-- The core mechanism: on mouseover, if the GUID is in a known pack,
-- apply the pack's assigned mark using the "mouseover" token directly.
local function OnMouseover()
  if not AutoMarkerDB.settings.enabled then return end
  local guid = UnitGUID("mouseover")
  if not guid then return end
  local name = UnitName("mouseover")
  rememberGuid(guid, name)

  if not AutoMarkerDB.settings.automark then return end
  if not (IsShiftKeyDown() and IsControlKeyDown()) then return end
  if not PlayerCanMark() then return end

  local zone = GetRealZoneText()
  local pn, pack = guidToPack(guid, zone)
  if pn and pack and pack[guid] then
    local desired = pack[guid]
    local current = GetRaidTargetIndex("mouseover") or 0
    if current ~= desired then
      SetRaidTarget("mouseover", desired)
      if AutoMarkerDB.settings.debug then
        auto_print(c("AutoMarker: ", color.yellow)..(name or "?").." ("..guid..") "..raidMarks[current+1].." -> "..raidMarks[desired+1].." [pack: "..pn.."]")
      end
    end
  end
end

-- Called from sweep: stores the mouseover's GUID and its current raid mark in `pack`.
local function AddToPack(guid, pack)
  if not guid or not pack then return end

  local unitName = UnitName("mouseover") or AutoMarkerDB.unitCache[guid] or "<unknown>"
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
autoMarker:RegisterEvent("PLAYER_TARGET_CHANGED")
autoMarker:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

function autoMarker:Initialize()
  if not AutoMarkerDB then AutoMarkerDB = {} end
  if not AutoMarkerDB.customNpcsToMark then AutoMarkerDB.customNpcsToMark = {} end
  if not AutoMarkerDB.unitCache then AutoMarkerDB.unitCache = {} end

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

  auto_print(c(L["AutoMarker loaded!"], color.yellow) .. L[" Type "] .. c("/am", color.green) .. L[" to see commands."])
  auto_print(c("AutoMarker: ", color.orange).."mouseover-driven mode. Sweep cursor over mobs to mark.")
end

local function HandleEvent(self, event, ...)
  if event == "ADDON_LOADED" then
    if (...) == "AutoMarker" then self:Initialize() end
    return
  end
  if not (AutoMarkerDB and AutoMarkerDB.settings and AutoMarkerDB.settings.enabled) then return end

  if event == "UPDATE_MOUSEOVER_UNIT" then
    OnMouseover()
    if sweep_on then
      local g = UnitGUID("mouseover")
      if g then AddToPack(g, sweepPackName) end
    end
    return
  end
  if event == "PLAYER_TARGET_CHANGED" then
    local g, n = UnitGUID("target"), UnitName("target")
    if g and n then rememberGuid(g, n) end
    return
  end
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, _, sourceGUID, sourceName, _, destGUID, destName = ...
    rememberGuid(sourceGUID, sourceName)
    rememberGuid(destGUID, destName)
    return
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
  elseif command == "automark" then
    AutoMarkerDB.settings.automark = not AutoMarkerDB.settings.automark
    auto_print("Automark on mouseover: "..(AutoMarkerDB.settings.automark and c("on", color.green) or c("off", color.red)))
  elseif command == "set" or command == "s" then
    if not packName then auto_print(L["You must provide a pack name as well when using set."]); return end
    currentPackName = packName
    auto_print(L["Packname set to: "] .. c(currentPackName, color.orange))
  elseif command == "clear" or command == "c" then
    if currentPackName then
      if AutoMarkerDB.customNpcsToMark[zoneName] then
        AutoMarkerDB.customNpcsToMark[zoneName][currentPackName] = nil
        auto_print(L["Mobs in "] .. currentPackName .. L[" have been cleared."])
      end
    else
      auto_print(L["A packname isn't currently set."])
    end
  elseif command == "sweep" then
    local off_aliases = { off = true, stop = true, cancel = true, ["false"] = true }
    if sweep_on and (not packName or packName == sweepPackName or off_aliases[packName]) then
      sweep_on = false
      auto_print(L["Sweep mode [ "] .. c(L["off"], color.red) .. " ]")
      return
    end
    if off_aliases[packName] then return end
    local target = packName or currentPackName
    if not target then auto_print(L["Provide the pack name to this command as well or set one using "] .. c("/am set", color.yellow)); return end
    sweep_on = true; sweepPackName = target
    auto_print(L["Sweep mode [ "] .. c(L["on"], color.green) .. L[" ] sweep your mouse over enemies to add them to pack: "] .. c(sweepPackName, color.orange))
  elseif command == "debug" then
    AutoMarkerDB.settings.debug = not AutoMarkerDB.settings.debug
    auto_print(L["Debug mode set to: "] .. (AutoMarkerDB.settings.debug and c(L["on"], color.green) or c(L["off"], color.red)))
  else
    auto_print(L["Commands:"])
    auto_print("/am " .. c("e", color.green) .. "nable - toggle the addon")
    auto_print("/am " .. c("automark", color.green) .. " - toggle mouseover-automark (default on)")
    auto_print("/am " .. c("s", color.green) .. "et <packname> - set the current pack name for sweep")
    auto_print("/am " .. c("sweep", color.green) .. " [packname] - sweep mouse over mobs to add them to a pack; repeat or '/am sweep off' to cancel")
    auto_print("/am " .. c("c", color.green) .. "lear - clear the current custom pack")
    auto_print("/am debug - toggle debug print on each automark")
  end
end

SLASH_AUTOMARKER1 = "/automarker"
SLASH_AUTOMARKER2 = "/am"
SlashCmdList["AUTOMARKER"] = handleCommands
