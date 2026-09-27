const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const source=fs.readFileSync(path.join(__dirname,'shell.qml'),'utf8');
const start=source.indexOf('            ColumnLayout {\n                id: keyboard');
const end=source.indexOf('            RowLayout {\n                id: suggestionRow',start);
const keyboard=source.slice(start,end).replace('id: keyboard','id: keyboard; width: panel.width-32; height: keyboardHeight');
const directory=fs.mkdtempSync(path.join(os.tmpdir(),'yoga-keyboard-geometry-'));
try {
 fs.writeFileSync(path.join(directory,'tst_geometry.qml'),`import QtQuick
import QtQuick.Layouts
import QtTest
import "file://${__dirname}"
import "file://${__dirname}/KeyboardLayout.js" as Layouts
TestCase {
 id: root; name: "KeyboardGeometry"; when: windowShown
 width: 1440; height: 500; visible: true
 property bool tablet: true
 property bool book: false
 property bool settingsOpen: false
 property bool russian: true
 property bool shift: false
 property bool caps: false
 property bool fnActive: false
 property bool control: false
 property bool logo: false
 property bool alt: false
 function holdMod(name,down) {}
 Item { id: panel; width: 900; property real areaHeight: 1440
 property bool settingsVisible: false
 property bool leftHalf: false
 readonly property bool rightHalf: root.book && !leftHalf
 ${keyboard}
 }
 function test_bounds_data() {
  let cases=[]; for(let w of [900,874,1440]) for(let ru of [true,false]) for(let fn of [false,true]) cases.push({tag:w+"-"+ru+"-"+fn,width:w,ru:ru,fn:fn}); cases.push({tag:"laptop",width:1440,ru:true,fn:false,laptop:true}); for(let left of [true,false]) for(let ru of [true,false]) cases.push({tag:"book-"+left+"-"+ru,width:900,ru:ru,fn:false,book:true,left:left}); return cases;
 }
 function test_bounds(data) {
  book=!!data.book; panel.leftHalf=!!data.left; tablet=!data.laptop && !book; panel.width=data.width; panel.areaHeight=data.width<1000 ? 1440 : 900; russian=data.ru; fnActive=data.fn;
  wait(50);
  let keys=[];
  function visit(item) {
   if (item.visible && item.label!==undefined && item.activated!==undefined) keys.push(item);
   for (let child of item.children || []) visit(child);
  }
  visit(keyboard);
  verify(keys.length>(book ? 20 : 50));
  for (let i=0;i<keys.length;i++) {
   let a=keys[i],p=a.mapToItem(keyboard,0,0);
   verify(p.x>=-1 && p.x+a.width<=keyboard.width+1,"Key outside keyboard: "+a.label);
   for(let j=i+1;j<keys.length;j++) {
    let b=keys[j],q=b.mapToItem(keyboard,0,0);
    verify(Math.min(p.x+a.width,q.x+b.width)-Math.max(p.x,q.x)<=1 || Math.min(p.y+a.height,q.y+b.height)-Math.max(p.y,q.y)<=1,"Keys overlap: "+a.label+" / "+b.label);
   }
   let labels=a.children.filter(c=>c.text!==undefined && c.visible && c.text.length>0);
   for(let text of labels) {
    verify(!text.truncated,"Truncated label: "+text.text);
    verify(text.x>=0 && text.y>=0 && text.x+text.width<=a.width+1 && text.y+text.height<=a.height+1,"Text outside key: "+text.text);
   }
   for(let m=0;m<labels.length;m++) for(let n=m+1;n<labels.length;n++) {
    let t=labels[m],u=labels[n];
    verify(Math.min(t.x+t.width,u.x+u.width)-Math.max(t.x,u.x)<=1 || Math.min(t.y+t.height,u.y+u.height)-Math.max(t.y,u.y)<=1,"Labels overlap: "+t.text+" / "+u.text);
   }
  }
  let up=upKey.mapToItem(keyboard,0,0),down=arrowKeys.itemAt(1).mapToItem(keyboard,0,0);
  verify(panel.leftHalf || Math.abs(up.x-down.x)<1,"Up arrow must align with Down");
 }
}`);
 const result=cp.spawnSync('/usr/lib/qt6/bin/qmltestrunner',['-input',directory],{encoding:'utf8',env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software'}});
 process.stdout.write(result.stdout||'');process.stderr.write(result.stderr||'');process.exitCode=result.status===0 && !/QWARN|Binding loop/.test((result.stdout||'')+(result.stderr||'')) ? 0 : 1;
} finally {fs.rmSync(directory,{recursive:true,force:true});}
