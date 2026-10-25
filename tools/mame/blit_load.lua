-- MAME autoboot script (shangha3 / shangha3j): per frame, the blitter workload
-- (commands, clipped destination area, tilemap cells) at each go, the vblank IRQ
-- and the moment the main loop raises its "update done" flag (307906).
-- Used to calibrate the v0.1.10 blitter bus-hold model; see docs/DEVELOPMENT.md.
--   S3_OUT=/abs/dir [S3_COIN=900] [S3_FRAMES=3600] mame shangha3j ... -autoboot_script tools/mame/blit_load.lua
-- per blitter GO: command count, clipped destination area, tilemap cells, plus main-loop wait flag timing
local out = os.getenv("S3_OUT")
local coinf = tonumber(os.getenv("S3_COIN") or "-1")
local frames = tonumber(os.getenv("S3_FRAMES") or "3600")
os.execute('mkdir -p "' .. out .. '"')
local log = io.open(out .. "/blitload.txt", "w")
local function t() return manager.machine.time:as_double() end
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local gl = 0
ltap = sp:install_write_tap(0x360000, 0x360001, "l", function(o, d, m) gl = d end)
wtap = sp:install_write_tap(0x307906, 0x307907, "w", function(o, d, m) if d ~= 0 then log:write(string.format("%.7f WAIT\n", t())) end end)
atap = sp:install_write_tap(0x20000a, 0x20000b, "a", function(o, d, m) log:write(string.format("%.7f IRQ\n", t())) end)
gtap = sp:install_write_tap(0x200008, 0x200009, "g", function(o, d, m)
    local cmds, area, tiles, rows = 0, 0, 0, 0
    local offs = gl * 8
    while offs < 0x8000 do
        local base = 0x300000 + offs * 2
        local w4 = sp:read_u16(base + 8)
        local sx = (sp:read_u16(base + 4) & 0x1ff0) >> 4; if sx >= 0x180 then sx = sx - 0x200 end
        local sy = (sp:read_u16(base + 6) & 0x1ff0) >> 4; if sy >= 0x100 then sy = sy - 0x200 end
        local szx, szy = sp:read_u16(base + 12), sp:read_u16(base + 14)
        if (szx ~= 0 or szy ~= 0) and szx < 512 and szy < 256 then
            cmds = cmds + 1
            local x0, x1 = math.max(sx, 0), math.min(sx + szx, 383)
            local y0, y1 = math.max(sy, 16), math.min(sy + szy, 239)
            if x1 >= x0 and y1 >= y0 then area = area + (x1 - x0 + 1) * (y1 - y0 + 1); rows = rows + (y1 - y0 + 1) end
            if (w4 & 8) ~= 0 then tiles = tiles + ((szx + 15) // 16 + 1) * ((szy + 15) // 16 + 1) end
        end
        offs = offs + 16
    end
    log:write(string.format("%.7f GO cmds=%d area=%d tiles=%d rows=%d\n", t(), cmds, area, tiles, rows))
end)
local P = manager.machine.ioport.ports
local coin, start = P[":SYSTEM"].fields["Coin 1"], P[":SYSTEM"].fields["1 Player Start"]
local n = 0
sub = emu.add_machine_frame_notifier(function()
    n = n + 1
    if coinf >= 0 then
        coin:set_value((n >= coinf and n < coinf + 6) and 1 or 0)
        start:set_value((n >= coinf + 60 and n < coinf + 66) and 1 or 0)
    end
    if n >= frames then log:close(); manager.machine:exit() end
end)
