# nvim EDA-стек — диагностика и восстановление

Заметки по инциденту **2026-08-04**: разом отвалились jupytext, molten, image.nvim и
Jupyter-ядра. Причина у всех одна — см. ниже.

## Первопричина

Одновременно были стёрты:
- `~/.venvs/neovim` (host-venv провайдера python3 для molten),
- uv-tools (`~/.local/bin/jupytext` и т.п.),
- Jupyter kernelspec'и (`~/Library/Jupyter/kernels`).

Подозрение — какая-то чистка/MDM. Что именно чистит эти каталоги — **не выяснено**
(открытый вопрос). Если повторится, полный ремонт — раздел «Быстрое восстановление».

## Архитектура (не путать два Python)

- **Host / провайдер** — `~/.venvs/neovim` (нужны `pynvim` + `jupyter_client` + `nbformat`).
  Задаётся `vim.g.python3_host_prog` в `init.lua`. Это плагинная сантехника molten —
  **код ноутбука тут НЕ выполняется**.
- **Kernel** — venv `~/work/jupyter-utils/.venv` (`ipykernel` + `polars`/nb_utils),
  регистрируется как kernelspec и выбирается в `:MoltenInit`. **Код выполняется здесь.**
- **Картинки** — image.nvim (`backend=kitty`, `processor=magick_cli` → `/opt/homebrew/bin/magick`),
  **без luarocks**.

## Проблемы и фиксы

### 1. image.nvim — `Failed to spawn process luarocks`
- **Симптом:** на старте `Failed installing image.nvim with luarocks`, `Failed to spawn process luarocks`.
- **Причина:** lazy.nvim пытается собрать rockspec image.nvim через hererocks, а `luarocks` не установлен. Тебе rock не нужен — image.nvim рендерит через `magick_cli`.
- **Фикс (уже в конфиге):** в `lua/custom/lazy.lua` в opts `require("lazy").setup` добавлено `rocks = { enabled = false }`.
- **Проверка:** перезапуск nvim → ошибки нет.

### 2. jupytext — `... jupytext ... : 127`, `E484: Can't open file ...md`
- **Симптом:** при открытии `.ipynb` в BufReadCmd падает jupytext с кодом 127.
- **Причина:** exit 127 = бинарь `jupytext` не найден в PATH. Ставился как uv-tool → `~/.local/bin/jupytext`, но uv-tools стёрты.
- **Фикс:** `uv tool install jupytext`
- **Проверка:** `jupytext --version`; открыть `.ipynb`.

### 3. molten — `not an editor command MoltenInit`
- **Симптом:** `<leader>ji` / `:MoltenInit` → `not an editor command MoltenInit`.
- **Причина:** molten — remote-плагин на host-venv `~/.venvs/neovim`; venv стёрт (нет `pynvim`), а rplugin-манифест без molten. Плюс molten грузится по `ft`, поэтому в headless `UpdateRemotePlugins` без явной загрузки не регистрируется.
- **Фикс:**
  ```sh
  uv venv ~/.venvs/neovim
  uv pip install --python ~/.venvs/neovim/bin/python pynvim jupyter_client nbformat
  nvim --headless "+Lazy! load molten-nvim" "+UpdateRemotePlugins" +qa
  ```
  `+Lazy! load molten-nvim` обязателен — без него манифест соберётся с 0 записей molten.
- **Проверка:** `grep -c -i molten ~/.local/share/nvim/rplugin.vim` > 0; перезапуск nvim → `:MoltenInit` существует.

### 4. Нет Jupyter-ядра / `:MoltenInit` не видит jupyter-utils
- **Симптом:** `:MoltenInit` не предлагает ядер; `find_kernel_specs()` == `{}`.
- **Причина:** kernelspec'и стёрты. venv jupyter-utils цел (ipykernel + polars), но не зарегистрирован как ядро.
- **Фикс:**
  ```sh
  ~/work/jupyter-utils/.venv/bin/python -m ipykernel install --user \
    --name jupyter-utils --display-name "jupyter-utils (polars)"
  ```
- **Проверка:** ядро в `~/Library/Jupyter/kernels/jupyter-utils`; `:MoltenInit` показывает «jupyter-utils (polars)».

## Быстрое восстановление (если снова снесёт)

По порядку:

```sh
# 1. jupytext CLI (uv-tool → ~/.local/bin/jupytext)
uv tool install jupytext

# 2. molten host-venv + провайдер-зависимости
uv venv ~/.venvs/neovim
uv pip install --python ~/.venvs/neovim/bin/python pynvim jupyter_client nbformat

# 3. ядро jupyter-utils
~/work/jupyter-utils/.venv/bin/python -m ipykernel install --user \
  --name jupyter-utils --display-name "jupyter-utils (polars)"

# 4. пересобрать remote-plugin манифест (с force-load molten)
nvim --headless "+Lazy! load molten-nvim" "+UpdateRemotePlugins" +qa
```

Потом перезапусти nvim. Фикс image.nvim (`rocks = false`) уже в конфиге под git — трогать не нужно.

## Версии на момент фикса (2026-08-04)
nvim 0.12.4 · uv 0.11.25 · jupytext 1.19.5 · pynvim 0.6.0 · ipykernel 7.3.0 · polars 1.42.1
