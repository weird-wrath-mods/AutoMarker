-- AutoMarker pack data
-- Empty by design: full-GUID matching requires counters from the live
-- ChromieCraft world DB, which differ from the AzerothCore base SQL dump.
-- Packs below were captured live with /am sweep.

local L = AutoMarkerLocale

local SKULL=8 local CROSS=7 local SQUARE=6 local MOON=5
local TRIANGLE=4 local DIAMOND=3 local CIRCLE=2 local STAR=1 local UNMARKED=0

defaultNpcsToMark = {}
defaultEntryPacks = {}
orderedPacks = {}

local function addPack(instance, packName, npcs)
  defaultNpcsToMark[instance] = defaultNpcsToMark[instance] or {}
  defaultNpcsToMark[instance][packName] = npcs or {}
  table.insert(orderedPacks, { instance = instance, packName = packName })
end

-- Entry packs match on the creature_template entry carried in every GUID rather
-- than the whole GUID, for mobs whose spawn counter is allocated at runtime and
-- therefore differs every pull. Each entry maps to an ordered pool of marks;
-- pool length should equal the real add count, since a full pool is what tells
-- the addon a new cohort has replaced the old one.
local function addEntryPack(instance, packName, pools)
  defaultEntryPacks[instance] = defaultEntryPacks[instance] or {}
  defaultEntryPacks[instance][packName] = pools or {}
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
--
-- Matched on whole GUIDs rather than entry: every one of these is a creature
-- table spawn, and their GUIDs came back byte-identical across eight raid
-- nights, so a mark can be pinned to a specific mob. Pinning has no notion of
-- sweep order, which means marking one mob of a pack is always correct on its
-- own. Blaze Mistress (Flame Shock, Rain of Fire, Conjure Flame Orb) takes
-- skull, and a second one in the same pack takes cross. Sanctum Guardian
-- (Shockwave, Curse of Mending, Frenzy at 25-30%) gets a single skull per pair,
-- since they are pulled apart from the Mistresses and never compete for it.
-- =========================================================

-- Left side trash + patrol
addPack("The Obsidian Sanctum", "os_left_1", {
  ["0xF1300077D800001D"] = UNMARKED, -- Onyx Brood General
  ["0xF1300077D900001E"] = SKULL,    -- Onyx Blaze Mistress
  ["0xF1300077D900001F"] = CROSS,    -- Onyx Blaze Mistress
  ["0xF1300077DA000020"] = UNMARKED, -- Onyx Flight Captain
})

addPack("The Obsidian Sanctum", "os_left_2", {
  ["0xF1300076F5000045"] = SKULL,    -- Onyx Sanctum Guardian
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
  ["0xF1300076F50000A0"] = SKULL,    -- Onyx Sanctum Guardian
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
  ["0xF1300076F5000047"] = UNMARKED,    -- Onyx Sanctum Guardian
  ["0xF1300076F5000048"] = SKULL, -- Onyx Sanctum Guardian
})

-- =========================================================
-- Naxxramas (entry-matched)
-- =========================================================

-- Followers are the adds worth tracking: they carry Silence (54093, every
-- 11-15s) and Berserker Charge (56107, every 16-21s). Worshippers only Fireball
-- their current target, so they are left unmarked.
--
-- boss_faerlina.cpp summons both from SummonHelpers() rather than spawning them
-- from the creature table, so their GUID counters come from the runtime
-- generator and shift every pull; Reset() despawns and re-summons on each wipe.
-- Only the entry is stable. Exactly 2 Followers, and only on 25-man: the pair of
-- SummonCreature calls sit behind Is25ManRaid() and are the only references to
-- 16505 in the server source. On 10-man the pool simply goes unused.
--
-- Faerlina is matched by entry too. She is a real creature-table spawn, but her
-- live counter does not match the AzerothCore dump, so an entry avoids baking in
-- a GUID that is wrong for this server.
addEntryPack("Naxxramas", "faerlina", {
  [16505] = { SKULL, CROSS }, -- Naxxramas Follower
  [15953] = { TRIANGLE },     -- Grand Widow Faerlina
})
