import Foundation

/// 部位的三態顯示狀態：`unbound`（`device` 表沒有紀錄）／`reconnecting`（有紀錄但目前
/// 沒有實際 BLE 連線，背景重連中）／`connected`（有紀錄且目前有實際 BLE 連線）。
enum DeviceConnectionStatus {
    case unbound
    case reconnecting
    case connected

    /// 資料庫是否有這個部位的綁定紀錄（`reconnecting`／`connected` 都算，只有 `unbound` 不算）——
    /// 「最多同時綁 2 顆、同一側優先湊滿」規則要用這個判斷，不是看目前是否有實際連線。
    var isBound: Bool { self != .unbound }
}

/// 「最多同時綁 2 顆裝置、同一側優先湊滿」規則，供人形圖（`DeviceIllustration`）／設定頁
/// 藍芽裝置綁定視窗（`DashboardBluetoothBindingModal`）共用，避免兩處各自維護一份一樣的業務規則。
enum DeviceBindingRules {
    struct SlotState {
        let status: DeviceConnectionStatus
        let isDisabled: Bool
    }

    struct Snapshot {
        let leftThigh: SlotState
        let leftCalf: SlotState
        let rightThigh: SlotState
        let rightCalf: SlotState

        /// 4 個部位裡目前有幾個已經綁定（`reconnecting`／`connected` 都算，不論是否有實際連線）。
        var boundCount: Int {
            [leftThigh, leftCalf, rightThigh, rightCalf].filter { $0.status.isBound }.count
        }

        /// 是否已經湊滿「最多同時綁 2 顆裝置」的上限——給「藍芽裝置綁定」按鈕決定要不要整顆 disabled 用，
        /// 不是只鎖單一部位（那是 `SlotState.isDisabled` 的職責）。
        var isMaxDevicesReached: Bool { boundCount >= 2 }
    }

    /// 依 `deviceVM` 目前的綁定狀態＋`btVM` 目前的實際 BLE 連線狀態，算出 4 個部位
    /// （左大腿/左小腿/右大腿/右小腿）各自的三態顯示狀態、「是否不可再點擊」。
    /// 鎖定規則：同一側湊滿 2 顆（`isBound`，不論是否已實際連線）前鎖住另一側；全部湊滿 2 顆後，
    /// 未綁定的部位一律鎖住。
    static func snapshot(deviceVM: DeviceViewModel, btVM: BluetoothViewModel) -> Snapshot {
        func status(side: Int, limb: Int) -> DeviceConnectionStatus {
            guard let device = deviceVM.fetch(side: side, limb: limb),
                  let uuid = UUID(uuidString: device.device_uuid)
            else { return .unbound }
            return btVM.connectedPeripherals[uuid] != nil ? .connected : .reconnecting
        }

        let leftThighStatus = status(side: 0, limb: 0)
        let leftCalfStatus = status(side: 0, limb: 1)
        let rightThighStatus = status(side: 1, limb: 0)
        let rightCalfStatus = status(side: 1, limb: 1)

        let leftConnectedCount = (leftThighStatus.isBound ? 1 : 0) + (leftCalfStatus.isBound ? 1 : 0)
        let rightConnectedCount = (rightThighStatus.isBound ? 1 : 0) + (rightCalfStatus.isBound ? 1 : 0)

        let isLeftDisabled = rightConnectedCount == 1 && leftConnectedCount == 0
        let isRightDisabled = leftConnectedCount == 1 && rightConnectedCount == 0
        let isMaxDevicesReached = leftConnectedCount + rightConnectedCount >= 2

        return Snapshot(
            leftThigh: SlotState(
                status: leftThighStatus,
                isDisabled: isLeftDisabled || (isMaxDevicesReached && !leftThighStatus.isBound)
            ),
            leftCalf: SlotState(
                status: leftCalfStatus,
                isDisabled: isLeftDisabled || (isMaxDevicesReached && !leftCalfStatus.isBound)
            ),
            rightThigh: SlotState(
                status: rightThighStatus,
                isDisabled: isRightDisabled || (isMaxDevicesReached && !rightThighStatus.isBound)
            ),
            rightCalf: SlotState(
                status: rightCalfStatus,
                isDisabled: isRightDisabled || (isMaxDevicesReached && !rightCalfStatus.isBound)
            )
        )
    }
}
