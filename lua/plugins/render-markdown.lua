return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
	ft = { "markdown" },
	opts = {
		-- Дефолт — { "n", "c", "t" }: при входе в insert или visual рендер выключался
		-- целиком. `true` значит «во всех режимах»: плагин принимает boolean наравне
		-- со списком (render_modes: boolean|string[], settings.lua:97). Сырой при этом
		-- показывается только строка под курсором — это anti_conceal, он включён по
		-- умолчанию (above/below = 0).
		--
		-- Почему не перечислением: режимов у nvim сильно больше семи, и пропуски видны
		-- не сразу. Самый заметный — `ic`/`ix`, insert с открытым меню автодополнения:
		-- в sql-ячейках оно открыто почти всегда (cmp_catalog), и на каждом всплытии
		-- попапа форматирование гасло, а буфер дёргался. Сюда же replace (`R`), select
		-- (`s`/`S`) и operator-pending (`no*`).
		--
		-- Если когда-нибудь понадобится исключение — у плагина есть disabled_modes.
		render_modes = true,
		-- Дефолт `hide` прячет строку закрывающего ``` целиком (conceal_lines): она есть в
		-- буфере, курсор по ней ходит, а на экране её нет — j/dd попадают в невидимое.
		-- Заодно nvim путается при скролле рядом с полностью скрытой строкой (README
		-- jupyter.nvim, «Ripple next to concealed lines»). `thin` оставляет строку на
		-- месте и рисует поверх неё тонкую черту ▀ — конец ячейки виден.
		--
		-- highlight_border — своя группа, см. paint() ниже: строка языка над ячейкой.
		code = { border = "thin", highlight_border = "RenderMarkdownCellBorder" },
	},
	config = function(_, opts)
		require("render-markdown").setup(opts)
		-- Рендер гаснет целиком, как только окно сдвинуто по горизонтали (core/ui.lua:
		-- `leftcol == 0`), а при nowrap тачпад сдвигает его почти на каждом скролле.
		-- Опции нет, поэтому плагину всегда говорим «не сдвинуто». leftcol он больше
		-- нигде не читает (env.win.view ещё зовётся ради topline). Цена: паддинг
		-- заголовков и код-блоков при width = "block" стоит по колонкам окна и при
		-- сдвиге не уезжает вместе с текстом — при дефолтном width = "full" его нет.
		local env = require("render-markdown.lib.env")
		local view = env.win.view
		env.win.view = function(win)
			local v = view(win)
			v.leftcol = 0
			return v
		end

		-- Мигание при быстром скролле. Рендерится не буфер, а окно плюс 10 строк с каждой
		-- стороны (request/view.lua:19, число зашито), а `debounce` у плагина — не дебаунс,
		-- а дроссель без хвоста (lib/decorator.lua:51): первый WinScrolled рендерит сразу,
		-- следующие 100 мс отбрасываются. Скролл дальше чем на 10 строк за это окно
		-- показывает сырой markdown, пока не придёт следующее событие. Запас в целый экран
		-- с каждой стороны перекрывает <C-d>/<C-u> и колесо: ноутбук в сотни строк
		-- рендерится за миллисекунды, а offset = 0 (видимая область) не трогаем.
		local range = env.range
		env.range = function(buf, win, offset)
			if offset > 0 then
				offset = math.max(offset, vim.api.nvim_win_get_height(win))
			end
			return range(buf, win, offset)
		end

		-- Границы ячейки — строка языка сверху и подвал со статусом jupyter.nvim снизу
		-- (status.position = "fence", группа JupyterStatusFooter) — цветом
		-- чуть темнее тела ячейки, см. шкалу у paint().
		--
		-- Фон окна nvim не знает: Normal у темы прозрачный, фон рисует Ghostty. Поэтому
		-- спрашиваем у терминала (OSC 11, ответ приходит через TermResponse) и повторяем
		-- на ColorScheme — omarchy меняет тему терминалу и nvim вместе. Без ответа и без
		-- палитры темы граница сверху цвета ячейки, подвал прозрачный — как без настройки.
		--
		-- reload() после перекраски обязателен: █-заливку render-markdown рисует
		-- производной группой (bg_as_fg) и пересчитывает её на ColorScheme своей
		-- автокомандой — она зарегистрирована раньше нашей и успевает взять старый цвет.
		local term_bg
		local function mix(a, b, t)
			local out = 0
			for shift = 16, 0, -8 do
				local x, y = bit.band(bit.rshift(a, shift), 0xff), bit.band(bit.rshift(b, shift), 0xff)
				local v = math.max(0, math.min(255, math.floor(x + (y - x) * t + 0.5)))
				out = out + bit.lshift(v, shift)
			end
			return out
		end
		-- Запасной источник, пока терминал не ответил (или не ответит: tmux без клиента):
		-- фон из палитры tokyonight — transparency.lua снимает его только с групп.
		local function theme_bg()
			if not (vim.g.colors_name or ""):match("^tokyonight") then
				return nil
			end
			local ok, hex = pcall(function()
				return require("tokyonight.colors").setup().bg
			end)
			return ok and type(hex) == "string" and tonumber(hex:gsub("^#", ""), 16) or nil
		end
		-- Шкала фонов в шагах D = CursorLine − окно (подстраивается под тему):
		--   граница 0.75·D — чуть темнее тела: шапка той же ячейки, а не отдельная полоса;
		--   ячейка  1.0·D  — на уровне CursorLine;
		--   текущая 1.8·D  — jupyter.nvim, JupyterCellCurrent, светлее CursorLine.
		-- Раньше всё лежало внутри [окно, CursorLine] (0.2/0.4/0.75): соседние уровни
		-- отличались на 0.01–0.02 по OKLab L при пороге заметности ~0.04 — ячейки сливались
		-- с фоном. Отделяет ячейку от соседей теперь сам скачок окно → ячейка (0.06).
		-- Граница темнее окна (рамка-желобок) пробовалась: читалась отдельной полосой
		-- чужого цвета и шумела.
		--
		-- Считаем от окна и CursorLine, а не от прежнего RenderMarkdownCode: paint()
		-- зовётся повторно и брал бы свой же цвет.
		local BORDER, CELL, CURRENT = 0.75, 1.0, 1.8
		local function paint()
			local win = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg or term_bg or theme_bg()
			local lift = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }).bg
			local edge
			if win and lift then
				vim.api.nvim_set_hl(0, "RenderMarkdownCode", { bg = mix(win, lift, CELL) })
				vim.api.nvim_set_hl(0, "JupyterCellCurrent", { bg = mix(win, lift, CURRENT) })
				edge = mix(win, lift, BORDER)
			end
			local code = vim.api.nvim_get_hl(0, { name = "RenderMarkdownCode", link = false }).bg
			vim.api.nvim_set_hl(0, "RenderMarkdownCellBorder", { bg = edge or code })
			vim.api.nvim_set_hl(0, "JupyterStatusFooter", { bg = edge })
			pcall(require("render-markdown.core.colors").reload)
		end
		local group = vim.api.nvim_create_augroup("CellBorderColor", { clear = true })
		vim.api.nvim_create_autocmd("TermResponse", {
			group = group,
			callback = function(ev)
				local seq = type(ev.data) == "table" and ev.data.sequence or ev.data or ""
				local r, g, b = seq:match("\027%]11;rgb:(%x+)/(%x+)/(%x+)")
				if r then
					-- 1–4 hex-цифры на канал; старшие два — это 8 бит
					local function byte(h)
						return tonumber((h .. h):sub(1, 2), 16)
					end
					term_bg = byte(r) * 0x10000 + byte(g) * 0x100 + byte(b)
					paint()
				end
			end,
		})
		local function ask()
			paint()
			pcall(vim.api.nvim_ui_send, "\027]11;?\027\\")
		end
		vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = ask })
		ask()
	end,
}
