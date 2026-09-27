-- Run from yoga-panel: lua test_book_windows.lua
local callback, calls, shown
hl = {
  on = function(_, fn) callback = fn end,
  get_layers = function() return shown and {{}} or {} end,
  get_active_workspace = function() return {id=1} end,
  dispatch = function() calls=calls+1 end,
  dsp = {window={move=function(v) return v end},focus=function(v) return v end},
  config = function() end,
}
dofile('../config/hypr/yoga-windows.lua')
for _, transform in ipairs({0,1,3}) do
  for _, open in ipairs({false,true}) do
    calls=0; shown=open
    callback({address='test',monitor={name='eDP-2',transform=transform}})
    assert(calls == ((open and transform==0) and 2 or 0), 'Book windows must stay on their screen')
  end
end
print('PASS: book windows stay on lower screen; laptop keyboard still redirects')
