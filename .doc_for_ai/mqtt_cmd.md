# ESPHome 固件 MQTT 主题与指令手册

> 本文档根据 `build_all/` 下的实际 YAML 配置生成（`common.yaml` + `network.yaml` + `esphome_<chip>.yaml`），
> 不是通用模板 —— 主题、设备名、Broker 均为本项目真实值。

## 一、Broker 连接信息（network.yaml）

| 项 | 值 |
| --- | --- |
| Broker | `iot.iosbuy.com` |
| 端口 | `1883`（TCP，无 TLS） |
| 用户名 | `admin` |
| 密码 | `admin@123` |

## 二、设备名与主题前缀

设备名为 `elink-${chip}`（common.yaml）。未配置 `topic_prefix`，因此 **主题前缀 = 设备名**。

| 芯片 | 设备名 / 主题前缀 | 开关引脚 | MQTT |
| --- | --- | --- | --- |
| ESP8266 | `elink-8266` | GPIO4 | ✅ |
| ESP32 | `elink-32` | GPIO4 | ✅ |
| ESP32 Solo1 | `elink-solo1` | GPIO4 | ✅ |
| ESP32-S2 | `elink-s2` | GPIO4 | ✅ |
| ESP32-S2 CDC | `elink-s2cdc` | GPIO4 | ✅ |
| ESP32-S3 | `elink-s3` | GPIO4 | ✅ |
| ESP32-C2 | `elink-c2` | GPIO4 | ✅ |
| ESP32-C3 | `elink-c3` | **GPIO9** | ✅ |
| ESP32-C5 | `elink-c5` | GPIO4 | ✅ |
| ESP32-C6 | `elink-c6` | GPIO4 | ✅ |
| ESP32-P4 | `elink-p4` | GPIO4 | ❌ 无内置无线，未引入 network.yaml，**无 MQTT** |

下文以 `elink-c3` 为例，其他芯片把前缀替换为对应设备名即可。

## 三、设备发布的主题（客户端应订阅）

ESPHome 主题结构：`<前缀>/<组件类型>/<object_id>/state`。
当前配置的组件：开关 `switch_1`（Switch 1）、倒计时 `countdown`（Countdown）、定时 `timer_on` / `timer_off`（Timer On / Timer Off）。

| 主题 | Payload | retain | 说明 |
| --- | --- | --- | --- |
| `elink-c3/status` | `online` / `offline` | ✅ | 出生消息 / 遗言（LWT）。`offline` 由 Broker 在设备掉线时代发 |
| `elink-c3/switch/switch_1/state` | `ON` / `OFF` | ✅ | 开关当前状态。状态变化（无论来自 MQTT、API 还是本地）都会发布 |
| `elink-c3/number/countdown/state` | 数字（如 `59`） | ✅ | 倒计时剩余秒数，倒数期间每秒发布一次 |
| `elink-c3/datetime/timer_on/state` | JSON `{"hour":7,"minute":0,"second":0}` | ✅ | 每日定时开启时刻 |
| `elink-c3/datetime/timer_off/state` | JSON `{"hour":23,"minute":0,"second":0}` | ✅ | 每日定时关闭时刻 |
| `elink-c3/debug` | 日志文本 | ❌ | ESPHome 默认日志主题（logger 已启用） |
| `homeassistant/.../config` | JSON | ✅ | HA MQTT Discovery 自动发现配置（switch / number / datetime 各一条） |

一条命令订阅某设备全部消息：

```bash
mosquitto_sub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' -t 'elink-c3/#' -v
```

订阅全部 10 台设备的开关状态：

```bash
mosquitto_sub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' -t '+/switch/+/state' -v
```

## 四、设备订阅的主题（客户端发布以控制设备）

| 主题 | 允许的 Payload | 说明 |
| --- | --- | --- |
| `elink-c3/switch/switch_1/command` | `ON` / `OFF` / `TOGGLE` | 控制开关（继电器） |
| `elink-c3/number/countdown/command` | 数字字符串，`0`~`86400` | 倒计时秒数：发 `60` = 60 秒后自动关闭开关；发 `0` = 取消倒计时（不动开关） |
| `elink-c3/datetime/timer_on/command` | JSON `{"hour":7,"minute":0,"second":0}` | 设置每日定时开启时刻（断电保存） |
| `elink-c3/datetime/timer_off/command` | JSON `{"hour":23,"minute":0,"second":0}` | 设置每日定时关闭时刻（断电保存） |

### 开关控制指令（全部）

```bash
# 开
mosquitto_pub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' \
  -t 'elink-c3/switch/switch_1/command' -m 'ON'

# 关
mosquitto_pub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' \
  -t 'elink-c3/switch/switch_1/command' -m 'OFF'

# 反转
mosquitto_pub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' \
  -t 'elink-c3/switch/switch_1/command' -m 'TOGGLE'
```

执行后设备会立即在 `elink-c3/switch/switch_1/state` 回发新状态（`ON` / `OFF`），以此确认指令生效。

### 倒计时指令

```bash
# 120 秒后自动关闭开关（倒数期间 state 主题每秒回报剩余秒数）
mosquitto_pub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' \
  -t 'elink-c3/number/countdown/command' -m '120'

# 取消倒计时（开关保持当前状态）
mosquitto_pub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' \
  -t 'elink-c3/number/countdown/command' -m '0'
```

### 定时指令（每天到点执行）

```bash
# 每天 18:30 自动开启
mosquitto_pub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' \
  -t 'elink-c3/datetime/timer_on/command' -m '{"hour":18,"minute":30,"second":0}'

# 每天 23:00 自动关闭
mosquitto_pub -h iot.iosbuy.com -p 1883 -u admin -P 'admin@123' \
  -t 'elink-c3/datetime/timer_off/command' -m '{"hour":23,"minute":0,"second":0}'
```

定时依赖 SNTP 网络时间（时区 Asia/Shanghai），设备联网后才会走时；出厂默认 07:00:00 开、23:00:00 关，修改后断电保存。

## 五、全部设备主题速查表

| 设备 | 状态(LWT) | 开关状态（订阅） | 开关控制（发布） |
| --- | --- | --- | --- |
| elink-8266 | `elink-8266/status` | `elink-8266/switch/switch_1/state` | `elink-8266/switch/switch_1/command` |
| elink-32 | `elink-32/status` | `elink-32/switch/switch_1/state` | `elink-32/switch/switch_1/command` |
| elink-solo1 | `elink-solo1/status` | `elink-solo1/switch/switch_1/state` | `elink-solo1/switch/switch_1/command` |
| elink-s2 | `elink-s2/status` | `elink-s2/switch/switch_1/state` | `elink-s2/switch/switch_1/command` |
| elink-s2cdc | `elink-s2cdc/status` | `elink-s2cdc/switch/switch_1/state` | `elink-s2cdc/switch/switch_1/command` |
| elink-s3 | `elink-s3/status` | `elink-s3/switch/switch_1/state` | `elink-s3/switch/switch_1/command` |
| elink-c2 | `elink-c2/status` | `elink-c2/switch/switch_1/state` | `elink-c2/switch/switch_1/command` |
| elink-c3 | `elink-c3/status` | `elink-c3/switch/switch_1/state` | `elink-c3/switch/switch_1/command` |
| elink-c5 | `elink-c5/status` | `elink-c5/switch/switch_1/state` | `elink-c5/switch/switch_1/command` |
| elink-c6 | `elink-c6/status` | `elink-c6/switch/switch_1/state` | `elink-c6/switch/switch_1/command` |

（elink-p4 无网络，不出现在表中。）

倒计时与定时主题同理，把前缀换成对应设备名：
`elink-xx/number/countdown/state|command`、`elink-xx/datetime/timer_on/state|command`、`elink-xx/datetime/timer_off/state|command`。

## 六、注意事项

1. **大小写敏感**：开关指令必须是大写 `ON` / `OFF` / `TOGGLE`，小写无效。
2. **command 不要 retain**：向 `.../command` 发布时不要设置 `retain=true`，否则设备每次重启都会重放最后一条指令；`state` 与 `status` 由 ESPHome 默认 retain，客户端上线即可拿到最新状态。
3. **开关掉电不保持**：`restore_mode: RESTORE_DEFAULT_OFF` —— 设备重启后开关恢复为上次保存的状态，无记录时默认 OFF。
4. **object_id 来源**：`switch_1` / `countdown` / `timer_on` 由组件 `name` 小写化、空格转下划线得到；YAML 中的 `id:` 仅是内部引用名，不影响 MQTT 主题。
5. **倒计时语义**：倒计时只负责「到 0 关闭开关」，启动倒计时不会自动打开开关（需要的话先发 `ON` 再发秒数）；从 1 减到 0 才触发关闭，直接发 `0` 只是取消。倒数期间 state 每秒发布一次，订阅端注意消息量。
6. **定时语义**：`timer_on` / `timer_off` 每天到点都会执行，没有"单次"模式；时间值断电保存（NVS/EEPROM），SNTP 未同步前（如刚配网）不会触发。
7. **尚未配置的功能**：`button`（远程重启）和 `mqtt.on_message` 自定义动作主题（`elink-xx/action`）当前未配置，如需可在 common.yaml 继续扩展。
