# Speaker amp power logic for the Yoga Book 9 13IRU8: judge's verdict

Leave `Speaker Force Firmware Load` on from boot and let WirePlumber close the speaker PCM again after a short idle period. Neither part is tested yet: no reload, pop or power measurement has been run on this machine.

I read both final answers (`r2/a1.md`, `r2/a2.md`) and the board. I made two read-only checks myself: `/proc/asound/card0/pcm0p/sub0/status` and `config/wireplumber/52-yoga-speakers-keep-open.conf`. My Bash commands were denied, so I could not read battery power, runtime-PM status or `pw-top`.

The two answers agree on everything important; the leftover differences are settled below. The kernel claims come from a1 and a2 reading the v7.2 and mainline source; a2 also disassembled the installed 7.2.5 `tasdevice_config_put`. I did not re-read the kernel source myself.

## 1. Where the 0.65 W goes

**The amps are the small part.** The TAS2781 datasheet (SLOSE86B §6.5, p. 9–10) gives idle currents of AVDD ~15.5 mA at 1.8 V, PVDDL ~2.2 mA at 3.8 V and PVDDH 0.04–3 mA. Scaled to 8–12 V, two amps playing silence draw:

| Power mode | Two amps |
|---|---|
| PWR_MODE1 | ≈ 0.07 W |
| PWR_MODE0 / PWR_MODE2 | ≈ 0.11–0.13 W |
| Software shutdown | ≈ 40 µW |

Regulator losses add a little. So at least ~0.5 W is on the SoC side.

**What keeps the SoC busy is now explained.** The PCM status file shows:
- `state: RUNNING`
- `trigger_time 6084.8`, `tstamp 8393.2`: about 38 minutes of continuous running
- `hw_ptr` advancing, owner pid 835 (PipeWire)

The cause is the keep-open config. With `session.suspend-timeout-seconds = 0` the sink is never suspended, and PipeWire's ALSA sink does not pause when idle. It keeps writing zeros through the HDA DMA, the SOF pipeline and the graph's timer and IRQ wakeups. So the "PCM open but paused" state never occurs on this setup. The cost is:
- SOF DSP and HDA link active
- ALC287 in D0
- periodic DMA interrupts and PipeWire graph cycles, which plausibly also block deep package C-states (not yet proven: see below)

Both answers reported `low_power_idle_cpu_residency_us = 0` from earlier runs. It was read while the PCM was running and the machine was busy, so it says nothing yet about the closed baseline.

**A read-only split.** RAPL `energy_uj` is denied and `turbostat` needs root, so use what an ordinary user can read. Average `/sys/class/power_supply/BAT*/power_now` over 2–3 minutes per state, on battery, with fixed brightness and an idle workload. Record the PCM `status`, `power/runtime_status` of `0000:00:1f.3` and `i2c-TIAS2781:00`, and the LPIT residency counter alongside each one:

| State | What is on | Notes |
|---|---|---|
| S0 | Amps active (held by the udev rule), DSP suspended, PCM closed | Fresh boot, before any sound |
| S1 | Everything off | Only after the new design closes the PCM. Note whether the LPIT counter starts moving |
| S3 | Today's state: PCM running silence | — |

- S0 − S1 is the amps; S3 − S0 is SOF/HDA/codec plus graph wakeups.
- The 8.93 W "closed" baseline was most likely taken in S0. If so, the whole 0.65 W is SoC and audio-path cost, not the amps.
- Amps versus their regulators cannot be separated without a rail measurement.

## 2. The calibration bug

**Still present in v7.2 and mainline.** Neither answer found a fixing commit through August 2026 (f6635d6, 431c156 and b601633 do not touch it). The mechanism:
- **OPEN:** `tas2781_hda_playback_hook` takes a runtime-PM reference, then `tasdevice_tuning_switch(priv, 0)` calls `tasdevice_select_tuningprm_cfg()`.
- **The skip:** `tasdev_load_calibrated_data()` runs only when the per-device `tasdevice[i].cur_conf != cfg_no`. Otherwise the driver logs `Unneeded loading dsp conf` and writes nothing.
- **CLOSE:** the shutdown block runs, but the per-device `cur_conf` is never invalidated.
- **History:** commit `bec7760a6c5f` removed the `cur_*` reset from runtime suspend, assuming software shutdown keeps the registers. That holds for the chip but apparently not for Lenovo's firmware blocks. Which block actually clobbers the calibration is not decoded.

**The README's workaround is wrong.** `tasdevice_config_put()` only stores `tas_priv->cur_conf` and writes no hardware. Toggling `Speaker Config Id` 1 → 0 between two OPENs does nothing. It only helps if a PCM OPEN happens while the value is 1 and another after it returns to 0, and that dance risks `alsactl store` saving `Config Id = 1`. The README section and the comment in `52-yoga-speakers-keep-open.conf` should be corrected.

**The minimal action:** set `Speaker Force Firmware Load` (numid=3) to on, **before** OPEN.
- The flag is persistent and is checked inside the OPEN hook.
- When set, the driver resets the per-device `cur_prog`/`cur_conf`, then reloads program → config → calibration → the pre-power-up block, all synchronously inside `open()`.
- Set after an OPEN, it only fixes the *next* OPEN. So set it once and leave it on.
- The first OPEN after boot is calibrated anyway: `cur_conf` starts at −1. After system suspend, `tas2781_system_resume` resets everything, and the flag lives in RAM, so it survives suspend.
- "Guaranteed" means the reload *path* is guaranteed. Whether the writes succeed is not reported: `tasdev_load_calibrated_data` returns void and has silent early returns.

## 3. Amps off while the PCM stays alive

**No.** There is no kcontrol for amp power:
- numid 7 and 9 are codec pin switches.
- Mute leaves the Class-D stage switching.
- The OPEN hook holds a runtime-PM reference until CLOSE, so runtime suspend is impossible while the PCM is open, whatever `power/control` says.
- `tas2781_runtime_resume` only calls `tasdevice_prmg_load()` and does not reload calibration.
- Raw I2C writes would desynchronise the driver's cache.

It would also save only ~0.1 W while the expensive part, the running SOF/HDA path, stays on. Not worth pursuing.

## 4. Proposed logic

**Pick option (d): a static flag plus normal idle suspend.** The kernel's own OPEN/CLOSE hook is already the event-driven trigger, so no watcher is needed.

| Option | Verdict |
|---|---|
| (a) WirePlumber Lua hook on node state | Fires after OPEN — too late for calibration |
| (b) `pactl subscribe` / `pw-mon` watcher | Same lateness, plus an extra process and reconnect races |
| (c) Suspend timeout per power source | Policy only, does not fix calibration. Optional later layer |
| (d) Force flag + idle suspend | **Chosen** — the reload runs synchronously inside `open()`, so there is no race |
| (e) Kernel patch: invalidate `cur_conf` on CLOSE | The proper long-term fix, much cheaper than a full program reload. Worth sending to linux-sound after confirming it works here |

**Implementation sketch:**

1. **`bin/yoga-amp-arm`**, run by a user oneshot unit `After=wireplumber.service` (and after the system `alsa-restore`):
   ```bash
   #!/bin/bash
   # Force Firmware Load makes every PCM open reload program+config+calibration
   # (tasdevice_select_tuningprm_cfg skips calibration when cur_conf is unchanged).
   # The control appears only after the async firmware load, hence the bounded wait.
   for _ in $(seq 50); do
     amixer -c sofhdadsp -q cset name='Speaker Force Firmware Load' on 2>/dev/null &&
       amixer -c sofhdadsp cget name='Speaker Force Firmware Load' | grep -q 'values=on' && exit 0
     sleep 0.2
   done
   exit 1
   ```
   This is a bounded one-time wait at boot, not polling while idle. a2 preferred waiting on a control-add event (`alsactl monitor` or a udev rule on the sound card), which is cleaner but more code. Either is acceptable. Re-run the unit if the tas2781 modules are reloaded.
2. **In `52-yoga-speakers-keep-open.conf`**, change `session.suspend-timeout-seconds` from `0` to `15`.
   - a2 proposed 3–5 s; a1 proposed 10–30 s. I side with a1: a full reload reportedly costs 2–3 s per OPEN on the Yoga Pro 9 16IMH9 (linux-sound, 2026-06-07), so a short timeout would delay sounds after every pause.
   - Tune it after measuring the reload time here. Making it 0 on AC is possible later.
3. **Keep the udev rule for now.** Remove it in a separate later step, so a regression can be traced to one change.

**Failure modes:**
- **Start delay:** each OPEN after idle waits for the reload (unknown here, possibly seconds). Short notification sounds may be clipped or late. Getting the first 100 ms right is not promised.
- **Pop/click:** possible during reload or shutdown; the datasheet's 0.8 mV figure is for the chip alone. Measure the whole chain.
- **Sink never idles:** another client, `yoga_dolby` held running, or capture keeps the PCM or DSP active, so nothing is saved. Check with `wpctl status` / `pw-top`.
- **ALSA state across reboot:** `alsactl restore` may restore the flag as off or a stale `Config Id`. Hence arming after restore, and never leaving `Config Id = 1` saved.
- **Reload failure:** an I2C error mid-reload plays that stream uncalibrated with no error returned. Watch the kernel log for `bulk_wr` / `process_block` errors.

**Verification plan** (dynamic debug and tracing need root):
1. Enable `module snd_soc_tas2781_fmwlib +p` and `module snd_hda_scodec_tas2781_i2c +p` in dynamic debug.
2. With the flag off, a reopen logs `Unneeded loading dsp conf`. This reproduces the bug.
3. With the flag on, that line is gone and program/config loading is logged. Then confirm the calibration writes themselves with a kprobe or ftrace on the tas2781 bulk-write path, for both amps: addresses and return codes. A missing skip line alone is not proof.
4. Take the OPEN-to-first-audio latency from journal timestamps.
5. Record a sweep with the internal mic after boot and after a reopen, and compare the 100–300 Hz band. The sink monitor is digital and cannot see amp calibration.
6. When idle, check that:
   - the PCM `status` reads `closed`
   - `0000:00:1f.3` and `i2c-TIAS2781:00` read `suspended` (the I2C one only once the udev rule is gone)
   - `power_now` is back near 8.9 W
   - the LPIT counter moves
7. Repeat across a short pause, a pause longer than the timeout, suspend/resume, a WirePlumber restart and a reboot.

## Unresolved issues

- Which Lenovo firmware block destroys the calibration (shutdown or power-up) is not decoded.
- The real reload latency, pop behaviour and amp power mode on this machine are not measured.
- Whether package C10 becomes reachable once the PCM closes is not shown.
- The exact split between amps, codec, DSP and regulators needs a rail measurement or the S0/S1/S3 battery comparison above.
- No upstream fix exists; the kernel patch in (e) is a hypothesis until tested.

Sources: Linux v7.2 `sound/hda/codecs/side-codecs/tas2781_hda_i2c.c` and `tas2781_hda.c`; `sound/soc/codecs/tas2781-fmwlib.c` (`tasdevice_select_tuningprm_cfg`, `tasdev_load_calibrated_data`, `tasdevice_tuning_switch`); commit `bec7760a6c5f`; TI TAS2781 datasheet SLOSE86B §6.5 and §8.5; WirePlumber `src/scripts/node/suspend-node.lua`.
