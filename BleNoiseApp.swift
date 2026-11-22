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
                    LabeledContent("Lỗi phát") {
                        Text(engine.advError)
                            .font(.caption)
                            .foregroundStyle(engine.advError == "—" ? Color.secondary : Color.red)
                    }
                    HStack {
                        Text("Đổi tên mỗi")
                        Slider(value: $engine.interval, in: 2...15, step: 1)
                        Text("\(Int(engine.interval))s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
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
                    Text("App phải ở foreground, màn hình sáng. Quét bằng PC hoặc máy khác, tìm tên bắt đầu bằng NZ-NOISE-.")
                }

                Section("Nhật ký") {
                    if engine.log.isEmpty {
                        Text("Chưa có gì.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(engine.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption2).monospaced()
                        }
                    }
                    Button("Copy nhật ký") {
                        UIPasteboard.general.string = engine.log.joined(separator: "\n")
                    }
                }

                Section("Máy này nghe được (\(engine.seenCount))") {
                    if engine.seenLines.isEmpty {
                        Text("Chưa có gói nào…").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(engine.seenLines.prefix(20).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption2).monospaced()
                        }
                    }
                }

                Section("Cách kiểm tra") {
                    Text("PC: Bluetooth LE Explorer → Start → tìm NZ-NOISE-…")
                    Text("Android: nRF Connect → Scan.")
                    Text("Nếu PC thấy thiết bị khác mà không thấy NZ-NOISE- thì gửi mình nhật ký.")
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
    @Published private(set) var seenLines: [String] = []
    @Published private(set) var seenCount = 0
    @Published private(set) var advError = "—"
    @Published private(set) var log: [String] = []
    @Published var interval: Double = 5 {
        didSet { if isRunning { restartTimer() } }
    }

    private var manager: CBPeripheralManager?
    private var central: CBCentralManager?
    private var timer: Timer?
    private var wantsToRun = false
    private var serviceAdded = false
    private var advOK = false

    private let serviceUUID = CBUUID(string: "FCCD")
    private let charUUID = CBUUID(string: "FFF1")

    func start() {
        wantsToRun = true
        addLog("Bấm bắt đầu")
        if manager == nil {
            manager = CBPeripheralManager(delegate: self, queue: .main)
        }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        if manager?.state == .poweredOn {
            begin()
        } else {
            stateText = "Đang chờ quyền Bluetooth…"
            addLog("Chờ Bluetooth: \(stateName(manager?.state))")
        }
    }

    func stop() {
        wantsToRun = false
        timer?.invalidate()
        timer = nil
        manager?.stopAdvertising()
        central?.stopScan()
        isRunning = false
        advOK = false
        stateText = "Đã dừng"
        UIApplication.shared.isIdleTimerDisabled = false
        addLog("Dừng")
    }

    private func begin() {
        guard wantsToRun, let m = manager else { return }
        guard m.state == .poweredOn else { return }
        isRunning = true
        stateText = "Đang phát"
        UIApplication.shared.isIdleTimerDisabled = true
        addServiceIfNeeded()
        startAdvertise()
        restartTimer()
        beginScan()
    }

    private func addServiceIfNeeded() {
        guard !serviceAdded, let m = manager, m.state == .poweredOn else { return }
        let service = CBMutableService(type: serviceUUID, primary: true)
        let ch = CBMutableCharacteristic(
            type: charUUID,
            properties: [.read],
            value: Data([0x4E]),
            permissions: [.readable]
        )
        service.characteristics = [ch]
        m.add(service)
        addLog("Đang thêm service")
    }

    private func beginScan() {
        guard let c = central, c.state == .poweredOn else {
            addLog("Không quét được: \(stateName(central?.state))")
            return
        }
        c.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        addLog("Bắt đầu quét")
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: max(2, interval), repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard wantsToRun, isRunning else { return }
        if !advOK {
            addLog("Thử phát lại")
            startAdvertise()
            return
        }
        let name = Self.randomName()
        lastName = name
        manager?.stopAdvertising()
        startAdvertise()
        addLog("Đổi tên → \(name)")
    }

    private func startAdvertise() {
        guard let m = manager, m.state == .poweredOn else { return }
        let name = Self.randomName()
        lastName = name
        var data: [String: Any] = [CBAdvertisementDataLocalNameKey: name]
        if serviceAdded {
            data[CBAdvertisementDataServiceUUIDsKey] = [serviceUUID]
        }
        m.startAdvertising(data)
        packets += 1
        addLog("startAdvertising(\(name)) service=\(serviceAdded)")
    }

    private static func randomName() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var s = "NZ-NOISE-"
        for _ in 0..<4 {
            s.append(chars.randomElement()!)
        }
        return s
    }

    private func addLog(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.insert("\(f.string(from: Date()))  \(text)", at: 0)
        if log.count > 80 { log.removeLast(log.count - 80) }
    }

    private func stateName(_ state: CBManagerState?) -> String {
        guard let state else { return "nil" }
        switch state {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        case .unknown: return "unknown"
        @unknown default: return "khác"
        }
    }
}

extension NoiseEngine: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        addLog("Central state: \(stateName(central.state))")
        if central.state == .poweredOn, isRunning {
            beginScan()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "(không tên)"
        seenCount += 1
        seenLines.insert("\(name)   \(RSSI.intValue) dBm", at: 0)
        if seenLines.count > 40 {
            seenLines.removeLast(seenLines.count - 40)
        }
    }
}

extension NoiseEngine: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        addLog("Peripheral state: \(stateName(peripheral.state))")
        switch peripheral.state {
        case .poweredOn:
            addServiceIfNeeded()
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
            advError = "Lỗi service: \(error.localizedDescription)"
            addLog("didAdd LỖI: \(error.localizedDescription)")
            return
        }
        if service.uuid == serviceUUID {
            serviceAdded = true
            addLog("Service đã thêm")
            if wantsToRun && !isRunning { begin() }
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            advOK = false
            advError = error.localizedDescription
            stateText = "Lỗi phát"
            addLog("didStartAdvertising LỖI: \(error.localizedDescription)")
        } else {
            advOK = true
            advError = "—"
            stateText = "Đang phát"
            addLog("didStartAdvertising OK")
        }
    }
}
