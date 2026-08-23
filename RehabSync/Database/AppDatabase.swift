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
    //   knee_flexion = 小腿分項（只有動作 2 是真的膝屈曲角，見 database-schema.md）
    // angle 維持不變，三者一起存才能事後回頭診斷「角度不對是大腿側還是小腿側的問題」。
    //
    // 🔴 三欄之間**沒有恆等式**：四個動作的 calfReportSign 都是 −1，小腿那一項已經翻過號，
    // 兩欄又各自帶自己的 report 基準，所以 angle ≠ hip_flexion − knee_flexion。
    //
    // NOT NULL 必須帶 DEFAULT，否則既有列無法通過約束。既有列補 0 代表「當時沒有記錄分項」，
    // 不是真的量到 0；分析時要用 v11 之後的資料才有意義。
    migrator.registerMigration("v11") { db in
        try db.alter(table: "advanced_statistics") { t in
            t.add(column: "knee_flexion", .double).notNull().defaults(to: 0)
            t.add(column: "hip_flexion",  .double).notNull().defaults(to: 0)
        }
    }

    // exercise 加 target_angle：每個動作的目標角度（度），遊戲判定用的門檻。
    //
    // 目前值：exercise_id 1–21 = 45、exercise_id 22 = 50。
    // 22（前跨步弓步蹲）對應 `Working22.holdAngleThreshold`，其餘沿用 45。
    //
    // NOT NULL 必須帶 DEFAULT，否則既有列無法通過約束 —— 這裡的 45 同時扮演兩個角色：
    // 既有列的補值，以及 1–21 的正式值，所以只需要再把 22 改成 50。
    //
    // ⚠️ 這一欄目前**沒有任何程式在讀** —— 遊戲判定仍然讀寫死在畫面檔裡的常數
    //（`Working2/9.holdThreshold`、`Working22.holdAngleThreshold`），
    // 結果頁的「目標角度」卡片也是讀那些常數。**同一個數字現在有兩份**，
    // 這正是這個專案反覆踩到的「有兩份、改了一份」。要改門檻時兩邊都要動，
    // 或者把判定與顯示都改成讀這一欄（未做）。
    //
    // ⚠️ 1–21 的 45 是一次性的統一填值，不是每個動作各自量出來的：
    // 動作 12（登階）根本不看角度（用狀態機判定），它的 45 是惰性資料；
    // 其餘 18 個動作尚未實作，45 只是佔位。
    migrator.registerMigration("v12") { db in
        try db.alter(table: "exercise") { t in
            t.add(column: "target_angle", .integer).notNull().defaults(to: 45)
        }
        try db.execute(sql: "UPDATE exercise SET target_angle = 50 WHERE id = 22")
    }

    // treatment_result 加兩欄（working2-database-port-plan.md §22.5）：
    //   exercise_id  —— 這一場是哪個動作。**本來就能從 treatment_content_id
    //                    → treatment_content.exercise_id 還原**，加它只是為了查詢／匯出方便
    //                    （直接 WHERE exercise_id = 9、匯出檔案自帶動作身分）。
    //                    兩者理論上必須永遠相等，但沒有任何機制保證。
    //   target_angle —— 這一場**當時**的目標角度。無法從別處還原，是真正的新資料：
    //                    exercise.target_angle 可編輯，一次 UPDATE 就會讓所有歷史場次
    //                    的結果頁跟著變；存了快照，結果頁才能顯示那一場當時的值。
    //
    // 🔴 exercise_id **可為 NULL，是刻意的**（§22.5.3）：既有列靠下面的 UPDATE 從
    // treatment_content 回填，若存在孤兒列（查不到對應 treatment_content），NOT NULL 會讓
    // 整個 migration 失敗 —— 那代表使用者更新後 app 直接開不起來。可為 NULL 則只是
    // 那幾列留 NULL。理論上不該有孤兒（treatment_content_id 是 ON DELETE CASCADE，
    // 從 v1 就啟用），但不值得拿全體使用者去賭。
    // 附帶好處：REFERENCES ＋ NULL 預設值在任何情況下都合法，不必依賴
    // 「GRDB 在 migration 期間有沒有關掉 PRAGMA foreign_keys」這個沒寫在合約裡的細節。
    //
    // 🔴 target_angle 的 DEFAULT 用 0 而不是 45：0 代表「這一場沒有記錄目標角度」，
    // 是 v13 之前既有列的狀態。用 45 當預設會讓所有舊場次都宣稱目標是 45，
    // 而動作 22 的舊場次實際上是 50 —— 那是憑空捏造的資料。
    // 顯示時 0 要畫成「－」，不是「0 度」。比照 v11 既有列補 0 的處理方式。
    //
    // ⚠️ onDelete: .restrict 與 treatment_content.exercise_id 一致 —— 不用 .cascade，
    // 否則刪掉一個 exercise 會連帶刪掉病人的訓練紀錄。
    migrator.registerMigration("v13") { db in
        try db.alter(table: "treatment_result") { t in
            t.add(column: "exercise_id", .integer)
                .references("exercise", onDelete: .restrict)
            t.add(column: "target_angle", .integer).notNull().defaults(to: 0)
        }
        // exercise_id 從 treatment_content 回填 —— 同一個事實的另一條路徑，
        // 回填出來的值與新寫入的值同源，不會有語意落差。
        // 查不到對應 treatment_content 的孤兒列會留 NULL，不會讓 migration 失敗。
        //
        // ⚠️ target_angle **不回填**：舊場次當時用的門檻是寫死在當時那一版程式裡的
        // 常數，已經無從得知，留 0 表示「沒有記錄」才誠實。
        try db.execute(sql: """
            UPDATE treatment_result
               SET exercise_id = (
                   SELECT exercise_id FROM treatment_content
                    WHERE treatment_content.id = treatment_result.treatment_content_id
               )
        """)
    }

    try migrator.migrate(dbQueue)
    return dbQueue
}
