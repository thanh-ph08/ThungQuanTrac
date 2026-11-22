# Cảm biến RS485

Bus RS485: 9600 baud, 8N1, Modbus RTU, function 0x03. Ba cảm biến có địa chỉ **2, 4, 16**. Theo chú thích trong `berry/autoexec.be`, mã model là **ES-PH-WT-01** (ID 2), **ES-DO-WT-01** (ID 16) và **ES-EC-WT-01** (ID 4).

Giá trị là float 32-bit ghép từ 2 thanh ghi 16-bit theo thứ tự **CDAB**: thanh ghi có địa chỉ nhỏ hơn là từ thấp, thanh ghi sau là từ cao. Công thức: `float = bytes(từ cao, từ thấp)` đọc big-endian.

Ví dụ ID 2, `ModbusReceived` trả `Values:[585,16574]` ở `StartAddress 1` ⇒ từ thấp = 585 (0x0249), từ cao = 16574 (0x40BE) ⇒ 0x40BE0249 = **5.94** (pH).

Cú pháp lệnh đọc trong Tasmota (theo tài liệu ModbusBridge):
```
ModbusSend {"deviceaddress":2,"functioncode":3,"startaddress":1,"type":"uint16","count":2}
```
Kết quả đến dạng `tele/<topic>/RESULT = {"ModbusReceived":{"DeviceAddress":2,"FunctionCode":3,"StartAddress":1,"Length":9,"Count":2,"Values":[585,16574]}}`.

## Bản đồ thanh ghi (đối chiếu với log 22/11/2026)

| ID | Cảm biến | Thanh ghi bắt đầu → đại lượng | Giá trị trong log |
|---|---|---|---|
| 2 | **pH** | 1 (2 thanh ghi) → pH; 3 → nhiệt độ °C | pH 5.94; nhiệt độ 27.9 °C |
| 16 | **DO** (oxy hòa tan, mg/L) | 1 → DO; 3 → nhiệt độ °C | DO 0.02 mg/L; nhiệt độ 26.3 °C |
| 4 | **EC / TDS** | 0 → EC; 4 → nhiệt độ °C | EC gần 0 (đầu dò có thể đang khô); nhiệt độ 27.9–28.0 °C |

Ghi chú thêm về ID 16: thang đo 20.0 (thanh ghi 11–12 trong lần quét 14/11). Giá trị 0.02 mg/L khớp một đầu dò DO chưa nhúng nước hoặc chưa hiệu chuẩn. Cần kiểm tra lại khi nhúng nước thật.

## Chi tiết ID 4 (EC) từ lần quét 14/11/2026 (đầu dò trong nước thường)
| Thanh ghi | Giá trị | Nhận xét |
|---|---|---|
| 0–1 | 0.12015 | EC, suy đoán mS/cm (khoảng 120 µS/cm) |
| 4–5 | 29.085 | nhiệt độ °C |
| 6–7 | 60.077 | đúng 500 × thanh ghi 0–1, có vẻ là TDS (ppm) |
| 8–9 | 62.480 | đúng 520 × thanh ghi 0–1 |
| 10–11 | 0.94163 | có thể là hằng số cell K |
| 12–13 | 0.018 | có thể là hệ số bù nhiệt 1.8 %/°C |
| 14–15 | 25.0 | có thể là nhiệt độ chuẩn |
| 18–19 | 9600 | baud rate |

Đơn vị EC chưa xác nhận. Script `berry/autoexec.be` coi thanh ghi 0–1 là µS/cm và in thẳng giá trị (không nhân 1000). Lần quét trong nước thường cho 0.12 ở thanh ghi 0–1, nếu đúng µS/cm thì đó là nước rất tinh khiết, không giống nước máy. Cần thử với dung dịch EC chuẩn hoặc xem tài liệu của hãng.

Lệnh đổi địa chỉ Modbus (script có sẵn lệnh `PhSetId <id_cũ>,<id_mới>`): ghi thanh ghi 25 bằng function 6.

## Chỉnh lại so với ghi chú cũ
Trước đây ghi chú trong repo/chat từng giải mã slave 2 và 16 theo kiểu ABCD ở thanh ghi 2–3 và đoán ID 16 là độ đục hoặc clo dư. Log của hệ thống đang chạy cho thấy cách đọc đúng là CDAB ở thanh ghi 1–2 và 3–4, và ID 16 là **DO**. Các con số chỉ lệch ở chữ số thập phân cuối nên trước đó trông gần đúng.

## Dữ liệu thô lần quét 14/11/2026 (đọc 20 thanh ghi từ địa chỉ 0)
Lần 1 (đầu dò trong dung dịch bảo quản; EC để khô), lần 2 (nước thường).

ID 2, lần 1: `1C20 3C06 40BF 22D5 41E0 46DF 412D 0000 0000 000A 0000 4160 0000 0000 0000 4270 0000 0000 0000 0000`
ID 2, lần 2: `1C20 B74E 40F7 C666 41E0 8D51 414D 0000 0000 000A 0000 4160 0000 0000 0000 4270 0000 0000 0000 0000`

ID 16, lần 1: `1348 0EEA 3C41 498F 41D8 4D39 4080 0000 0001 001E 0000 41A0 0000 0000 0000 4270 0000 0000 0000 0000`
ID 16, lần 2: `1348 702C 3C58 A488 41D9 5693 4080 0000 0001 001E 0000 41A0 0000 0000 0000 4270 0000 0000 0000 0000`

ID 4, lần 1: `0000 0000 0000 0000 E836 41E3 0000 0000 0000 0000 0E5D 3F71 74BC 3C93 0000 41C8 0000 0000 0000 4616`
ID 4, lần 2: `1315 3DF6 0ABA 4602 AECC 41E8 4EA3 4270 EB61 4279 0E5D 3F71 74BC 3C93 0000 41C8 0000 0000 0000 4616`
