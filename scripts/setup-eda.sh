#!/usr/bin/env bash
#
# Настройка/восстановление EDA-стека nvim (molten + jupytext + image.nvim + ядро).
# Кросс-платформенно: Linux и macOS. Идемпотентно — можно запускать повторно.
#
# Что делает (см. TROUBLESHOOTING.md — архитектура и первопричины):
#   1) jupytext CLI          -> uv tool (~/.local/bin/jupytext)
#   2) host-venv провайдера   -> ~/.venvs/neovim (pynvim + jupyter_client + nbformat)
#   3) ядро jupyter-utils     -> ipykernel из venv репозитория jupyter-utils
#   4) пересборка rplugin     -> nvim --headless UpdateRemotePlugins (с force-load molten)
#   5) проверка magick        -> image.nvim рендерит через системный `magick` (PATH)
#
# Переопределение пути к репозиторию jupyter-utils:
#   JUPYTER_UTILS_DIR=/path/to/jupyter-utils ./setup-eda.sh
#
set -euo pipefail

# ---- вывод ------------------------------------------------------------------
c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_hdr=$'\033[36m'; c_off=$'\033[0m'
step() { printf '\n%s==> %s%s\n' "$c_hdr" "$*" "$c_off"; }
ok()   { printf '%s  ok:%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '%s  warn:%s %s\n' "$c_warn" "$c_off" "$*"; }
die()  { printf '%s  error:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }

# ---- определение ОС ---------------------------------------------------------
case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  OS=linux ;;
  *)      die "неподдерживаемая ОС: $(uname -s)" ;;
esac
step "ОС: $OS"

# ---- prerequisites ----------------------------------------------------------
command -v uv >/dev/null 2>&1 || die "нет uv. Установи: https://docs.astral.sh/uv/  (curl -LsSf https://astral.sh/uv/install.sh | sh)"
command -v nvim >/dev/null 2>&1 || die "нет nvim в PATH."
ok "uv: $(uv --version)"
ok "nvim: $(nvim --version | head -1)"

# ---- 1. jupytext CLI --------------------------------------------------------
step "jupytext CLI (uv tool)"
uv tool install --quiet jupytext 2>/dev/null || uv tool upgrade jupytext >/dev/null 2>&1 || true
if command -v jupytext >/dev/null 2>&1; then
  ok "jupytext: $(jupytext --version)"
else
  warn "jupytext не в PATH. Проверь, что ~/.local/bin в PATH (uv tool dir --bin)."
fi

# ---- 2. host-venv провайдера molten ----------------------------------------
# Путь совпадает с vim.g.python3_host_prog в init.lua (одинаков на обеих ОС).
step "host-venv провайдера: ~/.venvs/neovim"
HOST_VENV="$HOME/.venvs/neovim"
HOST_PY="$HOST_VENV/bin/python"
[ -x "$HOST_PY" ] || uv venv "$HOST_VENV"
uv pip install --quiet --python "$HOST_PY" pynvim jupyter_client nbformat
ok "провайдер готов: $HOST_PY"

# ---- 3. ядро jupyter-utils --------------------------------------------------
# Машинно-зависимый путь. Кандидаты + override через JUPYTER_UTILS_DIR.
step "ядро jupyter-utils"
JU_DIR="${JUPYTER_UTILS_DIR:-}"
if [ -z "$JU_DIR" ]; then
  for cand in "$HOME/Projects/jupyter-utils" "$HOME/work/jupyter-utils"; do
    [ -d "$cand" ] && { JU_DIR="$cand"; break; }
  done
fi

if [ -z "$JU_DIR" ] || [ ! -d "$JU_DIR" ]; then
  warn "репозиторий jupyter-utils не найден (искал ~/Projects и ~/work)."
  warn "склонируй его и перезапусти:  JUPYTER_UTILS_DIR=/path/to/jupyter-utils $0"
else
  ok "jupyter-utils: $JU_DIR"
  JU_PY="$JU_DIR/.venv/bin/python"
  if [ ! -x "$JU_PY" ]; then
    warn "venv репозитория не найден — создаю"
    if [ -f "$JU_DIR/pyproject.toml" ] || [ -f "$JU_DIR/uv.lock" ]; then
      ( cd "$JU_DIR" && uv sync )   # ставит зависимости репо (polars/nb_utils и т.п.)
    else
      uv venv "$JU_DIR/.venv"
    fi
  fi
  # ipykernel нужен для регистрации ядра — доставляем в venv репозитория.
  uv pip install --quiet --python "$JU_PY" ipykernel
  # name/display_name должны совпадать с lua/plugins/jupytext.lua.
  "$JU_PY" -m ipykernel install --user \
    --name jupyter-utils \
    --display-name "Python (jupyter-utils)"
  ok "ядро зарегистрировано: name=jupyter-utils"
fi

# ---- 4. пересборка remote-plugin манифеста ---------------------------------
# +Lazy! load molten-nvim обязателен: molten грузится по ft, иначе манифест
# соберётся без molten и :MoltenInit не появится.
step "пересборка rplugin-манифеста (force-load molten)"
nvim --headless "+Lazy! load molten-nvim" "+UpdateRemotePlugins" +qa
RPLUGIN="$HOME/.local/share/nvim/rplugin.vim"
if [ -f "$RPLUGIN" ] && grep -qi molten "$RPLUGIN"; then
  ok "molten в манифесте: $RPLUGIN"
else
  warn "molten не попал в $RPLUGIN — проверь, что плагин установлен (:Lazy)."
fi

# ---- 5. проверка magick (image.nvim / magick_cli) ---------------------------
step "ImageMagick (для image.nvim, processor=magick_cli)"
if command -v magick >/dev/null 2>&1; then
  ok "magick: $(command -v magick)"
else
  if [ "$OS" = mac ]; then
    warn "нет magick. Установи:  brew install imagemagick"
  else
    warn "нет magick. Установи:  sudo pacman -S imagemagick   (или пакет твоего дистро)"
  fi
fi

step "готово. Перезапусти nvim, открой .ipynb, :MoltenInit -> «Python (jupyter-utils)»."
