#!/usr/bin/env python3
"""Exercise display mode requests without changing the running compositor."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

FAKE = """#!/usr/bin/env python3
import json,os,pathlib,sys
if pathlib.Path(sys.argv[0]).name=='omarchy-notification-send':sys.exit(0)
root=pathlib.Path(os.environ['DISPLAY_FIXTURE'])
if sys.argv[1]=='eval':
 with (root/'calls').open('a') as f:f.write(json.dumps(sys.argv[2])+'\\n')
 print('ok')
elif sys.argv[1]=='monitors':print(json.dumps([{'name':'eDP-1','disabled':False,'activeWorkspace':{'id':1}},{'name':'eDP-2','disabled':False,'activeWorkspace':{'id':2}}]))
elif sys.argv[1]=='clients':print('[]')
"""


def main():
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "calls").write_text("")
        for name in ("hyprctl", "omarchy-notification-send"):
            command = root / name
            command.write_text(FAKE)
            command.chmod(0o755)
        env = {
            **os.environ,
            "DISPLAY_FIXTURE": str(root),
            "PATH": str(root) + ":" + os.environ["PATH"],
            "XDG_RUNTIME_DIR": str(root),
            "XDG_CONFIG_HOME": str(root / ".config"),
        }
        modes = ["stand", "book", "book-flip", "present"]
        if "--tablet" in sys.argv:
            modes.append("tablet")
        for mode in modes:
            (root / "calls").write_text("")
            subprocess.run(
                [str(repo / "bin/yoga-mode"), mode], env=env, check=True, timeout=5
            )
            requests = [
                json.loads(line) for line in (root / "calls").read_text().splitlines()
            ]
            monitors = [r for r in requests if r.startswith("hl.monitor(")]
            assert monitors
            for request in monitors:
                assert request.endswith("})"), request
                if "disabled = true" not in request:
                    assert "bitdepth = 10" in request and 'cm = "hdr"' in request, (
                        request
                    )
            assert (root / "yoga-mode").read_text().strip() == mode
            if mode == "tablet":
                assert any("disabled = true" in r and "eDP-2" in r for r in monitors)
                assert any("enabled = false" in r for r in requests), (
                    "Tablet must disable lower touch input"
                )
    print("DISPLAY_MODES_OK: HDR preserved across " + ", ".join(modes))


if __name__ == "__main__":
    main()
