local input, output = ...

local function readfile(filename)
    local f <close> = assert(io.open(filename, "rb"))
    return f:read "a"
end

local function writeline(f, data)
    if data then
        f:write(data)
    end
    f:write "\r\n"
end

local name = assert(output:match "([^./\\]+)%..*$")
local f <close> = assert(io.open(output, "wb"))
writeline(f, [[#pragma once]])
writeline(f)
writeline(f, ([[const char g%sData[] = R"firmware(]]):format(name))
writeline(f, readfile(input))
writeline(f, [[)firmware";]])
