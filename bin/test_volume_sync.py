#!/usr/bin/env python3
"""Exercise real volume commands with temporary audio-command fixtures."""

import cmath
import json
import math
import os
import re
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FAKE = """#!/usr/bin/env python3
import json,os,pathlib,re,sys,time
root=pathlib.Path(os.environ['AUDIO_FIXTURE'])
state=json.loads((root/'state.json').read_text())
cmd=pathlib.Path(sys.argv[0]).name
if cmd=='pw-dump':
 print(json.dumps([{'id':state['id'],'info':{'state':state['status'],'props':{'node.name':'yoga_dolby'}}}]))
 (root/'observed').write_text(str(state.get('event',-1)))
elif cmd=='pw-cli':
 gain=float(re.search(r'"bassL:Gain" ([0-9.]+)',sys.argv[-1])[1])
 with (root/'calls').open('a') as f:f.write(json.dumps({'id':sys.argv[2],'gain':gain})+'\\n')
elif cmd=='pactl':
 if sys.argv[1]=='get-sink-volume': print('Volume: front-left: 65536 / '+str(state['pct'])+'% / 0.00 dB')
 elif sys.argv[1]=='subscribe':
  for i,delta in enumerate(json.loads((root/'events.json').read_text())):
   state.update(delta,event=i);(root/'state.json').write_text(json.dumps(state))
   print("Event 'change' on sink #42",flush=True)
   deadline=time.monotonic()+5
   while not (root/'observed').exists() or (root/'observed').read_text()!=str(i):
    if time.monotonic()>deadline:sys.exit('event was not consumed')
    time.sleep(.01)
   if state['status']=='running':
    while len((root/'calls').read_text().splitlines())<i+2:
     if time.monotonic()>deadline:sys.exit('gain was not updated')
     time.sleep(.01)
"""


def check_sync():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "state.json").write_text(
            json.dumps({"id": 42, "pct": 100, "status": "running"})
        )
        (root / "events.json").write_text(
            json.dumps([{"pct": 50}, {"pct": 100, "id": 43}])
        )
        (root / "calls").write_text("")
        for name in ("pactl", "pw-dump", "pw-cli"):
            command = root / name
            command.write_text(FAKE)
            command.chmod(0o755)
        env = {
            **os.environ,
            "AUDIO_FIXTURE": str(root),
            "PATH": str(root) + ":" + os.environ["PATH"],
        }
        subprocess.run(
            [str(REPO / "bin/yoga-volume"), "watch"], env=env, check=True, timeout=15
        )
        calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
        assert calls == [
            {"id": "42", "gain": 4.0},
            {"id": "42", "gain": 11.5},
            {"id": "43", "gain": 4.0},
        ], calls
        # A suspended graph must retain the safe config until it starts running.
        (root / "state.json").write_text(
            json.dumps({"id": 43, "pct": 10, "status": "suspended"})
        )
        subprocess.run(
            [str(REPO / "bin/yoga-volume"), "sync"], env=env, check=True, timeout=5
        )
        assert len((root / "calls").read_text().splitlines()) == 3
    print("VOLUME_SYNC_OK: startup, direct slider, graph replacement, suspended graph")


def check_startup_headroom():
    conf = (REPO / "config/pipewire/62-yoga-dolby-eq.conf").read_text()
    for side in ("L", "R"):
        trim_match = re.search(r"name = trim" + side + r'.*?"Gain 1" = ([0-9.]+)', conf)
        bass_match = re.search(r"name = bass" + side + r'.*?"Gain" =\s*([0-9.]+)', conf)
        assert trim_match and bass_match, (
            "Both channels must contain trim and bass filters"
        )
        trim = float(trim_match[1])
        bass = float(bass_match[1])
        dc_gain = bass + 20 * math.log10(trim)
        assert dc_gain < 0, f"Startup bass gain exceeds full scale: {dc_gain:.3f} dB"
    print("EQ_STARTUP_HEADROOM_OK")


def check_response():
    # Independent RBJ biquad model; multiply the actual graph's transfer functions.
    conf = (REPO / "config/pipewire/62-yoga-dolby-eq.conf").read_text()
    filters = []
    for line in conf.splitlines():
        m = re.search(
            r'name = (\w+L)\s+label = bq_(\w+).*?"Freq" =\s*(\S+)\s+"Q" =\s*(\S+)\s+"Gain" =\s*(\S+)',
            line,
        )
        if m:
            name, kind, freq, q, gain = m.groups()
            filters.append((name, kind, float(freq), float(q), float(gain)))
    trim_match = re.search(r'name = trimL.*?"Gain 1" = ([0-9.]+)', conf)
    assert trim_match and len(filters) == 5, "Complete filter chain required"
    trim = float(trim_match[1])

    def coefficients(kind, freq, q, gain):
        a = 10 ** (gain / 40)
        w = 2 * math.pi * freq / 48000
        c, alpha = math.cos(w), math.sin(w) / (2 * q)
        beta = 2 * math.sqrt(a) * alpha
        if kind == "peaking":
            return (1 + alpha * a, -2 * c, 1 - alpha * a), (
                1 + alpha / a,
                -2 * c,
                1 - alpha / a,
            )
        if kind == "lowshelf":
            return (
                a * ((a + 1) - (a - 1) * c + beta),
                2 * a * ((a - 1) - (a + 1) * c),
                a * ((a + 1) - (a - 1) * c - beta),
            ), (
                (a + 1) + (a - 1) * c + beta,
                -2 * ((a - 1) + (a + 1) * c),
                (a + 1) + (a - 1) * c - beta,
            )
        assert kind == "highshelf"
        return (
            a * ((a + 1) + (a - 1) * c + beta),
            -2 * a * ((a - 1) + (a + 1) * c),
            a * ((a + 1) + (a - 1) * c - beta),
        ), (
            (a + 1) - (a - 1) * c + beta,
            2 * ((a - 1) - (a + 1) * c),
            (a + 1) - (a - 1) * c - beta,
        )

    worst = -math.inf
    for pct in range(1, 101):
        curves = [
            coefficients(
                kind, freq, q, 4 + 15 * (1 - pct / 100) if name == "bassL" else gain
            )
            for name, kind, freq, q, gain in filters
        ]
        for sample in range(600):
            freq = 20 * 1000 ** (sample / 599)
            z = cmath.exp(-2j * math.pi * freq / 48000)
            response = trim * (pct / 100) ** 3
            for b, a in curves:
                response *= (b[0] + b[1] * z + b[2] * z * z) / (
                    a[0] + a[1] * z + a[2] * z * z
                )
            worst = max(worst, 20 * math.log10(abs(response)))
    assert worst < 0, f"Nominal volume range exceeds full scale: {worst:.3f} dB"
    print(f"EQ_RESPONSE_OK: 20 Hz..20 kHz at 1..100%, maximum {worst:.3f} dB")


if __name__ == "__main__":
    check_startup_headroom()
    check_sync()
    check_response()
