#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/version.h>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <spawn.h>
#include <cstdlib>
#include <stdexcept>
#include <format>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include "gesture.hpp"
#include "cursor_bounds.hpp"
#include "tablet.hpp"
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>

extern char **environ;
static TouchGestures recognizer;
static bool claimed = false;
static std::unordered_map<int32_t, PHLLSREF> panelTouches;
static CFunctionHook* cursorHook = nullptr;
static bool confining = false;
static bool tabletTapped = false;

static bool bookMode(PHLMONITOR upper, PHLMONITOR lower) {
    if (!upper || !lower || !upper->m_enabled || !lower->m_enabled) return false;
    const auto upperBox = upper->logicalBox(), lowerBox = lower->logicalBox();
    return upperBox.h > upperBox.w && lowerBox.h > lowerBox.w;
}

static PHLLS panelOn(PHLMONITOR monitor) {
    if (!monitor) return {};
    for (const auto& weak : monitor->m_layerSurfaceLayers[3]) {
        auto layer = weak.lock();
        if (layer && layer->m_mapped && layer->m_namespace == "yoga-input-panel") return layer;
    }
    return {};
}

static Vector2D confinedPosition(Vector2D position) {
    if (g_pSessionLockManager->isSessionLocked()) return position;
    const auto upper = State::monitorState()->query().name("eDP-1").run();
    const auto lower = State::monitorState()->query().name("eDP-2").run();
    if (!upper || !lower || !upper->m_enabled || !lower->m_enabled || !upper->m_dpmsStatus) return position;
    if (bookMode(upper,lower)) return position;
    for (const auto& weak : lower->m_layerSurfaceLayers[3]) {
        const auto layer = weak.lock();
        if (!layer || !layer->m_mapped || layer->m_namespace != "yoga-input-panel") continue;
        const auto box = upper->logicalBox();
        const auto [x,y] = confinePointer(position.x,position.y,box.x,box.y,box.w,box.h);
        return {x,y};
    }
    return position;
}

// mouse.move fires AFTER the hardware cursor has moved. Clamp at the shared
// cursor update instead, before the backend sees relative or absolute motion.
static void cursorMoved(Pointer::CPointerManager* manager) {
    const auto position = manager->position();
    const auto target = confining ? position : confinedPosition(position);
    if (target != position) {
        confining = true;
        manager->warpTo(target);
        confining = false;
        return;
    }
    reinterpret_cast<void(*)(Pointer::CPointerManager*)>(cursorHook->m_original)(manager);
}

static void confineCurrentPointer() {
    const auto position = Pointer::mgr()->position();
    const auto target = confinedPosition(position);
    if (target == position) return;
    Pointer::mgr()->warpTo(target);
    g_pInputManager->simulateMouseMovement();
}

// Deliver panel touches without Hyprland's normal touchscreen refocus. Pointer
// focus must stay at the virtual mouse position, not follow the user's finger.
static void consume(Event::SCallbackInfo& info) {
    info.cancelled = true;
    g_pInputManager->m_lastInputTouch = false;
}
// Fixed executable and arguments; no shell or input-derived command text.
static void runPanel(const char* verb) {
    const char* home = std::getenv("HOME");
    if (!home) return;
    std::string executable = std::string(home) + "/.local/bin/yoga-panel";
    std::string argument = verb;
    char* args[]={executable.data(),argument.data(),nullptr};
    pid_t child;
    posix_spawn(&child,executable.c_str(),nullptr,nullptr,args,environ);
}

static void resetGesture() { recognizer.reset(); claimed = false; }
// Once several fingers are clearly a gesture, take the contact away from the app
// under them, so a swipe does not also scroll or draw there.
static void claim(Event::SCallbackInfo& info) {
    if (!claimed && recognizer.claimed()) {
        claimed = true;
        g_pSeatManager->sendTouchCancel();
        g_pSeatManager->sendTouchFrame();
    }
    if (claimed) consume(info);
}
static void down(ITouch::SDownEvent event, Event::SCallbackInfo& info) {
    const std::string output = event.device ? event.device->m_boundOutput : "";
    if (g_pSessionLockManager->isSessionLocked() || (output != "eDP-1" && output != "eDP-2")) { resetGesture(); return; }
    {
        auto monitor = State::monitorState()->query().name(output).run();
        if (monitor) {
            const auto global = monitor->m_position + event.pos * monitor->m_size;
            for (const auto& weak : monitor->m_layerSurfaceLayers[3]) {
                auto layer = weak.lock();
                if (!layer || !layer->m_mapped || layer->m_namespace != "yoga-input-panel" ||
                    !layer->m_geometry.containsPoint(global) || !layer->resource()) continue;
                panelTouches[event.touchID] = layer;
                resetGesture();
                consume(info);
                g_pSeatManager->sendTouchDown(layer->resource(), event.timeMs, event.touchID, global - layer->m_geometry.pos());
                return;
            }
        }
    }
    const auto upper = State::monitorState()->query().name("eDP-1").run();
    const auto lower = State::monitorState()->query().name("eDP-2").run();
    if (output == "eDP-1" || (output == "eDP-2" && bookMode(upper,lower))) tabletTapped = true;
    recognizer.down(event.touchID,event.timeMs,event.pos.x,event.pos.y);
    claim(info);
}
static void motion(ITouch::SMotionEvent event, Event::SCallbackInfo& info) {
    if (auto it = panelTouches.find(event.touchID); it != panelTouches.end()) {
        consume(info);
        auto layer = it->second.lock();
        if (layer && layer->m_mapped && !g_pSessionLockManager->isSessionLocked()) {
            auto monitor = layer->m_monitor.lock();
            if (monitor)
                g_pSeatManager->sendTouchMotion(event.timeMs, event.touchID,
                    monitor->m_position + event.pos * monitor->m_size - layer->m_geometry.pos());
        }
        return;
    }
    if (!recognizer.tracking(event.touchID)) return;
    recognizer.motion(event.touchID,event.pos.x,event.pos.y);
    claim(info);
}
static void up(ITouch::SUpEvent event, Event::SCallbackInfo& info) {
    if (panelTouches.erase(event.touchID)) {
        consume(info);
        g_pSeatManager->sendTouchUp(event.timeMs, event.touchID);
        return;
    }
    if (g_pSessionLockManager->isSessionLocked()) { resetGesture(); return; }
    if (!recognizer.tracking(event.touchID)) return;
    if (claimed) consume(info);
    const Gesture gesture = recognizer.up(event.touchID,event.timeMs);
    if (recognizer.idle()) claimed = false;
    const char* name = nullptr;
    switch (gesture) {
        case Gesture::OpenPanel: name = "show"; break;
        case Gesture::SwipeLeft: name = "previous"; break;
        case Gesture::SwipeRight: name = "next"; break;
        case Gesture::SwipeDown: name = "minimize"; break;
        case Gesture::SwipeUp: name = "restore"; break;
        case Gesture::Overview: name = "overview"; break;
        case Gesture::None: return;
    }
    if (gesture == Gesture::OpenPanel) { runPanel("show"); return; }
    const char* home = std::getenv("HOME");
    if (!home) return;
    std::string executable = std::string(home) + "/.local/bin/yoga-panel";
    std::string verb = "gesture";
    std::string argument = name;
    char* args[]={executable.data(),verb.data(),argument.data(),nullptr};
    pid_t child;
    posix_spawn(&child,executable.c_str(),nullptr,nullptr,args,environ);
}
static void cancel(ITouch::SCancelEvent event, Event::SCallbackInfo&) {
    panelTouches.erase(event.touchID);
    resetGesture();
}
// Keep client fullscreen state intact: only the compositor switches to its
// maximized work area, so a browser does not exit fullscreen or lose text focus.
struct TabletWindow {
    PHLWINDOWREF window;
    PHLMONITORREF monitor;
    WORKSPACEID workspace;
    Fullscreen::SFullscreenMode fullscreen;
    CBox original, applied, monitorBox;
};
static std::vector<TabletWindow> tabletWindows;

static CBox fittedBox(const CBox& box, const CBox& area) {
    const auto b = fitTabletWindow({box.x,box.y,box.w,box.h},{area.x,area.y,area.w,area.h});
    return {b[0],b[1],b[2],b[3]};
}

static void setTabletFullscreen(PHLWINDOW window, Fullscreen::eFullscreenMode internal) {
    // The controller otherwise forces internal=client when sync_fullscreen is
    // enabled. Match fullscreen_state dispatch without leaving a window override.
    auto& sync = window->m_ruleApplicator->syncFullscreen();
    constexpr auto priority = Desktop::Types::PRIORITY_SET_PROP;
    const std::optional<bool> previous = sync.hasValue() && sync.getPriority() == priority ? std::optional{sync.value()} : std::nullopt;
    sync.set(false,priority);
    // Omitting client also avoids the controller remembering a synthetic
    // maximized origin when we restore fullscreen after the keyboard closes.
    Fullscreen::controller()->setFullscreenMode(window,internal);
    sync.matchOptional(previous,priority);
}

static void restoreTabletWindows(PHLWINDOW keep={}) {
    std::vector<TabletWindow> pending;
    for (const auto& saved : tabletWindows) {
        const auto window = saved.window.lock();
        const auto monitor = saved.monitor.lock();
        if (!window || !window->m_isMapped || !window->m_target || !monitor || !monitor->m_enabled ||
            window->m_monitor != saved.monitor || window->workspaceID() != saved.workspace) continue;
        if (keep && saved.window == keep) { pending.push_back(saved); continue; }
        const auto modes = Fullscreen::controller()->getFullscreenModes(window);
        if (saved.fullscreen.internal == Fullscreen::FSMODE_FULLSCREEN) {
            // A user/client mode change takes precedence over our old snapshot.
            if (modes.internal == Fullscreen::FSMODE_MAXIMIZED && modes.client == saved.fullscreen.client)
                setTabletFullscreen(window,saved.fullscreen.internal);
        } else if (window->m_target->floating() && modes.internal == Fullscreen::FSMODE_NONE &&
                   window->m_target->position() == saved.applied) {
            // Rotation may make the old rectangle unreachable. Keep it on screen.
            const auto box = monitor->logicalBox();
            g_layoutManager->setTargetGeom(box == saved.monitorBox ? saved.original : fittedBox(saved.original,box),window->m_target);
        }
    }
    tabletWindows = std::move(pending);
}

static void fitTabletWindow(PHLWINDOW window, PHLMONITOR monitor, PHLLS panel) {
    if (!window || !window->m_isMapped || window->m_monitor != monitor || !window->m_target) return;
    const auto modes = Fullscreen::controller()->getFullscreenModes(window);
    auto saved = std::ranges::find_if(tabletWindows,[&](const auto& item) { return item.window == window; });
    if (modes.internal == Fullscreen::FSMODE_FULLSCREEN) {
        if (saved == tabletWindows.end())
            tabletWindows.push_back({window,monitor,window->workspaceID(),modes,window->m_target->position(),{},monitor->logicalBox()});
        setTabletFullscreen(window,Fullscreen::FSMODE_MAXIMIZED);
        return;
    }
    if (modes.internal != Fullscreen::FSMODE_NONE || !window->m_target->floating()) return;
    auto area = monitor->m_reservedArea.apply(monitor->logicalBox());
    area.h = std::min(area.h,panel->m_geometry.y-area.y);
    const auto extents = window->getFullWindowExtents();
    area.x += extents.topLeft.x; area.y += extents.topLeft.y;
    area.w -= extents.topLeft.x+extents.bottomRight.x;
    area.h -= extents.topLeft.y+extents.bottomRight.y;
    const auto current = window->m_target->position();
    const auto fit = fittedBox(current,area);
    if (fit == current) return;
    if (saved == tabletWindows.end()) {
        tabletWindows.push_back({window,monitor,window->workspaceID(),modes,current,fit,monitor->logicalBox()});
        saved = std::prev(tabletWindows.end());
    } else if (current != saved->applied) {
        // Preserve a deliberate drag/resize made while the keyboard was visible.
        saved->original = current;
    }
    g_layoutManager->setTargetGeom(fit,window->m_target);
    saved->applied = window->m_target->position();
}

// A light poll observes text-input activation and the actual mapped panel. No
// text or titles are read. Manual show works even for apps without text-input.
static SP<CEventLoopTimer> textInputTimer;
static TabletAutoShow tabletAutoShow;
static WP<CWLSurfaceResource> tabletInputSurface;
static void pollTextInput(SP<CEventLoopTimer> self, void*) {
    const auto lower = State::monitorState()->query().name("eDP-2").run();
    const auto upper = State::monitorState()->query().name("eDP-1").run();
    const bool tablet = upper && upper->m_enabled && (!lower || !lower->m_enabled);
    const bool book = bookMode(upper,lower);
    const bool docked = tablet || book;
    const bool tapped = std::exchange(tabletTapped,false);
    const auto window = Desktop::focusState()->window();
    const auto monitor = window ? window->m_monitor.lock() : PHLMONITOR{};
    const bool internal = monitor && (monitor == upper || (book && monitor == lower));
    const auto panel = internal ? panelOn(monitor) : PHLLS{};
    const bool visible = docked && (!!panelOn(upper) || !!panelOn(lower));
    if (docked && !g_pSessionLockManager->isSessionLocked()) {
        const auto input = g_pInputManager->m_relay.getFocusedTextInput();
        const bool wanted = window && internal && input && input->isEnabled();
        const auto surface = wanted ? input->focusedSurface() : nullptr;
        const bool activated = tapped || surface != tabletInputSurface;
        tabletInputSurface = surface;
        const auto action = tabletAutoShow.step(wanted,visible,activated);
        if (action == TabletAutoShow::Action::Show) runPanel("show");
        if (action == TabletAutoShow::Action::Hide) runPanel("hide");
        if (panel) {
            restoreTabletWindows(window);
            fitTabletWindow(window,monitor,panel);
        } else restoreTabletWindows();
    } else {
        if (g_pSessionLockManager->isSessionLocked() && tabletAutoShow.owned) runPanel("hide");
        // Returning to laptop keeps the keyboard on eDP-2, as before.
        tabletAutoShow = {}; tabletInputSurface.reset();
    }
    if (!visible || !docked || g_pSessionLockManager->isSessionLocked()) restoreTabletWindows();
    self->updateTimeout(std::chrono::milliseconds(200));
}

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash())
        throw std::runtime_error("Yoga gesture: Hyprland version mismatch; rebuild first");
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle,"onCursorMoved")) {
        if (match.demangled != "Pointer::CPointerManager::onCursorMoved()") continue;
        cursorHook = HyprlandAPI::createFunctionHook(handle,match.address,reinterpret_cast<void*>(cursorMoved));
        break;
    }
    if (!cursorHook || !cursorHook->hook())
        throw std::runtime_error("Yoga gesture: cursor confinement hook unavailable");
    static auto a=Event::bus()->m_events.input.touch.down.listen(down);
    static auto b=Event::bus()->m_events.input.touch.motion.listen(motion);
    static auto c=Event::bus()->m_events.input.touch.up.listen(up);
    static auto d=Event::bus()->m_events.input.touch.cancel.listen(cancel);
    static auto e=Event::bus()->m_events.layer.opened.listen([](PHLLS layer) {
        if (layer && layer->m_namespace == "yoga-input-panel") confineCurrentPointer();
    });
    confineCurrentPointer();
    textInputTimer = makeShared<CEventLoopTimer>(std::chrono::milliseconds(200), pollTextInput, nullptr);
    g_pEventLoopManager->addTimer(textInputTimer);
    // Changing the touch route mid-session must not leave Qt tracking fingers
    // from the previous route (it can otherwise ignore new touch updates).
    for (const auto& name : {"eDP-1","eDP-2"}) if (panelOn(State::monitorState()->query().name(name).run())) {
        g_pSeatManager->sendTouchCancel();
        g_pSeatManager->sendTouchFrame();
        break;
    }
    HyprlandAPI::registerHyprCtlCommand(handle, {"yoga-tablet-status", true, [](eHyprCtlOutputFormat, std::string) -> std::string {
        const auto lower = State::monitorState()->query().name("eDP-2").run();
        const auto window = Desktop::focusState()->window();
        const auto input = g_pInputManager->m_relay.getFocusedTextInput();
        const auto upper = State::monitorState()->query().name("eDP-1").run();
        return std::format("lower_enabled={} book={} text_input={} owned={} adjusted={} focused_internal={}",
            lower && lower->m_enabled, bookMode(upper,lower), input && input->isEnabled(), tabletAutoShow.owned, tabletWindows.size(),
            window && window->m_monitor && (window->m_monitor->m_name == "eDP-1" || window->m_monitor->m_name == "eDP-2"));
    }});
    HyprlandAPI::registerHyprCtlCommand(handle, {"yoga-gesture-last", true, [](eHyprCtlOutputFormat, std::string) -> std::string {
        const auto& l = recognizer.last;
        return std::format("fingers={} moved={} ms={} pinch_ratio={:.2f}", l.peak, l.moved, l.age, l.pinch);
    }});
#ifdef YOGA_PANEL_TESTING
    HyprlandAPI::registerHyprCtlCommand(handle, {"yoga-panel-test-touch", false, [](eHyprCtlOutputFormat, std::string request) -> std::string {
        const auto action = request.substr(request.find(' ') + 1);
        // Bounded integration probe: one synthetic finger in the pad centre.
        constexpr int id = 4095;
        if (action == "down") {
            for (const auto& device : g_pInputManager->m_touches) {
                if (device->m_boundOutput != "eDP-2") continue;
                g_pInputManager->onTouchDown({.timeMs=1000,.touchID=id,.pos={0.5,0.75},.device=device});
                g_pSeatManager->sendTouchFrame();
                return "ok";
            }
        } else if (action == "move") {
            g_pInputManager->onTouchMove({.timeMs=1050,.touchID=id,.pos={0.55,0.75}});
            g_pSeatManager->sendTouchFrame();
            return "ok";
        } else if (action == "up") {
            g_pInputManager->onTouchUp({.timeMs=1500,.touchID=id});
            g_pSeatManager->sendTouchFrame();
            return "ok";
        }
        return "Expected down/move/up and lower touchscreen";
    }});
#endif
    return {"yoga-panel-gesture","Yoga panel touch routing and multi-finger touchscreen gestures","local","0.5.0"};
}
APICALL EXPORT void PLUGIN_EXIT() {
    restoreTabletWindows();
    if (cursorHook) { cursorHook->unhook(); cursorHook = nullptr; }
    if (textInputTimer) { g_pEventLoopManager->removeTimer(textInputTimer); textInputTimer.reset(); }
    for (const auto& [id, layer] : panelTouches) g_pSeatManager->sendTouchUp(0, id);
    if (!panelTouches.empty()) g_pSeatManager->sendTouchFrame();
    panelTouches.clear();
    recognizer.reset();
}
