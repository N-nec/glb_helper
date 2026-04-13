-- glb_helper/init.lua

local GH = rawget(_G, "glb_helper")
if type(GH) ~= "table" then
    GH = {}
    _G.glb_helper = GH
end

GH.DEFAULT_SOURCE_FPS = tonumber(minetest.settings:get("glb_helper_default_source_fps")) or 24

-- Live (non-persistent) debug rotation overrides for mobs_redo entities.
-- Stored as degrees so users can copy/paste into mob defs.
GH._mob_rot_overrides = GH._mob_rot_overrides or {}

-- Live (non-persistent) debug rotation overrides for arbitrary entities.
-- Stored as degrees.
GH._entity_rot_overrides = GH._entity_rot_overrides or {}
GH._patched_entities = GH._patched_entities or {}

local function normalize_ext(s)
    s = tostring(s or "")
    -- case-insensitive extension check
    return s:lower()
end

function GH.is_gltf_mesh(mesh)
    local m = normalize_ext(mesh)
    return m:sub(-4) == ".glb" or m:sub(-5) == ".gltf"
end

local function get_mesh_from_object(object)
    if not object or type(object) ~= "userdata" then
        return nil
    end
    local ok, props = pcall(object.get_properties, object)
    if not ok or type(props) ~= "table" then
        return nil
    end
    return props.mesh
end

local function get_source_fps(opts)
    if type(opts) == "table" and tonumber(opts.source_fps) then
        return tonumber(opts.source_fps)
    end
    return GH.DEFAULT_SOURCE_FPS
end

function GH.anim_speed(mesh, fps, source_fps)
    source_fps = tonumber(source_fps) or GH.DEFAULT_SOURCE_FPS
    if GH.is_gltf_mesh(mesh) then
        return (tonumber(fps) or 0) / source_fps
    end
    return tonumber(fps)
end

function GH.anim_range(mesh, start_frame, end_frame, source_fps)
    source_fps = tonumber(source_fps) or GH.DEFAULT_SOURCE_FPS
    if GH.is_gltf_mesh(mesh) then
        return {
            x = (tonumber(start_frame) or 0) / source_fps,
            y = (tonumber(end_frame) or 0) / source_fps,
        }
    end
    return {x = tonumber(start_frame) or 0, y = tonumber(end_frame) or 0}
end

-- Wrapper: set animation by Blender frames + FPS.
-- opts:
--   source_fps (number)  - source/export FPS used in Blender/glTF
--   mesh (string)        - override mesh detection instead of reading object props
function GH.set_animation(object, start_frame, end_frame, fps, blend, loop, opts)
    if not object then
        return
    end
    local mesh = (type(opts) == "table" and type(opts.mesh) == "string" and opts.mesh ~= "") and opts.mesh
        or get_mesh_from_object(object)
    local source_fps = get_source_fps(opts)

    local range = GH.anim_range(mesh, start_frame, end_frame, source_fps)
    local speed = GH.anim_speed(mesh, fps, source_fps)

    -- blend/loop are passed through unchanged; most code uses blend=0.
    local ok = pcall(object.set_animation, object, range, speed, tonumber(blend) or 0, loop and true or false)
    if not ok then
        -- Keep silent: this helper should never crash the caller.
    end
end

local function fmt_vec_deg(v)
    v = v or {}
    return "{x = " .. string.format("%.3f", tonumber(v.x) or 0)
        .. ", y = " .. string.format("%.3f", tonumber(v.y) or 0)
        .. ", z = " .. string.format("%.3f", tonumber(v.z) or 0) .. "}"
end

local function fmt_vec2(v)
    v = v or {}
    return "{x = " .. string.format("%.3f", tonumber(v.x) or 0)
        .. ", y = " .. string.format("%.3f", tonumber(v.y) or 0) .. "}"
end

local function vec3(v)
    if type(v) ~= "table" then
        return {x = 0, y = 0, z = 0}
    end
    return {
        x = tonumber(v.x) or 0,
        y = tonumber(v.y) or 0,
        z = tonumber(v.z) or 0,
    }
end

-- Debug command: live tweak mobs_redo model orientation.
-- Usage:
--   /glb_mob <entityname>
--   /glb_mob <entityname> rot <x|y|z> <delta_deg>
--   /glb_mob <entityname> reset
minetest.register_chatcommand("glb_mob", {
    params = "<entityname> [rot|reset|get|help] ...",
    description = "Debug: nudge glTF mob rotation offsets (mobs_redo)",
    privs = {server = true},
    func = function(name, param)
        local args = {}
        for w in tostring(param or ""):gmatch("%S+") do
            args[#args + 1] = w
        end

        local entname = args[1]
        local action = args[2]

        if not entname or entname == "" or entname == "help" then
            return true,
                "Usage:\n"
                .. "/glb_mob <entityname>\n"
                .. "/glb_mob <entityname> rot <x|y|z> <delta_deg>\n"
                .. "/glb_mob <entityname> reset\n\n"
                .. "Tip: copy the printed 'glb_helper_rot = {...}' into your mobs_redo animation table."
        end

        local function print_cfg()
            local def = minetest.registered_entities[entname]
            local mesh = def and (def.mesh or (def.initial_properties and def.initial_properties.mesh))
            local is_gltf = GH.is_gltf_mesh(mesh)
            local live = vec3(GH._mob_rot_overrides[entname])
            return true,
                entname
                .. "\nmesh = " .. tostring(mesh)
                .. "\nis_gltf = " .. tostring(is_gltf)
                .. "\n\n-- Paste into your mob's animation table:\n"
                .. "glb_helper_rot = " .. fmt_vec_deg(live)
        end

        if not action or action == "get" or action == "print" then
            return print_cfg()
        end

        if action == "reset" then
            GH._mob_rot_overrides[entname] = nil
            return print_cfg()
        end

        if action ~= "rot" then
            return false, "Expected 'rot', 'reset', or 'get'. Try /glb_mob help"
        end

        local axis = args[3]
        local delta = tonumber(args[4])
        if axis ~= "x" and axis ~= "y" and axis ~= "z" then
            return false, "Axis must be x, y, or z."
        end
        if delta == nil then
            return false, "Delta must be a number (degrees)."
        end

        local v = vec3(GH._mob_rot_overrides[entname])
        v[axis] = (tonumber(v[axis]) or 0) + delta
        GH._mob_rot_overrides[entname] = v
        return print_cfg()
    end,
})

-- Debug command: live tweak *any* entity mesh orientation.
-- Intended for mesh entities that need a constant pitch/roll and/or yaw offset.
-- Usage:
--   /glb_entity <entityname>
--   /glb_entity <entityname> rot <x|y|z> <delta_deg>
--   /glb_entity <entityname> reset
local function get_entity_rot_offset_deg(entname)
    local def = minetest.registered_entities[entname]
    local from_def = (type(def) == "table") and def.glb_helper_rot or {}
    local from_live = GH._entity_rot_overrides[entname] or {}
    local a = vec3(from_def)
    local b = vec3(from_live)
    return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
end

local function apply_entity_rotation_offsets(entname, luaent)
    if type(luaent) ~= "table" or not luaent.object then
        return
    end

    local rot_deg = get_entity_rot_offset_deg(entname)
    local rx = tonumber(rot_deg.x) or 0
    local ry = tonumber(rot_deg.y) or 0
    local rz = tonumber(rot_deg.z) or 0
    if rx == 0 and ry == 0 and rz == 0 then
        return
    end

    local obj = luaent.object
    local yaw = 0
    local ok_yaw, v = pcall(obj.get_yaw, obj)
    if ok_yaw and type(v) == "number" then
        yaw = v
    end
    yaw = yaw + math.rad(ry)

    -- If only yaw is being adjusted, avoid clobbering pitch/roll.
    if rx == 0 and rz == 0 then
        if type(obj.set_yaw) == "function" then
            pcall(obj.set_yaw, obj, yaw)
        elseif type(obj.set_rotation) == "function" then
            pcall(obj.set_rotation, obj, {x = 0, y = yaw, z = 0})
        end
        return
    end

    if type(obj.set_rotation) == "function" then
        pcall(obj.set_rotation, obj, {
            x = math.rad(rx),
            y = yaw,
            z = math.rad(rz),
        })
    elseif type(obj.set_yaw) == "function" then
        pcall(obj.set_yaw, obj, yaw)
    end
end

local function patch_entity_rotation(entname)
    if GH._patched_entities[entname] then
        return true
    end

    local def = minetest.registered_entities[entname]
    if type(def) ~= "table" then
        return false
    end

    local orig_activate = def.on_activate
    local orig_step = def.on_step

    def.on_activate = function(self, staticdata, dtime_s)
        local ret
        if type(orig_activate) == "function" then
            ret = orig_activate(self, staticdata, dtime_s)
        end
        apply_entity_rotation_offsets(entname, self)
        return ret
    end

    def.on_step = function(self, dtime, moveresult)
        local ret
        if type(orig_step) == "function" then
            ret = orig_step(self, dtime, moveresult)
        end
        apply_entity_rotation_offsets(entname, self)
        return ret
    end

    GH._patched_entities[entname] = {
        on_activate = orig_activate,
        on_step = orig_step,
    }
    return true
end

minetest.register_chatcommand("glb_entity", {
    params = "<entityname> [rot|reset|get|help] ...",
    description = "Debug: nudge entity rotation offsets (mesh orientation)",
    privs = {server = true},
    func = function(name, param)
        local args = {}
        for w in tostring(param or ""):gmatch("%S+") do
            args[#args + 1] = w
        end

        local entname = args[1]
        local action = args[2]

        if not entname or entname == "" or entname == "help" then
            return true,
                "Usage:\n"
                .. "/glb_entity <entityname>\n"
                .. "/glb_entity <entityname> rot <x|y|z> <delta_deg>\n"
                .. "/glb_entity <entityname> reset\n\n"
                .. "Tip: copy the printed 'glb_helper_rot = {...}' into your entity definition table."
        end

        local function print_cfg()
            local def = minetest.registered_entities[entname]
            local mesh = def and (def.mesh or (def.initial_properties and def.initial_properties.mesh))
            local is_gltf = GH.is_gltf_mesh(mesh)
            local live = vec3(GH._entity_rot_overrides[entname])
            local total = get_entity_rot_offset_deg(entname)
            return true,
                entname
                .. "\nmesh = " .. tostring(mesh)
                .. "\nis_gltf = " .. tostring(is_gltf)
                .. "\n\n-- Live override only:\n"
                .. "override = " .. fmt_vec_deg(live)
                .. "\n\n-- Paste into your entity definition table:\n"
                .. "glb_helper_rot = " .. fmt_vec_deg(total)
        end

        if type(minetest.registered_entities[entname]) ~= "table" then
            return false, "Unknown entity: " .. tostring(entname)
        end

        patch_entity_rotation(entname)

        if not action or action == "get" or action == "print" then
            return print_cfg()
        end

        if action == "reset" then
            GH._entity_rot_overrides[entname] = nil
            return print_cfg()
        end

        if action ~= "rot" then
            return false, "Expected 'rot', 'reset', or 'get'. Try /glb_entity help"
        end

        local axis = args[3]
        local delta = tonumber(args[4])
        if axis ~= "x" and axis ~= "y" and axis ~= "z" then
            return false, "Axis must be x, y, or z."
        end
        if delta == nil then
            return false, "Delta must be a number (degrees)."
        end

        local v = vec3(GH._entity_rot_overrides[entname])
        v[axis] = (tonumber(v[axis]) or 0) + delta
        GH._entity_rot_overrides[entname] = v

        -- Apply immediately to nearby instances so the user sees it.
        local player = minetest.get_player_by_name(name)
        if player then
            local pos = player:get_pos()
            if pos then
                local objs = minetest.get_objects_inside_radius(pos, 20)
                for _, obj in ipairs(objs) do
                    if not obj:is_player() then
                        local e = obj:get_luaentity()
                        if e and e.name == entname then
                            apply_entity_rotation_offsets(entname, e)
                        end
                    end
                end
            end
        end

        return print_cfg()
    end,
})

-- Debug command: tune wield3d attach rotation for an item.
-- Usage:
--   /glb_wield              (uses held item)
--   /glb_wield <itemname>
--   /glb_wield [itemname] rot <x|y|z> <delta_deg>
--   /glb_wield [itemname] reset
minetest.register_chatcommand("glb_wield", {
    params = "[itemname] [rot|reset|get|help] ...",
    description = "Debug: nudge wield3d item rotation (third-person hand item)",
    privs = {server = true},
    func = function(name, param)
        local w3d = rawget(_G, "wield3d")
        if type(w3d) ~= "table" or type(w3d.location) ~= "table" then
            return false, "wield3d not found (enable the wield3d mod to use this command)."
        end

        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found."
        end

        local args = {}
        for w in tostring(param or ""):gmatch("%S+") do
            args[#args + 1] = w
        end

        local itemname
        local action = args[1]
        local base = 1

        local is_action = (action == nil)
            or action == "rot" or action == "reset" or action == "get" or action == "print" or action == "help"

        if not is_action then
            itemname = action
            action = args[2]
            base = 2
        else
            itemname = player:get_wielded_item():get_name()
        end

        if not itemname or itemname == "" then
            return false, "Hold an item first (or pass an item name)."
        end

        local function default_loc()
            local s = tonumber(minetest.settings:get("wield3d_scale")) or 0.25
            return {
                "Arm_Right",
                {x = 0, y = 5.5, z = 3},
                {x = -90, y = 225, z = 90},
                {x = s, y = s},
            }
        end

        local function get_loc(create)
            local loc = w3d.location[itemname]
            if type(loc) == "table" then
                if type(loc[1]) ~= "string" then
                    loc[1] = "Arm_Right"
                end
                if type(loc[2]) ~= "table" then
                    loc[2] = {x = 0, y = 5.5, z = 3}
                end
                if type(loc[3]) ~= "table" then
                    loc[3] = {x = -90, y = 225, z = 90}
                end
                if type(loc[4]) ~= "table" then
                    loc[4] = (default_loc())[4]
                end
                return loc
            end
            if not create then
                return nil
            end
            loc = default_loc()
            w3d.location[itemname] = loc
            return loc
        end

        local function apply_to_players(loc)
            for _, p in ipairs(minetest.get_connected_players()) do
                local pname = p:get_player_name()
                if pname and p:get_wielded_item():get_name() == itemname then
                    local pos = p:get_pos()
                    if pos then
                        pos = vector.new(pos.x, pos.y + 0.5, pos.z)
                        local objs = minetest.get_objects_inside_radius(pos, 2)
                        for _, obj in ipairs(objs) do
                            local e = obj:get_luaentity()
                            if e and e.name == "wield3d:wield_entity" and e.wielder == pname then
                                obj:set_attach(p, loc[1], loc[2], loc[3])
                                break
                            end
                        end
                    end
                end
            end
        end

        local function print_cfg(loc, is_default)
            loc = loc or default_loc()
            local bone = loc[1]
            local pos = vec3(loc[2])
            local rot = vec3(loc[3])
            local scale = loc[4] or {}

            local label = is_default and "(default)" or "(override)"
            return true,
                itemname .. " " .. label
                .. "\nbone = " .. tostring(bone)
                .. "\npos = " .. fmt_vec_deg(pos)
                .. "\nrot = " .. fmt_vec_deg(rot)
                .. "\nscale = " .. fmt_vec2(scale)
                .. "\n\n-- Paste into a mod (after wield3d loads):\n"
                .. "wield3d.location[\"" .. itemname .. "\"] = {\"" .. tostring(bone) .. "\", "
                .. fmt_vec_deg(pos) .. ", " .. fmt_vec_deg(rot) .. ", " .. fmt_vec2(scale) .. "}"
        end

        if not action or action == "get" or action == "print" then
            local loc = get_loc(false)
            if not loc then
                return print_cfg(nil, true)
            end
            return print_cfg(loc, false)
        end

        if action == "help" then
            return true,
                "Usage:\n"
                .. "/glb_wield\n"
                .. "/glb_wield <itemname>\n"
                .. "/glb_wield [itemname] rot <x|y|z> <delta_deg>\n"
                .. "/glb_wield [itemname] reset"
        end

        if action == "reset" then
            w3d.location[itemname] = nil
            local loc = default_loc()
            apply_to_players(loc)
            return print_cfg(nil, true)
        end

        if action ~= "rot" then
            return false, "Expected 'rot', 'reset', or 'get'. Try /glb_wield help"
        end

        local axis = args[base + 1]
        local delta = tonumber(args[base + 2])
        if axis ~= "x" and axis ~= "y" and axis ~= "z" then
            return false, "Axis must be x, y, or z."
        end
        if delta == nil then
            return false, "Delta must be a number (degrees)."
        end

        local loc = get_loc(true)
        loc[3][axis] = (tonumber(loc[3][axis]) or 0) + delta
        apply_to_players(loc)
        return print_cfg(loc, false)
    end,
})

-- ============================================================
-- Optional integration: mobs_redo style API
-- ============================================================
local patch_mobs = minetest.settings:get_bool("glb_helper_patch_mobs", true)

local function is_number(v)
    return type(v) == "number" and v == v
end

local function find_upvalue(func, wanted)
    if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
        return nil
    end
    if type(func) ~= "function" then
        return nil
    end
    for i = 1, 80 do
        local name, val = debug.getupvalue(func, i)
        if not name then
            break
        end
        if name == wanted then
            return val
        end
    end
    return nil
end

local function find_mobs_redo_mob_class()
    local mobs = rawget(_G, "mobs")
    if type(mobs) ~= "table" or mobs.mod ~= "redo" then
        return nil
    end

    -- Best case: get mob_class_meta upvalue from mobs:register_mob
    local meta = find_upvalue(mobs.register_mob, "mob_class_meta")
    if type(meta) == "table" and type(meta.__index) == "table" then
        return meta.__index
    end

    local mob_class = find_upvalue(mobs.register_mob, "mob_class")
    if type(mob_class) == "table" then
        return mob_class
    end

    -- Fallback: scan registered entities for one that uses the mob_class metatable.
    local reg = rawget(minetest, "registered_entities")
    if type(reg) == "table" then
        for _, def in pairs(reg) do
            local mt = getmetatable(def)
            local idx = mt and mt.__index
            if type(idx) == "table"
                and type(idx.set_animation) == "function"
                and type(idx.mob_activate) == "function" then
                return idx
            end
        end
    end

    return nil
end

local function mobs_redo_source_fps(ent)
    local a = ent and ent.animation
    return tonumber(ent and ent.glb_source_fps)
        or tonumber(ent and ent.gltf_source_fps)
        or (type(a) == "table" and tonumber(a.glb_source_fps))
        or (type(a) == "table" and tonumber(a.gltf_source_fps))
        or (type(a) == "table" and tonumber(a.source_fps))
        or GH.DEFAULT_SOURCE_FPS
end

local function get_mobs_redo_rot_offset_deg(ent)
    local from_anim = {}
    if type(ent) == "table" and type(ent.animation) == "table" and type(ent.animation.glb_helper_rot) == "table" then
        from_anim = ent.animation.glb_helper_rot
    end
    local from_live = {}
    if type(ent) == "table" and type(ent.name) == "string" then
        from_live = GH._mob_rot_overrides[ent.name] or {}
    end

    local a = vec3(from_anim)
    local b = vec3(from_live)
    return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
end

local function apply_mobs_redo_rotation_offsets(ent, after_step)
    if type(ent) ~= "table" or not ent.object then
        return
    end

    local mesh = (type(ent.mesh) == "string" and ent.mesh ~= "") and ent.mesh
        or get_mesh_from_object(ent.object)
    if not GH.is_gltf_mesh(mesh) then
        return
    end

    local rot_deg = get_mobs_redo_rot_offset_deg(ent)
    local rx = tonumber(rot_deg.x) or 0
    local ry = tonumber(rot_deg.y) or 0
    local rz = tonumber(rot_deg.z) or 0

    -- Yaw offset integrates best by adjusting mobs_redo's own yaw offset (self.rotate).
    if ent._glb_helper_base_rotate == nil then
        ent._glb_helper_base_rotate = tonumber(ent.rotate) or 0
    end
    ent.rotate = (tonumber(ent._glb_helper_base_rotate) or 0) + math.rad(ry)

    if not after_step then
        return
    end

    -- Pitch/roll offsets: re-apply after mobs_redo sets yaw.
    if type(ent.object.set_rotation) ~= "function" then
        return
    end

    local do_apply = (rx ~= 0) or (rz ~= 0) or ent._glb_helper_applied_rot_xyz
    if not do_apply then
        return
    end

    local yaw = ent.object:get_yaw() or 0
    ent._glb_helper_applied_rot_xyz = (rx ~= 0) or (rz ~= 0)
    pcall(ent.object.set_rotation, ent.object, {
        x = math.rad(rx),
        y = yaw,
        z = math.rad(rz),
    })
end

local function convert_mobs_redo_animation_table(animation, source_fps)
    if type(animation) ~= "table" then
        return false
    end
    if animation._glb_helper_converted then
        return false
    end
    if animation.glb_helper_disable then
        return false
    end

    source_fps = tonumber(source_fps) or GH.DEFAULT_SOURCE_FPS
    if not source_fps or source_fps <= 0 then
        return false
    end

    for k, v in pairs(animation) do
        if type(k) == "string" and is_number(v) then
            if k:sub(-6) == "_start" or k:sub(-4) == "_end" then
                animation[k] = v / source_fps
            elseif k:sub(-6) == "_speed" or k == "speed_normal" or k == "speed_run" then
                animation[k] = v / source_fps
            end
        end
    end

    animation._glb_helper_converted = true
    animation._glb_helper_source_fps = source_fps
    return true
end

local function patch_mobs_redo()
    if GH._mobs_redo_patched then
        return
    end

    local mobs = rawget(_G, "mobs")
    if type(mobs) ~= "table" or mobs.mod ~= "redo" then
        return
    end

    local mob_class = find_mobs_redo_mob_class()
    if type(mob_class) ~= "table" or type(mob_class.set_animation) ~= "function" then
        minetest.log("warning", "[glb_helper] mobs_redo detected, but could not locate mob_class to patch")
        return
    end

    local orig = mob_class.set_animation
    if orig == GH._mobs_redo_orig_set_animation then
        GH._mobs_redo_patched = true
        return
    end

    GH._mobs_redo_orig_set_animation = orig

    mob_class.set_animation = function(self, anim, force)
        local mesh = (type(self) == "table" and type(self.mesh) == "string" and self.mesh ~= "") and self.mesh
            or (type(self) == "table" and self.object and get_mesh_from_object(self.object))

        if GH.is_gltf_mesh(mesh) then
            local animation = type(self) == "table" and self.animation
            if type(animation) == "table"
                and not animation._glb_helper_converted
                and not (self.glb_helper_disable or animation.glb_helper_disable) then
                convert_mobs_redo_animation_table(animation, mobs_redo_source_fps(self))
            end
        end

        return orig(self, anim, force)
    end

    if type(mob_class.on_step) == "function" then
        local orig_step = mob_class.on_step
        mob_class.on_step = function(self, dtime, moveresult)
            apply_mobs_redo_rotation_offsets(self, false)
            local ret = orig_step(self, dtime, moveresult)
            apply_mobs_redo_rotation_offsets(self, true)
            return ret
        end
    end

    GH._mobs_redo_patched = true
    minetest.log("action", "[glb_helper] Patched mobs_redo animations for glTF meshes")
end

if patch_mobs then
    -- Patch after all mods have loaded (more reliable for finding mob_class).
    minetest.register_on_mods_loaded(patch_mobs_redo)
end
