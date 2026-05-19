import GRDB
import Observation

@Observable
class HomeViewModel {
    private let db = DatabaseManager.shared.dbQueue

    var plans: [TreatmentPlan] = []

    func fetchPlans() {
        plans = (try? db.read { db in
            try TreatmentPlan.fetchAll(db)
        }) ?? []
    }

    func insertPlan(_ plan: inout TreatmentPlan) {
        try? db.write { db in
            try plan.insert(db)
        }
    }
}
