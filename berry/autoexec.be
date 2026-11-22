# ============================================================
# HỆ THỐNG GIÁM SÁT & ĐIỀU KHIỂN AO TÔM THÔNG MINH
# Phần cứng: ESP32-S3-Relay-6CH + RS485 (pH ID 2, DO ID 16, EC ID 4) + CoreIoT
# - Đọc 3 cảm biến, in & gửi cùng lúc mỗi 10 giây
# - Relay chỉ bật/tắt THỦ CÔNG (web Tasmota hoặc widget CoreIoT), không hẹn giờ
# ============================================================
import mqtt
import string

# ------------------------------------------------------------
# 1. CẤU HÌNH CẢM BIẾN (3 CẢM BIẾN TRÊN CÙNG BUS RS485, 9600 8N1)
# ------------------------------------------------------------
var ID_PH           = 2                            # ES-PH-WT-01 : pH (reg 1-2), nhiệt độ (reg 3-4)
var ID_DO           = 16                           # ES-DO-WT-01 : DO mg/L (reg 1-2), nhiệt độ (reg 3-4)
var ID_EC           = 4                            # ES-EC-WT-01 : EC uS/cm (reg 0-1), nhiệt độ (reg 4-5)
var SENSOR_IDS      = [ID_PH, ID_DO, ID_EC]

# Danh sách lệnh đọc Modbus (function 3), mỗi lệnh 2 thanh ghi = 1 float (giống Insight Sensor).
# Mỗi chu kỳ 10 s: gửi lần lượt 6 lệnh (cách nhau 1.2 s, vì RS485 chỉ hỏi được 1 thiết bị mỗi lúc),
# sau đó in + gửi CÙNG LÚC cả 3 cảm biến lên Tasmota và CoreIoT.
var READS = [
    {"id": 2,  "start": 1, "count": 2},            # pH
    {"id": 2,  "start": 3, "count": 2},            # nhiệt độ (cảm biến pH)
    {"id": 16, "start": 1, "count": 2},            # DO
    {"id": 16, "start": 3, "count": 2},            # nhiệt độ (cảm biến DO)
    {"id": 4,  "start": 0, "count": 2},            # EC
    {"id": 4,  "start": 4, "count": 2}             # nhiệt độ (cảm biến EC)
]

var FLOAT_ABCD      = false                        # false = CDAB (word thấp trước) - đúng với log của 3 cảm biến
var TB_TOPIC        = "v1/devices/me/telemetry"

# Ngưỡng cảnh báo pH (chỉ báo bằng đèn + còi, KHÔNG điều khiển relay)
var PH_LOW          = 7.00
var PH_HIGH         = 8.50

var data = {
    "ph": 0.0, "do": 0.0, "ec": 0.0,
    "temp_ph": 0.0, "temp_do": 0.0, "temp_ec": 0.0
}
var TEMP_KEY        = {2: "temp_ph", 16: "temp_do", 4: "temp_ec"}   # {id: key nhiệt độ}
var last_seen       = {}                           # {id: millis lần đọc OK gần nhất}
var SENSOR_STALE_MS = 60000                        # Quá 60 s không trả lời -> coi là mất kết nối
var CYCLE_SEC       = 10                           # Chu kỳ in/gửi dữ liệu (giây)
var READ_GAP_MS     = 1200                         # Khoảng cách giữa 2 lệnh đọc Modbus
var poll_status     = "Đang khởi tạo..."
var last_level      = ""                           # Mức cảnh báo trước đó (để còi chỉ kêu khi đổi mức)

# ------------------------------------------------------------
# 2. GIẢI MÃ FLOAT32 TỪ REGISTERS (CDAB)
# ------------------------------------------------------------
def regs_to_float(r0, r1)
    var b = bytes()
    if FLOAT_ABCD
        b.add(r0, -2)
        b.add(r1, -2)
    else
        b.add(r1, -2)
        b.add(r0, -2)
    end
    return b.getfloat(0, true)
end

# ------------------------------------------------------------
# 3. GỬI LỆNH ĐỌC MODBUS
# ------------------------------------------------------------
var poll_paused_until = 0                          # Tạm dừng đọc định kỳ (khi đang đổi ID)

def modbus_read(id, start, count)
    tasmota.cmd(string.format('ModbusSend {"deviceaddress":%d,"functioncode":3,"startaddress":%d,"type":"uint16","count":%d}', id, start, count))
end

def sensor_online(id)
    return last_seen.contains(id) && (tasmota.millis() - last_seen[id]) < SENSOR_STALE_MS
end

# Đọc ngay 1 cảm biến từ Berry Console: sensor_poll_id(16)
def sensor_poll_id(id)
    for r: READS
        if r["id"] == id
            modbus_read(r["id"], r["start"], r["count"])
        end
    end
end

# Lệnh Console đổi Slave ID cảm biến (ghi thanh ghi 25):  PhSetId <id_cũ>,<id_mới>
# Ví dụ: PhSetId 1,2   (chỉ cảm biến cần đổi được cấp nguồn, các con cùng ID cũ phải tắt nguồn)
tasmota.add_cmd("PhSetId", def(cmd, idx, payload)
    var parts = string.split(payload, ",")
    if size(parts) < 2
        tasmota.resp_cmnd('{"PhSetId":"Usage: PhSetId <old_id>,<new_id>"}')
        return
    end
    var old_id = int(parts[0])
    var new_id = int(parts[1])
    if old_id < 1 || old_id > 247 || new_id < 1 || new_id > 247
        tasmota.resp_cmnd('{"PhSetId":"ID phải từ 1 đến 247"}')
        return
    end
    poll_paused_until = tasmota.millis() + 15000    # dừng đọc định kỳ 15 s để bus rảnh
    tasmota.set_timer(500, def ()
        tasmota.cmd(string.format('ModbusSend {"deviceaddress":%d,"functioncode":6,"startaddress":25,"type":"uint16","count":1,"values":[%d]}', old_id, new_id))
    end)
    tasmota.set_timer(5000, def () modbus_read(new_id, 1, 2) end)   # đọc thử ID mới sau 5 s
    print(string.format("PhSetId: ghi ID %d -> %d, 5 s sau sẽ đọc thử ID %d", old_id, new_id, new_id))
    tasmota.resp_cmnd(string.format('{"PhSetId":{"Old":%d,"New":%d,"Status":"Sent"}}', old_id, new_id))
end)

# ------------------------------------------------------------
# 4. CẢNH BÁO pH (ĐÈN + CÒI, KHÔNG ĐỘNG VÀO RELAY)
# ------------------------------------------------------------
def check_ph_alarm()
    var level = "ok"
    if !sensor_online(ID_PH)
        level = "offline"
        poll_status = "Chưa có dữ liệu cảm biến pH"
    elif data["ph"] > 0.0 && data["ph"] < PH_LOW
        level = "low"
        poll_status = string.format("CẢNH BÁO: pH THẤP (%.2f)", data["ph"])
    elif data["ph"] > PH_HIGH
        level = "high"
        poll_status = string.format("CẢNH BÁO: pH CAO (%.2f)", data["ph"])
    else
        poll_status = "An toàn (Bình thường)"
    end

    if level != last_level                         # Đèn + còi chỉ đổi khi mức cảnh báo thay đổi
        if level == "low"
            tasmota.cmd("Color FF0000")
            tasmota.cmd("Buzzer 2")
        elif level == "high"
            tasmota.cmd("Color FFA500")
            tasmota.cmd("Buzzer 1")
        elif level == "ok"
            tasmota.cmd("Color 00FF00")
        end
        last_level = level
    end
end

# Nhiệt độ nước = trung bình các cảm biến đang online
def water_temp()
    var s = 0.0
    var n = 0
    for id: SENSOR_IDS
        if sensor_online(id)
            s += data[TEMP_KEY[id]]
            n += 1
        end
    end
    if n == 0
        return 0.0
    end
    return s / n
end

# ------------------------------------------------------------
# 5. NHẬN DỮ LIỆU TỪ CẢM BIẾN (CHỈ LƯU, CHƯA GỬI)
# ------------------------------------------------------------
def sensors_on_rx(value, trigger, msg)
    var id = value["DeviceAddress"]
    var start = value["StartAddress"]
    var v = value["Values"]
    if v == nil || size(v) < 2
        return
    end

    var f = regs_to_float(v[0], v[1])
    if id == ID_PH && start == 1        data["ph"] = f
    elif id == ID_PH && start == 3      data["temp_ph"] = f
    elif id == ID_DO && start == 1      data["do"] = f
    elif id == ID_DO && start == 3      data["temp_do"] = f
    elif id == ID_EC && start == 0      data["ec"] = f
    elif id == ID_EC && start == 4      data["temp_ec"] = f
    else
        return
    end
    last_seen[id] = tasmota.millis()
end

tasmota.add_rule("ModbusReceived", sensors_on_rx)

# ------------------------------------------------------------
# 6. MỖI 10 GIÂY: ĐỌC 3 CẢM BIẾN -> IN & GỬI CÙNG LÚC LÊN COREIOT
# ------------------------------------------------------------
def publish_snapshot()
    check_ph_alarm()

    var parts = []
    var line = []
    if sensor_online(ID_PH)
        parts.push(string.format('"ph":%.2f,"temp_ph":%.1f', data["ph"], data["temp_ph"]))
        line.push(string.format("pH %.2f (%.1f°C)", data["ph"], data["temp_ph"]))
    else
        line.push("pH: không phản hồi")
    end
    if sensor_online(ID_DO)
        parts.push(string.format('"do":%.2f,"temp_do":%.1f', data["do"], data["temp_do"]))
        line.push(string.format("DO %.2f mg/L (%.1f°C)", data["do"], data["temp_do"]))
    else
        line.push("DO: không phản hồi")
    end
    if sensor_online(ID_EC)
        parts.push(string.format('"ec":%.1f,"temp_ec":%.1f', data["ec"], data["temp_ec"]))
        line.push(string.format("EC %.1f uS/cm (%.1f°C)", data["ec"], data["temp_ec"]))
    else
        line.push("EC: không phản hồi")
    end
    if size(parts) > 0
        parts.push(string.format('"temp":%.1f', water_temp()))
    end
    parts.push(string.format('"status":"%s"', poll_status))

    var payload = "{" + parts.concat(",") + "}"
    print("SENSORS:", line.concat(" | "))
    print("COREIOT SENSOR:", payload)
    if mqtt.connected()
        mqtt.publish(TB_TOPIC, payload)
    end
end

def make_read(r)
    return def () modbus_read(r["id"], r["start"], r["count"]) end
end

def start_cycle()
    if tasmota.millis() < poll_paused_until
        return
    end
    var i = 0
    for r: READS
        tasmota.set_timer(i * READ_GAP_MS, make_read(r))
        i += 1
    end
    # Gửi sau khi lệnh đọc cuối cùng đã có thời gian trả lời
    tasmota.set_timer(i * READ_GAP_MS + 500, publish_snapshot)
end

tasmota.add_cron(string.format("*/%d * * * * *", CYCLE_SEC), start_cycle, "sensor_cycle")

# ------------------------------------------------------------
# 7. HIỂN THỊ TRÊN TRANG CHÍNH TASMOTA & BẢN TIN tele/SENSOR
# ------------------------------------------------------------
class PondSensorDriver
    def web_sensor()
        var msg = ""
        if sensor_online(ID_PH)
            msg += string.format("{s}pH (ID %d){m}%.2f / %.1f &deg;C{e}", ID_PH, data["ph"], data["temp_ph"])
        else
            msg += string.format("{s}pH (ID %d){m}Không phản hồi{e}", ID_PH)
        end
        if sensor_online(ID_DO)
            msg += string.format("{s}DO (ID %d){m}%.2f mg/L / %.1f &deg;C{e}", ID_DO, data["do"], data["temp_do"])
        else
            msg += string.format("{s}DO (ID %d){m}Không phản hồi{e}", ID_DO)
        end
        if sensor_online(ID_EC)
            msg += string.format("{s}EC (ID %d){m}%.1f &micro;S/cm / %.1f &deg;C{e}", ID_EC, data["ec"], data["temp_ec"])
        else
            msg += string.format("{s}EC (ID %d){m}Không phản hồi{e}", ID_EC)
        end
        msg += string.format("{s}Nhiệt độ nước (TB){m}%.1f &deg;C{e}", water_temp())
        msg += string.format("{s}Trạng thái chung{m}%s{e}", poll_status)
        tasmota.web_send_decimal(msg)
    end

    def json_append()
        tasmota.response_append(string.format(',"PondWater":{"pH":%.2f,"DO":%.2f,"EC":%.1f,"Temp":%.1f,"Temp_pH":%.1f,"Temp_DO":%.1f,"Temp_EC":%.1f,"Status":"%s"}',
            data["ph"], data["do"], data["ec"], water_temp(),
            data["temp_ph"], data["temp_do"], data["temp_ec"], poll_status))
    end
end
tasmota.add_driver(PondSensorDriver())

# ------------------------------------------------------------
# 8. ĐIỀU KHIỂN RELAY THỦ CÔNG TỪ COREIOT (RPC) & ĐỒNG BỘ TRẠNG THÁI RELAY
#    CoreIoT gửi:  v1/devices/me/rpc/request/<id>   {"method":"setRelay2","params":true}
#    Thiết bị trả: v1/devices/me/rpc/response/<id>  true / false
#    Method hỗ trợ: getGpioStatus / setGpioStatus (widget Basic GPIO Control),
#                   setRelayN / getRelayN (N = 1..6), setValue / getValue (= Relay 1),
#                   setRelay với params {"relay":N,"state":true}
# ------------------------------------------------------------
import json

var RPC_REQ_TOPIC  = "v1/devices/me/rpc/request/+"
var RPC_RESP_TOPIC = "v1/devices/me/rpc/response/"
var RELAY_COUNT    = 6

# Chuyển params của widget (true/false, 1/0, "on"/"off", {"state":..}) thành bool
def to_bool(p)
    if type(p) == 'bool'   return p end
    if type(p) == 'int' || type(p) == 'real'   return p != 0 end
    if type(p) == 'string'
        var s = string.tolower(p)
        return s == "true" || s == "on" || s == "1"
    end
    if classname(p) == 'map'
        if p.contains("state") return to_bool(p["state"]) end
        if p.contains("value") return to_bool(p["value"]) end
    end
    return false
end

def relay_state(ch)          # ch: 1..6
    var pw = tasmota.get_power()
    if pw == nil || ch < 1 || ch > size(pw) return false end
    return pw[ch - 1]
end

# Gửi trạng thái 1 relay lên CoreIoT dạng telemetry: {"relay2":true}
def publish_relay(ch)
    if mqtt.connected()
        mqtt.publish(TB_TOPIC, string.format('{"relay%d":%s}', ch, relay_state(ch) ? "true" : "false"))
    end
end

def publish_all_relays()
    if !mqtt.connected() return end
    var parts = []
    for ch: 1 .. RELAY_COUNT
        parts.push(string.format('"relay%d":%s', ch, relay_state(ch) ? "true" : "false"))
    end
    mqtt.publish(TB_TOPIC, "{" + parts.concat(",") + "}")
end

# Widget "Basic GPIO Control" của CoreIoT dùng số GPIO -> ánh xạ sang kênh relay
var GPIO_TO_RELAY = {1: 1, 2: 2, 41: 3, 42: 4, 45: 5, 46: 6}

def gpio_status_json()
    var parts = []
    for pin: GPIO_TO_RELAY.keys()
        parts.push(string.format('"%d":%s', pin, relay_state(GPIO_TO_RELAY[pin]) ? "true" : "false"))
    end
    return "{" + parts.concat(",") + "}"
end

def on_rpc(topic, idx, payload_s, payload_b)
    var req_id = string.split(topic, "/")[-1]
    var req = json.load(payload_s)
    if req == nil return true end
    var method = req.find("method", "")
    var params = req.find("params")
    var ch = 0
    var result = nil

    # --- Widget "Basic GPIO Control": getGpioStatus / setGpioStatus {"pin":41,"enabled":true}
    if method == "getGpioStatus" || method == "setGpioStatus"
        if method == "setGpioStatus" && classname(params) == 'map'
            var pin = int(params.find("pin", -1))
            var rch = GPIO_TO_RELAY.find(pin)
            if rch != nil
                tasmota.set_power(rch - 1, to_bool(params.find("enabled", false)))
                print(string.format("RPC: setGpioStatus GPIO%d -> Relay %d = %s", pin, rch, relay_state(rch) ? "ON" : "OFF"))
                publish_relay(rch)
            else
                print("RPC: GPIO không phải chân relay:", pin)
            end
        end
        mqtt.publish(RPC_RESP_TOPIC + req_id, gpio_status_json())
        return true
    end

    if method == "setValue" || method == "getValue"
        ch = 1                                         # widget mặc định -> Relay 1
    elif method == "setRelay" && classname(params) == 'map'
        ch = int(params.find("relay", 0))
    elif string.find(method, "setRelay") == 0 || string.find(method, "getRelay") == 0
        ch = int(method[8..])                          # "setRelay3" -> 3
    end

    if ch < 1 || ch > RELAY_COUNT
        print("RPC: method không hỗ trợ:", payload_s)
        mqtt.publish(RPC_RESP_TOPIC + req_id, '{"error":"unsupported method"}')
        return true
    end

    if string.find(method, "set") == 0
        tasmota.set_power(ch - 1, to_bool(params))
        print(string.format("RPC: %s -> Relay %d = %s", method, ch, relay_state(ch) ? "ON" : "OFF"))
    end
    result = relay_state(ch) ? "true" : "false"
    mqtt.publish(RPC_RESP_TOPIC + req_id, result)      # trả lời để widget cập nhật trạng thái
    publish_relay(ch)
    return true
end

mqtt.subscribe(RPC_REQ_TOPIC, on_rpc)

# Relay đổi trạng thái (nút web Tasmota hoặc widget CoreIoT) -> báo lên CoreIoT
def make_power_rule(ch)
    return def (value, trigger) publish_relay(ch) end
end
for ch: 1 .. RELAY_COUNT
    tasmota.add_rule(string.format("Power%d#State", ch), make_power_rule(ch))
end

# Gửi trạng thái toàn bộ relay mỗi khi MQTT kết nối lại và định kỳ 5 phút
tasmota.add_rule("Mqtt#Connected", def (value, trigger) tasmota.set_timer(2000, publish_all_relays) end)
tasmota.add_cron("0 */5 * * * *", publish_all_relays, "relay_sync")

# Khởi tạo đèn trạng thái ban đầu: Xanh lá (Sẵn sàng) & kêu 1 bíp ngắn khởi động
try
    tasmota.cmd("Color 00FF00")
    tasmota.cmd("Buzzer 1")
except .. as e
end

print("=== HỆ THỐNG GIÁM SÁT AO TÔM ĐÃ SẴN SÀNG (pH ID 2 | DO ID 16 | EC ID 4 + COREIOT) ===")
