import SwiftUI
import Foundation
import CoreBluetooth
import UIKit

@main
struct BleNoiseApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var engine = NoiseEngine()

    var body: some View {
        NavigationStack {
            Form {
                Section("Trạng thái") {
                    LabeledContent("Máy phát", value: engine.stateText)
                    LabeledContent("Gói đã phát") {
                        Text("\(engine.packets)").monospacedDigit()
                    }
                    LabeledContent("Tên đang phát") {
                        Text(engine.lastName).monospaced()
                    }
                    HStack {
                        Text("Đổi tên mỗi")
                        Slider(value: $engine.interval, in: 0.3...3.0, step: 0.1)
                        Text(String(format: "%.1fs", engine.interval))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                Section {
                    Button {
                        if engine.isRunning { engine.stop() } else { engine.start() }
                    } label: {
                        Text(engine.isRunning ? "Dừng phát" : "Bắt đầu phát nhiễu")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("Bắt buộc: app phải ở foreground, màn hình sáng, đã cấp quyền Bluetooth. Không thấy được trên chính máy này — phải quét bằng máy thứ hai.")
                }

                Section("Cách kiểm tra") {
                    Text("1. Cài nRF Connect trên một điện thoại/tablet khác (hoặc Bluetooth LE Explorer trên PC).")
                    Text("2. Bấm Bắt đầu ở máy này, rồi quét bằng máy kia.")
                    Text("3. Danh sách sẽ xuất hiện liên tục các tên ngẫu nhiên 6 ký tự, đổi mỗi vài giây.")
                    Text("Lưu ý: đây là nhiễu BLE mức nhẹ. Wi-Fi, 4G, sóng Smart Key xe vẫn bình thường — đừng chờ thấy mạng yếu đi.")
                        .foregroundStyle(.secondary)
                }

                Section("iPhone có radio gì?") {
                    Text("BLE 2.4 GHz — app này phát")
                    Text("Wi-Fi 2.4/5/6 GHz — chỉ tạo tải")
                    Text("NFC 13.56 MHz — vài cm")
                    Text("UWB — không có API phát thô")
                    Text("Không có 433 MHz / 125 kHz")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("BLE Noise")
        }
    }
}

// MARK: - Engine

final class NoiseEngine: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var packets = 0
    @Published private(set) var stateText = "Chưa bật"
    @Published private(set) var lastName = "—"
    @Published var interval: Double = 1.0 {
        didSet { if isRunning { restartTimer() } }
    }

    private var manager: CBPeripheralManager?
    private var timer: Timer?
    private var wantsToRun = false

    func start() {
        wantsToRun = true
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: .main)
        }
        if manager?.state == .poweredOn {
            begin()
        } else {
            stateText = "Đang chờ quyền Bluetooth…"
        }
    }

    func stop() {
        wantsToRun = false
        timer?.invalidate()
        timer = nil
        manager?.stopAdvertising()
        isRunning = false
        stateText = "Đã dừng"
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func begin() {
        guard wantsToRun, let m = manager, m.state == .poweredOn else { return }
        isRunning = true
        stateText = "Đang phát"
        UIApplication.shared.isIdleTimerDisabled = true
        burst(on: m)
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: max(0.3, interval), repeats: true) { [weak self] _ in
            guard let self, let m = self.manager, m.state == .poweredOn else { return }
            self.burst(on: m)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func burst(on m: CBPeripheralManager) {
        if m.isAdvertising { m.stopAdvertising() }

        // Chỉ quảng cáo local name, KHÔNG kèm service UUID.
        // Lý do: iOS giới hạn gói quảng cáo 31 byte; name + UUID 128-bit dễ vượt
        // và iOS sẽ cắt mất tên, khiến máy quét thấy "BLE Device" vô danh.
        let name = Self.randomName()
        lastName = name
        m.startAdvertising([CBAdvertisementDataLocalNameKey: name])
        packets += 1
    }

    private static func randomName() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var s = ""
        for _ in 0..<6 {
            s.append(chars.randomElement()!)
        }
        return s
    }
}

extension NoiseEngine: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if wantsToRun { begin() }
        case .unauthorized:
            stateText = "Chưa cấp quyền Bluetooth"
        case .poweredOff:
            stateText = "Bluetooth đang tắt"
        default:
            stateText = "Bluetooth chưa sẵn sàng"
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            stateText = "Lỗi service: \(error.localizedDescription)"
        }
    }
}
