.pragma library

function pair(en, ru, enShift, ruShift) {
    return {en:en, ru:ru, enShift:enShift || en.toUpperCase(), ruShift:ruShift || ru.toUpperCase()};
}
function letters(en, ru) {
    return en.split("").map((key,i)=>pair(key,ru[i]));
}
var numbers = [pair("`","ё","~","Ё"),pair("1","1","!","!"),pair("2","2","@","\""),
    pair("3","3","#","№"),pair("4","4","$",";"),pair("5","5","%","%"),
    pair("6","6","^",":"),pair("7","7","&","?"),pair("8","8","*","*"),
    pair("9","9","(","("),pair("0","0",")",")"),pair("-","-","_","_"),pair("=","=","+","+")];
var upper = letters("qwertyuiop", "йцукенгшщз").concat([pair("[","х","{","Х"),pair("]","ъ","}","Ъ")]);
var middle = letters("asdfghjkl", "фывапролд").concat([pair(";","ж",":","Ж"),pair("'","э","\"","Э")]);
var lower = letters("zxcvbnm", "ячсмить").concat([pair(",","б","<","Б"),pair(".","ю",">","Ю"),pair("/",".","?",",")]);
function character(key, russian, shift, caps) {
    let base=russian ? key.ru : key.en;
    if (/^[a-zа-яё]$/i.test(base)) return shift !== caps ? base.toUpperCase() : base.toLowerCase();
    return shift ? (russian ? key.ruShift : key.enShift) : base;
}

// Fn actions are explicit; unrelated letters keep their normal input.
var secondary = {
    "F1": {
        "action": "mute",
        "icon": "volume-x"
    },
    "F2": {
        "action": "volume-down",
        "icon": "volume-1"
    },
    "F3": {
        "action": "volume-up",
        "icon": "volume-2"
    },
    "F4": {
        "action": "mic-mute",
        "icon": "mic-off"
    },
    "F5": {
        "action": "brightness-down",
        "icon": "sun-dim"
    },
    "F6": {
        "action": "brightness-up",
        "icon": "sun"
    },
    "F7": {
        "action": "displays",
        "icon": "monitor"
    },
    "F8": {
        "action": "settings",
        "icon": "settings"
    },
    "F9": {
        "action": "lock",
        "icon": "lock-keyhole"
    },
    "F10": {
        "action": "pad",
        "icon": "rectangle-ellipsis"
    },
    "F11": {
        "action": "words",
        "icon": "message-square"
    },
    "F12": {
        "action": "panel-settings",
        "icon": "panels-top-left"
    },
    "Escape": {
        "action": "fn-lock",
        "icon": "fn-lock"
    },
    "BackSpace": {
        "action": "power",
        "icon": "power"
    },
    "Return": {
        "action": "nightlight",
        "icon": "night"
    },
    "\\": {
        "action": "audio",
        "icon": "audio"
    },
    " ": {
        "action": "theme",
        "icon": "oled"
    },
    "Left": {
        "action": "home",
        "icon": "home"
    },
    "Right": {
        "action": "end",
        "icon": "end"
    },
    "Up": {
        "action": "page-up",
        "icon": "page-up"
    },
    "Down": {
        "action": "page-down",
        "icon": "page-down"
    }
};
var iconPaths = {
    "words": "M3 3h18v14H8l-5 4V3 M7 8h10 M7 12h6",
    "camera": "M3 6h4l2-3h6l2 3h4v15H3Z M12 9a4 4 0 1 0 0 8 4 4 0 0 0 0-8",
    "insert": "M5 2h10l5 5v15H5Z M15 2v5h5 M8 14h9 M12 10v8",
    "page-down": "M5 4l7 7 7-7 M5 13l7 7 7-7",
    "page-up": "M5 20l7-7 7 7 M5 11l7-7 7 7",
    "end": "M20 4v16 M4 6l8 6-8 6 M12 12h7",
    "home": "M4 4v16 M20 6l-8 6 8 6 M12 12H5",
    "oled": "M12 2a10 10 0 1 0 0 20V2 M12 2a10 10 0 0 1 0 20",
    "overview": "M2 2h8v8H2Z M14 2h8v8h-8Z M2 14h8v8H2Z M14 14h8v8h-8Z",
    "audio": "M5 3v18 M12 3v18 M19 3v18 M2 8h6 M9 16h6 M16 6h6",
    "night": "M20 15A9 9 0 0 1 9 3a9 9 0 1 0 11 12Z",
    "power": "M12 2v10 M6 5a9 9 0 1 0 12 0",
    "fn-lock": "M5 10h14v12H5V10 M8 10V6a4 4 0 0 1 8 0v4 M12 15v3",
    "volume-x": "M11 5 6 9H3v6h3l5 4V5 M17 9l5 6 M22 9l-5 6",
    "volume-1": "M11 5 6 9H3v6h3l5 4V5 M15.5 8.5a5 5 0 0 1 0 7",
    "volume-2": "M11 5 6 9H3v6h3l5 4V5 M15.5 8.5a5 5 0 0 1 0 7 M19 5a10 10 0 0 1 0 14",
    "mic-off": "M9 9v3a3 3 0 0 0 5 2 M15 9V5a3 3 0 0 0-6 0 M5 10v2a7 7 0 0 0 12 5 M19 10v2 M12 19v3 M8 22h8 M2 2l20 20",
    "sun-dim": "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v2 M12 20v2 M2 12h2 M20 12h2",
    "sun": "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 2v2 M12 20v2 M2 12h2 M20 12h2 M5 5l1 1 M18 18l1 1 M5 19l1-1 M18 6l1-1",
    "monitor": "M2 3h20v14H2V3 M8 21h8 M12 17v4",
    "settings": "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M9 2h6l1 4 4 1 2 5-3 3v5l-5 2-3-3-5 1-3-5 2-4-1-5 5-1Z",
    "lock-keyhole": "M5 10h14v12H5V10 M8 10V6a4 4 0 0 1 8 0v4 M12 15v3",
    "rectangle-ellipsis": "M2 3h20v18H2V3 M2 16h20 M12 16v5",
    "message-square": "M3 3h18v14H8l-5 4V3 M7 8h10 M7 12h6",
    "panels-top-left": "M2 2h20v20H2V2 M2 8h20 M9 8v14"
};
