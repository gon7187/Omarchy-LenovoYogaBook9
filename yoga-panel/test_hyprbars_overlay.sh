#!/bin/bash
# Live check: close only our disposable window through its overlay button.
set -euo pipefail
cd -- "$(dirname -- "$0")"
pointer=${1:-build/yoga-pointer}
app_id="yoga-titlebar-test-$$"
focus=$(hyprctl activewindow -j | jq -r '.address')
cursor=$(hyprctl cursorpos -j)
read -r width height < <(hyprctl monitors -j | jq -r '[(map(.x + .width/.scale)|max), (map(.y + .height/.scale)|max)] | @tsv')
probe=
cleanup() {
  if [[ -n $probe ]]; then kill "$probe" 2>/dev/null || true; wait "$probe" 2>/dev/null || true; fi
  hyprctl eval "hl.dispatch(hl.dsp.focus({window='address:$focus'}))" >/dev/null
  printf 'a %s %s %s %s\n' "$(jq -r '.x' <<< "$cursor")" "$(jq -r '.y' <<< "$cursor")" "$width" "$height" | "$pointer"
}
trap cleanup EXIT
foot --app-id="$app_id" sh -c 'sleep 30' &
probe=$!
window=null
for ((i=0; i<50; i++)); do
  window=$(hyprctl clients -j | jq --arg id "$app_id" '[.[] | select(.class == $id)][0]')
  [[ $window != null ]] && break
  sleep .1
done
[[ $window != null ]]
sleep .5
window=$(hyprctl clients -j | jq --arg id "$app_id" '[.[] | select(.class == $id)][0]')
# Hit the enlarged button near its lower-left edge, outside the old 16px target.
x=$(jq '.at[0] + .size[0] - 30' <<< "$window")
y=$(jq '.at[1] + 22' <<< "$window")
{ printf 'a %s %s %s %s\n' "$x" "$y" "$width" "$height"; sleep .2; printf 'b 272 1\n'; sleep .1; printf 'b 272 0\n'; } | "$pointer"
sleep .3
hyprctl clients -j | jq -e --arg id "$app_id" 'all(.[]; .class != $id)' >/dev/null
echo 'PASS: close button receives clicks inside client content'
