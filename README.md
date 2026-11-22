# BLE Noise (iPhone)

App SwiftUI nhỏ để iPhone **phát quảng cáo BLE liên tục với tên ngẫu nhiên**, làm rối
không gian BLE quanh đó. Đây là mức "gây nhiễu nhẹ", không phải jammer thật.

## Sự thật trước khi làm

iPhone **không thể phát sóng vô tuyến tùy ý**. Nó chỉ có:

| Radio | Dùng được để làm nhiễu? |
|---|---|
| BLE 2.4 GHz | Có, ở mức nhẹ (app này) |
| Wi-Fi 2.4/5/6 GHz | Chỉ tạo tải/nghẽn, không jam được |
| NFC 13.56 MHz | Chỉ vài cm, vô nghĩa |
| UWB | Không có API phát thô |
| Cellular | Không |
| 433 MHz / 125 kHz | **Không có** → không đụng được Smart Key SH 160i |

Muốn "bất kể sóng gì" phải dùng phần cứng ngoài (ESP32, nRF24L01, SDR, jammer).
Gây nhiễu tần số cũng là chuyện pháp lý ở Việt Nam — dùng công suất lớn có thể ảnh hưởng
Wi-Fi, camera, tai nghe quanh đó.

## Chạy app

Cần **Mac + Xcode** (hoặc nhờ người build .ipa như app SH160Mate).

1. Xcode → **File → New → Project → iOS → App**.
2. Product name: `BleNoise`, Interface: **SwiftUI**, Language: **Swift**.
3. Xoá `ContentView.swift` và `BleNoiseApp.swift` mặc định.
4. Kéo file `BleNoiseApp.swift` trong thư mục này vào project.
5. Vào target → **Info** → thêm key:
   - `Privacy - Bluetooth Always Usage Description`
   - giá trị: `Ứng dụng cần Bluetooth để phát quảng cáo BLE.`
6. Chọn iPhone thật (không dùng Simulator — Simulator không có Bluetooth).
7. Build & Run, cấp quyền Bluetooth, bấm **Bắt đầu phát nhiễu**, giữ app ở foreground.

Nếu muốn sideload nhanh: dùng tài khoản Apple miễn phí (7 ngày) hoặc AltStore/Sideloadly.

## Cách nó hoạt động

- Dùng `CBPeripheralManager` phát `CBAdvertisementDataLocalNameKey` với tên ngẫu nhiên
  mỗi 50–500 ms, kèm một service UUID cố định.
- Mỗi lần phát sẽ `stopAdvertising()` rồi `startAdvertising()` để ép iOS đổi gói.
- iOS tự quyết định khoảng cách phát thật, nên số "gói" trong app chỉ là số lần gọi API.

## Giới hạn

- Chỉ chạy khi app **foreground**; background iOS sẽ bóp nghẹt quảng cáo.
- Không phát được manufacturer data / raw bytes trên iOS.
- Không chặn được Wi-Fi, sóng điện thoại, 433 MHz, 125 kHz.
- Tầm ảnh hưởng thực tế: vài mét đến vài chục mét, tùy môi trường.

## Không muốn code?

Cài **nRF Connect for iOS** → tab **Advertiser** → đặt tên → Start. Cũng phát BLE liên tục,
không cần Xcode, nhưng ít tùy biến hơn app này.

## Cảnh báo

Đừng dùng để phá sóng người khác. Ở Việt Nam, gây nhiễu có hại là hành vi bị quản lý;
thiết bị bay/drone, Wi-Fi quán, camera an ninh có thể bị ảnh hưởng.
