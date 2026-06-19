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
        try? db.write { db in
            try device.insert(db, onConflict: .replace)
        }
    }

    func delete(uuid: String) {
        try? db.write { db in
            try Device.filter(Column("device_uuid") == uuid).deleteAll(db)
        }
    }

    private func defaultBluetoothId() -> Int64? {
        try? db.read { db in
            try Bluetooth.filter(Column("is_default") == 1).fetchOne(db)?.id
        }
    }
}
