return {
  'Wansmer/langmapper.nvim',
  lazy = false,
  priority = 1,
  config = function()
    local lm = require('langmapper')
    lm.setup()
    lm.hack_get_keymap()
    lm.automapping({ global = true, buffer = true })
  end,
}
