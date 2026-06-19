import GRDB
import Observation

@Observable
class DeviceViewModel {
    private let db = DatabaseManager.shared.dbQueue

    func fetch(limb: Int) -> Device? {
        try? db.read { db in
            try Device.filter(Column("limb") == limb).fetchOne(db)
        }
    }

    func insert(uuid: String, name: String, limb: Int) {
        guard let bluetoothId = defaultBluetoothId() else { return }
        var device = Device(
            device_uuid:  uuid,
            device_name:  name,
            limb:         limb,
            bluetooth_id: bluetoothId
        )
        device.id = Int64(limb)
        try? db.write { db in
            try device.insert(db, onConflict: .replace)
        }
    }

    func delete(uuid: String) {
        try? db.write { db in
            try Device.filter(Column("device_uuid") == uuid).deleteAll(db)
        }
    }

    func insertACC(deviceId: Int64, timestamp: Int64, samples: [(x: Double, y: Double, z: Double)]) {
        db.asyncWrite { db in
            for s in samples {
                var row = Acc(device_id: deviceId, timestamp: timestamp, x: s.x, y: s.y, z: s.z)
                try row.insert(db)
            }
        } completion: { _, _ in }
    }

    func insertGYRO(deviceId: Int64, timestamp: Int64, samples: [(pitch: Double, roll: Double, yaw: Double)]) {
        db.asyncWrite { db in
            for s in samples {
                var row = Gyro(device_id: deviceId, timestamp: timestamp, pitch: s.pitch, roll: s.roll, yaw: s.yaw)
                try row.insert(db)
            }
        } completion: { _, _ in }
    }

    func insertEXGBatch(deviceId: Int64, timestamp: Int64, channel: Int, values: [Int]) {
        db.asyncWrite { db in
            for value in values {
                var row = Exg(device_id: deviceId, timestamp: timestamp, channel: channel, value: value)
                try row.insert(db)
            }
        } completion: { _, _ in }
    }

    private func defaultBluetoothId() -> Int64? {
        try? db.read { db in
            try Bluetooth.filter(Column("is_default") == 1).fetchOne(db)?.id
        }
    }
}
