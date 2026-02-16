#!/bin/bash
set -e

USER_NAME="$USER"
TARGET_DIR=""
TELEGRAM_TOKEN=""
SERVICE_NAME=""


# -----------------------------------------------------
# ----------------------- Sudo ------------------------
# -----------------------------------------------------
sudo -v

while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
done 2>/dev/null &

# -----------------------------------------------------
# ---------------------- Colors -----------------------
# -----------------------------------------------------
if [ -t 1 ]; then
    C_RESET="$(printf '\033[0m')"
    C_RED="$(printf '\033[31m')"
    C_GREEN="$(printf '\033[32m')"
    C_YELLOW="$(printf '\033[33m')"
    C_CYAN="$(printf '\033[36m')"
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi


# -----------------------------------------------------
# --------------------- Distro ID ---------------------
# -----------------------------------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="$ID"
else
    DISTRO_ID="unknown"
fi


case "$DISTRO_ID" in
    ubuntu)
        echo "${C_CYAN}=== FunPay Hub on Ubuntu ===${C_RESET}"
        ;;
    debian)
        echo "${C_CYAN}=== FunPay Hub on Debian ===${C_RESET}"
        ;;
    arch)
        echo "${C_CYAN}=== FunPay Hub on Arch linux ===${C_RESET}"
        ;;
    *)
        echo "Неизвестный дистрибутив: $DISTRO_ID"
        exit 1
        ;;
esac


# -----------------------------------------------------
# --------------------- Functions ---------------------
# -----------------------------------------------------
check_telegram_token() {
  local token="$1"
  curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://api.telegram.org/bot${token}/getMe"
}


install_deps() {
  echo "${C_CYAN}Устанавливаем зависимости...${C_RESET}"
  case "$DISTRO_ID" in
    ubuntu|debian)
      sudo apt update
      sudo apt install -y git curl unzip
      ;;
    arch)
      sudo pacman -Syu --noconfirm git curl unzip
      ;;
    *)
      echo "Неподдерживаемый дистрибутив: $DISTRO_ID" >&2
      exit 1
      ;;
  esac
}


install_uv() {
  if [ ! -f ~/.local/bin/uv ]; then
    echo "${C_CYAN}Устанавливаем UV...${C_RESET}"

    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
}


install_python() {
  echo "${C_CYAN}Устанавливаем Python...${C_RESET}"
  ~/.local/bin/uv python install 3.13
}


clone_fph() {
    local DEFAULT_DIR="funpayhub"
    local INSTALL_DIR=""

    while :; do
        read -rp "Куда установить FunPay Hub? [${DEFAULT_DIR}]: " INSTALL_DIR

        if [ -z "$INSTALL_DIR" ]; then
            INSTALL_DIR="$DEFAULT_DIR"
        fi
        TARGET_DIR="$HOME/$INSTALL_DIR"
        echo "$TARGET_DIR" >&2

        if [ -e "$TARGET_DIR" ]; then
            echo "Папка '$INSTALL_DIR' уже существует. Пожалуйста, выберите другой путь." >&2
            continue
        fi

        if ! mkdir -p "$TARGET_DIR"; then
            echo "Не удалось создать папку '$TARGET_DIR'. Проверьте права." >&2
            continue
        fi

        echo "FunPay Hub будет установлен в '$TARGET_DIR'."
        break
    done

    if ! git clone https://github.com/funpayhub/funpayhub "$TARGET_DIR"; then
      echo "Ошибка клонирования репозитория!" >&2
      exit 1
    fi
}


bootstrap() {
  echo "Создаю виртуальное окружение..."
  cd "$TARGET_DIR"
  if ! ~/.local/bin/uv venv --python 3.13; then
    echo "Ошибка при создании виртуального окружения." >&2
    exit 1
  fi

  if ! ~/.local/bin/uv sync; then
    echo "Ошибка при загрузке Python зависимостей." >&2
    exit 1
  fi

  if ! .venv/bin/python bootstrap.py; then
    echo "Ошибка при запуске bootstrap." >&2
    exit 1
  fi
}


setup_config() {
  if ! .venv/bin/python releases/current/launcher.py --setup-config; then
    echo "Произошла ошибка при создании конфига." >&2
    exit 1
  fi
}


create_service() {
  echo "${C_CYAN}Создаю systemd сервис...${C_RESET}"

  local INSTALL_NAME
  INSTALL_NAME="$(basename "$TARGET_DIR")"

  SERVICE_NAME="funpayhub_${USER_NAME}_${INSTALL_NAME}.service"
  local SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

  sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=FunPay Hub
After=network.target

[Service]
User=$USER_NAME
WorkingDirectory=$TARGET_DIR
Environment=PYTHONUNBUFFERED=1
PassEnvironment=TELEGRAM_TOKEN

ExecStart=$TARGET_DIR/.venv/bin/python releases/current/launcher.py

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"

  echo "${C_GREEN}Сервис $SERVICE_NAME создан.${C_RESET}"
  return
}


install_deps
install_uv
install_python
clone_fph
bootstrap
setup_config
create_service
sudo systemctl start "$SERVICE_NAME"
echo "Сервис $SERVICE_NAME запущен!"
echo "Теперь перейдите в вашего Telegram бота и отправьте ему пароль."
echo "Для запуска / остановки FunPay Hub используйте команды"
echo "sudo systemctl start $SERVICE_NAME"
echo "sudo systemctl stop $SERVICE_NAME"
