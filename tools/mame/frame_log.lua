-- MAME autoboot script: save every frame and log blitter starts, for
-- frame-latency comparison with the HDL simulation (scripts/mame_latency.py).
--
--   mame shangha3j -rompath ROMS -video none -sound none -nothrottle \
--        -snapview native -autoboot_script tools/mame/frame_log.lua
--
-- Environment: S3_OUT (output folder, give an ABSOLUTE path), S3_FRAMES (default 1700),
--   S3_GO (hex address of the blitter-go register: 200008 for shangha3 and
--   heberpop (default), 100008 for blocken).
-- Writes OUT/f00001.png ... (one per frame, native 384x224) and OUT/log.txt:
--   GO   <n> snaps=<snapshots saved so far> frame=<screen frame> t=<emulated seconds>
--   SNAP <n> frame=<screen frame>
local out    = os.getenv("S3_OUT") or "s3_mame"
local frames = tonumber(os.getenv("S3_FRAMES") or "1700")
local scr    = manager.machine.screens[":screen"]
local space  = manager.machine.devices[":maincpu"].spaces["program"]
local go_at  = tonumber(os.getenv("S3_GO") or "200008", 16)
os.execute('mkdir "' .. out .. '" 2>nul || mkdir -p "' .. out .. '"')
local log    = io.open(out .. "/log.txt", "w")
local snaps, gos = 0, 0

go_tap = space:install_write_tap(go_at, go_at + 1, "s3go", function(offset, data, mask)
    gos = gos + 1
    log:write(string.format("GO %d snaps=%d frame=%d t=%.6f\n", gos, snaps, scr:frame_number(), manager.machine.time:as_double()))
end)

frame_sub = emu.add_machine_frame_notifier(function()
    snaps = snaps + 1
    local fn = string.format("%s/f%05d.png", out, snaps)
    scr:snapshot(fn)
    log:write(string.format("SNAP %d frame=%d\n", snaps, scr:frame_number()))
    if snaps >= frames then log:close(); manager.machine:exit() end
end)
