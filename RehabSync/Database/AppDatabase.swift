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
            t.column("patientId", .integer).notNull()
            t.column("startTime", .integer).notNull()
            t.column("endTime", .integer).notNull()
        }

        try db.create(table: "treatment_content") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatmentId", .integer).notNull()
                .references("treatment", onDelete: .cascade)
            t.column("exerciseId", .integer).notNull()
                .references("exercise", onDelete: .restrict)
            t.column("sets", .integer).notNull()
            t.column("setRestTime", .integer).notNull()
            t.column("reps", .integer).notNull()
            t.column("repTrainingTime", .integer).notNull()
            t.column("repRestTime", .integer).notNull()
            t.column("date", .integer).notNull()
        }

        try db.create(table: "treatment_result") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("treatmentId", .integer).notNull()
                .references("treatment", onDelete: .cascade)
            t.column("treatmentContentId", .integer).notNull()
                .references("treatment_content", onDelete: .cascade)
            t.column("reps", .integer).notNull()
            t.column("totalTime", .integer).notNull()
            t.column("date", .integer).notNull()
        }
    }

    try migrator.migrate(dbQueue)
    return dbQueue
}
