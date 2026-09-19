import QtQuick
import "KeyboardLayout.js" as Layouts

Image {
    property string name: ""
    property color tint: Theme.textDim
    source: name && Layouts.iconPaths[name] ? "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="' + Layouts.iconPaths[name] + '" fill="none" stroke="' + tint + '" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>') : ""
    sourceSize.width: 48
    sourceSize.height: 48
}
