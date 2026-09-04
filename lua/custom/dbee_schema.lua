-- Схема таблицы прямо из запроса: K в sql-буфере (или <leader>ds где угодно)
-- берёт идентификатор под курсором, гоняет по нему колонки на активном
-- коннекте и открывает результат. <leader>dS — то же для svv_table_info
-- (размер, sortkey, distkey, skew).
--
-- svv_columns, а не information_schema.columns из встроенного хелпера dbee:
-- в information_schema не видно внешних (Spectrum) таблиц и late-binding вьюх.
local M = {}

-- из чего может состоять идентификатор: schema.table, "Mixed"."Case", $-суффиксы
local IDENT = '[%w_%.%"%$]'

-- на этих словах K нажимают мимо таблицы, а лишний рейстрип в Redshift не бесплатный
local KEYWORDS = {}
for word in
  string.gmatch(
    "select from where join on left right inner outer full cross union all distinct "
      .. "group order by having limit offset with as and or not null is in exists "
      .. "case when then else end over partition asc desc between like ilike "
      .. "insert update delete create table view schema temp temporary",
    "%S+"
  )
do
  KEYWORDS[word] = true
end

-- Разбирает идентификатор в строке line на позиции col (1-based, байты).
---@param line string
---@param col integer
---@return string? schema
---@return string? table_name
function M.parse(line, col)
  if col < 1 or col > #line or not line:sub(col, col):match(IDENT) then
    return nil, nil
  end

  local from, to = col, col
  while from > 1 and line:sub(from - 1, from - 1):match(IDENT) do
    from = from - 1
  end
  while to < #line and line:sub(to + 1, to + 1):match(IDENT) do
    to = to + 1
  end

  local raw = line:sub(from, to):gsub('"', ""):gsub("^%.+", ""):gsub("%.+$", "")
  local parts = {}
  for part in raw:gmatch("[^%.]+") do
    table.insert(parts, part:lower())
  end

  -- db.schema.table — лишний префикс отбрасываем
  while #parts > 2 do
    table.remove(parts, 1)
  end
  if #parts == 0 then
    return nil, nil
  end
  if #parts == 1 then
    return nil, parts[1]
  end
  return parts[1], parts[2]
end

---@param s string
---@return string
local function quote(s)
  return "'" .. s:gsub("'", "''") .. "'"
end

-- Запрос по колонкам или по определению таблицы.
---@param kind "columns"|"info"
---@param schema string?
---@param table_name string
---@return string
function M.query(kind, schema, table_name)
  if kind == "info" then
    local sql = {
      "select *",
      "from svv_table_info",
      'where lower("table") = ' .. quote(table_name),
    }
    if schema then
      table.insert(sql, '    and lower("schema") = ' .. quote(schema))
    end
    return table.concat(sql, "\n")
  end

  local sql = {
    "select",
    "    table_schema,",
    "    ordinal_position,",
    "    column_name,",
    "    data_type,",
    "    character_maximum_length,",
    "    is_nullable",
    "from svv_columns",
    "where lower(table_name) = " .. quote(table_name),
  }
  if schema then
    table.insert(sql, "    and lower(table_schema) = " .. quote(schema))
  end
  table.insert(sql, "order by table_schema, ordinal_position")
  return table.concat(sql, "\n")
end

-- цель: выделение, если мы в визуальном режиме, иначе слово под курсором
---@return string? schema
---@return string? table_name
local function target()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    local text = vim.trim(table.concat(region, " "))
    return M.parse(text, 1)
  end
  return M.parse(vim.api.nvim_get_current_line(), vim.fn.col("."))
end

---@param kind "columns"|"info"
function M.show(kind)
  kind = kind or "columns"

  local schema, table_name = target()
  if not table_name then
    vim.notify("dbee: под курсором не видно имени таблицы", vim.log.levels.WARN)
    return
  end
  if KEYWORDS[table_name] then
    vim.notify("dbee: " .. table_name .. " — это ключевое слово, не таблица", vim.log.levels.WARN)
    return
  end

  local api = require("dbee").api
  local conn = api.core.get_current_connection()
  if not conn then
    vim.notify("dbee: не выбрано соединение (<leader>dc)", vim.log.levels.ERROR)
    return
  end

  local full = (schema and schema .. "." or "") .. table_name
  -- маркер читает dbee_call_log_patch и показывает в истории только эту метку
  local label = (kind == "info" and "table info: " or "columns: ") .. full
  local query = "-- @dbee-file: " .. label .. "\n" .. M.query(kind, schema, table_name)

  api.ui.result_set_call(api.core.connection_execute(conn.id, query))
  require("dbee").open()
end

function M.setup()
  local group = vim.api.nvim_create_augroup("DbeeSchema", { clear = true })

  -- K в sql-буферах: LSP на sql не настроен, так что клавиша свободна
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "sql",
    callback = function(args)
      vim.keymap.set("n", "K", function()
        M.show("columns")
      end, { buffer = args.buf, desc = "DBee: колонки таблицы под курсором" })
    end,
  })

  vim.keymap.set({ "n", "x" }, "<leader>ds", function()
    M.show("columns")
  end, { desc = "DBee: колонки таблицы под курсором" })
  vim.keymap.set({ "n", "x" }, "<leader>dS", function()
    M.show("info")
  end, { desc = "DBee: svv_table_info по таблице под курсором" })
end

return M
