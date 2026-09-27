#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build
g++ -std=c++23 -Wall -Wextra -Werror test_gesture.cpp -o build/test-gesture
build/test-gesture
g++ -std=c++23 -Wall -Wextra -Werror test_cursor_bounds.cpp -o build/test-cursor-bounds
g++ -std=c++23 -Wall -Wextra -Werror test_tablet.cpp -o build/test-tablet
build/test-tablet
build/test-cursor-bounds
temporary=$(mktemp build/yoga-panel-gesture.XXXXXX.so)
trap 'rm -f -- "$temporary"' EXIT
# pkg-config emits separate compiler flags; word splitting is intentional.
# shellcheck disable=SC2046
g++ -std=c++23 -O2 -shared -fPIC -fno-gnu-unique $(pkg-config --cflags hyprland pixman-1 libinput wayland-server xkbcommon libdrm) gesture.cpp -o "$temporary"
# Atomic replacement never truncates the inode mapped by a running compositor.
mv -- "$temporary" build/yoga-panel-gesture.so
