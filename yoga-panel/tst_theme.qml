import QtQuick
import QtTest
TestCase {
    name: "ThemePalette"
    function test_surface_alpha_and_foreground() {
        Theme.palette={mode:"light",background:"#ffffff",foreground:"#000000",accent:"#205ea6",lighter_background:"#eeeeee"};
        Theme.surfaceOpacity=.65;
        fuzzyCompare(Theme.key.a,.65,.005);
        compare(Theme.text.a,1); compare(Theme.textDim.a,1);
        verify(Theme.textDim.r<.4);
        Theme.palette={mode:"dark",background:"#000000",foreground:"#ffffff",accent:"#7aa2f7"};
        verify(Theme.textDim.r>.6);
        Theme.surfaceOpacity=1;
    }
}
