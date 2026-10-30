-- MAME autoboot script: log the sound traffic of heberpop / blocken, as the
-- golden reference for the Z80 + YM3438 + OKI sound section.
--
--   S3_OUT=/abs/dir S3_FRAMES=3600 mame heberpop -rompath ROMS -video none \
--       -nothrottle -wavwrite /abs/dir/mame.wav -autoboot_script tools/mame/sound_log.lua
--
-- Environment: S3_OUT (absolute output folder), S3_FRAMES (default 3600 = 1 min),
--   S3_LATCH (hex address of the 68000 sound-latch byte: 20000F heberpop (default),
--   10000F blocken), S3_COIN (hex address of the coin-control byte, which also
--   selects the OKI ROM bank: 20000D heberpop (default), 10000D blocken).
-- Writes OUT/sound_log.txt, one line per event, time in emulated seconds:
--   <t> LATCH <data>          68000 -> sound latch
--   <t> COIN <data>           68000 coin control (OKI bank: heberpop bit 3, blocken bits 5:4)
--   <t> Z80W <port> <data>    Z80 I/O write (00-03 YM3438, 80 OKI, 40/41 unknown)
--   <t> Z80R <port> <data>    Z80 I/O read  (00-03 YM3438 status, 80 OKI status, C0 latch)
--   <t> FRAME <n>
-- Tested on heberpop (20261027): the Z80 writes match the core's simulation
-- write for write. shangha3j has no Z80, so the Z80 taps are skipped there.
local out    = os.getenv("S3_OUT") or "s3_sound"
local frames = tonumber(os.getenv("S3_FRAMES") or "3600")
local latch  = tonumber(os.getenv("S3_LATCH") or "20000F", 16)
local coin   = tonumber(os.getenv("S3_COIN") or "20000D", 16)
os.execute('mkdir "' .. out .. '" 2>nul || mkdir -p "' .. out .. '"')
local log    = io.open(out .. "/sound_log.txt", "w")
local function t() return manager.machine.time:as_double() end

local main = manager.machine.devices[":maincpu"].spaces["program"]
latch_tap = main:install_write_tap(latch & ~1, latch | 1, "s3latch", function(offset, data, mask)
    -- 16-bit bus: offset is word-aligned; the mask says which byte was written
    local byte = ((mask & 0x00ff) ~= 0) and (data & 0xff) or ((data >> 8) & 0xff)
    log:write(string.format("%.7f LATCH %02X\n", t(), byte))
end)

coin_tap = main:install_write_tap(coin & ~1, coin | 1, "s3coin", function(offset, data, mask)
    local byte = ((mask & 0x00ff) ~= 0) and (data & 0xff) or ((data >> 8) & 0xff)
    log:write(string.format("%.7f COIN %02X\n", t(), byte))
end)

local audio = manager.machine.devices[":audiocpu"]
if audio then
    local io = audio.spaces["io"]
    z80w_tap = io:install_write_tap(0x00, 0xff, "s3z80w", function(offset, data, mask)
        log:write(string.format("%.7f Z80W %02X %02X\n", t(), offset & 0xff, data & 0xff))
    end)
    z80r_tap = io:install_read_tap(0x00, 0xff, "s3z80r", function(offset, data, mask)
        log:write(string.format("%.7f Z80R %02X %02X\n", t(), offset & 0xff, data & 0xff))
        return data
    end)
else
    log:write("no :audiocpu on this machine (shangha3 has no Z80)\n")
end

local n = 0
frame_sub = emu.add_machine_frame_notifier(function()
    n = n + 1
    log:write(string.format("%.7f FRAME %d\n", t(), n))
    if n >= frames then log:close(); manager.machine:exit() end
end)
