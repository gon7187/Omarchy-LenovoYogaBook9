-- Blur the desktop widget layer so its translucent cards read as frosted glass
-- over the wallpaper. ignore_alpha skips the fully transparent gaps between
-- cards, which would otherwise blur the whole right edge of the screen.
hl.layer_rule({ match = { namespace = "yoga-widgets" }, blur = true, ignore_alpha = 0.2, no_anim = true })
