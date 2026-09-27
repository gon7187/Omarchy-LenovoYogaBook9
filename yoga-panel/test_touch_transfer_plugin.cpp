// Explicit live-test helper: touches only the focused Yoga GTK test window.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/version.h>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <string>

static PHLMONITORREF source;
static double y;
static uint32_t stamp=10000;
APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }
APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash())!=__hyprland_api_get_client_hash()) throw std::runtime_error("Test helper ABI mismatch");
    HyprlandAPI::registerHyprCtlCommand(handle,{"yoga-test-edge",false,[](eHyprCtlOutputFormat,std::string request) -> std::string {
        const auto window=Desktop::focusState()->window();
        if (!window || window->m_class!="org.gon7187.YogaTabletKeyboardTest") return "Refusing: focus the test window";
        const auto action=request.substr(request.find(' ')+1);
        stamp+=30;
        if (action=="down") {
            source=window->m_monitor;
            const auto monitor=source.lock();
            if (!monitor) return "No monitor";
            const auto pos=window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            const auto size=window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
            y=(pos.y+12-monitor->m_position.y)/monitor->m_size.y;
            for (const auto& device:g_pInputManager->m_touches) if(device->m_boundOutput==monitor->m_name) {
                g_pInputManager->onTouchDown({.timeMs=stamp,.touchID=0,.pos={(pos.x+size.x/2-monitor->m_position.x)/monitor->m_size.x,y},.device=device});
                g_pSeatManager->sendTouchFrame();return "ok";
            }
            return "No touchscreen";
        }
        if(action=="up") {
            g_pInputManager->onTouchUp({.timeMs=stamp,.touchID=0});
            g_pSeatManager->sendTouchFrame();source.reset();return "ok";
        }
        const auto monitor=source.lock();
        if(!monitor) return "No test contact";
        const double edge=monitor->m_position.x<450 ? .995 : .005;
        const double x=action=="edge" ? edge : action=="jitter" ? (edge<.5 ? .01 : .99) : .5;
        g_pInputManager->onTouchMove({.timeMs=stamp,.touchID=0,.pos={x,y}});
        g_pSeatManager->sendTouchFrame();return "ok";
    }});
    return {"yoga-touch-transfer-test","Own-window touch replay","local","0.1"};
}
APICALL EXPORT void PLUGIN_EXIT() {}
