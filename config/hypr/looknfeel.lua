-- Append to ~/.config/hypr/looknfeel.lua
--
-- Keep compositor blur disabled by owner preference; retain tuning for manual re-enable.
hl.config({
  decoration = {
    blur = {
      enabled = false,
      size = 6,
      passes = 3,
      popups = true,
    },
  },
})
