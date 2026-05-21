# AutoMarker

Mouseover-driven raid marking for WoW 3.3.5a.

Hold `Ctrl` + `Shift` and sweep your cursor across a pull. Mobs defined in
a pack snap to their assigned raid mark instantly.

## Commands

- `/am enable` - master toggle
- `/am automark` - toggle mouseover-automark (default on)
- `/am set <packname>` - sets the pack name used by sweep when no name is passed
- `/am sweep [packname]` - start sweep mode; mouseover mobs to add them to the pack with their current raid mark. Repeat, pass the same pack name, or `/am sweep off` to cancel.
- `/am clear` - clear the pack named by `/am set`
- `/am debug` - print every automark application

## Defining a pack

```
/am sweep my_pack
```

Mouseover each mob. To set marks, target a mob and apply a mark via the
standard raid icon UI, then mouseover during sweep to record.

## Permissions

Solo marking works on this server. In a group you must be party leader or
raid leader/assist.
