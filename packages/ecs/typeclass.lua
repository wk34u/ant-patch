local interface = require "interface"
local fs = require "filesystem"

local function sourceinfo()
	local info = debug.getinfo(3, "Sl")
	return string.format("%s(%d)", info.source, info.currentline)
end

local function keys(tbl)
	local k = {}
	for _, v in ipairs(tbl) do
		k[v] = true
	end
	return k
end

local function splitname(fullname)
    return fullname:match "^([^|]*)|(.*)$"
end

local function register_pkg(w, package)
	local ecs = { world = w, method = w._set_methods }
	local declaration = w._decl
	local import = w._import
	local function register(what)
		local class_set = {}
		ecs[what] = function(name)
			local fullname = name
			if what ~= "action" and what ~= "component" then
				fullname = package .. "|" .. name
			end
			local r = class_set[fullname]
			if r == nil then
				log.info("Register", #what<8 and what.."  " or what, fullname)
				r = {}
				class_set[fullname] = r
				local decl = declaration[what][fullname]
				if not decl then
					error(("%s `%s` has no declaration."):format(what, fullname))
				end
				if not decl.method then
					error(("%s `%s` has no method."):format(what, fullname))
				end
				decl.source = {}
				decl.defined = sourceinfo()
				local callback = keys(decl.method)
				local object = import[what](fullname)
				setmetatable(r, {
					__pairs = function ()
						return pairs(object)
					end,
					__index = object,
					__newindex = function(_, key, func)
						if type(func) ~= "function" then
							error("Method should be a function")
						end
						if callback[key] == nil then
							error("Invalid callback function " .. key)
						end
						if decl.source[key] ~= nil then
							error("Method " .. key .. " has already defined at " .. decl.source[key])
						end
						decl.source[key] = sourceinfo()
						object[key] = func
					end,
				})
			end
			return r
		end
	end
	register "system"
	register "transform"
	register "interface"
	register "action"
	register "component"
	function ecs.require(fullname)
		local pkg, file = splitname(fullname)
		if not pkg then
			pkg = package
			file = fullname
		end
		local path = "/pkg/"..package.."/"..file:gsub("%.", "/")..".lua"
		local loaded = w._loaded
		local r = loaded[path]
		if r ~= nil then
			return r
		end
		r = w:dofile(path)
		if r == nil then
			r = true
		end
		loaded[path] = r
		return r
	end
	w._ecs[package] = ecs
	return ecs
end

local function import_impl(w, package, file)
	local loaded = w._loaded
	local path = "/pkg/"..package.."/"..file
	local r = loaded[path]
	if r ~= nil then
		return
	end
	loaded[path] = true
	w:dofile(path)
end

local function solve_policy(fullname, v)
	local _, policy_name = splitname(fullname)
	local union_name, name = policy_name:match "^([%a_][%w_]*)%.([%a_][%w_]*)$"
	if not union_name then
		name = policy_name:match "^([%a_][%w_]*)$"
	end
	if not name then
		error(("invalid policy name: `%s`."):format(policy_name))
	end
	v.union = union_name
end

local check_map = {
	require_system = "system",
	require_interface = "interface",
	require_policy = "policy",
	require_policy_v2 = "policy_v2",
	require_transform = "transform",
	component_v2 = "component_v2",
	component_opt = "component_v2",
	pipeline = "pipeline",
	action = "action",
}

local OBJECT = {"system","policy","policy_v2","transform","interface","component","component_v2","pipeline","action"}

local function solve_object(o, w, what, fullname)
	local decl = w._decl[what][fullname]
	if decl and decl.method then
		for _, name in ipairs(decl.method) do
			if not o[name] then
				error(("`%s`'s `%s` method is not defined."):format(fullname, name))
			end
		end
	end
end

local function table_append(t, a)
	table.move(a, 1, #a, #t+1, t)
end

local copy = {}
function copy.policy(v)
	local t = {}
	table_append(t, v.component)
	table_append(t, v.unique_component)
	return {
		policy = v.require_policy,
		transform = v.require_transform,
		component = t,
		action = v.action,
	}
end
function copy.policy_v2(v)
	return {
		policy_v2 = v.require_policy_v2,
		component_v2 = v.component_v2,
		component_opt = v.component_opt,
	}
end
function copy.transform(v)
	return {
		policy = v.require_policy,
		transform = v.require_transform,
		input = v.input,
		output = v.output,
	}
end
function copy.pipeline(v)
	return {
		value = v.value
	}
end
function copy.component_v2(v)
	return {
		type = v.type[1]
	}
end
function copy.system() return {} end
function copy.interface() return {} end
function copy.component() return {} end
function copy.action() return {} end

local function create_importor(w)
	local declaration = w._decl
	local import = {}
    for _, objname in ipairs(OBJECT) do
		w._class[objname] = setmetatable({}, {__index=function(_, name)
			local res = import[objname](name)
			if res then
				solve_object(res, w, objname, name)
			end
			return res
		end})
		import[objname] = function (name)
			local class = w._class[objname]
			local v = rawget(class, name)
            if v then
                return v
			end
			if not w._initializing and objname == "system" then
                error(("system `%s` can only be imported during initialization."):format(name))
			end
            local v = declaration[objname][name]
			if not v then
				if objname == "pipeline" then
					return
				end
				if objname == "component" then
					return
				end
                error(("invalid %s name: `%s`."):format(objname, name))
            end
			log.info("Import  ", objname, name)
			local res = copy[objname](v)
			class[name] = res
			for _, tuple in ipairs(v.value) do
				local what, k = tuple[1], tuple[2]
				local attrib = check_map[what]
				if attrib then
					import[attrib](k)
				end
				if what == "unique_component" then
					w._class.unique[k] = true
				end
			end
			if objname == "policy" then
				solve_policy(name, res)
			end
			if v.implement then
				for _, impl in ipairs(v.implement) do
					import_impl(w, v.packname, impl)
				end
			end
			return res
		end
	end
	return import
end

local function import_decl(w, fullname)
	local packname, filename
	assert(fullname:sub(1,1) == "@")
	if fullname:find "/" then
		packname, filename = fullname:match "^@([^/]*)/(.*)$"
	else
		packname = fullname:sub(2)
		filename = "package.ecs"
	end
	w._decl:load(packname, filename)
	w._decl:check()
end

local function init(w, config)
	w._initializing = true
	w._class = { unique = {} }
	w._decl = interface.new(function(packname, filename)
		local file = fs.path "/pkg" / packname / filename
		log.info(("Import decl %q"):format(file:string()))
		return assert(fs.loadfile(file))
	end)
	w._import = create_importor(w)
	w._set_methods = setmetatable({}, {
		__index = w._methods,
		__newindex = function(_, name, f)
			if w._methods[name] then
				local info = debug.getinfo(w._methods[name], "Sl")
				assert(info.source:sub(1,1) == "@")
				error(string.format("Method `%s` has already defined at %s(%d).", name, info.source:sub(2), info.linedefined))
			end
			w._methods[name] = f
		end,
	})
	setmetatable(w._ecs, {__index = function (_, package)
		return register_pkg(w, package)
	end})

	config.ecs = config.ecs or {}
	if config.ecs.import then
		for _, k in ipairs(config.ecs.import) do
			import_decl(w, k)
		end
	end
	if config.update_decl then
		config.update_decl(w)
	end

	local import = w._import
	for _, objname in ipairs(OBJECT) do
		if config.ecs[objname] then
			for _, k in ipairs(config.ecs[objname]) do
				import[objname](k)
			end
		end
	end
    --for _, objname in ipairs(OBJECT) do
	--	setmetatable(w._class[objname], nil)
	--end
	w._initializing = false

    for _, objname in ipairs(OBJECT) do
		for fullname, o in pairs(w._class[objname]) do
			solve_object(o, w, objname, fullname)
        end
    end
	require "system".solve(w)
end

return {
	init = init,
	import_decl = import_decl,
}
