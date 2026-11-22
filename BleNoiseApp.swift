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
                    HStack {
                        Text("Chu kỳ")
                        Slider(value: $engine.interval, in: 0.05...0.5, step: 0.01)
                        Text(String(format: "%.2fs", engine.interval))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
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
                    Text("Giữ app ở foreground và màn hình sáng. iOS tự giới hạn tần suất quảng cáo BLE nên đây là nhiễu mức nhẹ, không phải jammer thật.")
                }

                Section("iPhone phát được sóng gì?") {
                    Text("BLE 2.4 GHz (app này)")
                    Text("Wi-Fi 2.4/5/6 GHz (chỉ tạo tải, không jam)")
                    Text("NFC 13.56 MHz (chỉ vài cm)")
                    Text("UWB (không có API phát thô)")
                    Text("Không có 433 MHz / 125 kHz → không đụng được Smart Key xe")
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
    @Published var interval: Double = 0.12 {
        didSet { if isRunning { restartTimer() } }
    }

    private var manager: CBPeripheralManager?
    private var timer: Timer?
    private var wantsToRun = false
    private var counter = 0

    private let serviceUUID = CBUUID(string: "0000FCCD-0000-1000-8000-00805F9B34FB")

    func start() {
        wantsToRun = true
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: .main)
        }
        if manager?.state == .poweredOn {
            begin()
        } else {
            stateText = "Đang chờ Bluetooth…"
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
        if m.isAdvertising { m.stopAdvertising() }
        publishService(on: m)
        restartTimer()
    }

    private func publishService(on m: CBPeripheralManager) {
        m.removeAllServices()
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = []
        m.add(service)
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: max(0.05, interval), repeats: true) { [weak self] _ in
            self?.burst()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func burst() {
        guard let m = manager, m.state == .poweredOn else { return }
        counter += 1
        if m.isAdvertising { m.stopAdvertising() }
        m.startAdvertising([
            CBAdvertisementDataLocalNameKey: Self.randomName(),
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])
        packets += 1
    }

    private static func randomName() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var s = ""
        for _ in 0..<Int.random(in: 4...8) {
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
}
