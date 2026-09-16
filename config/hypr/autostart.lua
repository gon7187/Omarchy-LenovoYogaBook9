-- Append to ~/.config/hypr/autostart.lua
--
-- Match eDP-2's backlight to eDP-1 at login. systemd-backlight saves and
-- restores each panel independently, so eDP-2 can come back far dimmer.
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/yoga-brightness --no-osd +0%")

-- Autologin skips the password, so lock right away: the lock screen carries the
-- touch keyboard (bin/yoga-lock-keyboard). sleep-lock retries until the shell is
-- up and the lock is secure, which a bare `omarchy-shell lock lock` would not.
-- Skipped when an update dropped the keys, so a boot never strands behind a password.
o.exec_on_start("grep -q TouchKeys /usr/share/omarchy/shell/plugins/lock/LockView.qml && omarchy-system-sleep-lock 12000")
