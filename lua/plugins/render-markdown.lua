return {
	"MeanderingProgrammer/render-markdown.nvim",
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
	ft = { "markdown" },
	opts = {
		-- Дефолт — { "n", "c", "t" }: при входе в insert или visual рендер выключался
		-- целиком. Теперь форматирование остаётся, а сырой показывается только строка
		-- под курсором — это делает anti_conceal, он включён по умолчанию (above/below = 0).
		-- "\22" это Ctrl-V, блочный visual; такими же строками режимы сверяет сам плагин.
		render_modes = { "n", "c", "t", "i", "v", "V", "\22" },
	},
}
