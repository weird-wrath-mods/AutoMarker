# AutoMarker

Mouseover-driven raid marking for WoW 3.3.5a.

Hold `Ctrl` + `Shift` and sweep your cursor across a pull. Mobs defined in
a pack snap to their assigned raid mark instantly.

## Commands

- `/am enable` - master toggle
- `/am sweep <packname>` - start sweep mode; mouseover mobs to add them to the pack with their current raid mark. Repeat the command, pass the same pack name, or `/am sweep off` to cancel.
- `/am clear <packname>` - delete a custom pack in this zone
- `/am reset` - forget entry-pack mark assignments
- `/am debug` - print every automark application

## Pack types

**GUID packs** pin a mark to one specific spawn. They suit mobs placed by the
creature table, whose GUID is the same every night. Pinning has no notion of
sweep order, so marking a single mob of a pack is always correct on its own.
Capture them with `/am sweep`. Obsidian Sanctum trash works this way.

**Entry packs** match only the creature entry carried in the GUID. They exist for
mobs summoned by a boss script, whose spawn counter is handed out at runtime and
differs every pull, so no GUID can be pinned to them. An entry maps to an ordered
pool of marks and each mob you sweep claims the next slot; sweeping the same mob
twice will not reshuffle it. Faerlina's adds work this way.

Entry pools are **pull-scoped**: they reset when you leave combat. Nothing about
a mouseover can distinguish "still marking this pull" from "same mob type, next
pull", so combat end supplies that signal. You can therefore sweep as few mobs as
you like and the next pull still starts at the top of the pool. A wipe ends
combat too, which covers the boss re-summoning its adds with new GUIDs.

As a mid-combat backstop, a full pool plus a mob nobody has seen also means the
previous cohort is gone, and reassigns from the top. `/am reset` forces a reset
by hand.

Entry packs live in `NPCList.lua` and are not captured in-game, since an entry is
knowable up front from the server script.

## Defining a pack

```
/am sweep my_pack
```

Mouseover each mob. To set marks, target a mob and apply a mark via the
standard raid icon UI, then mouseover during sweep to record.

## Permissions

Solo marking works on this server. In a group you must be party leader or
raid leader/assist.

___
Made by and for Weird Vibes