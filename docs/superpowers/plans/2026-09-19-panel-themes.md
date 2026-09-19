# Panel themes implementation plan

> Execute with subagent-driven-development. User approved native theme mockups and requested all remaining themes and a larger heart.

Goal: Follow installed Omarchy themes, expose opacity and icon choices, reduce static OLED exposure, preserve input and owner calibration.

Architecture: Backend supplies validated theme palettes/catalogue on private JSON stream; QML owns surface alpha, icons and idle effects. No external dependencies or changes to Omarchy files. Existing legacy oledTheme remains readable for compatibility; themeName defaults to system and supersedes the legacy appearance.

- [x] Backend: load installed stock themes plus user overrides, watch current theme changes, validated settings themeName='system', iconStyle='theme', panelOpacity=1.0 (0.65–1), oledShift=true, oledDim=true. Tests for merge, invalid palettes, fallback, changes and persistence.
- [x] QML: use theme tokens, large heart, pixel/line/mic icon choices, remove Words header, compact settings icon. Appearance settings separate tab from existing touchpad settings. Surface-only alpha, opaque labels.
- [x] OLED: max ±2 physical pixels on rare idle timer, defer while touching, idle dim after 60s, immediate wake without eating first input. No continuous idle animation. Tests use real QML effect controller.
- [x] Verify: offline suites, QtTest, native render all 23 themes, real Wayland input. Preserve owner settings. Review diff.
Delivery gate (result recorded in Git and ~/.local/state/yoga-panel/deploy.json): own commit, protected-policy-aware merge/push main, lock deployment and verify remote ancestry, clean immutable release checkout, single build/install, health check and artifact record. Remove own temporary branches/worktrees.

Ruling: user approval covers the discussed behavior and design; no additional design gate. Implementation targets all themes automatically, including future installed palettes.

Validation: 40 Python tests, Node layout/Fn/touchpad/appearance suites, QtTest OLED/theme/key-repeat checks, 23 native theme renders plus settings, live Wayland delegate/Fn/autocorrect/punctuation tests. Review found no remaining blockers.
