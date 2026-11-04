-- assets/conky/kali-setup-classic.lua — помощник для kali-setup-classic.conf.
-- Заметки из ~/notes.txt в виде текста Conky (через ${lua_parse notes}):
-- «# » — заголовок, «x » в начале — сделано (бледным), остальное — пункт списка.

local NOTES = (os.getenv('HOME') or '') .. '/notes.txt'
local NOTES_MAX = 8     -- строк заметок на виджете
local WIDTH = 46        -- символов в строке (моноширинный шрифт)

local function cut(s)
    if #s <= WIDTH then return s end
    -- режем по символам UTF-8, а не байтам, чтобы не порвать кириллицу
    local out, n = {}, 0
    for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        n = n + 1
        if n >= WIDTH then break end
        out[#out + 1] = ch
    end
    return table.concat(out) .. '…'
end

function conky_notes()
    local f = io.open(NOTES, 'r')
    if not f then return '${color4} пусто — ~/notes.txt' end
    local out = {}
    for l in f:lines() do
        if #out >= NOTES_MAX then break end
        if l:match('%S') then
            l = l:gsub('%$', '$$')   -- «$» в заметке не должен стать переменной Conky
            if l:match('^#+%s') then
                out[#out + 1] = '${color1}' .. cut(l:gsub('^#+%s+', ''))
            elseif l:match('^x%s') then
                out[#out + 1] = '${color4} ✓ ' .. cut(l:gsub('^x%s+', ''))
            else
                out[#out + 1] = '${color} • ' .. cut(l:gsub('^%s*[-*•]%s*', ''))
            end
        end
    end
    f:close()
    if #out == 0 then return '${color4} пусто — ~/notes.txt' end
    return table.concat(out, '\n')
end
