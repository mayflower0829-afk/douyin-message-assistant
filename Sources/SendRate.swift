import Foundation

struct SendRate {
    static let minimum = 0.1
    static func parse(_ input:String)->Double? {
        guard let seconds = Double(input.trimmingCharacters(in:.whitespacesAndNewlines)), seconds.isFinite, seconds >= minimum else {return nil}
        return seconds
    }
    static func description(_ seconds:Double)->String {
        String(format:"目标约 %.1f 条/秒；实际以抖音处理速度为准",1 / seconds)
    }
}
