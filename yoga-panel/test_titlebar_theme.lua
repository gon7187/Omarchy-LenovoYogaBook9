-- Run from the repository root: lua yoga-panel/test_titlebar_theme.lua
local button
hl = { config = function() end, plugin = { hyprbars = {
  add_button = function(value) button = value end,
} } }
local original_popen = io.popen
local function check(palette, background, foreground)
  io.popen = function(command)
    assert(command == "omarchy-theme-color --all")
    if not palette then return nil end
    return { lines = function() return palette:gmatch("[^\n]+") end, close = function() end }
  end
  dofile("config/hypr/yoga-titlebars.lua")
  assert(button.bg_color == background and button.fg_color == foreground)
  assert(button.size == 24)
end
check("foreground\t#bebebe\nbackground\t#121212", "rgb(bebebe)", "rgb(121212)")
check("foreground\t#202020\nbackground\t#ffffff", "rgb(202020)", "rgb(ffffff)")
check("foreground\tinvalid\nbackground\t#123", "rgb(eeeeee)", "rgb(222222)")
check(nil, "rgb(eeeeee)", "rgb(222222)")
io.popen = original_popen
print("PASS: theme colors reload for dark/light palettes; invalid/missing colors fall back")
