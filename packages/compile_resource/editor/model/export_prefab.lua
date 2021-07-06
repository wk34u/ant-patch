local math3d = require "math3d"
local utility = require "editor.model.utility"

local fs = require "filesystem.local"

local invalid_chars<const> = {
    '<', '>', ':', '/', '\\', '|', '?', '*', ' ', '\t', '\r', '%[', '%]', '%(', '%)'
}

local replace_char<const> = '_'

local function fix_invalid_name(name)
    for _, ic in ipairs(invalid_chars) do
        name = name:gsub(ic, replace_char)
    end

    return name
end

local prefab = {}

local function create_entity(t)
    if t.parent then
        t.policy[#t.policy+1] = "ant.scene|hierarchy_policy"
        t.action = {mount = t.parent}
        t.data["scene_entity"] = true
    end
    table.sort(t.policy)
    prefab[#prefab+1] = {
        policy = t.policy,
        data = t.data,
        action = t.action,
    }
    return #prefab
end

local function get_transform(node)
    if node.matrix then
        local s, r, t = math3d.srt(math3d.matrix(node.matrix))
        return {
            s = math3d.tovalue(s),
            r = math3d.tovalue(r),
            t = math3d.tovalue(t),
        }
    end

    return {
        s = node.scale,
        r = node.rotation,
        t = node.translation,
    }
end

local STATE_TYPE = {
    visible     = 0x00000001,
    cast_shadow = 0x00000002,
    selectable  = 0x00000004,
}

local DEFAULT_STATE = STATE_TYPE.visible|STATE_TYPE.cast_shadow|STATE_TYPE.selectable
local function update_transform(ptrans, transform)
    local lm = math3d.matrix(transform)
    lm = math3d.mul(ptrans, lm)
    local s, r, t = math3d.srt(lm)
    return {
        s = {math3d.index(s, 1, 2, 3)},
        r = math3d.tovalue(r),
        t = {math3d.index(t, 1, 2, 3)}
    }
end

local function is_mirror_transform(scale)
    for _, s in ipairs(scale) do
        if s < 0 then
            return true
        end
    end
end

local function duplicate_table(m)
    local t = {}
    for k, v in pairs(m) do
        t[k] = type(v) == "table" and
             duplicate_table(v) or
             v
    end
    return t
end

local primitive_state_names = {
    "POINTS",
    "LINES",
    false, --LINELOOP, not support
    "LINESTRIP",
    "",         --TRIANGLES
    "TRISTRIP", --TRIANGLE_STRIP
    false, --TRIANGLE_FAN not support
}

local materials = {}

local function generate_material(mi, mode, cull, deffile)
    local sname = primitive_state_names[mode+1]
    if not sname then
        error(("not support primitate state, mode:%d"):format(mode))
    end
    local cullname = cull or "NONE"
    local filename = deffile or mi.filename
    local key = sname .. cullname .. filename:string()

    local m = materials[key]
    if m == nil then
        local change = true
        if sname == "" and cull == "CW" then
            m = mi
            change = nil
        else
            local f = mi.filename
            local basename = f:stem():string()

            local nm = duplicate_table(mi.material)
            local s = nm.state
            s.CULL = cullname
            if sname == "" then
                s.PT = nil
            else
                s.PT = sname
                basename = basename .. "_" .. sname
            end

            basename = basename .. "_" .. cullname
            filename = f:parent_path() / basename:lower() .. ".material"
            m = {
                filename = filename,
                material = nm
            }
        end

        materials[key] = m

        if change or not deffile then
            utility.save_txt_file(filename:string(), m.material)
        end
    end

    return filename
end

local function read_datalist(filename)
    local f = fs.open(filename)
    local c = f:read "a"
    f:close()
    return c
end

local default_material_info = {
    filename = fs.path "./materials/pbr_default_cw.material",
}

local function create_mesh_node_entity(gltfscene, nodeidx, ptrans, parent, exports, tolocalpath)
    local node = gltfscene.nodes[nodeidx+1]
    local transform = update_transform(ptrans, get_transform(node))
    local meshidx = node.mesh
    local mesh = gltfscene.meshes[meshidx+1]

    for primidx, prim in ipairs(mesh.primitives) do
        local meshname = mesh.name and fix_invalid_name(mesh.name) or ("mesh" .. meshidx)
        local materialfile
        local mode = prim.mode or 4
        if prim.material then 
            if exports.material and next(exports.material) then
                local mi = exports.material[prim.material+1]
                local cull = is_mirror_transform(transform.s) and "CW" or "CCW"
                materialfile = generate_material(mi, mode, cull):string()
            else
                error(("primitive need material, but no material files output:%s %d"):format(meshname, prim.material))
            end
        else
            local default_material_path<const> = fs.path "/pkg/ant.resources/materials/pbr_default_cw.material"
            if default_material_info.material == nil then
                default_material_info.material = read_datalist(tolocalpath(default_material_path))
            end
            local cull = is_mirror_transform(transform.s) and "CW" or "CCW"
            materialfile = generate_material(default_material_info, mode, cull, default_material_path):string()
        end

        local meshfile = exports.mesh[meshidx+1][primidx]
        if meshfile == nil then
            error(("not found meshfile in export data:%d, %d"):format(meshidx+1, primidx))
        end

        local data = {
            scene_entity= true,
            transform   = transform,
            mesh        = meshfile,
            material    = materialfile,
            name        = node.name or "",
            state       = DEFAULT_STATE,
        }

        local policy = {
            "ant.general|name",
            "ant.render|render",
        }

        if node.skin and exports.skeleton and next(exports.animations) then
            local f = exports.skin[node.skin+1]
            if f == nil then
                error(("mesh need skin data, but no skin file output:%d"):format(node.skin))
            end
            data.skeleton = exports.skeleton

            --skinning
            data.meshskin = f
            policy[#policy+1] = "ant.animation|skinning"

            local lst = {}
            data.animation = {}
            for name, file in pairs(exports.animations) do
                local n = fix_invalid_name(name)
                data.animation[n] = file
                lst[#lst+1] = n
            end
            table.sort(lst)
            data.animation_birth = lst[1]
            policy[#policy+1] = "ant.animation|animation"
            policy[#policy+1] = "ant.animation|animation_controller.birth"
        end

        create_entity {
            policy = policy,
            data = data,
            parent = parent,
        }
    end
end

local function create_node_entity(gltfscene, nodeidx, parent)
    local node = gltfscene.nodes[nodeidx+1]
    local transform = get_transform(node)
    local nname = node.name and fix_invalid_name(node.name) or ("node" .. nodeidx)
    return create_entity {
        policy = {
            "ant.general|name",
            "ant.scene|transform_policy"
        },
        data = {
            name = nname,
            scene_entity = true,
            transform = transform,
        },
        parent = parent,
    }
end

local function find_mesh_nodes(gltfscene, scenenodes)
    local meshnodes = {}
    for _, nodeidx in ipairs(scenenodes) do
        local node = gltfscene.nodes[nodeidx+1]
        if node.children then
            local c_meshnodes = find_mesh_nodes(gltfscene, node.children)
            for ni, l in pairs(c_meshnodes) do
                l[#l+1] = nodeidx
                assert(meshnodes[ni] == nil)
                meshnodes[ni] = l
            end
        end
        if node.mesh then
            assert(node.children == nil)
            local meshlist = {}
            assert(meshnodes[nodeidx] == nil)
            meshnodes[nodeidx] = meshlist

            meshlist[#meshlist+1] = nodeidx
        end
    end

    return meshnodes
end

local function righthand2lefthand_transform()
    return math3d.matrix {
        s = {-1.0, 1.0, 1.0}
    }
end

return function(output, glbdata, exports, tolocalpath)
    prefab = {}

    local gltfscene = glbdata.info
    local sceneidx = gltfscene.scene or 0
    local scene = gltfscene.scenes[sceneidx+1]
    local rootid = create_entity {
        policy = {
            "ant.general|name",
            "ant.scene|transform_policy",
        },
        data = {
            name = scene.name or "Rootscene",
            transform = {},
        },
        parent = "root",
    }

    local r2l_trans = righthand2lefthand_transform()

    local meshnodes = find_mesh_nodes(gltfscene, scene.nodes)

    local C = {}
    for mesh_nodeidx, meshlist in pairs(meshnodes) do
        local parent = rootid
        for i=#meshlist, 2, -1 do
            local nodeidx = meshlist[i]
            local p = C[nodeidx]
            if p then
                parent = p
            else
                parent = create_node_entity(gltfscene, nodeidx, parent)
                C[nodeidx] = parent
            end
        end

        local nodeidx = meshlist[1]
        assert(C[nodeidx] == nil)
        C[nodeidx] = parent
        assert(nodeidx == mesh_nodeidx)
        create_mesh_node_entity(gltfscene, nodeidx, r2l_trans, parent, exports)
    end
    utility.save_txt_file("./mesh.prefab", prefab)
end
