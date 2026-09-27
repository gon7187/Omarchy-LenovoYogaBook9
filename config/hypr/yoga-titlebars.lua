-- Title bars for a machine driven by touch: drag a window by its bar, close it
-- with the button. From the hyprbars plugin, which yoga-panel builds and loads
-- (yoga-panel/build-hyprbars.sh, ensure-plugin.py). The plugin registers
-- hl.plugin.hyprbars on load and reloads the config, so this block only runs
-- once the plugin exists -- until then it must not be a config error.

if not (hl.plugin and hl.plugin.hyprbars) then return end

-- Resolve the same palette as Omarchy; theme switching reloads this config.
local colors = { foreground = "rgb(eeeeee)", background = "rgb(222222)" }
local palette = io.popen("omarchy-theme-color --all")
if palette then
  for line in palette:lines() do
    local key, hex = line:match("^(%w+)%s+#(%x%x%x%x%x%x)$")
    if key then colors[key] = "rgb(" .. hex .. ")" end
  end
  palette:close()
end

hl.config({
  plugin = {
    hyprbars = {
      bar_height = 28,
      bar_text_size = 10,
      bar_padding = 8,
      bar_button_padding = 6,
      bar_color = "rgba(00000000)",
      bar_title_enabled = false,
      ["col.text"] = colors.foreground,
    },
  },
})

hl.plugin.hyprbars.add_button({
  bg_color = colors.accent or colors.foreground,
  fg_color = colors.background,
  size = 24,
  icon = "✕",
  action = "hyprctl eval 'hl.dispatch(hl.dsp.window.close())'",
})
