-- Рендер картинок в терминале через kitty graphics protocol (ghostty умеет,
-- tmux — через allow-passthrough, уже включён в tmux.conf).
-- Основной потребитель — molten (molten_image_provider = "image.nvim").
return {
    "3rd/image.nvim",
    opts = {
        backend = "kitty",
        processor = "magick_cli", -- системный ImageMagick CLI, без luarocks/hererocks
        integrations = {
            -- только molten: картинки в markdown/neorg-буферах не трогаем,
            -- чтобы не пересекаться с render-markdown
            markdown = { enabled = false },
            neorg = { enabled = false },
        },
        max_width_window_percentage = 100,
        max_height_window_percentage = 50,
        -- в tmux рисовать только в активном окне (иначе артефакты при переключении)
        tmux_show_only_in_active_window = true,
    },
}
