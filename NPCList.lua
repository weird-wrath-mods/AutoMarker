-- AutoMarker pack data
-- Empty by design: full-GUID matching requires counters from the live
-- ChromieCraft world DB, which differ from the AzerothCore base SQL dump.
-- Packs below were captured live with /am sweep.

local L = AutoMarkerLocale

local SKULL=8 local CROSS=7 local SQUARE=6 local MOON=5
local TRIANGLE=4 local DIAMOND=3 local CIRCLE=2 local STAR=1 local UNMARKED=0

defaultNpcsToMark = {}
orderedPacks = {}

local function addPack(instance, packName, npcs)
  defaultNpcsToMark[instance] = defaultNpcsToMark[instance] or {}
  defaultNpcsToMark[instance][packName] = npcs or {}
  table.insert(orderedPacks, { instance = instance, packName = packName })
end

-- =========================================================
-- Thunder Bluff (mouseover-marking smoke test)
-- =========================================================

addPack("Thunder Bluff", "foo2", {
  ["0xF130007F9A001824"] = SKULL,    -- Expert Training Dummy
  ["0xF130007F9A001825"] = CROSS,    -- Expert Training Dummy
  ["0xF130000C0C0017AA"] = SQUARE,   -- Bluffwatcher
  ["0xF130007F9B001826"] = MOON,     -- Heroic Training Dummy
  ["0xF130007F9B001827"] = TRIANGLE, -- Heroic Training Dummy
})

-- =========================================================
-- The Obsidian Sanctum (10 and 25 share spawn GUIDs)
-- Entries: 30453 Onyx Sanctum Guardian, 30680 Onyx Brood General,
--          30681 Onyx Blaze Mistress, 30682 Onyx Flight Captain
-- =========================================================

-- Left side trash + patrol
addPack("The Obsidian Sanctum", "os_left_1", {
  ["0xF1300077D800001D"] = UNMARKED, -- Onyx Brood General
  ["0xF1300077D900001E"] = SKULL,    -- Onyx Blaze Mistress
  ["0xF1300077D900001F"] = CROSS,    -- Onyx Blaze Mistress
  ["0xF1300077DA000020"] = UNMARKED, -- Onyx Flight Captain
})

addPack("The Obsidian Sanctum", "os_left_2", {
  ["0xF1300076F5000045"] = UNMARKED, -- Onyx Sanctum Guardian
  ["0xF1300076F5000046"] = UNMARKED, -- Onyx Sanctum Guardian
})

addPack("The Obsidian Sanctum", "os_left_3", {
  ["0xF1300077D8000041"] = UNMARKED, -- Onyx Brood General
  ["0xF1300077D9000042"] = SKULL,    -- Onyx Blaze Mistress
  ["0xF1300077DA000043"] = UNMARKED, -- Onyx Flight Captain
  ["0xF1300077DA000044"] = UNMARKED, -- Onyx Flight Captain
})

-- Right side trash + patrol
addPack("The Obsidian Sanctum", "os_right_1", {
  ["0xF1300077D800005E"] = UNMARKED, -- Onyx Brood General
  ["0xF1300077D900005F"] = SKULL,    -- Onyx Blaze Mistress
  ["0xF1300077DA000060"] = UNMARKED, -- Onyx Flight Captain
  ["0xF1300077DA000061"] = UNMARKED, -- Onyx Flight Captain
})

addPack("The Obsidian Sanctum", "os_right_2", {
  ["0xF1300076F50000A0"] = UNMARKED, -- Onyx Sanctum Guardian
  ["0xF1300076F50000A1"] = UNMARKED, -- Onyx Sanctum Guardian
})

addPack("The Obsidian Sanctum", "os_right_3", {
  ["0xF1300077D800009B"] = UNMARKED, -- Onyx Brood General
  ["0xF1300077D900009C"] = CROSS,    -- Onyx Blaze Mistress
  ["0xF1300077D900009D"] = SKULL,    -- Onyx Blaze Mistress
  ["0xF1300077DA00009E"] = UNMARKED, -- Onyx Flight Captain
})

-- Shared center patrol (was os_left_4 / os_right_4 with identical GUIDs)
addPack("The Obsidian Sanctum", "os_patrol_shared", {
  ["0xF1300076F5000047"] = UNMARKED, -- Onyx Sanctum Guardian
  ["0xF1300076F5000048"] = UNMARKED, -- Onyx Sanctum Guardian
})
