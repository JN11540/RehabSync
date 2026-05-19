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

    try migrator.migrate(dbQueue)
    return dbQueue
}
