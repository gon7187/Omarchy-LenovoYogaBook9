-- Append to ~/.config/hypr/looknfeel.lua
--
-- Omarchy ships with decoration:blur:enabled = false, which the desktop widgets
-- depend on: their cards are translucent, and without the compositor blurring
-- the layer (hypr/yoga-widgets.lua asks for it) every detail of the wallpaper
-- shows through the card and the text sits on noise. Turning blur back on is
-- what makes the frosted material work — and it costs GPU time on battery,
-- which is why the default is off and this is a deliberate choice.
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 6,
      passes = 3,
      popups = true,
    },
  },
})
