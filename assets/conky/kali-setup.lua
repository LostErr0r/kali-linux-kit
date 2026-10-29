-- assets/conky/kali-setup.lua — виджет Conky для XFCE (kali-setup).
-- Рисует всё через Cairo: часы, кольца CPU/RAM/диск, сеть с графиками, VPN,
-- заметки из ~/notes.txt (правка — Win+N или любой редактор, виджет обновляется сам).
-- Цвета палитры берутся из kali-setup-colors.lua рядом (его пишет шаг xextras).

require 'cairo'
pcall(require, 'cairo_xlib')

local dir = debug.getinfo(1, 'S').source:match('^@(.*/)') or './'
local ok, pal = pcall(dofile, dir .. 'kali-setup-colors.lua')
if not ok or type(pal) ~= 'table' then
    pal = { fg = '#eeeeee', acc = '#1a73e8', bg = '#212121' }
end

local W = 300           -- ширина виджета
local FONT = 'Inter'
local HIST = 60         -- точек в графике сети (секунд)
local down_hist, up_hist = {}, {}
local NOTES = (os.getenv('HOME') or '') .. '/notes.txt'
local NOTES_MAX = 10    -- строк заметок на виджете

local function rgb(hex, a)
    local r, g, b = hex:match('#(%x%x)(%x%x)(%x%x)')
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, a or 1
end

local function num(s) return tonumber(s) or 0 end
local function parse(s) return conky_parse(s) or '' end

local function text(cr, s, x, y, size, color, alpha, bold, align)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    tolua.takeownership(ext)
    cairo_text_extents(cr, s, ext)
    if align == 'center' then x = x - ext.width / 2 - ext.x_bearing
    elseif align == 'right' then x = x - ext.width - ext.x_bearing end
    cairo_set_source_rgba(cr, rgb(color, alpha))
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, s)
end

local function ring(cr, x, y, r, pct, label, value)
    local start, sweep = -math.pi / 2, 2 * math.pi
    cairo_set_line_width(cr, 7)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_new_path(cr)   -- иначе дуга соединится линией с концом предыдущего текста
    cairo_set_source_rgba(cr, rgb(pal.fg, 0.12))
    cairo_arc(cr, x, y, r, 0, sweep)
    cairo_stroke(cr)
    if pct > 0 then
        cairo_new_path(cr)
        cairo_set_source_rgba(cr, rgb(pal.acc, 1))
        cairo_arc(cr, x, y, r, start, start + sweep * math.min(pct, 100) / 100)
        cairo_stroke(cr)
    end
    text(cr, value, x, y + 6, 16, pal.fg, 1, true, 'center')
    text(cr, label, x, y + r + 22, 11, pal.fg, 0.7, false, 'center')
end

local function push(hist, v)
    table.insert(hist, v)
    if #hist > HIST then table.remove(hist, 1) end
end

-- график-заливка: значения hist в прямоугольнике x,y,w,h
local function graph(cr, hist, x, y, w, h, alpha)
    local maxv = 1
    for _, v in ipairs(hist) do if v > maxv then maxv = v end end
    local step = w / (HIST - 1)
    local x0 = x + w - (#hist - 1) * step
    cairo_new_path(cr)
    cairo_move_to(cr, x0, y + h)
    for i, v in ipairs(hist) do
        cairo_line_to(cr, x0 + (i - 1) * step, y + h - h * v / maxv)
    end
    cairo_line_to(cr, x + w, y + h)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, rgb(pal.acc, alpha))
    cairo_fill(cr)
end

local function speed(kib)
    if kib >= 1024 then return string.format('%.1f MiB/s', kib / 1024) end
    return string.format('%.0f KiB/s', kib)
end

-- разбить строку на куски, которые влезают в ширину w
local function wrap(cr, s, w, size)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    tolua.takeownership(ext)
    local out, line = {}, ''
    for word in s:gmatch('%S+') do
        local try = line == '' and word or (line .. ' ' .. word)
        cairo_text_extents(cr, try, ext)
        if ext.width > w and line ~= '' then
            table.insert(out, line); line = word
        else
            line = try
        end
    end
    if line ~= '' then table.insert(out, line) end
    return out
end

local function read_notes()
    local f = io.open(NOTES, 'r')
    if not f then return {} end
    local lines = {}
    for l in f:lines() do
        if l:match('%S') then table.insert(lines, l) end
    end
    f:close()
    return lines
end

local function section(cr, title, y)
    text(cr, title, 0, y, 11, pal.acc, 1, true)
    cairo_set_source_rgba(cr, rgb(pal.fg, 0.15))
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, 0, y + 7); cairo_line_to(cr, W, y + 7)
    cairo_stroke(cr)
end

function conky_main()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    cairo_translate(cr, 10, 0)

    -- Часы и дата
    text(cr, parse('${time %H:%M}'), W / 2, 62, 56, pal.fg, 1, true, 'center')
    text(cr, parse('${time %A, %d %B}'), W / 2, 90, 14, pal.acc, 1, false, 'center')
    text(cr, 'в работе ' .. parse('${uptime_short}'), W / 2, 110, 11, pal.fg, 0.6, false, 'center')

    -- Кольца
    local cpu, mem, disk = num(parse('${cpu}')), num(parse('${memperc}')), num(parse('${fs_used_perc /}'))
    ring(cr, 50, 168, 34, cpu, 'CPU', cpu .. '%')
    ring(cr, 150, 168, 34, mem, 'RAM', mem .. '%')
    ring(cr, 250, 168, 34, disk, 'Диск', disk .. '%')

    -- Сеть: интерфейс по умолчанию + VPN
    local y = 250
    section(cr, 'СЕТЬ', y)
    local iface = parse('${gw_iface}')
    if iface == '' or iface == 'multiple' then iface = 'eth0' end
    y = y + 28
    text(cr, iface, 0, y, 12, pal.fg, 0.7)
    text(cr, parse('${addr ' .. iface .. '}'), W, y, 12, pal.fg, 1, true, 'right')
    for _, vpn in ipairs({ 'tun0', 'amn0', 'wg0' }) do
        if parse('${if_up ' .. vpn .. '}1${endif}') == '1' then
            y = y + 20
            text(cr, 'VPN ' .. vpn, 0, y, 12, pal.acc, 1, true)
            text(cr, parse('${addr ' .. vpn .. '}'), W, y, 12, pal.fg, 1, true, 'right')
        end
    end
    y = y + 20
    text(cr, 'внешний IP', 0, y, 12, pal.fg, 0.7)
    text(cr, parse('${execi 900 curl -s --max-time 4 https://api.ipify.org}'), W, y, 12, pal.fg, 1, false, 'right')

    -- Графики загрузки и отдачи
    local down, up = num(parse('${downspeedf ' .. iface .. '}')), num(parse('${upspeedf ' .. iface .. '}'))
    push(down_hist, down); push(up_hist, up)
    y = y + 26
    text(cr, '↓ ' .. speed(down), 0, y, 12, pal.fg, 1)
    text(cr, '↑ ' .. speed(up), W, y, 12, pal.fg, 1, false, 'right')
    graph(cr, down_hist, 0, y + 8, W / 2 - 6, 34, 0.55)
    graph(cr, up_hist, W / 2 + 6, y + 8, W / 2 - 6, 34, 0.35)

    -- Заметки: строки с «# » — заголовки, «x » в начале — сделано (бледным)
    y = y + 76
    section(cr, 'ЗАМЕТКИ', y)
    y = y + 4
    local shown = 0
    for _, l in ipairs(read_notes()) do
        local color, alpha, bold, s = pal.fg, 1, false, l
        if l:match('^#+%s') then
            color, bold, s = pal.acc, true, l:gsub('^#+%s+', '')
        elseif l:match('^x%s') then
            alpha, s = 0.4, '✓ ' .. l:gsub('^x%s+', '')
        elseif not l:match('^%s*[-*•]') then
            s = '• ' .. l
        end
        for n, part in ipairs(wrap(cr, s, W - 12, 12)) do
            if shown >= NOTES_MAX then break end
            y = y + 19
            text(cr, part, n > 1 and 12 or 0, y, 12, color, alpha, bold)   -- перенос — с отступом
            shown = shown + 1
        end
    end
    if shown == 0 then
        y = y + 19
        text(cr, 'пусто — Win+N, чтобы добавить', 0, y, 12, pal.fg, 0.5)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
