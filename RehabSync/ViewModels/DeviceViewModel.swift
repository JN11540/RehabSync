import Foundation
import GRDB
import Observation

@Observable
class DeviceViewModel {
    private let db = DatabaseManager.shared.dbQueue

    /// `side`：0 = 左，1 = 右。舊呼叫端（單一大腿/小腿裝置的畫面）不傳就固定用 0，行為與過去完全一致。
    func fetch(side: Int = 0, limb: Int) -> Device? {
        try? db.read { db in
            try Device.filter(Column("side") == side && Column("limb") == limb).fetchOne(db)
        }
    }

    /// 不指定 side，直接取任一筆已配對裝置的 side 值（用來判斷使用者裝的是左腳還是右腳）。
    /// 資料表沒有任何裝置時回傳 nil，呼叫端應視為預設左腳。
    func fetchAnySide() -> Int? {
        try? db.read { db in
            try Device.fetchOne(db)?.side
        }
    }

    func insert(uuid: String, name: String, side: Int = 0, limb: Int) {
        guard let bluetoothId = defaultBluetoothId() else { return }
        var device = Device(
            device_uuid:  uuid,
            device_name:  name,
            limb:         limb,
            side:         side,
            bluetooth_id: bluetoothId
        )
        // side/limb 各只有 0、1 兩種值，id = side*2 + limb 讓四種組合各自對應唯一的一列，
        // 不會像過去只用 limb 當 id 時，左右腿共用同一列而互相覆蓋。
        device.id = Int64(side * 2 + limb)
        try? db.write { db in
            try device.insert(db, onConflict: .replace)
        }
    }

    func delete(uuid: String) {
        try? db.write { db in
            try Device.filter(Column("device_uuid") == uuid).deleteAll(db)
        }
    }

    func insertACC(deviceId: Int64, timestamp: Int64, treatmentResultId: Int64? = nil, samples: [(x: Double, y: Double, z: Double)]) {
        db.asyncWrite { db in
            for s in samples {
                var row = Acc(treatment_result_id: treatmentResultId, device_id: deviceId, timestamp: timestamp, x: s.x, y: s.y, z: s.z)
                try row.insert(db)
            }
        } completion: { _, _ in }
    }

    func insertGYRO(deviceId: Int64, timestamp: Int64, treatmentResultId: Int64? = nil, samples: [(pitch: Double, roll: Double, yaw: Double)]) {
        db.asyncWrite { db in
            for s in samples {
                var row = Gyro(treatment_result_id: treatmentResultId, device_id: deviceId, timestamp: timestamp, pitch: s.pitch, roll: s.roll, yaw: s.yaw)
                try row.insert(db)
            }
        } completion: { _, _ in }
    }

    func insertEXGBatch(deviceId: Int64, timestamp: Int64, treatmentResultId: Int64? = nil, channel: Int, values: [Int]) {
        db.asyncWrite { db in
            for value in values {
                var row = Exg(treatment_result_id: treatmentResultId, device_id: deviceId, timestamp: timestamp, channel: channel, value: value)
                try row.insert(db)
            }
        } completion: { _, _ in }
    }

    func insertAdvancedStatistics(timestamp: Int64, angle: Double, treatmentResultId: Int64? = nil) {
        db.asyncWrite { db in
            var row = AdvancedStatistics(treatment_result_id: treatmentResultId, timestamp: timestamp, angle: angle)
            try row.insert(db)
        } completion: { _, _ in }
    }

    func fetchACC(deviceId: Int64, from: Int64, to: Int64) -> [Acc] {
        (try? db.read { db in
            try Acc
                .filter(Column("device_id") == deviceId
                     && Column("timestamp") >= from
                     && Column("timestamp") <= to)
                .order(Column("id").asc)
                .fetchAll(db)
        }) ?? []
    }

    func fetchGYRO(deviceId: Int64, from: Int64, to: Int64) -> [Gyro] {
        (try? db.read { db in
            try Gyro
                .filter(Column("device_id") == deviceId
                     && Column("timestamp") >= from
                     && Column("timestamp") <= to)
                .order(Column("id").asc)
                .fetchAll(db)
        }) ?? []
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

    func fetchTableCounts() -> (acc: Int, gyro: Int, exg: Int, advancedStatistics: Int) {
        (try? db.read { db in (
            acc:  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM acc")  ?? 0,
            gyro: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gyro") ?? 0,
            exg:  try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exg")  ?? 0,
            advancedStatistics: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM advanced_statistics") ?? 0
        )}) ?? (0, 0, 0, 0)
    }

    private func defaultBluetoothId() -> Int64? {
        try? db.read { db in
            try Bluetooth.filter(Column("is_default") == 1).fetchOne(db)?.id
        }
    }
}
