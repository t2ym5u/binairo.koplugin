local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. _dir .. "../game-common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase = require("plugin_base")
local _          = require("i18n")

local BinairoScreen = lrequire("screen")

local BinairoPlugin = PluginBase:extend{
    name      = "binairo",
    menu_text = _("Binairo"),
    menu_hint = "tools",
}

function BinairoPlugin:createScreen()
    return BinairoScreen:new{ plugin = self }
end

return BinairoPlugin
