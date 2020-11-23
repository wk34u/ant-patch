#include "pch.h"
#define LUA_LIB 1
#include "lua.hpp"
#include "render.h"
#include "file.h"
#include "font.h"
#include "system.h"
#include "context.h"
#include "luabind.h"

#include <bgfx/bgfx_interface.h>
#include <bgfx/luabgfx.h>
#include <bgfx/c99/bgfx.h>

#include <RmlUi/Core.h>
#include <RmlUi/Debugger.h>

#include <cassert>
#include <cstring>

struct RmlInterface {
    SystemInterface system;
    FontEngine      font;
    File            file;
    Renderer        renderer;
    RmlInterface(RmlContext* context)
        : system()
        , font(context)
        , file(context)
        , renderer(context)
    {
        Rml::SetSystemInterface(&system);
        Rml::SetFontEngineInterface(&font);
        Rml::SetFileInterface(&file);
        Rml::SetRenderInterface(&renderer);
    }
};

struct RmlWrapper {
    RmlContext   context;
    RmlInterface interface;
    RmlWrapper(lua_State* L, int idx)
        : context(L, idx)
        , interface(&context)
	{}
};

static RmlWrapper* g_wrapper = nullptr;

lua_plugin* get_lua_plugin() {
    return g_wrapper
        ? g_wrapper->context.plugin
        : nullptr;
}

static int
lrmlui_init(lua_State *L){
    if (g_wrapper) {
        return luaL_error(L, "RmlUi has been initialized.");
    }
    g_wrapper = new RmlWrapper(L, 1);
    if (!Rml::Initialise()){
        return luaL_error(L, "Failed to Initialise RmlUi.");
    }
    g_wrapper->interface.font.RegisterFontEffectInstancer();

    auto plugin = std::make_unique<lua_plugin>();
    std::string errmsg;
    if (!plugin->initialize(g_wrapper->context.bootstrap, errmsg)) {
        lua_pushfstring(L, "Lua init error : %s\n", errmsg.c_str());
        return lua_error(L);
    }
    g_wrapper->context.plugin = plugin.release();
    Rml::RegisterPlugin(g_wrapper->context.plugin);
    return 0;
}

static int
lrmlui_shutdown(lua_State* L) {
    Rml::Shutdown();
    if (g_wrapper) {
        delete g_wrapper;
        g_wrapper = nullptr;
    }
    return 0;
}

static int
lrmlui_update(lua_State* L) {
    if (!g_wrapper) {
        return 0;
    }
    double delta = luaL_checknumber(L, 1);
    g_wrapper->interface.system.update(delta);

    lua_plugin* plugin = g_wrapper->context.plugin;
    lua_State* rL = plugin->L;
    luabind::invoke(rL, [&]() {
        lua_pushnumber(rL, delta);
        plugin->call(LuaEvent::OnUpdate, 1);
    });
    return 0;
}

int
lRenderBegin(lua_State* L) {
    if (g_wrapper) {
        g_wrapper->interface.renderer.Begin();
    }
    return 0;
}

int
lRenderFrame(lua_State* L){
    if (g_wrapper){
        g_wrapper->interface.renderer.Frame();
    }
    return 0;
}

extern "C"
#if defined(_WIN32)
__declspec(dllexport)
#endif
int
luaopen_rmlui(lua_State* L) {
    init_interface(L);
    luaL_Reg l[] = {
        { "init",     lrmlui_init },
        { "shutdown", lrmlui_shutdown },
        { "update",   lrmlui_update },
        { nullptr, nullptr },
    };
    luaL_newlib(L, l);
    return 1;
}

bgfx_interface_vtbl_t* 
get_bgfx_interface(){
    return bgfx_inf_;
}
