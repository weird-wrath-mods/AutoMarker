-- AutoMarker pack data
-- Empty by design: full-GUID matching requires counters from the live
-- ChromieCraft world DB, which differ from the AzerothCore base SQL dump.
-- Packs below were captured live with /am sweep.

local L = AutoMarkerLocale

local SKULL=8 local CROSS=7 local SQUARE=6 local MOON=5
local TRIANGLE=4 local DIAMOND=3 local CIRCLE=2 local STAR=1 local UNMARKED=0

defaultNpcsToMark = {}
defaultEntryPacks = {}
defaultPackRaidSize = {}
orderedPacks = {}

-- raidSize limits a pack to 10- or 25-man instances. It is needed wherever the
-- two sizes spawn different mobs: the creation counter then lands on different
-- mobs, and the same GUID string can name another mob in the other size.
local function addPack(instance, packName, npcs, raidSize)
  defaultNpcsToMark[instance] = defaultNpcsToMark[instance] or {}
  defaultNpcsToMark[instance][packName] = npcs or {}
  if raidSize then
    defaultPackRaidSize[instance] = defaultPackRaidSize[instance] or {}
    defaultPackRaidSize[instance][packName] = raidSize
  end
  table.insert(orderedPacks, { instance = instance, packName = packName })
end

-- A shift group is a set of GUID packs whose counters move together when the
-- instance map loads differently (a rebuild after kills, a server update). Every
-- pinned mob votes on the shift; the anchor, pack 1's only mob of its type,
-- breaks ties, since pack 1 is always the first pack pulled.
defaultShiftGroups = {}
local function addShiftGroup(instance, name, raidSize, anchor, packNames)
  defaultShiftGroups[instance] = defaultShiftGroups[instance] or {}
  local packs = {}
  for _, p in ipairs(packNames) do packs[p] = true end
  table.insert(defaultShiftGroups[instance],
    { name = name, raidSize = raidSize, anchor = anchor, packs = packs })
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
-- Ulduar (GUID-pinned, separate 10- and 25-man packs)
--
-- The counter in a GUID is the mob's place in the order the instance creates
-- units at load: grid by grid, then by spawn id. It holds for the life of one
-- instance map, but a map rebuilt mid-lockout (restart, or empty past the unload
-- delay) skips the load-time summons of dead bosses and shifts every later
-- counter: a non-fresh capture had every Twilight counter exactly 14 lower. So
-- these pins match fresh instances only.
-- Guardians and Trash are listed UNMARKED so a stray sweep never marks them.
-- =========================================================

-- Scrapyard (before XT-002)
-- Technicians cast Defense Matrix (65070) on a damaged ally within 29 yards, so
-- they die first. Four creature-table spawns shared by both raid sizes, two on
-- each side of the yard: diamond and triangle per side, the pool restarting when
-- combat ends between sides. Entry-matched because no live sweep of their
-- counters exists, and the dump's counters do not match this server.
addEntryPack("Ulduar", "uld_scrapyard", {
  [34267] = { DIAMOND, TRIANGLE }, -- Parts Recovery Technician
})

-- Storm Tempered Keepers (before Thorim and Hodir's wings)
-- Four pairs, each one 33699 and one 33722. Both entries share a pool so the
-- first keeper swept takes skull whichever type it is. Entry-matched to cover
-- all four pairs in both raid sizes without depending on load-order counters.
local keeperMarks = { SKULL, CROSS }
addEntryPack("Ulduar", "uld_keepers", {
  [33699] = keeperMarks, -- Storm Tempered Keeper
  [33722] = keeperMarks, -- Storm Tempered Keeper
})

-- Twilight packs (before General Vezax)
-- Priority: Adherent, Frost Mage, Pyromancer, Slayer, Shadowblade; icons in
-- the order Skull, Cross, Square, Moon, Star, Circle. Diamond and Triangle are
-- kept for the fire elementals, except in the upper pack: it has no Pyromancer
-- to summon one, so its second Shadowblade takes Triangle instead of Star.

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
  ["0xF13000842000039F"] = TRIANGLE, -- Twilight Shadowblade
  ["0xF13000841E00039A"] = UNMARKED, -- Twilight Guardian
  ["0xF13000841E0003A0"] = UNMARKED, -- Twilight Guardian
}, 25)

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
}, 25)

-- Lower pack, two Pyromancers
addPack("Ulduar", "uld_twilight_3_25", {
  ["0xF13000841A00038C"] = SKULL,    -- Twilight Adherent
  ["0xF13000841A0003B3"] = CROSS,    -- Twilight Adherent
  ["0xF13000841B000391"] = SQUARE,   -- Twilight Frost Mage
  ["0xF13000841B000390"] = MOON,     -- Twilight Frost Mage
  ["0xF13000841C000396"] = STAR,     -- Twilight Pyromancer
  ["0xF13000841C0003B6"] = CIRCLE,   -- Twilight Pyromancer
  ["0xF13000841E00039B"] = UNMARKED, -- Twilight Guardian
  ["0xF13000841E0003B5"] = UNMARKED, -- Twilight Guardian
}, 25)

-- Lower pack, two Pyromancers
addPack("Ulduar", "uld_twilight_4_25", {
  ["0xF13000841A000389"] = SKULL,    -- Twilight Adherent
  ["0xF13000841A0003A1"] = CROSS,    -- Twilight Adherent
  ["0xF13000841B00038D"] = MOON,   -- Twilight Frost Mage
  ["0xF13000841B00038E"] = SQUARE,     -- Twilight Frost Mage
  ["0xF13000841C000392"] = STAR,     -- Twilight Pyromancer
  ["0xF13000841C0003A3"] = CIRCLE,   -- Twilight Pyromancer
  ["0xF13000841E000398"] = UNMARKED, -- Twilight Guardian
  ["0xF13000841E0003A2"] = UNMARKED, -- Twilight Guardian
}, 25)

-- Mimiron hallway (Spark of Imagination corridor, before the tram)
-- Pack 1: Arachnopod skull. Packs 2 and 3: Sappers skull and cross, then
-- Arachnopods (pack 3's second takes triangle). Boomers go unmarked.

-- Pack 1: Arachnopod, 2 Boomers, 4 Trash
addPack("Ulduar", "uld_mim_1_25", {
  ["0xF15000858700036B"] = SKULL,    -- Arachnopod Destroyer (vehicle GUID)
  ["0xF130008590000377"] = UNMARKED, -- Boomer XP-500
  ["0xF130008590000378"] = UNMARKED, -- Boomer XP-500
  ["0xF13000858F00036D"] = UNMARKED, -- Trash
  ["0xF13000858F00036E"] = UNMARKED, -- Trash
  ["0xF13000858F00036F"] = UNMARKED, -- Trash
  ["0xF13000858F000370"] = UNMARKED, -- Trash
}, 25)

-- Pack 2: Arachnopod, 2 Sappers, 6 Trash
addPack("Ulduar", "uld_mim_2_25", {
  ["0xF13000859100037C"] = SKULL,    -- Clockwork Sapper
  ["0xF13000859100037B"] = CROSS,    -- Clockwork Sapper
  ["0xF15000858700036C"] = SQUARE,   -- Arachnopod Destroyer (vehicle GUID)
  ["0xF13000858F000371"] = UNMARKED, -- Trash
  ["0xF13000858F000372"] = UNMARKED, -- Trash
  ["0xF13000858F000373"] = UNMARKED, -- Trash
  ["0xF13000858F000374"] = UNMARKED, -- Trash
  ["0xF13000858F000375"] = UNMARKED, -- Trash
  ["0xF13000858F000376"] = UNMARKED, -- Trash
}, 25)

-- Pack 3: 2 Arachnopods, 2 Boomers, 2 Sappers. Three of these sit at counters
-- 574-576, far past the rest of the hallway, but two captures in separate
-- instances returned the same GUIDs.
addPack("Ulduar", "uld_mim_3_25", {
  ["0xF13000859100037A"] = SKULL,    -- Clockwork Sapper
  ["0xF130008591000576"] = CROSS,    -- Clockwork Sapper
  ["0xF15000858700036A"] = SQUARE,   -- Arachnopod Destroyer (vehicle GUID)
  ["0xF150008587000574"] = TRIANGLE, -- Arachnopod Destroyer (vehicle GUID)
  ["0xF130008590000379"] = UNMARKED, -- Boomer XP-500
  ["0xF130008590000575"] = UNMARKED, -- Boomer XP-500
}, 25)

-- Ulduar 10-man
--
-- Laid out from the server's creature table (spawn-id order within the grid,
-- plus one counter after each Pyromancer for the elemental it summons at load)
-- and anchored by an 11-mob PTR sweep of a fresh 10-man, which fit this layout
-- at exactly one base. 10-man spawns the same hallway mobs as 25 but fewer
-- Twilight ones, so the marks follow the same priority over a smaller pack.
-- Twilight upper pack
addPack("Ulduar", "uld_twilight_1_10", {
  ["0xF13000841A00038A"] = SKULL,    -- Twilight Adherent
  ["0xF13000841F00039B"] = CROSS,    -- Twilight Slayer
  ["0xF13000842000039D"] = SQUARE,   -- Twilight Shadowblade
  ["0xF13000841E000399"] = UNMARKED, -- Twilight Guardian
}, 10)

-- Twilight lower east pack
addPack("Ulduar", "uld_twilight_2_10", {
  ["0xF13000841A000389"] = SKULL,    -- Twilight Adherent
  ["0xF13000841B00038E"] = CROSS,    -- Twilight Frost Mage
  ["0xF13000841C000393"] = MOON,   -- Twilight Pyromancer
  ["0xF13000842000039C"] = SQUARE,     -- Twilight Shadowblade
  ["0xF13000841E000398"] = UNMARKED, -- Twilight Guardian
}, 10)

-- Twilight lower middle pack
addPack("Ulduar", "uld_twilight_3_10", {
  ["0xF13000841A00038B"] = SKULL,    -- Twilight Adherent
  ["0xF13000841B00038F"] = CROSS,    -- Twilight Frost Mage
  ["0xF13000841B000390"] = SQUARE,   -- Twilight Frost Mage
  ["0xF13000841C000395"] = MOON,     -- Twilight Pyromancer
  ["0xF13000841E00039A"] = UNMARKED, -- Twilight Guardian
}, 10)

-- Twilight lower west pack
addPack("Ulduar", "uld_twilight_4_10", {
  ["0xF13000841A000388"] = SKULL,    -- Twilight Adherent
  ["0xF13000841B00038C"] = CROSS,    -- Twilight Frost Mage
  ["0xF13000841B00038D"] = SQUARE,   -- Twilight Frost Mage
  ["0xF13000841C000391"] = MOON,     -- Twilight Pyromancer
  ["0xF13000841E000397"] = UNMARKED, -- Twilight Guardian
}, 10)

-- Mimiron hallway pack 1
addPack("Ulduar", "uld_mim_1_10", {
  ["0xF15000858700036C"] = SKULL,    -- Arachnopod Destroyer (vehicle GUID)
  ["0xF130008590000378"] = UNMARKED, -- Boomer XP-500
  ["0xF130008590000379"] = UNMARKED, -- Boomer XP-500
  ["0xF13000858F00036E"] = UNMARKED, -- Trash
  ["0xF13000858F00036F"] = UNMARKED, -- Trash
  ["0xF13000858F000370"] = UNMARKED, -- Trash
  ["0xF13000858F000371"] = UNMARKED, -- Trash
}, 10)

-- Mimiron hallway pack 2
addPack("Ulduar", "uld_mim_2_10", {
  ["0xF13000859100037D"] = SKULL,    -- Clockwork Sapper
  ["0xF13000859100037C"] = CROSS,    -- Clockwork Sapper
  ["0xF15000858700036D"] = SQUARE,   -- Arachnopod Destroyer (vehicle GUID)
  ["0xF13000858F000372"] = UNMARKED, -- Trash
  ["0xF13000858F000373"] = UNMARKED, -- Trash
  ["0xF13000858F000374"] = UNMARKED, -- Trash
  ["0xF13000858F000375"] = UNMARKED, -- Trash
  ["0xF13000858F000376"] = UNMARKED, -- Trash
  ["0xF13000858F000377"] = UNMARKED, -- Trash
}, 10)

-- Mimiron hallway pack 3. Its late Arachnopod, Boomer and Sapper load from a
-- later grid the creature table cannot place, so they come from a 10-man sweep.
addPack("Ulduar", "uld_mim_3_10", {
  ["0xF13000859100037B"] = SKULL,    -- Clockwork Sapper
  ["0xF13000859100055C"] = CROSS,    -- Clockwork Sapper
  ["0xF15000858700036B"] = SQUARE,   -- Arachnopod Destroyer (vehicle GUID)
  ["0xF15000858700055A"] = TRIANGLE, -- Arachnopod Destroyer (vehicle GUID)
  ["0xF13000859000037A"] = UNMARKED, -- Boomer XP-500
  ["0xF13000859000055B"] = UNMARKED, -- Boomer XP-500
}, 10)

-- Ulduar shift groups. Twilight anchors on the upper pack's lone Adherent and
-- the hallway on pack 1's Arachnopod. Hallway pack 3's late mobs load from a
-- later grid and could in principle shift further; they ride the same shift.
addShiftGroup("Ulduar", "twilight", 25, "0xF13000841A00038B",
  { "uld_twilight_1_25", "uld_twilight_2_25", "uld_twilight_3_25", "uld_twilight_4_25" })
addShiftGroup("Ulduar", "twilight", 10, "0xF13000841A00038A",
  { "uld_twilight_1_10", "uld_twilight_2_10", "uld_twilight_3_10", "uld_twilight_4_10" })
addShiftGroup("Ulduar", "mimiron", 25, "0xF15000858700036B",
  { "uld_mim_1_25", "uld_mim_2_25", "uld_mim_3_25" })
addShiftGroup("Ulduar", "mimiron", 10, "0xF15000858700036C",
  { "uld_mim_1_10", "uld_mim_2_10", "uld_mim_3_10" })
