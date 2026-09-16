-- Append to ~/.config/hypr/monitors.lua
--
-- Lenovo Yoga Book 9 13IRU8 (82YQ): two stacked internal panels.
-- eDP-1 is the upper panel and is mounted 180 degrees out, so it needs
-- transform 2. eDP-2 sits directly below it (1440x900 logical at scale 2).
--
-- Do NOT also set video=eDP-1:panel_orientation=upside_down on the kernel
-- command line. It fixes the upside-down boot splash, but Hyprland's backend
-- reads the same property and rotates the scanout WITHOUT remapping input --
-- the image looks right while the pointer travels backwards. See the "boot
-- splash" entry under Open items in the README.

-- The power-saver profile (platform_profile low-power) drops HDR: ~0.7 W at
-- idle. bin/yoga-display-power switches it live; this covers hyprctl reload.
local profile = io.open("/sys/firmware/acpi/platform_profile")
local saver = profile and profile:read("l") == "low-power"
if profile then profile:close() end
local depth, cm = saver and 8 or 10, saver and "srgb" or "hdr"
hl.monitor({ output = "eDP-1", mode = "2880x1800@60", position = "0x0", scale = 2, transform = 2, bitdepth = depth, cm = cm })
hl.monitor({ output = "eDP-2", mode = "2880x1800@60", position = "0x900", scale = 2, bitdepth = depth, cm = cm })

-- SDR apps in HDR mode: decode them with the piecewise sRGB curve instead of
-- pure gamma 2.2, which crushes the dark greys of terminals and dark themes.
hl.config({ render = { cm_sdr_eotf = "srgb" } })
