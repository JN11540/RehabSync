import Foundation
import GRDB

func createAppDatabase() throws -> DatabaseQueue {
    let url = try FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("rehabsync.sqlite")

    let dbQueue = try DatabaseQueue(path: url.path)

    var migrator = DatabaseMigrator()

    migrator.registerMigration("v1") { db in
        try db.create(table: "exercise") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
        }

        try db.create(table: "treatment") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull()
            t.column("patient_id", .integer).notNull()
            t.column("start_time", .integer).notNull()
            t.column("end_time", .integer).notNull()
        }

        try db.create(table: "treatment_content") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatment_id", .integer).notNull()
                .references("treatment", onDelete: .cascade)
            t.column("exercise_id", .integer).notNull()
                .references("exercise", onDelete: .restrict)
            t.column("sets", .integer).notNull()
            t.column("set_rest_time", .integer).notNull()
            t.column("reps", .integer).notNull()
            t.column("date", .integer).notNull()
        }

        try db.create(table: "treatment_result") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatment_id", .integer).notNull()
                .references("treatment", onDelete: .cascade)
            t.column("treatment_content_id", .integer).notNull()
                .references("treatment_content", onDelete: .cascade)
            t.column("reps", .text).notNull()
            t.column("extension_length", .text).notNull()
            t.column("set_start_time", .text).notNull()
            t.column("set_end_time", .text).notNull()
            t.column("date", .integer).notNull()
        }
    }

    migrator.registerMigration("v2") { db in
        try db.alter(table: "exercise") { t in
            t.add(column: "info",       .text).notNull().defaults(to: "")
            t.add(column: "device",     .text)
            t.add(column: "target",     .text).notNull().defaults(to: "")
            t.add(column: "joint",      .text).notNull().defaults(to: "")
            t.add(column: "rep_stage1", .integer)
            t.add(column: "act_stage1", .text)
            t.add(column: "rep_stage2", .integer)
            t.add(column: "act_stage2", .text)
            t.add(column: "rep_stage3", .integer)
            t.add(column: "act_stage3", .text)
            t.add(column: "rep_stage4", .integer)
            t.add(column: "act_stage4", .text)
        }
    }

    // Drop legacy columns that are no longer in the model (safe-check for fresh installs)
    migrator.registerMigration("v3") { db in
        let cols = try db.columns(in: "treatment_content").map { $0.name }
        if cols.contains("rep_training_time") {
            try db.execute(sql: "ALTER TABLE treatment_content DROP COLUMN rep_training_time")
        }
        if cols.contains("rep_rest_time") {
            try db.execute(sql: "ALTER TABLE treatment_content DROP COLUMN rep_rest_time")
        }
    }

    migrator.registerMigration("v4") { db in
        try db.create(table: "bluetooth") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("write_uuid",       .text).notNull()
            t.column("sub_acc_uuid",     .text).notNull()
            t.column("sub_gyro_uuid",    .text).notNull()
            t.column("sub_exg_uuid",     .text).notNull()
            t.column("acc_sensitivity",  .double).notNull()
            t.column("gyro_sensitivity", .double).notNull()
            t.column("cmd_a0",           .blob).notNull()
            t.column("cmd_a1",           .blob).notNull()
            t.column("is_default",       .integer).notNull().defaults(to: 0)
        }
    }

    migrator.registerMigration("v5") { db in
        try db.create(table: "device") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("device_uuid",  .text).notNull().unique()
            t.column("device_name",  .text).notNull()
            t.column("limb",         .integer).notNull()
            t.column("bluetooth_id", .integer).notNull()
                .references("bluetooth", onDelete: .setNull)
        }
    }

    migrator.registerMigration("v6") { db in
        try db.create(table: "acc") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatment_result_id", .integer)
            t.column("device_id",  .integer).notNull().references("device", onDelete: .cascade)
            t.column("timestamp", .integer).notNull()
            t.column("x",         .double).notNull()
            t.column("y",         .double).notNull()
            t.column("z",         .double).notNull()
        }
        try db.create(table: "gyro") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatment_result_id", .integer)
            t.column("device_id",  .integer).notNull().references("device", onDelete: .cascade)
            t.column("timestamp", .integer).notNull()
            t.column("pitch",     .double).notNull()
            t.column("roll",      .double).notNull()
            t.column("yaw",       .double).notNull()
        }
        try db.create(table: "exg") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatment_result_id", .integer)
            t.column("device_id", .integer).notNull().references("device", onDelete: .cascade)
            t.column("timestamp", .integer).notNull()
            t.column("channel",   .integer).notNull()
            t.column("value",     .integer).notNull()
        }
    }

    migrator.registerMigration("v7") { db in
        try db.alter(table: "device") { t in
            t.add(column: "side", .integer).notNull().defaults(to: 0)
        }
    }

    migrator.registerMigration("v8") { db in
        try db.create(table: "advanced_statistics") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatment_result_id", .integer)
            t.column("timestamp", .integer).notNull()
            t.column("angle",     .double).notNull()
            t.column("emg",       .double)
        }
    }

    // 匯出功能專用查詢（GameDataExporter.export）原本是全表掃描，這幾張表的清理門檻高達
    // 1,728 萬筆（見 DeviceViewModel.swift 的 shouldCleanAcc/Gyro/Exg），全表掃描會很慢。
    migrator.registerMigration("v9") { db in
        try db.create(index: "idx_acc_treatment_result_id", on: "acc", columns: ["treatment_result_id"])
        try db.create(index: "idx_gyro_treatment_result_id", on: "gyro", columns: ["treatment_result_id"])
        try db.create(index: "idx_exg_treatment_result_id_device_id_channel", on: "exg", columns: ["treatment_result_id", "device_id", "channel"])
        try db.create(index: "idx_advanced_statistics_treatment_result_id", on: "advanced_statistics", columns: ["treatment_result_id"])
    }

    // A2（Enable EXG RAW DATA short package）：實測發現裝置必須收到這道指令（就算內容是全 0）
    // 才會真正套用 A0 設定的取樣率，否則會停留在異常的慢速狀態（見 game-data-flow.md 2.1 節）。
    migrator.registerMigration("v10") { db in
        try db.alter(table: "bluetooth") { t in
            t.add(column: "cmd_a2", .blob).notNull().defaults(to: Data([0xA2, 0x00]))
        }
    }

    // advanced_statistics 加記 theta 的兩個分項（tke-sitting-calibration-port-plan.md §10／§11）：
    //   hip_flexion  = 大腿分項（髖屈曲角）
    //   knee_flexion = 小腿分項（膝屈曲角）
    // angle（= hip_flexion − knee_flexion）維持不變，三者一起存才能事後回頭診斷
    // 「角度不對是大腿側還是小腿側的問題」——只存 angle 的話兩者相減後就分不出來了。
    //
    // NOT NULL 必須帶 DEFAULT，否則既有列無法通過約束。既有列補 0 代表「當時沒有記錄分項」，
    // 不是真的量到 0；分析時要用 v11 之後的資料才有意義。
    migrator.registerMigration("v11") { db in
        try db.alter(table: "advanced_statistics") { t in
            t.add(column: "knee_flexion", .double).notNull().defaults(to: 0)
            t.add(column: "hip_flexion",  .double).notNull().defaults(to: 0)
        }
    }

    try migrator.migrate(dbQueue)
    return dbQueue
}
