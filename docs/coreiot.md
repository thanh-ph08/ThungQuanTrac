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
File xuất: [`coreiot/dashboard-thung-quan-trac.json`](../coreiot/dashboard-thung-quan-trac.json). Giao diện nền tối, bố cục 24 cột:

| Khu vực | Widget | Key |
|---|---|---|
| Banner trên cùng | thẻ giá trị, chữ đỏ khi có "CẢNH BÁO" | `status` |
| 3 đồng hồ neon | pH (thang 4–10), DO (0–12 mg/L), nhiệt độ nước (15–40 °C) | `ph`, `do`, `temp` |
| 4 thẻ nhỏ | EC, nhiệt độ cảm biến pH / EC / DO | `ec`, `temp_ph`, `temp_ec`, `temp_do` |
| 6 công tắc | Relay 1–6 (Switch Control, `setRelayN`/`getRelayN`) | RPC |
| 4 biểu đồ | pH, DO, EC, nhiệt độ (4 đường) | |

Nhập lại dashboard: Dashboards → + → **Import dashboard** → chọn file JSON. Sau khi nhập, vào **Entity aliases** và trỏ alias `THUNGQUANTRAC` tới thiết bị của bạn (file đang trỏ tới ID thiết bị của hệ thống gốc, không dùng được trên tài khoản khác).

Lưu ý hiển thị:
- Đơn vị của đồng hồ DO và nhiệt độ nằm trong tiêu đề, vì phông 7 đoạn của đồng hồ neon vẽ chữ "mg/L" bị méo.
- Dải màu theo ngưỡng đã khai báo trong cấu hình đồng hồ, nhưng chưa thấy hiện trên cung đồng hồ; chỉ màu chữ banner trạng thái đổi được.

Cập nhật file: sửa dashboard trên CoreIoT, bấm biểu tượng tải xuống ở thanh trên để Export, rồi chép đè file JSON.

## Bảo mật
Access token từng lộ trong khung chat. Đổi token ở **Manage credentials** rồi cập nhật `MqttUser` trên mạch. Không commit token vào repo.
