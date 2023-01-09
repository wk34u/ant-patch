local lfs = require "bee.filesystem"
local vfs = require "vfs"

return function (repopath, access)
    local repo
    function vfs.realpath(path)
        local rp = access.realpath(repo, path)
        if rp then
            return rp:string()
        end
    end
    local ListValue <const> = {
        dir = true,
        file = false,
    }
    function vfs.list(path)
        local item = {}
        for _, filename in ipairs(access.list_files(repo, path)) do
            item[filename] = ListValue[vfs.type(path .. filename)]
        end
        return item
    end
    function vfs.type(path)
        return access.type(repo, path)
    end
    function vfs.repopath()
        return repopath
    end
    function vfs.mount(path)
        access.addmount(repo, path)
    end
    local path = lfs.path(repopath)
    if not lfs.is_directory(path) then
       error "Not a dir"
    end
    repo = {
        _root = path,
    }
    access.readmount(repo)
end
