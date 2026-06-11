#!/bin/bash
# ESPHome ESP32-C3 编译与烧录脚本
# 自动检测串口:  ./build_esp32c3.sh flash
# 手动指定串口:  SERIAL_PORT=/dev/cu.usbserial-3120 ./build_esp32c3.sh flash
# 指定配置文件:  CONFIG=my_device.yaml ./build_esp32c3.sh build
#
# 命令:
#   build       编译固件
#   buildall    编译 build_all/ 下所有芯片固件 (可指定芯片: buildall c3 s3)
#   flash       烧录固件
#   buildflash  编译并烧录
#   run         编译 + 烧录 + 监控 (esphome run)
#   logs        查看串口日志
#   clean       清理编译产物
#   erase       擦除 Flash
#
# buildall 芯片:
#   8266      ESP8266
#   32        ESP32
#   solo1     ESP32 Solo1 (单核)
#   s2        ESP32-S2
#   s2cdc     ESP32-S2 (USB CDC)
#   s3        ESP32-S3
#   c2        ESP32-C2
#   c3        ESP32-C3
#   c5        ESP32-C5
#   c6        ESP32-C6
#   p4        ESP32-P4 (无内置无线)

set -e

CONFIG="${CONFIG:-esp32c3.yaml}"
UPLOAD_BAUD="${UPLOAD_BAUD:-460800}"
BUILD_ALL_DIR="build_all"
ALL_CHIPS=(8266 32 solo1 s2 s2cdc s3 c2 c3 c5 c6 p4)

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 查找 esphome CLI（优先系统安装，其次 venv，再 python3 -m esphome）
find_esphome() {
    if command -v esphome &>/dev/null; then
        echo "esphome"
        return
    fi
    for venv in .venv venv env; do
        if [ -x "$venv/bin/esphome" ]; then
            echo "$venv/bin/esphome"
            return
        fi
    done
    if python3 -m esphome version &>/dev/null 2>&1; then
        echo "python3_module"
        return
    fi
    echo ""
}

run_esphome() {
    local esphome_path
    esphome_path=$(find_esphome)
    if [ -z "$esphome_path" ]; then
        echo -e "${RED}错误: 未找到 esphome${NC}" >&2
        echo "安装命令: pip3 install esphome" >&2
        exit 1
    fi
    if [ "$esphome_path" = "python3_module" ]; then
        python3 -m esphome "$@"
    else
        "$esphome_path" "$@"
    fi
}

check_config() {
    if [ ! -f "$CONFIG" ]; then
        echo -e "${RED}错误: 配置文件不存在: ${CONFIG}${NC}" >&2
        echo "用法: CONFIG=your_device.yaml $0 $1" >&2
        exit 1
    fi
}

# 查找 esptool（用于 erase）
find_esptool() {
    local pio_python="$HOME/.platformio/penv/bin/python3"
    if [ -x "$pio_python" ] && "$pio_python" -m esptool version &>/dev/null; then
        echo "pio_python"; return
    fi
    if command -v esptool.py &>/dev/null; then
        echo "esptool.py"; return
    fi
    if python3 -m esptool version &>/dev/null 2>&1; then
        echo "python3_module"; return
    fi
    echo ""
}

run_esptool() {
    local esptool_path
    esptool_path=$(find_esptool)
    if [ -z "$esptool_path" ]; then
        echo -e "${RED}错误: 未找到 esptool${NC}" >&2
        echo "安装命令: pip3 install esptool" >&2
        return 1
    fi
    case "$esptool_path" in
        pio_python)    "$HOME/.platformio/penv/bin/python3" -m esptool "$@" ;;
        python3_module) python3 -m esptool "$@" ;;
        *)             $esptool_path "$@" ;;
    esac
}

# 自动检测串口，优先 usbserial，其次 usbmodem
detect_serial_port() {
    local ports
    ports=($(ls /dev/cu.usbserial-* /dev/cu.usbmodem* 2>/dev/null))
    if [ ${#ports[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未检测到 USB 串口设备${NC}" >&2
        echo "请检查：" >&2
        echo "  1. USB 线已连接" >&2
        echo "  2. 使用支持数据传输的 USB 线" >&2
        echo "  3. 直连电脑，不通过 Hub" >&2
        exit 1
    fi
    if [ ${#ports[@]} -eq 1 ]; then
        echo "${ports[0]}"
        return
    fi
    echo -e "${YELLOW}检测到多个串口设备：${NC}" >&2
    for i in "${!ports[@]}"; do
        echo -e "  ${CYAN}[$((i+1))]${NC} ${ports[$i]}" >&2
    done
    echo -n "请选择串口 [1-${#ports[@]}]: " >&2
    local choice
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#ports[@]} ]; then
        echo "${ports[$((choice-1))]}"
    else
        echo -e "${RED}无效选择${NC}" >&2
        exit 1
    fi
}

usage() {
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  build       编译固件"
    echo "  buildall    编译所有芯片固件 (可指定: buildall c3 s3)"
    echo "              芯片: ${ALL_CHIPS[*]}"
    echo "  flash       烧录固件"
    echo "  buildflash  编译并烧录"
    echo "  run         编译 + 烧录 + 监控"
    echo "  logs        查看串口日志"
    echo "  erase       擦除 Flash"
    echo "  clean       清理编译产物"
    echo ""
    echo "环境变量:"
    echo "  CONFIG       配置文件 (默认 esp32c3.yaml)"
    echo "  SERIAL_PORT  串口设备 (默认自动检测)"
    echo "  UPLOAD_BAUD  烧录波特率 (默认 460800)"
}

do_build() {
    check_config build
    echo -e "${GREEN}开始编译 ${CONFIG}...${NC}"
    run_esphome compile "$CONFIG"
    echo -e "${GREEN}编译完成！${NC}"
}

do_buildall() {
    local chips=("$@")
    [ ${#chips[@]} -eq 0 ] && chips=("${ALL_CHIPS[@]}")
    local ok=() fail=()
    mkdir -p "$BUILD_ALL_DIR/firmware"
    for chip in "${chips[@]}"; do
        local cfg="$BUILD_ALL_DIR/esphome_${chip}.yaml"
        if [ ! -f "$cfg" ]; then
            echo -e "${RED}跳过 ${chip}: 配置不存在 ${cfg}${NC}"
            fail+=("${chip}(无配置)")
            continue
        fi
        echo ""
        echo -e "${GREEN}========== 编译 ${chip} (${cfg}) ==========${NC}"
        if run_esphome compile "$cfg"; then
            ok+=("$chip")
            # 收集固件到 build_all/firmware/（优先 factory 整片镜像）
            local build_dir="$BUILD_ALL_DIR/.esphome/build/elink-${chip}"
            local bin
            bin=$(find "$build_dir" -name 'firmware.factory.bin' 2>/dev/null | head -1)
            [ -z "$bin" ] && bin=$(find "$build_dir" -name 'firmware.bin' 2>/dev/null | head -1)
            if [ -n "$bin" ]; then
                cp "$bin" "$BUILD_ALL_DIR/firmware/esphome_${chip}.bin"
                echo -e "${CYAN}固件: ${BUILD_ALL_DIR}/firmware/esphome_${chip}.bin${NC}"
            fi
        else
            fail+=("$chip")
        fi
    done
    echo ""
    echo -e "${GREEN}========== buildall 汇总 ==========${NC}"
    echo -e "${GREEN}成功 (${#ok[@]}): ${ok[*]:-无}${NC}"
    if [ ${#fail[@]} -gt 0 ]; then
        echo -e "${RED}失败 (${#fail[@]}): ${fail[*]}${NC}"
        return 1
    fi
}

do_flash() {
    check_config flash
    SERIAL_PORT="${SERIAL_PORT:-$(detect_serial_port)}"
    echo -e "${YELLOW}开始烧录...${NC}"
    echo -e "${CYAN}配置: ${CONFIG}${NC}"
    echo -e "${CYAN}串口: ${SERIAL_PORT}${NC}"
    run_esphome upload "$CONFIG" --device "$SERIAL_PORT"
    echo -e "${GREEN}烧录完成！设备将自动重启。${NC}"
}

do_run() {
    check_config run
    SERIAL_PORT="${SERIAL_PORT:-$(detect_serial_port)}"
    echo -e "${GREEN}编译 + 烧录 + 监控 ${CONFIG}...${NC}"
    run_esphome run "$CONFIG" --device "$SERIAL_PORT"
}

do_logs() {
    check_config logs
    SERIAL_PORT="${SERIAL_PORT:-$(detect_serial_port)}"
    echo -e "${CYAN}监控串口日志（Ctrl+C 退出）...${NC}"
    run_esphome logs "$CONFIG" --device "$SERIAL_PORT"
}

do_erase() {
    SERIAL_PORT="${SERIAL_PORT:-$(detect_serial_port)}"
    echo -e "${YELLOW}擦除 Flash...${NC}"
    echo -e "${CYAN}串口: ${SERIAL_PORT}${NC}"
    run_esptool --chip esp32c3 --port "$SERIAL_PORT" --baud "$UPLOAD_BAUD" erase-flash
    echo -e "${GREEN}擦除完成！${NC}"
}

do_clean() {
    check_config clean
    echo "清理编译产物..."
    run_esphome clean "$CONFIG"
    echo -e "${GREEN}清理完成！${NC}"
}

case "${1}" in
    build)      do_build ;;
    buildall)   shift; do_buildall "$@" ;;
    flash)      do_flash ;;
    buildflash) do_build && do_flash ;;
    run)        do_run ;;
    logs)       do_logs ;;
    erase)      do_erase ;;
    clean)      do_clean ;;
    *)          usage ;;
esac
