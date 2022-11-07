local ecs   = ...
local world = ecs.world
local w     = world.w

local setting   = import_package "ant.settings".setting
local renderutil = require "util"
local s = ecs.system "pre_depth_system"

if setting:get "graphic/disable_pre_z" then
    renderutil.default_system(s, "init", "data_changed", "update_filter")
    return 
end

local irender   = ecs.import.interface "ant.render|irender"
local irq       = ecs.import.interface "ant.render|irenderqueue"
local imaterial = ecs.import.interface "ant.asset|imaterial"

local pre_depth_material
local pre_depth_skinning_material

local function which_material(skinning)
	local res = skinning and pre_depth_skinning_material or pre_depth_material
    return res.object
end

function s:init()
    pre_depth_material 			= imaterial.load_res "/pkg/ant.resources/materials/predepth.material"
    pre_depth_skinning_material = imaterial.load_res "/pkg/ant.resources/materials/predepth_skin.material"
end

local vr_mb = world:sub{"view_rect_changed", "main_queue"}
local mc_mb = world:sub{"main_queue", "camera_changed"}
function s:data_changed()
    for _, _, vr in vr_mb:unpack() do
        irq.set_view_rect("pre_depth_queue", vr)
    end

    for _, _, ceid in mc_mb:unpack() do
        local e = w:first "pre_depth_queue camera_ref:out"
        e.camera_ref = ceid
        w:submit(e)
    end
end

local material_cache = {__mode="k"}

local function create_depth_only_material(mo, ro, fm)
    local newstate = irender.check_set_state(mo, fm.main_queue:get_material())
    local new_mo = irender.create_material_from_template(mo, newstate, material_cache)

    return new_mo:instance()
end

function s:update_filter()
    for e in w:select "filter_result pre_depth_queue_visible opacity render_object:update filter_material:in skinning?in" do
        local mo = assert(which_material(e.skinning))
        local ro = e.render_object
        local fm = e.filter_material

        local mi = create_depth_only_material(mo, ro, fm)

        local h = mi:ptr()
        fm["pre_depth_queue"] = mi
        ro.mat_predepth = h

        -- fm["scene_depth_queue"] = mi
        -- ro.mat_scenedepth = h
        --e["scene_depth_queue_visible"] = true
    end
end