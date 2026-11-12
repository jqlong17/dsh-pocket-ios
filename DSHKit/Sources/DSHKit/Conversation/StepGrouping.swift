import Foundation

/// 把扁平的步骤序列切成「过程行」分组。
///
/// 规则（原先内联在模型的 stepGroups 里，无测试）：
/// - 按 sequence 升序；
/// - **轮次变化**处断开；
/// - **助手文字消息**是分隔点：桌面端会把工具活动拆成多段，手机端要跟着断，
///   否则「说话—干活—再说话」会被挤成一条超长过程行。
public enum StepGrouping {
    public struct Step: Equatable, Sendable {
        public let turn: Int
        public let sequence: Int
        public init(turn: Int, sequence: Int) {
            self.turn = turn
            self.sequence = sequence
        }
    }

    /// - Parameters:
    ///   - steps: 未排序的步骤（只用到 turn 与 sequence）。
    ///   - textBoundaries: 助手文字消息的 sequence（作为分隔点）。
    /// - Returns: 每个分组内步骤的原始下标（指向传入的 steps 数组）。
    public static func groups(steps: [Step], textBoundaries: [Int]) -> [[Int]] {
        let sorted = steps.enumerated().sorted { lhs, rhs in
            lhs.element.sequence < rhs.element.sequence
        }
        let boundaries = textBoundaries.sorted()
        var result: [[Int]] = []
        var current: [Int] = []
        var lastSequence = Int.min
        var lastTurn: Int?

        func flush() {
            guard !current.isEmpty else { return }
            result.append(current)
            current = []
        }

        for (index, step) in sorted {
            let turnChanged = lastTurn != nil && step.turn != lastTurn
            let crossedText = boundaries.contains { $0 > lastSequence && $0 < step.sequence }
            if turnChanged || crossedText { flush() }
            current.append(index)
            lastSequence = step.sequence
            lastTurn = step.turn
        }
        flush()
        return result
    }
}
