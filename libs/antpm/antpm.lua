local fs = require "filesystem"
local sandbox = require "antpm.sandbox"

local WORKDIR = fs.path 'engine'

local registered = {}
local loaded = {}

local function register(pkg)	
    if not fs.exists(pkg) then
        error(('Cannot find package `%s`.'):format(pkg:string()))
    end
    local cfg = pkg / "package.lua"
    if not fs.exists(pkg) then
        error(('Cannot find package config `%s`.'):format(cfg:string()))
    end
    local config = fs.dofile(cfg)
    for _, field in ipairs {'name'} do
        if not config[field] then
            error(('Missing `%s` field in `%s`.'):format(field, cfg:string()))
        end 
    end
    if registered[config.name] then
        error(('Duplicate definition package `%s` in `%s`.'):format(config.name, pkg:string()))
    end
    registered[config.name] = {
        root = pkg,
        config = config,
    }
    return config.name
end

local function require_package(name)
    if not registered[name] or not registered[name].config.entry then
        error(("\n\tno package '%s'"):format(name))
    end
    local info = registered[name]
    if not info.env then
		info.env = sandbox.env(info.root:string(), name)
    end
    return info.env.require(info.config.entry)
end

local packagedir = WORKDIR / "packages"
for pkg in packagedir:list_directory() do
    register(pkg)
end

local function import(name)
    if loaded[name] then
        return loaded[name]
    end
    local res = require_package(name)
    if res == nil then
        loaded[name] = false
    else
        loaded[name] = res
    end
    return loaded[name]
end

local function test(name, entry)
    if not loaded[name] then
        import(name)
    end
    if not registered[name] then
        error(("\n\tno package '%s'"):format(name))
    end
    local info = registered[name]
    if not info.env then
		info.env = sandbox.env(info.root:string(), name)
    end
    return info.env.require(entry or 'test')
end

local function find(name)
    if not registered[name] then
        return
    end
    return registered[name].root, registered[name].config
end

local function m_loadfile(name, filename)
    local info = registered[name]
    if not info.env then
        info.env = sandbox.env(info.root:string(), name)
    end
    return fs.loadfile(filename, 't', info.env)
end

local function get_registered_list(sort)
    local t = {}
    for name,_ in pairs(registered) do
        table.insert(t,name)
    end
    if sort then
        table.sort(t)
    end
    return t
end

return {
    find = find,
    register = register,
    import = import,
    test = test,
    loadfile = m_loadfile,
    get_registered_list = get_registered_list,
}
