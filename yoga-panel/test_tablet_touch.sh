#!/bin/bash
# Exercise production mode functions without changing the desktop.
set -euo pipefail
cd -- "$(dirname -- "$0")"
# shellcheck disable=SC1090
source <(sed '/^case "${1:-cycle}"/,$d' ../bin/yoga-mode)
apply() { echo "$1"; }
lower_input() { :; }
for pair in '2 0' '3 1' '1 3' '0 2'; do
  read -r monitor touch <<< "$pair"
  result=$(mode_tablet "$monitor")
  [[ $result == *"touchscreen-top"*"transform = $touch"* ]] || { echo "Missing touch rotation for monitor $monitor"; exit 1; }
done
lower_disabled() { return 1; }
result=$(park)
[[ $result == *"touchscreen-top"*"transform = 0"* ]] || { echo 'Leaving tablet must restore touch calibration'; exit 1; }
echo 'PASS: portrait touch rotation and landscape calibration restoration'
