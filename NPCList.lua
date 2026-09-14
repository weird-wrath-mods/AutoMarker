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


-- =========================================================
-- Ulduar (25-man, GUID-pinned)
--
-- Spawn GUIDs are stable across fresh 25-man instances: hallway pack 1 came
-- back byte-identical in four, Twilight pack 1 in two. A capture from an
-- instance that was not fresh had every Twilight counter exactly 14 lower, so
-- these pins come from fresh-instance sweeps. 10-man is not captured; its
-- extra/missing spawns may shift counters, so it needs its own sweeps.
-- Guardians and Trash are listed UNMARKED so a stray sweep never marks them.
-- =========================================================

-- Twilight packs (before General Vezax)
-- Priority: Adherent, Frost Mage, Pyromancer, Slayer, Shadowblade; icons in
-- the order Skull, Cross, Square, Moon, Star, Circle. Diamond and Triangle are
-- kept for the fire elementals.

-- Pyromancers summon the elementals on reset (63774), so their counters come
-- from the runtime generator: entry match only.
addEntryPack("Ulduar", "uld_fire_elementals", {
  [33838] = { DIAMOND, TRIANGLE }, -- Enslaved Fire Elemental
})

-- Upper-level pack
addPack("Ulduar", "uld_twilight_1_25", {
  ["0xF13000841A00038B"] = SKULL,    -- Twilight Adherent
  ["0xF13000841F00039C"] = CROSS,    -- Twilight Slayer
  ["0xF13000841F00039E"] = SQUARE,   -- Twilight Slayer
  ["0xF13000842000039D"] = MOON,     -- Twilight Shadowblade
  ["0xF13000842000039F"] = STAR,     -- Twilight Shadowblade
  ["0xF13000841E00039A"] = UNMARKED, -- Twilight Guardian
  ["0xF13000841E0003A0"] = UNMARKED, -- Twilight Guardian
})

-- Lower pack with the 25-man Slayer
addPack("Ulduar", "uld_twilight_2_25", {
  ["0xF13000841A00038A"] = SKULL,    -- Twilight Adherent
  ["0xF13000841A0003B8"] = CROSS,    -- Twilight Adherent
  ["0xF13000841B00038F"] = SQUARE,   -- Twilight Frost Mage
  ["0xF13000841B0003B9"] = MOON,     -- Twilight Frost Mage
  ["0xF13000841C000394"] = STAR,     -- Twilight Pyromancer
  ["0xF13000841F0003BA"] = CIRCLE,   -- Twilight Slayer
  ["0xF13000841E000399"] = UNMARKED, -- Twilight Guardian
  ["0xF13000841E0003BB"] = UNMARKED, -- Twilight Guardian
})

-- Lower pack, two Pyromancers
addPack("Ulduar", "uld_twilight_3_25", {
  ["0xF13000841A00038C"] = SKULL,    -- Twilight Adherent
  ["0xF13000841A0003B3"] = CROSS,    -- Twilight Adherent
  ["0xF13000841B000390"] = SQUARE,   -- Twilight Frost Mage
  ["0xF13000841B000391"] = MOON,     -- Twilight Frost Mage
  ["0xF13000841C000396"] = STAR,     -- Twilight Pyromancer
  ["0xF13000841C0003B6"] = CIRCLE,   -- Twilight Pyromancer
  ["0xF13000841E00039B"] = UNMARKED, -- Twilight Guardian
  ["0xF13000841E0003B5"] = UNMARKED, -- Twilight Guardian
})

-- Lower pack, two Pyromancers
addPack("Ulduar", "uld_twilight_4_25", {
  ["0xF13000841A000389"] = SKULL,    -- Twilight Adherent
  ["0xF13000841A0003A1"] = CROSS,    -- Twilight Adherent
  ["0xF13000841B00038D"] = SQUARE,   -- Twilight Frost Mage
  ["0xF13000841B00038E"] = MOON,     -- Twilight Frost Mage
  ["0xF13000841C000392"] = STAR,     -- Twilight Pyromancer
  ["0xF13000841C0003A3"] = CIRCLE,   -- Twilight Pyromancer
  ["0xF13000841E000398"] = UNMARKED, -- Twilight Guardian
  ["0xF13000841E0003A2"] = UNMARKED, -- Twilight Guardian
})

-- Mimiron hallway (Spark of Imagination corridor, before the tram)
-- Boomers (on-contact Bomb Bot blast) take the top icons, then Arachnopod
-- Destroyers, then Clockwork Sappers.

-- Pack 1: Arachnopod, 2 Boomers, 4 Trash
addPack("Ulduar", "uld_mim_1_25", {
  ["0xF130008590000377"] = SKULL,    -- Boomer XP-500
  ["0xF130008590000378"] = CROSS,    -- Boomer XP-500
  ["0xF15000858700036B"] = SQUARE,   -- Arachnopod Destroyer (vehicle GUID)
  ["0xF13000858F00036D"] = UNMARKED, -- Trash
  ["0xF13000858F00036E"] = UNMARKED, -- Trash
  ["0xF13000858F00036F"] = UNMARKED, -- Trash
  ["0xF13000858F000370"] = UNMARKED, -- Trash
})

-- Pack 2: Arachnopod, 2 Sappers, 6 Trash
addPack("Ulduar", "uld_mim_2_25", {
  ["0xF15000858700036C"] = SKULL,    -- Arachnopod Destroyer (vehicle GUID)
  ["0xF13000859100037B"] = CROSS,    -- Clockwork Sapper
  ["0xF13000859100037C"] = SQUARE,   -- Clockwork Sapper
  ["0xF13000858F000371"] = UNMARKED, -- Trash
  ["0xF13000858F000372"] = UNMARKED, -- Trash
  ["0xF13000858F000373"] = UNMARKED, -- Trash
  ["0xF13000858F000374"] = UNMARKED, -- Trash
  ["0xF13000858F000375"] = UNMARKED, -- Trash
  ["0xF13000858F000376"] = UNMARKED, -- Trash
})

-- Pack 3: 2 Arachnopods, 2 Boomers, 2 Sappers. Three of these sit at counters
-- 574-576, far past the rest of the hallway, but two captures in separate
-- instances returned the same GUIDs.
addPack("Ulduar", "uld_mim_3_25", {
  ["0xF130008590000379"] = SKULL,    -- Boomer XP-500
  ["0xF130008590000575"] = CROSS,    -- Boomer XP-500
  ["0xF15000858700036A"] = SQUARE,   -- Arachnopod Destroyer (vehicle GUID)
  ["0xF150008587000574"] = MOON,     -- Arachnopod Destroyer (vehicle GUID)
  ["0xF13000859100037A"] = UNMARKED, -- Clockwork Sapper
  ["0xF130008591000576"] = UNMARKED, -- Clockwork Sapper
})
