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
            t.column("reps", .integer).notNull()
            t.column("total_time", .integer).notNull()
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
            t.column("device_id",  .integer).notNull().references("device", onDelete: .cascade)
            t.column("timestamp", .integer).notNull()
            t.column("x",         .double).notNull()
            t.column("y",         .double).notNull()
            t.column("z",         .double).notNull()
        }
        try db.create(table: "gyro") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("device_id",  .integer).notNull().references("device", onDelete: .cascade)
            t.column("timestamp", .integer).notNull()
            t.column("pitch",     .double).notNull()
            t.column("roll",      .double).notNull()
            t.column("yaw",       .double).notNull()
        }
        try db.create(table: "exg") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("device_id", .integer).notNull().references("device", onDelete: .cascade)
            t.column("timestamp", .integer).notNull()
            t.column("channel",   .integer).notNull()
            t.column("value",     .integer).notNull()
        }
    }

    try migrator.migrate(dbQueue)
    return dbQueue
}
