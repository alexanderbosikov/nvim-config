-- cmp-источник: имена таблиц и колонок из кэша каталога nb_utils.
--
-- Зачем свой источник: в sql-ячейках ноутбука подсказок не даёт никто.
--   * cmp-dbee смотрит на filetype БУФЕРА (cmp-dbee/queries.lua:31), а буфер тут
--     markdown — sql живёт в нём только как инъекция treesitter; и грузится он
--     по ft = "sql", т.е. в ноутбуке не грузится вообще;
--   * каталожный matcher nb_utils (nb_utils/completion.py) висит в
--     ip.Completer.custom_matchers, т.е. живёт В ЯДРЕ и приезжает по
--     complete_request — сообщению, которого сайдкар jupyter.nvim пока не умеет.
--
-- Читаем тот же кэш, что и матчер в Lab: ~/.cache/nb_utils/schema/*.json,
-- формат {"saved_at": ..., "columns": {"схема.таблица": [[колонка, тип, nullable], ...]}}.
-- Обновляется он не отсюда, а из Jupyter — nb_utils.catalog.refresh_schema().
-- В БД не ходим никогда, живое ядро и подключение dbee не нужны.
--
-- Три позиции подсказки:
--   1. после from/join — CTE ячейки и таблицы каталога. Ранжирование — порт
--      catalog.search_names: имя с начала, потом схема с начала, потом кусок
--      внутри имени. Лимита нет намеренно: в отличие от Lab, который спрашивает
--      ядро один раз и дальше фильтрует локально, cmp с isIncomplete = true
--      переспрашивает на каждый символ, так что потолок MAX_SUGGESTIONS с
--      теряющимся хвостом здесь не нужен;
--   2. после `алиас.` / `схема.таблица.` — колонки этого отношения;
--   3. в остальных позициях (select-список, where, group by) — колонки ВСЕХ
--      отношений текущего запроса, источник виден в detail.
--
-- Про колонки, которые в Lab не поддержаны (nb_utils/CLAUDE.md: «нужен резолв
-- алиасов по всей ячейке, а колонки CTE вообще требуют разбора её select-списка»).
-- Здесь оба куска решаются, но РАЗНЫМИ инструментами, и это не вкусовщина:
--   * отношения и алиасы берём текстом. Пока строку с курсором дописывают, она
--     синтаксически битая, и sql-парсер съедает вместе с ней весь хвост запроса:
--     на `select b.` + `from base b` ниже from не попадает в дерево вообще
--     (проверено — из `from` получается ERROR-узел), т.е. AST именно там, где
--     нужен, недоступен;
--   * колонки CTE — деревом. Тело CTE лежит в скобках выше курсора, оно всегда
--     дописано и парсится нормально даже при битом хвосте; вытащить из его
--     select-списка выходные имена (алиасы, поля, раскрытие `*` по своим же
--     отношениям, вложенные CTE) регуляркой нельзя, а по дереву — ровно и с
--     переносом типа колонки из каталога.
-- Область видимости ограничиваем скобочной группой вокруг курсора и режем
-- вложенные скобки: иначе в подсказки внутри одной CTE лезут отношения соседних.
local M = {}

local SCHEMA_DIR = vim.fn.expand("~/.cache/nb_utils/schema")
local RECHECK_SEC = 5 -- как часто сверять mtime кэша; разбор json — только при изменении
local MAX_CTE_DEPTH = 8 -- CTE поверх CTE; заодно страховка от циклов вместе с visited

-- Слова, которые стоят там же, где алиас (`from t where`, `join x on`),
-- и потому алиасом быть не могут.
local NOT_AN_ALIAS = {}
for word in ([[
  where group order limit offset having window qualify union except intersect
  join inner left right full cross outer natural on using as and or not
  select from with distinct lateral asof
]]):gmatch("%S+") do
  NOT_AN_ALIAS[word] = true
end

local cache = { stamp = "", checked_at = 0, names = {}, columns = {} }

-- --- кэш каталога -----------------------------------------------------------

local function load_catalog()
  local files = vim.fn.glob(SCHEMA_DIR .. "/*.json", false, true)
  local marks = {}
  for _, file in ipairs(files) do
    marks[#marks + 1] = file .. ":" .. vim.fn.getftime(file)
  end
  local stamp = table.concat(marks, ",")
  if stamp == cache.stamp then
    return
  end

  local columns, names = {}, {}
  for _, file in ipairs(files) do
    -- файл обычно один (одно подключение), но если их несколько — сливаем:
    -- имена в кэше полные, со схемой, так что пересечься им негде
    local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(file), "\n"))
    if ok and type(data) == "table" and type(data.columns) == "table" then
      for table_name, cols in pairs(data.columns) do
        if columns[table_name] == nil then
          names[#names + 1] = table_name
        end
        columns[table_name] = cols
      end
    end
  end
  table.sort(names)
  cache.stamp, cache.names, cache.columns = stamp, names, columns
end

local function ensure_catalog()
  local now = os.time()
  if now - cache.checked_at >= RECHECK_SEC then
    cache.checked_at = now
    pcall(load_catalog)
  end
  return #cache.names > 0
end

-- --- имена ------------------------------------------------------------------

local function split_name(name)
  local schema, tail = name:match("^(.*)%.([^.]*)$")
  if not schema then
    return nil, name
  end
  return schema, tail
end

local function unquote(name)
  return (name:gsub('"', ""))
end

-- Порт catalog.search_names: три группы по убыванию релевантности.
local function search_names(pattern, names)
  local low = (pattern or ""):lower()
  local schema_part, name_part = split_name(low)
  local dotted = schema_part ~= nil
  schema_part = schema_part or ""

  local starts, by_schema, contains = {}, {}, {}
  for _, name in ipairs(names) do
    local low_name = name:lower()
    local table_schema, table_name = split_name(low_name)
    table_schema = table_schema or ""
    if not (dotted and table_schema:sub(1, #schema_part) ~= schema_part) then
      if name_part == "" or table_name:sub(1, #name_part) == name_part then
        starts[#starts + 1] = name
      elseif not dotted and table_schema:sub(1, #name_part) == name_part then
        by_schema[#by_schema + 1] = name
      elseif table_name:find(name_part, 1, true) then
        contains[#contains + 1] = name
      end
    end
  end
  local out = starts
  vim.list_extend(out, by_schema)
  vim.list_extend(out, contains)
  return out
end

-- Полное имя таблицы каталога по (возможно короткому) имени.
local function resolve_table(name)
  local low = unquote(name:lower())
  if cache.columns[low] then
    return low
  end
  local hit
  for _, full in ipairs(cache.names) do
    if full:lower():match("%." .. vim.pesc(low) .. "$") then
      if hit then
        return nil -- хвост неоднозначен: угадывать не будем
      end
      hit = full
    end
  end
  return hit
end

local function table_columns(full_name)
  local out = {}
  for _, column in ipairs(cache.columns[full_name] or {}) do
    out[#out + 1] = { name = column[1], type = column[2] }
  end
  return out
end

-- --- позиция курсора в тексте ----------------------------------------------

-- Позиция подсказки таблицы: сразу после from/join, включая перечисление через
-- запятую (`from a, b, sy`). Завершённое имя с пробелом после сюда намеренно не
-- попадает — подсказывать там нечего.
local function relation_prefix(before)
  local prefix = before:match('([%w_%.%"]*)$')
  local head = before:sub(1, #before - #prefix):lower()
  while true do
    local trimmed = head:gsub('[%w_%.%"]+%s*,%s*$', "", 1)
    if trimmed == head then
      break
    end
    head = trimmed
  end
  if head:match("%f[%w_]from%s+$") or head:match("%f[%w_]join%s+$") then
    return prefix
  end
  return nil
end

-- Квалификатор перед точкой: алиас (`t.`) или имя таблицы (`site.sessions.`).
local function column_prefix(before)
  return before:match('([%a_][%w_%.%"]*)%.([%w_]*)$')
end

-- Слово под курсором для неквалифицированной колонки.
local function word_prefix(before)
  return before:match("([%a_][%w_]*)$") or ""
end

-- CTE, объявленные выше: `with x as (`, `, y as (`, `with recursive z as materialized (`.
-- Имена отдаём в нижнем регистре — верхний из lua-паттернов не восстановить, а
-- в наших запросах идентификаторы и так строчные.
local function cte_names(before)
  local text = before:lower():gsub("%s+not%s+materialized%s*%(", " ("):gsub("%s+materialized%s*%(", " (")
  local names, seen, pos = {}, {}, 1
  while true do
    local from, to, name = text:find("([%a_][%w_]*)%s+as%s*%(", pos)
    if not from then
      break
    end
    pos = to
    local head = text:sub(1, from - 1)
    local anchored = head:match(",%s*$") or head:match("%f[%w_]with%s+$") or head:match("%f[%w_]recursive%s+$")
    if anchored and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  return names
end

-- Скобочная группа, внутри которой стоит курсор: тело своей CTE или, на верхнем
-- уровне, весь запрос. Смещение — в байтах от начала ячейки.
local function enclosing_span(text, offset)
  local start, depth = 1, 0
  for i = offset, 1, -1 do
    local ch = text:sub(i, i)
    if ch == ")" then
      depth = depth + 1
    elseif ch == "(" then
      if depth == 0 then
        start = i + 1
        break
      end
      depth = depth - 1
    end
  end
  local stop, forward = #text, 0
  for i = offset + 1, #text do
    local ch = text:sub(i, i)
    if ch == "(" then
      forward = forward + 1
    elseif ch == ")" then
      if forward == 0 then
        stop = i - 1
        break
      end
      forward = forward - 1
    end
  end
  return text:sub(start, stop)
end

-- Всё внутри вложенных скобок — в пробелы, длина и переносы сохраняются.
-- Без этого `from` соседних подзапросов и CTE попадает в область видимости.
local function mask_nested(text)
  local out, depth = {}, 0
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == "(" then
      depth = depth + 1
      out[i] = " "
    elseif ch == ")" then
      depth = math.max(0, depth - 1)
      out[i] = " "
    elseif depth > 0 then
      out[i] = ch == "\n" and "\n" or " "
    else
      out[i] = ch
    end
  end
  return table.concat(out)
end

-- Отношения запроса: {ref = "web.t", alias = "t"}. Текстом, а не деревом —
-- строка под курсором битая, и парсер уносит с ней весь хвост запроса.
local function relations_in(text)
  local low = text:lower()
  local out, seen = {}, {}

  local function add(ref, alias)
    ref = unquote(ref)
    local key = ref .. "|" .. (alias or "")
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = { ref = ref, alias = alias }
    end
  end

  -- `ref [as] [alias]` начиная с pos; возвращает позицию после разобранного
  local function consume(pos)
    local _, ref_end, ref = low:find('^%s*([%w_%.%"]+)', pos)
    if not ref then
      return nil
    end
    local next_pos = ref_end + 1
    local _, alias_end, alias = low:find("^%s+as%s+([%a_][%w_]*)", next_pos)
    if not alias then
      _, alias_end, alias = low:find("^%s+([%a_][%w_]*)", next_pos)
      if alias and NOT_AN_ALIAS[alias] then
        alias, alias_end = nil, nil
      end
    end
    if alias_end then
      next_pos = alias_end + 1
    end
    add(ref, alias)
    return next_pos
  end

  for _, keyword in ipairs({ "from", "join" }) do
    local pos = 1
    while true do
      local from, to = low:find("%f[%w_]" .. keyword .. "%f[^%w_]", pos)
      if not from then
        break
      end
      pos = to + 1
      local next_pos = consume(to + 1)
      -- перечисление через запятую: `from a, b x, c`
      while next_pos do
        local _, comma_end = low:find("^%s*,", next_pos)
        if not comma_end then
          break
        end
        next_pos = consume(comma_end + 1)
      end
    end
  end
  return out
end

-- --- CTE: выходные колонки по дереву ---------------------------------------

local function node_text(node, text)
  return vim.treesitter.get_node_text(node, text)
end

local function child_of_type(node, wanted)
  for child in node:iter_children() do
    if child:type() == wanted then
      return child
    end
  end
end

-- Отношения запроса по дереву: тело CTE дописано, тут AST надёжен.
local function statement_relations(statement, text)
  local out = {}
  local function scan(node)
    for child in node:iter_children() do
      local kind = child:type()
      if kind == "relation" then
        local ref, alias
        for part in child:iter_children() do
          if part:type() == "object_reference" then
            ref = unquote(node_text(part, text)):lower()
          elseif part:type() == "identifier" then
            alias = unquote(node_text(part, text)):lower()
          end
        end
        if ref then -- подзапрос вместо имени: колонки оттуда не выводим
          out[#out + 1] = { ref = ref, alias = alias }
        end
      elseif kind == "join" or kind == "from" or kind == "set_operation" then
        scan(child)
      end
    end
  end
  scan(statement)
  return out
end

-- Что за колонка получается из терма select-списка.
local function term_output(term)
  local last
  for child in term:iter_children() do
    if child:named() then
      last = child
    end
  end
  if not last then
    return nil
  end
  local kind = last:type()
  if kind == "identifier" then
    return { alias = last } -- `count(*) as cnt`, `... revenue`
  elseif kind == "all_fields" then
    return { all_fields = last } -- `*`, `b.*`
  elseif kind == "field" then
    return { field = last } -- `user_id`, `a.user_id`
  end
  return nil -- выражение без алиаса: имени у колонки нет
end

local relation_columns -- взаимная рекурсия с cte_columns

-- Колонки CTE из её select-списка: алиасы, поля (с переносом типа из каталога),
-- раскрытие `*` по своим же отношениям, вложенные CTE.
local function cte_columns(name, ctx, visited, depth)
  local statement = ctx.ctes[name]
  if not statement or visited[name] or depth > MAX_CTE_DEPTH then
    return {}
  end
  if ctx.memo[name] then
    return ctx.memo[name]
  end
  visited[name] = true

  local out = {}
  -- `select … union all select …` заворачивается в set_operation, и select/from
  -- лежат уже в нём; имена колонок в SQL даёт первая ветка
  local body = child_of_type(statement, "set_operation") or statement
  local select_node = child_of_type(body, "select")
  local expr = select_node and child_of_type(select_node, "select_expression")
  if expr then
    local relations = statement_relations(body, ctx.text)

    -- тип колонки, если терм — просто поле: ищем по своим отношениям
    local function type_of(qualifier, column)
      for _, relation in ipairs(relations) do
        local matches = not qualifier
          or (relation.alias and relation.alias == qualifier)
          or relation.ref == qualifier
          or select(2, split_name(relation.ref)) == qualifier
        if matches then
          for _, col in ipairs(relation_columns(relation, ctx, visited, depth + 1)) do
            if col.name:lower() == column:lower() then
              return col.type
            end
          end
        end
      end
    end

    for term in expr:iter_children() do
      if term:type() == "term" then
        local info = term_output(term)
        if info and info.alias then
          out[#out + 1] = { name = node_text(info.alias, ctx.text) }
        elseif info and info.field then
          local qualifier, column = split_name(unquote(node_text(info.field, ctx.text)):lower())
          out[#out + 1] = { name = column, type = type_of(qualifier, column) }
        elseif info and info.all_fields then
          local qualifier = node_text(info.all_fields, ctx.text):match("^(.*)%.%*$")
          qualifier = qualifier and unquote(qualifier):lower() or nil
          for _, relation in ipairs(relations) do
            local matches = not qualifier
              or (relation.alias and relation.alias == qualifier)
              or relation.ref == qualifier
              or select(2, split_name(relation.ref)) == qualifier
            if matches then
              vim.list_extend(out, relation_columns(relation, ctx, visited, depth + 1))
            end
          end
        end
      end
    end
  end

  visited[name] = nil
  ctx.memo[name] = out
  return out
end

-- Колонки отношения: таблица каталога или CTE этой же ячейки.
function relation_columns(relation, ctx, visited, depth)
  local ref = relation.ref:lower()
  if ctx.ctes[ref] then
    return cte_columns(ref, ctx, visited or {}, depth or 1)
  end
  local full = resolve_table(ref)
  return full and table_columns(full) or {}
end

-- --- контекст в буфере ------------------------------------------------------

-- Мы внутри sql-инъекции? Возвращает текст ячейки целиком и до курсора.
-- Язык спрашиваем у treesitter, а не по фенсу глазами: инъекции описаны в
-- queries/markdown/injections.scm, и он тут единственный источник истины.
local function sql_region(bufnr, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end
  -- парсим только строку курсора: полный parse на длинном ноутбуке дорог, а
  -- инъекции в видимой части подсветка уже разобрала
  pcall(parser.parse, parser, { row, 0, row + 1, 0 })
  local got, tree_for_lang = pcall(parser.language_for_range, parser, { row, col, row, col })
  if not got or not tree_for_lang or tree_for_lang:lang() ~= "sql" then
    return nil
  end
  local tree = tree_for_lang:tree_for_range({ row, col, row, col })
  if not tree then
    return nil
  end
  local srow, scol, erow, ecol = tree:root():range()
  if srow > row then
    return nil
  end
  -- у незакрытого фенса в конце файла инъекция тянется до (число строк, 0) — на
  -- строку за последней, и get_text падает с Index out of bounds. Бывает, пока
  -- новая ячейка набирается руками. Прижимаем конец к последнему символу буфера
  local last = vim.api.nvim_buf_line_count(bufnr) - 1
  if erow > last then
    erow = last
    ecol = #vim.api.nvim_buf_get_lines(bufnr, last, last + 1, false)[1]
  else
    ecol = math.min(ecol, #vim.api.nvim_buf_get_lines(bufnr, erow, erow + 1, false)[1])
  end
  local whole = vim.api.nvim_buf_get_text(bufnr, srow, scol, erow, ecol, {})
  local head = vim.api.nvim_buf_get_text(bufnr, srow, scol, row, col, {})
  return table.concat(whole, "\n"), table.concat(head, "\n")
end

-- Разбор ячейки: карта CTE → её statement. Дерево строим по тексту ячейки, а не
-- по инъекции в буфере: инъекция парсится по видимой области, и CTE, уехавшая за
-- край экрана, из неё может быть не разобрана.
local parsed = { text = nil, ctes = {} }

local function cell_ctes(text)
  if parsed.text == text then
    return parsed.ctes
  end
  local ctes = {}
  local ok = pcall(function()
    local tree = vim.treesitter.get_string_parser(text, "sql"):parse()[1]
    local query = vim.treesitter.query.parse("sql", "(cte (identifier) @name (statement) @body)")
    -- iter_matches, а не iter_captures: у captures пары @name/@body пришлось бы
    -- склеивать порядком, и CTE без тела утащила бы тело следующей
    for _, match in query:iter_matches(tree:root(), text) do
      local nodes = {}
      for id, captured in pairs(match) do
        nodes[query.captures[id]] = type(captured) == "table" and captured[1] or captured
      end
      if nodes.name and nodes.body then
        ctes[unquote(node_text(nodes.name, text)):lower()] = nodes.body
      end
    end
  end)
  if not ok then
    ctes = {}
  end
  parsed.text, parsed.ctes = text, ctes
  return ctes
end

-- --- источник cmp -----------------------------------------------------------

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  -- только markdown: sql-ячейки ноутбука — это инъекция в markdown-буфере.
  -- В .sql-файлах то же самое уже отдаёт cmp-dbee, дублировать список не надо.
  return vim.bo.filetype == "markdown"
end

function source:get_debug_name()
  return "nb_catalog"
end

function source:get_trigger_characters()
  return { "." }
end

function source:complete(params, callback)
  local empty = { items = {}, isIncomplete = false }
  if not ensure_catalog() then
    return callback(empty)
  end

  local row = params.context.cursor.row - 1
  local col = params.context.cursor.col - 1
  local cell, before = sql_region(vim.api.nvim_get_current_buf(), row, col)
  if not cell then
    return callback(empty)
  end

  local kinds = require("cmp").lsp.CompletionItemKind
  local items = {}

  -- 1. after from/join: CTE и таблицы каталога
  local prefix = relation_prefix(before)
  if prefix then
    local taken = {}
    local low = prefix:lower()
    for _, name in ipairs(cte_names(before)) do
      if name:sub(1, #low) == low then
        taken[name] = true
        items[#items + 1] = { label = name, kind = kinds.Class, detail = "cte" }
      end
    end
    -- textEdit на всю набранную часть, включая схему: без него cmp взял бы
    -- границу слова после точки и `site.sess` превратилось бы в `site.site.…`
    local edit_range = {
      start = { line = row, character = col - #prefix },
      ["end"] = { line = row, character = col },
    }
    for _, name in ipairs(search_names(prefix, cache.names)) do
      if not taken[name] then
        items[#items + 1] = {
          label = name,
          kind = kinds.Struct,
          textEdit = { range = edit_range, newText = name },
        }
      end
    end
    return callback({ items = items, isIncomplete = true })
  end

  local ctx = { text = cell, ctes = cell_ctes(cell), memo = {} }
  local scope = mask_nested(enclosing_span(cell, #before))
  local relations = relations_in(scope)

  -- 2. after `алиас.` / `схема.таблица.`: колонки этого отношения
  local qualifier, typed = column_prefix(before)
  if qualifier then
    local low_qualifier = unquote(qualifier:lower())
    local target
    for _, relation in ipairs(relations) do
      if relation.alias == low_qualifier or relation.ref == low_qualifier then
        target = relation
        break
      end
    end
    -- квалификатор может быть и именем таблицы, которой в from ещё нет
    target = target or { ref = low_qualifier }
    local low = (typed or ""):lower()
    for _, column in ipairs(relation_columns(target, ctx, {}, 1)) do
      if column.name:lower():find(low, 1, true) then
        items[#items + 1] = { label = column.name, kind = kinds.Field, detail = column.type or "cte" }
      end
    end
    return callback({ items = items, isIncomplete = true })
  end

  -- 3. остальное (select-список, where, group by): колонки всех отношений запроса
  local low = word_prefix(before):lower()
  local seen = {}
  for _, relation in ipairs(relations) do
    local _, tail = split_name(relation.ref)
    local origin = relation.alias or tail
    for _, column in ipairs(relation_columns(relation, ctx, {}, 1)) do
      local key = origin .. "." .. column.name
      if not seen[key] and column.name:lower():find(low, 1, true) then
        seen[key] = true
        items[#items + 1] = {
          label = column.name,
          kind = kinds.Field,
          detail = origin .. (column.type and (" · " .. column.type) or ""),
        }
      end
    end
  end
  return callback({ items = items, isIncomplete = true })
end

M.source = source

-- Чистые функции наружу — под ручную проверку и тесты.
M._search_names = search_names
M._relation_prefix = relation_prefix
M._column_prefix = column_prefix
M._word_prefix = word_prefix
M._cte_names = cte_names
M._relations_in = relations_in
M._enclosing_span = enclosing_span
M._mask_nested = mask_nested
M._sql_region = sql_region

return M
