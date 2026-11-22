# CoreIoT (app.coreiot.io)

CoreIoT là nền tảng IoT nền ThingsBoard (ứng dụng di động của họ dựng từ ThingsBoard Flutter app). Thiết bị trong dự án: **THUNGQUANTRAC** (profile `default`).

## Kết nối MQTT
| Mục | Giá trị |
|---|---|
| Host | `app.coreiot.io` |
| Cổng | `1883` (không mã hóa) |
| Username | access token của thiết bị (lấy ở **Manage credentials**) |
| Mật khẩu | để trống |

| Việc | Topic |
|---|---|
| Gửi telemetry | `v1/devices/me/telemetry` |
| Nhận lệnh RPC | `v1/devices/me/rpc/request/+` |
| Trả lời RPC | `v1/devices/me/rpc/response/<id>` |

Đã kiểm chứng bằng MQTTX: gửi `{"test":1}` lên topic telemetry thì thiết bị chuyển **Active** và key `test` hiện trong **Latest telemetry**. Gửi một bản tin tới topic lạ (`tele/test/LWT`) không làm MQTTX bị ngắt kết nối.

Gửi bằng HTTP (đã thử, trả về 200): `POST https://app.coreiot.io/api/v1/<ACCESS_TOKEN>/telemetry` với body JSON.

## Key telemetry (từ `berry/autoexec.be`)
Gửi mỗi 10 giây một gói JSON. Cảm biến nào không phản hồi quá 60 giây thì không có key của nó trong gói.

| Key | Ý nghĩa |
|---|---|
| `ph` | pH (ID 2) |
| `temp_ph` | nhiệt độ từ cảm biến pH, °C |
| `do` | oxy hòa tan, mg/L (ID 16) |
| `temp_do` | nhiệt độ từ cảm biến DO, °C |
| `ec` | độ dẫn điện (ID 4); đơn vị chưa xác nhận, script coi là µS/cm |
| `temp_ec` | nhiệt độ từ cảm biến EC, °C |
| `temp` | nhiệt độ nước, trung bình các cảm biến đang online |
| `status` | `An toàn (Bình thường)`, `CẢNH BÁO: pH THẤP (x)`, `CẢNH BÁO: pH CAO (x)` hoặc `Chưa có dữ liệu cảm biến pH` |
| `relay1`…`relay6` | trạng thái relay (true/false), gửi khi relay đổi, khi MQTT nối lại và mỗi 5 phút |

Ngưỡng pH: thấp dưới 7.00, cao trên 8.50 (biến `PH_LOW`, `PH_HIGH` trong script).

## Điều khiển relay (RPC)
CoreIoT gửi `v1/devices/me/rpc/request/<id>`, mạch trả lời ở `v1/devices/me/rpc/response/<id>` bằng `true` hoặc `false`. Các method script hỗ trợ:

| Method | Tác dụng |
|---|---|
| `setRelayN` / `getRelayN` (N = 1…6) | bật/tắt hoặc đọc relay N (widget Switch Control) |
| `setValue` / `getValue` | tương đương Relay 1 |
| `setRelay` với params `{"relay":N,"state":true}` | bật/tắt relay N |
| `setGpioStatus` / `getGpioStatus` | widget **Basic GPIO Control**, ánh xạ GPIO sang relay: 1→Relay 1, 2→Relay 2, 41→Relay 3, 42→Relay 4, 45→Relay 5, 46→Relay 6 |

Params của widget có thể là `true/false`, `1/0`, `"on"/"off"` hoặc `{"state":…}`. Widget Switch Control: Set value method `setRelayN`, Get value method `getRelayN`, timeout 5000 ms.

## Dashboard "Thung Quan Trac"
Đã tạo trên tài khoản CoreIoT gồm 6 công tắc relay, 8 ô giá trị (Value card) và 4 biểu đồ (Time series chart). Dashboard này dựng theo bộ key cũ (`tds`, `turbidity/chlorine`, `temp_x16`, `rssi`) nên cần đổi sang bộ key hiện tại:

| Key cũ trong dashboard | Thay bằng |
|---|---|
| `turbidity/chlorine` | `do` (mg/L) |
| `temp_x16` | `temp_do` |
| `tds`, `rssi` | bỏ (script hiện tại không gửi) |
| (chưa có) | thêm `temp` và `status` |

Sao lưu: Export dashboard (biểu tượng tải xuống ở thanh trên). Khôi phục: Dashboards → + → Import dashboard.

## Bảo mật
Access token từng lộ trong khung chat. Đổi token ở **Manage credentials** rồi cập nhật `MqttUser` trên mạch. Không commit token vào repo.
