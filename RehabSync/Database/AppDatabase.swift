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
            t.column("rep_training_time", .integer).notNull()
            t.column("rep_rest_time", .integer).notNull()
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

    try migrator.migrate(dbQueue)
    return dbQueue
}
