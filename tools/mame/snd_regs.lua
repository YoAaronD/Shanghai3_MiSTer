-- MAME autoboot script (shangha3 / shangha3j): log every YM2149 and OKI M6295
-- write with its emulated time, as input for scripts/snd_replay.sh.
--
--   S3_OUT=/abs/dir S3_FRAMES=14400 mame shangha3j -rompath ROMS -video none \
--       -sound none -nothrottle -wavwrite /abs/dir/mame.wav \
--       -autoboot_script tools/mame/snd_regs.lua
--
-- Environment:
--   S3_OUT     absolute output folder (snd_log.txt, snapshots)
--   S3_FRAMES  frames to run (default 14400 = 4 min)
--   S3_COIN    frame to insert a coin and press Start 60 frames later
--              (default: none, attract mode only; 900 = after the self-test)
--   S3_SNAP    snapshot every N frames (default 600)
-- Writes OUT/snd_log.txt: "<t> AYA <reg>", "<t> AYD <data>", "<t> OKI <data>".
-- Notes from v0.1.6 (20261022):
--   * The attract demo (about 68-80 s in) plays the same tune as a game on
--     Aaron's PCB clip; idle 1-player games play a different one.
--   * OKI phrases: 32-61 are the music's drums (attenuation 3 or 5);
--     3 = tile pick, 24 = season/flower pair, 27 = ending jingle (all att 0).
local out    = os.getenv("S3_OUT")
local frames = tonumber(os.getenv("S3_FRAMES") or "14400")
local coinf  = tonumber(os.getenv("S3_COIN") or "-1")
local snapn  = tonumber(os.getenv("S3_SNAP") or "600")
os.execute('mkdir -p "' .. out .. '"')
local log    = io.open(out .. "/snd_log.txt", "w")
local function t() return manager.machine.time:as_double() end
local sp = manager.machine.devices[":maincpu"].spaces["program"]
snd_tap = sp:install_write_tap(0x20002e, 0x20006f, "s3snd", function(offset, data, mask)
    local a = offset & ~1
    local byte = ((mask & 0x00ff) ~= 0) and (data & 0xff) or ((data >> 8) & 0xff)
    if a == 0x20002e then log:write(string.format("%.7f AYD %02X\n", t(), byte))
    elseif a == 0x20003e then log:write(string.format("%.7f AYA %02X\n", t(), byte))
    elseif a == 0x20006e then log:write(string.format("%.7f OKI %02X\n", t(), byte)) end
end)
local P = manager.machine.ioport.ports
local coin, start = P[":SYSTEM"].fields["Coin 1"], P[":SYSTEM"].fields["1 Player Start"]
local n = 0
frame_sub = emu.add_machine_frame_notifier(function()
    n = n + 1
    if coinf >= 0 then
        coin:set_value((n >= coinf and n < coinf + 6) and 1 or 0)
        start:set_value((n >= coinf + 60 and n < coinf + 66) and 1 or 0)
    end
    if snapn > 0 and n % snapn == 0 then
        manager.machine.screens[":screen"]:snapshot(string.format("%s/s%05d.png", out, n))
    end
    if n >= frames then log:close(); manager.machine:exit() end
end)
