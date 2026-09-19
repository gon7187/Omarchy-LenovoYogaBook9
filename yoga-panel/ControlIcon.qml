import QtQuick
Image {
 id:i
 property string kind:"heart"
 property string style: Theme.icons
 readonly property var pixel: ({
 heart:"M2 3h3v1h2V3h3v1h1v4h-1v1H9v1H8v1H7v1H6v-1H5v-1H4V9H3V8H2Z",
 mic:"M5 1h3v1h1v6H8v1H5V8H4V2h1ZM2 5h1v4h1v1h5V9h1V5h1v5h-1v1H7v2h3v1H3v-1h3v-2H3v-1H2Z",
 settings:"M5 1h3v2h2v2h2v3h-2v2H8v2H5v-2H3V8H1V5h2V3h2ZM5 5v3h3V5Z"
 })
 readonly property var lines: ({heart:"M12 20 3.8 12A5 5 0 0 1 12 5.5 5 5 0 0 1 20.2 12Z",mic:"M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0ZM6 10v2a6 6 0 0 0 12 0v-2M12 18v4M9 22h6",settings:"M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1ZM15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0"})
 source: !kind ? "" : "data:image/svg+xml,"+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+(style==="pixel"?'14 15':'24 24')+'"><path d="'+(style==="pixel"?pixel[kind]:lines[kind])+'" fill="'+(style==="pixel"?Theme.text:'none')+'" fill-rule="evenodd" stroke="'+(style==="pixel"?'none':Theme.text)+'" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/></svg>')
 sourceSize.width: Math.ceil(width*2); sourceSize.height: Math.ceil(height*2)
}
