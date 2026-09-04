-- Столбец выровненной таблицы (результат dbee) в блочном выделении.
--
-- g| в <C-v>-выделении тянет правую границу до конца самого длинного значения
-- столбца — вручную это либо "e" (даёт ширину случайной строки, той, где стоит
-- курсор), либо "t│" (тянет до разделителя вместе с добивкой пробелами).
--
-- Пробелы срезаются уже из регистра, после y: блочное выделение всегда
-- прямоугольное, значений разной длины в нём не бывает. Взвод снимается либо
-- самим yank'ом, либо выходом из визуального режима.
local M = {}

local SEP = "│"

-- взведён ли пост-обработчик следующего блочного yank'а
local armed = false

-- содержимое столбца в строке: от байта from до следующего разделителя
---@param line string
---@param from integer
---@return string
local function segment(line, from)
  local rest = line:sub(from)
  local sep = rest:find(SEP, 1, true)
  return sep and rest:sub(1, sep - 1) or rest
end

-- линейка вида ───┼─── в ширину столбца не считается
---@param text string
---@return boolean
local function is_rule(text)
  return text:gsub("[─┼%s]", "") == ""
end

-- Расширяет правую границу блока до конца значений столбца.
function M.extend()
  if vim.fn.mode() ~= "\22" then
    vim.notify("g|: нужен блочный режим (<C-v>)", vim.log.levels.WARN)
    return
  end

  local first, last = vim.fn.line("v"), vim.fn.line(".")
  if first > last then
    first, last = last, first
  end
  local left = math.min(vim.fn.col("v"), vim.fn.col("."))

  local width = 0
  for lnum = first, last do
    local seg = segment(vim.fn.getline(lnum), left)
    if not is_rule(seg) then
      width = math.max(width, #(seg:gsub("%s+$", "")))
    end
  end
  if width == 0 then
    return
  end

  -- правую границу двигает курсор, значит он должен стоять на правом углу
  if vim.fn.col(".") < vim.fn.col("v") then
    vim.cmd("normal! o")
  end
  vim.fn.cursor(vim.fn.line("."), left + width - 1)
  armed = true
end

function M.setup()
  local group = vim.api.nvim_create_augroup("TableColumn", { clear = true })

  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
      if not armed then
        return
      end
      armed = false

      local ev = vim.v.event
      if ev.operator ~= "y" or not vim.startswith(ev.regtype, "\22") then
        return
      end

      local values = vim.tbl_map(vim.trim, ev.regcontents)
      local reg = ev.regname ~= "" and ev.regname or '"'
      vim.schedule(function()
        -- строчный тип: при вставке каждое значение отдельной строкой
        vim.fn.setreg(reg, values, "V")
        if ev.regname == "" then
          vim.fn.setreg("0", values, "V") -- безымянный yank дублируется в "0
        end
      end)
    end,
  })

  -- вышли из визуального режима без yank'а — снимаем взвод. TextYankPost
  -- срабатывает раньше этого события, так что настоящий yank не теряем.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "[vV\22]*:*",
    callback = function()
      armed = false
    end,
  })

  vim.keymap.set("x", "g|", M.extend, { desc = "Таблица: блок до конца значений столбца" })
end

return M
