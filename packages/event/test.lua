-- Use lua test/package.lua ant.event to test.

local ecs = import_package "ant.ecs"

local w = ecs.new_world {
	packages = { "ant.event" },
	systems = { "test_event" },
	update_order = {},
}

local init = w:update_func "init"
local post_init = w:update_func "post_init"
local update = w:update_func "update"

init()
post_init()
update()

