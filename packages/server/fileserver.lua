local log = require "log"
local function LOG(...)
	log.info("FileSrv", ...)
end

local fw = require "filewatch"
local repo_new = require "repo".new
local protocol = require "protocol"
local network = require "network"
local lfs = require "filesystem.local"
local debugger = require "debugger"
local event = require "event"

local watch = {}
local repos = {}
local dbgserver_update
local config
local REPOPATH

local function vfsjoin(dir, file)
    if file:sub(1, 1) == '/' or dir == '' then
        return file
    end
    return dir:gsub("(.-)/?$", "%1") .. '/' .. file
end

local function split(path)
	local r = {}
	path:string():gsub("[^/\\]+", function(s)
		r[#r+1] = s
	end)
	return r
end

local function watch_add_path(path, repo, url)
	local tree = watch
	for _, e in ipairs(split(lfs.absolute(path))) do
		if not tree[e] then
			tree[e] = {}
		end
		tree = tree[e]
	end
	if not tree[".id"] then
		tree[".id"] = assert(fw.add(path:string()))
	end
	tree[#tree+1] = {
		repo = repo,
		url = url,
	}
end

local function watch_add(repo, repopath)
	watch_add_path(repopath, repo, '')
	for k, v in pairs(repo._mountpoint) do
		watch_add_path(v, repo, k)
	end
end

local function do_prebuilt(repopath, identity)
	local sp = require "subprocess"
	sp.spawn {
        config.lua,
		repopath / "prebuilt.lua",
		identity,
        hideWindow = true,
    } :wait()
end

local function repo_add(identity, reponame)
	local repopath = lfs.path(reponame)
	LOG ("Open repo : ", tostring(repopath))
	do_prebuilt(repopath, identity)
	if repos[reponame] then
		local repo = repos[reponame]
		assert(repo._identity == identity)
		if lfs.is_regular_file(repopath / ".repo" / "root") then
			repo:index()
		else
			repo:rebuild()
		end
		return repo
	end
	local repo = repo_new(repopath)
	if not repo then
		return
	end
	LOG ("Rebuild repo")
	repo._identity = identity
	if lfs.is_regular_file(repopath / ".repo" / "root") then
		repo:index()
	else
		repo:rebuild()
	end
	watch_add(repo, repopath)
	repos[reponame] = repo
	return repo
end

local function response(fd, ...)
	network.send(fd, protocol.packmessage({...}))
end

local debug = {}
local message = {}

function message:ROOT(identity, reponame)
	LOG("ROOT", identity, reponame)
	local reponame = assert(reponame or REPOPATH, "Need repo name")
	local repo = repo_add(identity, reponame)
	if repo == nil then
		response(self, "ROOT", "")
		return
	end
	self._repo = repo
	event[#event+1] = {"RUNTIME_CREATE", repo}
	response(self, "ROOT", repo:root())
end

function message:GET(hash)
	local repo = self._repo
	local filename = repo:hash(hash)
	if filename == nil then
		response(self, "MISSING", hash)
		return
	end
	local f = io.open(filename:string(), "rb")
	if not f then
		response(self, "MISSING", hash)
		return
	end
	local sz = f:seek "end"
	f:seek("set", 0)
	if sz < 0x10000 then
		response(self, "BLOB", hash, f:read "a")
	else
		response(self, "FILE", hash, tostring(sz))
		local offset = 0
		while true do
			local data = f:read(0x8000)
			response(self, "SLICE", hash, tostring(offset), data)
			offset = offset + #data
			if offset >= sz then
				break
			end
		end
	end
	f:close()
end

function message:DBG(data)
	if data == "" then
		local fd = assert(network.listen('127.0.0.1', 4278))
		fd.update = dbgserver_update
		LOG("LISTEN DEBUG", '127.0.0.1', 4278)
		debug[fd] = { server = self }
		return
	end
	for _, v in pairs(debug) do
		if v.server == self then
			if v.client then
				network.send(v.client, debugger.convertSend(self._repo, data))
			end
			break
		end
	end
end

function message:LOG(data)
	event[#event+1] = {"RUNTIME_LOG", data}
end

local output = {}
local function dispatch_obj(fd)
	local reading_queue = fd._read
	while true do
		local msg = protocol.readmessage(reading_queue, output)
		if msg == nil then
			break
		end
		local f = message[msg[1]]
		if f then
			f(fd, table.unpack(msg, 2))
		end
	end
end

local function fileserver_update(fd)
	dispatch_obj(fd)
	if fd._status == "CLOSED" then
		event[#event+1] = {"RUNTIME_CLOSE", fd._repo}
		for fd, v in pairs(debug) do
			if v.server == fd then
				if v.client then
					network.close(v.client)
				end
				network.close(fd)
				debug[fd] = nil
				break
			end
		end
	end
end

function dbgserver_update(fd)
	local dbg = debug[fd._ref]
	local data = table.concat(fd._read)
	fd._read = {}
	if data ~= "" then
		local self = dbg.server._repo
		local msg = debugger.convertRecv(self, data)
		while msg do
			response(dbg.server, "DBG", msg)
			msg = debugger.convertRecv(self, "")
		end
	end
	if fd._status == "CONNECTING" then
		fd._status = "CONNECTED"
		LOG("New DBG", fd._peer, fd._ref)
		if dbg.client then
			network.close(fd)
		else
			dbg.client = fd
		end
	elseif fd._status == "CLOSED" then
		if dbg.client == fd then
			dbg.client = nil
		end
		response(dbg.server, "DBG", "") --close DBG
	end
end

local function update()
	while true do
		local type, path = fw.select()
		if not type then
			break
		end
		if type == 'error' then
			log.error('FileWatch', path)
			goto continue
		end
		local tree = watch
		local elems = split(lfs.absolute(lfs.path(path)))
		for i, e in ipairs(elems) do
			tree = tree[e]
			if not tree then
				break
			end
			if tree[".id"] then
				local rel_path = table.concat(elems, "/", i+1, #elems)
				if rel_path ~= '' and rel_path:sub(1, 1) ~= '.' then
					for _, v in ipairs(tree) do
						local newpath = vfsjoin(v.url, rel_path)
						log.info('FileWatch', type, newpath)
						v.repo:touch(newpath)
					end
				end
			end
		end
		::continue::
	end
end

local function init(v)
	config = v
end

local function listen(ip, port)
	local fd = assert(network.listen(ip, port))
	fd.update = fileserver_update
	LOG ("Listen : " .. ip .. ":" .. port)
end

local function set_repopath(path)
	REPOPATH = path
end

return {
	init = init,
	listen = listen,
	update = update,
	set_repopath = set_repopath
}
