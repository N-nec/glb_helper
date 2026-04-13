# glb_helper

Helpers for using Blender-authored *frame numbers* with Luanti/Minetest `.glb` / `.gltf` meshes.

Why this exists:

- For legacy `.b3d`, `ObjectRef:set_animation({x=START,y=END}, FPS, ...)` uses **frames** and **FPS**.
- For `.glb/.gltf`, Luanti currently treats the range as **seconds** and the speed as a **multiplier**.

This mod provides small helpers so you can keep writing `start_frame/end_frame` + `fps` in Lua.

## API

- `glb_helper.is_gltf_mesh(mesh)`
- `glb_helper.anim_range(mesh, start_frame, end_frame, source_fps)`
- `glb_helper.anim_speed(mesh, fps, source_fps)`
- `glb_helper.set_animation(object, start_frame, end_frame, fps, blend, loop, opts)`

Defaults:

- `source_fps` defaults to `glb_helper.DEFAULT_SOURCE_FPS` (24 unless configured)

## Settings

- `glb_helper_default_source_fps` (number, default 24)

## Rotation tuning (mobs_redo)

If your mob mesh is facing the wrong direction (or needs a small pitch/roll tweak), you can live-tune it:

- Print current offsets: `/glb_mob mymod:my_mob`
- Nudge rotation (degrees): `/glb_mob mymod:my_mob rot y 5`
- Reset live override: `/glb_mob mymod:my_mob reset`

The command prints a `glb_helper_rot = {x=...,y=...,z=...}` snippet you can paste into the mob's `animation = { ... }` table.

## Rotation tuning (entities)

For non-mob mesh entities (decorations, props, custom tool entities, etc.), you can live-tune a constant rotation offset:

- Print current offsets: `/glb_entity mymod:my_entity`
- Nudge rotation (degrees): `/glb_entity mymod:my_entity rot y 90`
- Reset live override: `/glb_entity mymod:my_entity reset`

Paste the printed `glb_helper_rot = {...}` into the entity definition table.

## Rotation tuning (wield3d)

If you use the `wield3d` mod (third-person hand items), you can tune the attach rotation for a specific item:

- Print current held item config: `/glb_wield`
- Nudge rotation (degrees): `/glb_wield rot y 10`
- Or specify an item explicitly: `/glb_wield mymod:my_tool rot y 10`
- Reset to wield3d defaults: `/glb_wield [itemname] reset`

The command prints a `wield3d.location["item"] = {...}` snippet you can paste into a mod.

## Mobs integration (optional)

If you use the `mobs` mod (mobs_redo), this mod can automatically convert mob animation tables from **frames + FPS** into **seconds + speed multiplier** when the mob mesh is `.glb/.gltf`.

How it works:

- On first animation play for a mob whose `mesh` ends in `.glb` or `.gltf`, `glb_helper` converts `self.animation` in-place.
- After conversion, the original mobs_redo `set_animation(...)` continues to work unchanged.

Per-mob source FPS (important):

By default, conversion assumes your glTF was exported from Blender at **24 FPS**. Override per mob by setting one of these inside the animation table:

- `animation.source_fps = 30`
- or `animation.glb_source_fps = 30`
- or `animation.gltf_source_fps = 30`

Disable per mob:

- `animation.glb_helper_disable = true`

Disable globally:

- `glb_helper_patch_mobs = false`

### Example (mobs_redo)

```lua
mobs:register_mob("mymod:my_mob", {
	visual = "mesh",
	mesh = "my_mob.glb",
	textures = {"my_mob.png"},
	animation = {
		source_fps = 24, -- match your Blender export FPS
		glb_helper_rot = {x = 0, y = 0, z = 0},
		stand_start = 0,  stand_end = 40, stand_speed = 15,
		walk_start  = 41, walk_end  = 80, walk_speed  = 20,
	},
})
```
