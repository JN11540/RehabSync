import Foundation
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

    func cleanupIfNeeded(onStart: (() -> Void)? = nil, onFinish: (() -> Void)? = nil) {
        let db = DatabaseManager.shared.dbQueue

        guard let counts = try? db.read({ db in (
            acc:  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM acc")  ?? 0,
            gyro: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gyro") ?? 0,
            exg:  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exg")  ?? 0
        )}) else { return }

        let shouldCleanAcc  = counts.acc  >= 17_280_000
        let shouldCleanGyro = counts.gyro >= 17_280_000
        let shouldCleanExg  = counts.exg  >= 17_280_000

        guard shouldCleanAcc || shouldCleanGyro || shouldCleanExg else { return }

        DispatchQueue.main.async { onStart?() }

        let deviceIds = (try? db.read { db in
            try Int64.fetchAll(db, sql: "SELECT id FROM device")
        }) ?? []

        db.asyncWrite { db in
            for id in deviceIds {
                if shouldCleanAcc {
                    try db.execute(sql: """
                        DELETE FROM acc WHERE id IN (
                            SELECT id FROM acc WHERE device_id = ? ORDER BY id ASC LIMIT 720000
                        )
                    """, arguments: [id])
                }
                if shouldCleanGyro {
                    try db.execute(sql: """
                        DELETE FROM gyro WHERE id IN (
                            SELECT id FROM gyro WHERE device_id = ? ORDER BY id ASC LIMIT 720000
                        )
                    """, arguments: [id])
                }
                if shouldCleanExg {
                    try db.execute(sql: """
                        DELETE FROM exg WHERE id IN (
                            SELECT id FROM exg WHERE device_id = ? ORDER BY id ASC LIMIT 720000
                        )
                    """, arguments: [id])
                }
            }
        } completion: { _, _ in
            DispatchQueue.main.async { onFinish?() }
        }
    }

    private func defaultBluetoothId() -> Int64? {
        try? db.read { db in
            try Bluetooth.filter(Column("is_default") == 1).fetchOne(db)?.id
        }
    }
}
