# AutoMarker 1.22.2-wrath-test

3.3.5a port of the 1.12 SuperWoW AutoMarker, made to test whether
GUID-based automark is feasible on the Wrath client.

## Test outcome (what to expect)

Vanilla AutoMarker relies on SuperWoW's "GUIDs are unit tokens" feature.
3.3.5a does not allow this: `SetRaidTarget("0xF130...", 8)` is a no-op.

This build replaces SuperWoW with a runtime resolver that scans every
unit token reachable in 3.3.5a (target, mouseover, focus, party*target,
raid*target, *targettarget, partypet*, raidpet*, mark1-8) and calls
SetRaidTarget on whichever token currently resolves to the desired GUID.

Implications:
- Marking the pull when you mouseover/target a member: works
- Marking pack mates that show up via raid/party member targets: works
- Marking unseen mobs (no one in your group has them targeted): impossible without a client mod

## In-game test commands

- `/am test` - skull-mark current target via the resolver, prints before/after mark index
- `/am scan` - shows how many cached GUIDs currently resolve to a unit token
- `/am debug` - toggles per-call diagnostic output on `/am mark`

## Known unported behavior

- UnitPopup right-click solo marks (1.12 SuperWoW): cannot be replicated, removed
- `nampower` _GUID event variants: removed
- UNIT_MODEL_CHANGED-driven discovery (script-spawned adds): replaced with combat-log discovery, so some live-mark mechanics will only fire after a mob takes/deals damage
- NPCList.lua GUIDs are Turtle WoW server values; on Chromie they will not match. Use `/am add` to record server-specific GUIDs into custom packs

## Original commands (preserved)

- `/am set <packname>` (alias `/am s`)
- `/am get` (alias `/am g`)
- `/am clear` (alias `/am c`)
- `/am add [packname]` (alias `/am a`)
- `/am sweep [packname]`
- `/am remove` (alias `/am r`)
- `/am clearmarks`
- `/am next`
- `/am mark`
- `/am markname <unit name>`
- `/am debug`

___
Original by Weird Vibes of Turtle WoW.
