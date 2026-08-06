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

## Почему падало на Mac, а на Linux работает

Один и тот же конфиг под git, но окружение разное. Причины (от главной к мелким):

1. **Чистка окружения (главная).** Рабочий Mac — корпоративный, там MDM/эндпоинт-агент
   периодически чистит каталоги, куда мы кладём venv'ы, uv-tools и kernelspec'и
   (`~/.venvs`, `~/.local/bin`, `~/Library/Jupyter/kernels`). После чистки разом
   отваливается всё — это и есть инцидент 2026-08-04. Домашний Linux — личный,
   без MDM: поставил один раз, оно живёт. Что именно чистит на Mac — **не выяснено**
   (открытый вопрос). Скрипт `setup-eda.sh` — это лечение симптома: он пересобирает
   стёртое за один прогон, а не мешает чистке.

2. **Разные пути в файловой системе.** Часть путей у Linux и Mac не совпадает —
   если ориентироваться на чужую заметку/пример, промахиваешься:
   | | Linux | macOS |
   |---|---|---|
   | kernelspec (user) | `~/.local/share/jupyter/kernels` | `~/Library/Jupyter/kernels` |
   | ImageMagick | `/usr/bin/magick` (pacman) | `/opt/homebrew/bin/magick` (brew) |
   | репо jupyter-utils | `~/Projects/jupyter-utils` | у тебя было `~/work/...` |

   Путь к host-venv (`~/.venvs/neovim`) и `python3_host_prog` — одинаковы на обеих ОС,
   тут расхождений нет. Скрипт разруливает kernelspec автоматически (`ipykernel install
   --user` сам пишет в нужный для ОС каталог) и ищет jupyter-utils в обоих местах.

3. **PATH до uv-tools.** jupytext ставится в `~/.local/bin`. На Linux этот каталог
   обычно уже в PATH → `jupytext` виден. На Mac после чистки/переустановки uv его
   бин-каталог может быть не в PATH → jupytext «пропадает» (exit 127, см. проблему 2),
   хотя формально установлен. Проверка: `uv tool dir --bin` и что этот путь в PATH.

4. **Рассинхрон имени ядра в заметках.** В старой версии этого файла ядро
   регистрировалось как `"jupyter-utils (polars)"`, а конфиг (`jupytext.lua`) ждёт
   `name=jupyter-utils` / `display_name="Python (jupyter-utils)"`. На Linux ядро уже
   стояло правильно и работало; при ручном восстановлении на Mac по старой команде
   имя разъезжалось. Скрипт регистрирует строго то, что ждёт конфиг.

**Итого:** Linux «просто работает» не потому что конфиг другой, а потому что там
никто не стирает окружение и пути совпали. На Mac те же шаги нужно (пере)накатывать —
для этого и есть `setup-eda.sh`.

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

## Быстрое восстановление / первичная настройка

Один скрипт для Linux и macOS — идемпотентный, можно запускать повторно:

```sh
~/.config/nvim/scripts/setup-eda.sh
```

Делает всё по порядку: jupytext CLI → host-venv `~/.venvs/neovim` → ядро
jupyter-utils → пересборка rplugin-манифеста (force-load molten) → проверка `magick`.

Путь к репозиторию jupyter-utils определяется автоматически (`~/Projects` или
`~/work`). Если лежит в другом месте:

```sh
JUPYTER_UTILS_DIR=/path/to/jupyter-utils ~/.config/nvim/scripts/setup-eda.sh
```

Потом перезапусти nvim. Фикс image.nvim (`rocks = false`) уже в конфиге под git — трогать не нужно.

> Имя ядра: `name=jupyter-utils`, `display_name="Python (jupyter-utils)"` — должно
> совпадать с `lua/plugins/jupytext.lua`. Скрипт регистрирует именно так.

## Версии на момент фикса (2026-08-04)
nvim 0.12.4 · uv 0.11.25 · jupytext 1.19.5 · pynvim 0.6.0 · ipykernel 7.3.0 · polars 1.42.1
