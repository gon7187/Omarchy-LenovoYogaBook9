import QtQuick
import QtTest
TestCase {
    name: "ThemePalette"
    function test_monochrome_layout_contrast() {
        Theme.palette={mode:"dark",background:"#101315",foreground:"#c2c6c7",accent:"#798186"};
        verify(Theme.letterActive.r>Theme.textDim.r+.1);
        verify(Theme.letterActive.g>Theme.textDim.g+.1);
        verify(Theme.letterActive.b>Theme.textDim.b+.1);
    }
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
