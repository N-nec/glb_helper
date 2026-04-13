So.. Blender exports as GLB... Mobs_Redo cant process the animations. so now anything defined as a mob with a GLB file plays its animations cleanly.

1 Create Mob, 
2 Define the mob under the Mobs Api

  mobs:register_mob("MyMod:Enemy", {
  ......
  Visuals...
        visual = "mesh",
        mesh = "zombie_torso.glb",  
        textures = {"zombie_texture.png"},
        .....       
Then Animation....
        animation = {
            speed_normal = 15,
            speed_run = 20,
            stand_start = 0,
            stand_end = 0,
            walk_start = 24,        n 
            walk_end = 58,
            run_start = 24,
            run_end = 58,
            punch_start = 40,
            punch_end = 45,
        },
    })

... 

It will spawn as Normal





It also has another key funtion i feel will be useful for many....

It can rotate entities.

If your mob mesh is facing the wrong direction (or needs a small pitch/roll tweak), you can live-tune it:

- Print current offsets: `/glb_mob mymod:my_mob`
- Nudge rotation (degrees): `/glb_mob mymod:my_mob rot y 5`
- Reset live override: `/glb_mob mymod:my_mob reset`

The command prints a `glb_helper_rot = {x=...,y=...,z=...}` snippet you can paste into the mob's `animation = { ... }` table.


im using it to help rotate my wielded item, then copy the new X Y Z into the lua file.




