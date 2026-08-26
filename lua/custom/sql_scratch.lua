-- Одноразовые SQL-запросы для dbee: <leader>dn открывает черновик в отдельном
-- табе, на диск он попадает только когда запрос успешно отработал (или когда
-- закрываешь непустой черновик). Поиск по архиву — telescope.
--
-- Это обычные файлы в обычных буферах, а не dbee-«notes»: встроенные notes
-- живут только в editor-окне dbee, которого нет в нашем layout (dbee_layout.lua),
-- и не умеют ни дат в имени, ни автосейва, ни поиска. Зато обычный буфер
-- бесплатно получает <leader>dr/<leader>dk/<leader>dy из remap.lua.
--
-- Отдельный таб, а не сплит: черновик занимает место текущего файла целиком,
-- :q закрывает таб и возвращает прежний layout как был.
local M = {}

M.dir = vim.fn.expand("~/work/sql-scratch")

-- Записывать ли непустой черновик при закрытии таба. false — в архиве остаются
-- строго успешно отработавшие запросы; при 'hidden' (у нас включён) :q тогда
-- просто уводит черновик в скрытые буферы: файла нет, текст не потерян, но
-- буфер висит модифицированным и позже мешает :qa. Отсюда дефолт true.
M.save_on_close = true

-- буфер, чей запрос сейчас крутится в dbee; сохраняем его, когда запрос дойдёт
-- до успешного состояния
local running_bufnr = nil
local listener_registered = false

---@param s string
---@return string
local function slugify(s)
  -- vim.fn.tolower, а не :lower(): последний в LuaJIT умеет только ASCII
  s = vim.fn.tolower(vim.trim(s or ""))
  -- всё, кроме букв/цифр/дефиса, схлопываем в дефис. \128-\255 оставляет
  -- многобайтные символы (кириллицу) в имени, а пунктуация вида "!" уходит.
  s = s:gsub("[^%w\128-\255%-]+", "-")
  s = s:gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
  return s
end

---@param slug string
---@return string
local function path_for(slug)
  local stamp = os.date("%Y-%m-%d_%H%M")
  local base = slug ~= "" and (stamp .. "_" .. slug) or stamp

  local file = M.dir .. "/" .. base .. ".sql"
  -- два черновика в одну минуту с одним именем — добавляем счётчик. bufexists
  -- нужен потому, что несохранённого черновика на диске ещё нет.
  local n = 2
  while vim.uv.fs_stat(file) or vim.fn.bufexists(file) == 1 do
    file = M.dir .. "/" .. base .. "-" .. n .. ".sql"
    n = n + 1
  end
  return file
end

---@param bufnr integer?
---@return integer
local function resolve(bufnr)
  return (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
end

---@param bufnr integer?
---@return boolean
function M.is_scratch(bufnr)
  bufnr = resolve(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name ~= "" and vim.startswith(name, M.dir .. "/")
end

---@param bufnr integer
---@return boolean
local function is_blank(bufnr)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if vim.trim(line) ~= "" then
      return false
    end
  end
  return true
end

-- Метка для истории dbee: scratch-файлы лежат вне cwd, поэтому "%:." дал бы
-- полный путь на весь экран. Возвращает nil для обычных буферов.
---@param bufnr integer?
---@return string?
function M.dbee_label(bufnr)
  if not M.is_scratch(bufnr) then
    return nil
  end
  return "scratch/" .. vim.fs.basename(vim.api.nvim_buf_get_name(resolve(bufnr)))
end

-- Сохраняет scratch-буфер. No-op для всего остального и для несохранённых
-- изменений, которых нет, так что вызывать можно без проверок.
---@param bufnr integer?
function M.save(bufnr)
  bufnr = resolve(bufnr)
  if not M.is_scratch(bufnr) or not vim.bo[bufnr].modified then
    return
  end
  vim.fn.mkdir(M.dir, "p")
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent noautocmd write")
  end)
end

-- Закрываем черновик: непустой — на диск, пустой — стереть и не спрашивать про
-- несохранённые изменения (иначе :q на выпотрошенном черновике ругается E37).
---@param bufnr integer
local function on_close(bufnr)
  if not M.is_scratch(bufnr) then
    return
  end
  if is_blank(bufnr) then
    local file = vim.api.nvim_buf_get_name(bufnr)
    if vim.uv.fs_stat(file) then
      vim.fn.delete(file)
    end
    vim.bo[bufnr].modified = false
    return
  end
  if M.save_on_close then
    M.save(bufnr)
  end
  -- иначе не трогаем 'modified': nvim сам не даст закрыть черновик молча
end

-- Сохранение по факту успешного запроса. dbee_reconnect может перезапустить
-- упавший на мёртвом коннекте запрос под новым id, поэтому смотрим не на id
-- звонка, а на «последний запущенный scratch-буфер»: успех его повторной
-- попытки тоже сохранит черновик.
local function ensure_listener()
  if listener_registered then
    return
  end
  local ok, api = pcall(function()
    return require("dbee").api
  end)
  if not ok then
    return
  end

  api.core.register_event_listener("call_state_changed", function(data)
    local state = data.call and data.call.state
    if state ~= "retrieving" and state ~= "archived" then
      return
    end
    local bufnr = running_bufnr
    if not bufnr then
      return
    end
    running_bufnr = nil
    vim.schedule(function()
      M.save(bufnr)
    end)
  end)
  listener_registered = true
end

-- Вызывается из <leader>dr перед запуском запроса: помечает буфер как ждущий
-- успеха. No-op для обычных файлов.
---@param bufnr integer?
function M.track_run(bufnr)
  bufnr = resolve(bufnr)
  if not M.is_scratch(bufnr) then
    return
  end
  ensure_listener()
  running_bufnr = bufnr
end

-- Создаёт новый черновик в отдельном табе. Файла на диске ещё нет: он появится
-- после успешного прогона или при закрытии непустого черновика.
-- Имя спрашиваем сразу: пустой ввод — только дата-время, Esc — отмена.
---@param name string? если задано, промпт не показываем
function M.new(name)
  local function create(slug)
    vim.cmd("tabedit " .. vim.fn.fnameescape(path_for(slug)))
    vim.bo.filetype = "sql"
  end

  if name and name ~= "" then
    create(slugify(name))
    return
  end

  vim.ui.input({ prompt = "Имя scratch-запроса: " }, function(input)
    if input == nil then
      return -- Esc
    end
    create(slugify(input))
  end)
end

-- Переименовывает текущий черновик, сохраняя дату-время в имени: имя часто
-- становится понятно только после первого прогона.
---@param name string?
function M.rename(name)
  local bufnr = vim.api.nvim_get_current_buf()
  if not M.is_scratch(bufnr) then
    vim.notify("sql-scratch: это не scratch-буфер", vim.log.levels.WARN)
    return
  end

  local old = vim.api.nvim_buf_get_name(bufnr)
  local stamp = vim.fs.basename(old):match("^(%d%d%d%d%-%d%d%-%d%d_%d%d%d%d)") or os.date("%Y-%m-%d_%H%M")

  local function do_rename(slug)
    if slug == "" then
      return
    end
    local new = M.dir .. "/" .. stamp .. "_" .. slug .. ".sql"
    if vim.uv.fs_stat(new) then
      vim.notify("sql-scratch: " .. vim.fs.basename(new) .. " уже существует", vim.log.levels.ERROR)
      return
    end

    -- черновик мог ещё не попасть на диск — тогда двигать нечего
    if vim.uv.fs_stat(old) then
      local ok, err = vim.uv.fs_rename(old, new)
      if not ok then
        vim.notify("sql-scratch: не переименовать: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
    end
    vim.api.nvim_buf_set_name(bufnr, new)
    vim.cmd("silent! bwipeout " .. vim.fn.fnameescape(old))
    vim.notify("sql-scratch: " .. vim.fs.basename(new))
  end

  if name and name ~= "" then
    do_rename(slugify(name))
    return
  end

  vim.ui.input({ prompt = "Новое имя: " }, function(input)
    if input == nil then
      return
    end
    do_rename(slugify(input))
  end)
end

---@class ScratchEntry
---@field file string
---@field name string
---@field when string "2026-08-25 18:20"
---@field slug string
---@field mtime integer
---@field first string первая содержательная строка запроса

---Список черновиков, свежие сверху.
---@return ScratchEntry[]
function M.list()
  local entries = {}
  if not vim.uv.fs_stat(M.dir) then
    return entries
  end

  for name, type_ in vim.fs.dir(M.dir) do
    if type_ == "file" and name:match("%.sql$") then
      local file = M.dir .. "/" .. name
      local stat = vim.uv.fs_stat(file)
      local date, time, slug = name:match("^(%d%d%d%d%-%d%d%-%d%d)_(%d%d%d%d)_?(.*)%.sql$")

      -- первые строки — как подсказка в списке; больше пяти читать незачем
      local first = ""
      for _, line in ipairs(vim.fn.readfile(file, "", 5)) do
        line = vim.trim(line)
        if line ~= "" and not vim.startswith(line, "--") then
          first = line
          break
        end
      end

      table.insert(entries, {
        file = file,
        name = name,
        when = date and (date .. " " .. time:sub(1, 2) .. ":" .. time:sub(3, 4)) or "",
        slug = slug and slug ~= "" and slug or (date and "" or name:gsub("%.sql$", "")),
        mtime = stat and stat.mtime.sec or 0,
        first = first,
      })
    end
  end

  table.sort(entries, function(a, b)
    return a.mtime > b.mtime
  end)
  return entries
end

-- Telescope-пикер по архиву черновиков: дата-время, имя, начало запроса.
-- <CR> открыть в новом табе (как <leader>dn), dd удалить.
function M.pick()
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("sql-scratch: нет telescope", vim.log.levels.ERROR)
    return
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local displayer = entry_display.create({
    separator = "  ",
    items = { { width = 16 }, { width = 24 }, { remaining = true } },
  })

  local function make_finder()
    return finders.new_table({
      results = M.list(),
      entry_maker = function(item)
        return {
          value = item,
          path = item.file,
          ordinal = item.name .. " " .. item.first,
          display = function(entry)
            return displayer({
              { entry.value.when, "TelescopeResultsComment" },
              entry.value.slug,
              { entry.value.first, "TelescopeResultsComment" },
            })
          end,
        }
      end,
    })
  end

  if vim.tbl_isempty(M.list()) then
    vim.notify("sql-scratch: черновиков ещё нет (<leader>dn)", vim.log.levels.INFO)
    return
  end

  pickers
    .new({}, {
      prompt_title = "SQL scratch",
      finder = make_finder(),
      sorter = conf.generic_sorter({}),
      previewer = previewers.vim_buffer_cat.new({}),
      attach_mappings = function(prompt_bufnr, map)
        -- в таб, а не в текущее окно: :q вернёт туда, откуда искал
        actions.select_default:replace(function()
          actions.select_tab(prompt_bufnr)
        end)
        -- dd как в drawer'е dbee
        map("n", "dd", function(bufnr)
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          if vim.fn.confirm("Удалить " .. entry.value.name .. "?", "&Да\n&Нет", 2) ~= 1 then
            return
          end
          vim.fn.delete(entry.value.file)
          action_state.get_current_picker(bufnr):refresh(make_finder(), { reset_prompt = false })
        end)
        return true
      end,
    })
    :find()
end

-- Поиск по содержимому черновиков (нужный джойн вспоминается по коду, не по имени).
function M.grep()
  require("telescope.builtin").live_grep({ cwd = M.dir, prompt_title = "SQL scratch: grep" })
end

-- Ретенция вручную: удаляет черновики старше days дней.
---@param days integer?
function M.clean(days)
  days = days or 90
  local cutoff = os.time() - days * 86400
  local old = vim.tbl_filter(function(e)
    return e.mtime < cutoff
  end, M.list())

  if vim.tbl_isempty(old) then
    vim.notify("sql-scratch: старше " .. days .. " дней ничего нет", vim.log.levels.INFO)
    return
  end
  if vim.fn.confirm("Удалить " .. #old .. " черновиков старше " .. days .. " дней?", "&Да\n&Нет", 2) ~= 1 then
    return
  end
  for _, e in ipairs(old) do
    vim.fn.delete(e.file)
  end
  vim.notify("sql-scratch: удалено " .. #old)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("SqlScratch", { clear = true })

  -- QuitPre, а не только BufWinLeave: на :q он срабатывает до проверки
  -- несохранённых изменений, так что успеваем записать или пометить чистым
  vim.api.nvim_create_autocmd({ "QuitPre", "BufWinLeave" }, {
    group = group,
    pattern = M.dir .. "/*.sql",
    callback = function(args)
      on_close(args.buf)
    end,
  })

  -- у VimLeavePre pattern сверяется с v:this_session, путь тут не поможет —
  -- проходим по буферам сами
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        on_close(bufnr)
      end
    end,
  })

  vim.api.nvim_create_user_command("SqlScratchNew", function(o)
    M.new(o.args)
  end, { nargs = "?", desc = "SQL scratch: новый черновик" })
  vim.api.nvim_create_user_command("SqlScratchRename", function(o)
    M.rename(o.args)
  end, { nargs = "?", desc = "SQL scratch: переименовать текущий" })
  vim.api.nvim_create_user_command("SqlScratchFind", function()
    M.pick()
  end, { desc = "SQL scratch: поиск по черновикам" })
  vim.api.nvim_create_user_command("SqlScratchGrep", function()
    M.grep()
  end, { desc = "SQL scratch: grep по черновикам" })
  vim.api.nvim_create_user_command("SqlScratchClean", function(o)
    M.clean(tonumber(o.args))
  end, { nargs = "?", desc = "SQL scratch: удалить черновики старше N дней (по умолчанию 90)" })
end

return M
