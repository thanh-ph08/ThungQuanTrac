# Cài lại từ đầu

> Mọi lệnh trong Console của Tasmota nên **gõ tay từng dòng**. Copy-paste dễ kèm ký tự ẩn khiến lệnh báo `Command Unknown`.

## 0. Chuẩn bị
- Mạch Waveshare ESP32-S3-Relay-6CH (6 relay, RS485, nguồn 7–36 V hoặc 5 V qua USB-C), cáp USB-C có truyền dữ liệu.
- Chrome hoặc Edge (web installer cần Web Serial).
- WiFi có Internet, tài khoản CoreIoT (đăng nhập bằng Google được).
- File Berry `berry/autoexec.be` của repo này.

## 1. Nạp Tasmota32 cho ESP32-S3
1. Mở https://tasmota.github.io/install/ và cắm mạch bằng USB-C.
2. Chọn bản **Tasmota32 – ESP32-S3** (bản thường). **Không chọn `qio_opi`**: bản đó dành cho PSRAM octal, mạch này không có PSRAM.
3. Nếu mạch không vào chế độ nạp: giữ nút **BOOT** (GPIO0), bấm **RESET**, rồi thả BOOT. Nếu log kẹt ở `waiting for download`, rút cắm lại USB **không giữ BOOT** rồi thử lại.
4. Chọn **Erase device** khi cài mới hoàn toàn, bấm Install và chờ xong.
5. Nếu web installer báo lỗi 504 khi tải firmware từ GitHub: thử lại sau, hoặc tải `factory.bin` thủ công từ ota.tasmota.com rồi nạp bằng esptool.
6. Kết thúc, web installer cho nhập WiFi. Nếu bỏ qua, mạch phát WiFi `tasmota-xxxxxx`; nối vào đó để chọn WiFi.

## 2. WiFi (hai mạng)
```
SSId1 <tên WiFi>
Password1 <mật khẩu>
SSId2 <tên WiFi khác>
Password2 <mật khẩu>
Restart 1
```
Mạng không mật khẩu: chỉ gõ `SSId2 <tên>`, rồi vào **Configuration → Configure WiFi** để bỏ trống ô mật khẩu. Tùy chọn: `Sleep 0` giúp trang web Tasmota bớt chậm.

Không bắt được WiFi nào thì mạch tự phát `tasmota-xxxxxx` để bạn nhập lại WiFi.

## 3. Template cho mạch 6 relay
**Configuration → Configure Other → Template**, dán nội dung `tasmota/template.json`, tick **Activate**, bấm Save.

Sơ đồ chân: relay 1–6 = GPIO1, 2, 41, 42, 45, 46. RS485 TX = GPIO17, RX = GPIO18. Còi = GPIO21. LED WS2812 = GPIO38 (hiện thành `POWER7`).

Kiểm tra: trang chính phải có 6 nút relay. Thử `Power1 1` rồi `Power1 0`.

> Nếu log báo `Command Unknown` cho `COLOR` hoặc `BUZZER`, template chưa gán còi và WS2812. Dán lại template ở trên.

## 4. Thiết bị trên CoreIoT
1. Đăng nhập https://app.coreiot.io , vào **Entities → Devices → +** và tạo thiết bị `THUNGQUANTRAC` (profile `default`).
2. Mở thiết bị, **Manage credentials** / **Copy access token** để lấy token.
3. MQTT: host `app.coreiot.io`, cổng `1883` (không mã hóa), username = access token, mật khẩu để trống.

## 5. Kết nối Tasmota với CoreIoT
Tasmota chỉ nối **một** broker.
```
SetOption103 0
SetOption132 0
MqttHost app.coreiot.io
MqttPort 1883
MqttUser <ACCESS_TOKEN>
MqttPassword 0
Restart 1
```
Sau khi khởi động lại, Console phải có `MQT: Connected`.

Ghi chú: ở một lần chạy trước mạch từng bị rớt rồi nối lại MQTT liên tục mỗi vài giây với CoreIoT (log `Attempting connection` / `Connected` lặp lại), nguyên nhân chưa xác định. Ở log 22/11/2026 (`docs/boot-log-2026-11-22.txt`) mạch giữ kết nối ít nhất vài chục giây. Nếu rớt lại, phương án dự phòng là gửi telemetry bằng HTTP: `POST https://app.coreiot.io/api/v1/<TOKEN>/telemetry` (đã thử, trả về 200).

## 6. Upload file Berry
**Consoles → Manage File system → Choose file → Start upload** để tải `autoexec.be`. Sau đó `Restart 1`. Dòng `BRY: Successfully loaded 'autoexec.be'` trong log xác nhận file đã nạp.

Script đọc cảm biến bằng lệnh `ModbusSend` của Tasmota nên cần template đã gán GPIO17 và GPIO18 cho Modbus (có trong `tasmota/template.json`). Không chạy cùng lúc một script khác dùng chung cổng RS485.

Kiểm tra: trong Console phải có dòng `=== HỆ THỐNG GIÁM SÁT AO TÔM ĐÃ SẴN SÀNG ... ===`, rồi sau chừng 10 giây có `SENSORS: pH … | DO … | EC …` và `COREIOT SENSOR: {…}`.

## 7. Dashboard
Dashboard **Thung Quan Trac** nằm trên CoreIoT. Sao lưu: mở dashboard, bấm biểu tượng tải xuống (Export dashboard) để lấy file `.json`. Khôi phục: Dashboards → + → Import dashboard. Chi tiết widget xem `docs/coreiot.md`.

## 8. Mang mạch đi nơi khác
CoreIoT chạy trên Internet nên điều khiển được từ web hoặc app **Core IoT** trên điện thoại từ bất kỳ đâu, miễn là mạch có WiFi ra Internet. Trang web Tasmota (IP kiểu `192.168.x.x`) chỉ vào được khi cùng mạng với mạch.
- Nhập sẵn WiFi nơi đặt mạch vào `SSId2` / `Password2`.
- Nơi không có WiFi: dùng router 4G hoặc điện thoại phát WiFi với tên và mật khẩu đã lưu.
- Đặt trạng thái relay khi mất điện, ví dụ `PowerOnState 0` để tất cả tắt.

## 9. Xử lý sự cố
| Hiện tượng | Cách xử lý |
|---|---|
| `Command Unknown` khi gõ lệnh | Gõ tay từng dòng, đừng paste. Kiểm tra đúng tên lệnh. |
| Mất cấu hình sau khi reset | Cấu hình lại WiFi, template (mục 3) và MQTT (mục 5). |
| Web Tasmota rất chậm | `Sleep 0`, thử trình duyệt khác, tránh hotspot Windows. |
| Rớt MQTT liên tục với CoreIoT | Thử tắt các thiết bị dùng chung token. Nếu vẫn rớt: gửi telemetry bằng HTTP như mục 5. |
| Dashboard hiện `N/A` | Chưa upload Berry, hoặc mạch chưa nối MQTT. Kiểm tra Console. |
| Một cảm biến không có dữ liệu | Kiểm tra dây A/B, địa chỉ, baud 9600 và không có script khác đang dùng RS485. |
| `ModbusSend` không trả `ModbusReceived` | Kiểm tra GPIO17/18 trong template, dây RS485 và nguồn cảm biến. |

## 10. Bảo mật
- Đổi access token nếu từng lộ: **Manage credentials** trên CoreIoT, rồi chạy lại `MqttUser <TOKEN_MỚI>` và `Restart 1`.
- Đặt mật khẩu web cho Tasmota: `WebPassword <mật khẩu>`.
- Không commit token, mật khẩu WiFi hay mật khẩu web vào repo.
