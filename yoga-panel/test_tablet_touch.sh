#!/bin/bash
# Exercise production mode functions without changing the desktop.
set -euo pipefail
cd -- "$(dirname -- "$0")"
# shellcheck disable=SC1090
source <(sed '/^case "${1:-cycle}"/,$d' ../bin/yoga-mode)
apply() { echo "$1"; }
device_line() { grep -F "hl.device({ name = \"ingenic-gadget-serial-and-keyboard-$1\", output = \"eDP-2\", transform = $2, enabled = true })"; }
for pair in '2 0' '3 1' '1 3' '0 2'; do
  read -r monitor touch <<< "$pair"
  result=$(mode_tablet "$monitor")
  [[ $result == *"touchscreen-top"*"transform = $touch"* ]] || { echo "Missing touch rotation for monitor $monitor"; exit 1; }
done
lower_disabled() { return 1; }
result=$(park)
[[ $result == *"touchscreen-top"*"transform = 0"* ]] || { echo 'Leaving tablet must restore touch calibration'; exit 1; }
device_line touchscreen-bottom 0 <<< "$result" >/dev/null || { echo 'Parking must restore lower touch calibration'; exit 1; }
result=$(mode_book)
grep -F 'hl.device({ name = "ingenic-gadget-serial-and-keyboard-touchscreen-top", output = "eDP-1", transform = 1 })' <<< "$result" >/dev/null || { echo 'Book must rotate upper touch'; exit 1; }
device_line touchscreen-bottom 1 <<< "$result" >/dev/null || { echo 'Book must rotate lower touch'; exit 1; }
result=$(mode_book_flip)
grep -F 'hl.device({ name = "ingenic-gadget-serial-and-keyboard-touchscreen-top", output = "eDP-1", transform = 3 })' <<< "$result" >/dev/null || { echo 'Book flip must rotate upper touch'; exit 1; }
device_line touchscreen-bottom 3 <<< "$result" >/dev/null || { echo 'Book flip must rotate lower touch'; exit 1; }
echo 'PASS: portrait touch rotation and book calibration restoration'

# A book rotation must restore focus after monitor placement, not mid-switch.
MODE_FILE=$(mktemp)
trap 'rm -f "$MODE_FILE"' EXIT
hyprctl() { echo '{"address":"0x123"}'; }
bar_position() { :; }
restore_bar_position() { echo settled; }
notify() { :; }
result=$(switch_to book mode_book)
[[ $result == *$'settled\nhl.dispatch(hl.dsp.focus({ window = "address:0x123" }))' ]]
echo 'PASS: book rotation preserves active window after settling'
