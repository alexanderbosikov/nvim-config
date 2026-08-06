-- Нормализация ячеек с магикой языка в markdown-представлении jupytext.
--
-- jupytext хранит такую ячейку не как есть: язык уезжает в info-строку фенса,
-- аргументы магики — в cell metadata `magic_args`, а строка магики из тела
-- удаляется.
--
--     .ipynb                     markdown-представление
--     %%sql df <<          ->    ```sql magic_args="df <<"
--     select 1                   select 1
--                                ```
--
-- Для molten это смертельно: он отдаёт ядру тело фенса, а магики там уже нет —
-- ядро получает чистый SQL и падает на SyntaxError. Поэтому при чтении
-- возвращаем ячейку к виду из .ipynb: ```python-фенс, магика первой строкой.
-- Обратное преобразование не нужно — при записи jupytext снова вынесет язык
-- в info-строку, .ipynb получается тот же.
--
-- Только sql: подсветка и commentstring для таких ячеек лежат в
-- after/queries/markdown/*.scm и написаны под `%%sql`. Чтобы добавить ещё один
-- язык магики (%%bash и т.п.) — MAGIC_LANGS здесь + пара паттернов там.
local M = {}

local MAGIC_LANGS = { sql = true }

---@param lines string[] строки буфера (markdown-представление ноутбука)
---@return string[]|nil новые строки; nil — если менять нечего
function M.normalize(lines)
    local out, changed = {}, false
    local fence, in_region = nil, false
    for _, line in ipairs(lines) do
        if fence then
            -- внутри фенса: закрывающий — те же (или более длинные) бэктики
            if line:match("^" .. fence .. "`*%s*$") then
                fence = nil
            end
            table.insert(out, line)
        elseif line:match("^<!%-%- #region") then
            in_region = true
            table.insert(out, line)
        elseif line:match("^<!%-%- #endregion") then
            in_region = false
            table.insert(out, line)
        else
            local ticks, rest = line:match("^(```+)(.*)$")
            if not ticks then
                table.insert(out, line)
            else
                fence = ticks
                local lang, tail = rest:match("^(%S+)(.*)$")
                -- фенс внутри <!-- #region ... #endregion --> — это блок кода
                -- в markdown-ячейке (пример в документации), а не ячейка
                -- ноутбука: такими метками jupytext как раз и огораживает
                -- markdown-ячейки с фенсами внутри
                if in_region or not lang or not MAGIC_LANGS[lang] then
                    table.insert(out, line)
                else
                    local args = tail:match('magic_args="(.-)"')
                    -- остальная cell metadata (tags= и т.п.) остаётся на фенсе
                    tail = tail:gsub('%s*magic_args=".-"', "", 1)
                    table.insert(out, ticks .. "python" .. tail)
                    if args and args ~= "" then
                        table.insert(out, "%%" .. lang .. " " .. args)
                    else
                        table.insert(out, "%%" .. lang)
                    end
                    changed = true
                end
            end
        end
    end
    return changed and out or nil
end

return M
