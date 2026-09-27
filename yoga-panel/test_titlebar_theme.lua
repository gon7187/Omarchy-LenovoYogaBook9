-- Run from the repository root: lua yoga-panel/test_titlebar_theme.lua
local buttons = {}
hl = { config = function() end, plugin = { hyprbars = {
  add_button = function(value) table.insert(buttons, value) end,
} } }
local original_popen = io.popen
local function check(palette, background, foreground)
  io.popen = function(command)
    assert(command == "omarchy-theme-color --all")
    if not palette then return nil end
    return { lines = function() return palette:gmatch("[^\n]+") end, close = function() end }
  end
  buttons = {}
  dofile("config/hypr/yoga-titlebars.lua")
  assert(#buttons == 2)
  for _, button in ipairs(buttons) do
    assert(button.bg_color == background and button.fg_color == foreground)
    assert(button.size == 24)
  end
  assert(buttons[1].icon == "✕" and buttons[1].action ~= "")
  assert(buttons[2].icon == "⠿" and buttons[2].action == "")
end
check("accent\t#faa968\nforeground\t#bebebe\nbackground\t#05182e", "rgb(faa968)", "rgb(05182e)")
check("accent\t#345678\nforeground\t#202020\nbackground\t#ffffff", "rgb(345678)", "rgb(ffffff)")
check("foreground\t#202020\nbackground\t#ffffff", "rgb(202020)", "rgb(ffffff)")
check("foreground\tinvalid\nbackground\t#123", "rgb(eeeeee)", "rgb(222222)")
check(nil, "rgb(eeeeee)", "rgb(222222)")
io.popen = original_popen
print("PASS: theme colors reload for dark/light palettes; invalid/missing colors fall back")
