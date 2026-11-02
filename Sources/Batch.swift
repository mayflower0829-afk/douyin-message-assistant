import Foundation

enum BatchOutcome:Equatable {
    case sent, verified, skipped, cancelled, failed(String)
    var text:String {
        switch self {
        case .sent:return "完成界面发送操作"
        case .verified:return "预检通过（未发送）"
        case .skipped:return "今日已尝试，跳过"
        case .cancelled:return "已取消，未继续执行"
        case .failed(let reason):return "失败："+reason
        }
    }
}
struct BatchResult:Equatable {let name:String;let outcome:BatchOutcome}
struct BatchRun {
    let people:[String]
    let dryRun:Bool
    private(set) var current:String?
    private(set) var results = [BatchResult]()
    private var index = 0
    static func roster(_ names:[String])->[String] {
        var seen = Set<String>()
        return names.map{MessageRules.clean($0)}.filter{!$0.isEmpty && MessageRules.valid($0) && $0 != "请选择会话" && seen.insert($0).inserted}
    }
    init(people:[String],dryRun:Bool) {self.people = Self.roster(people);self.dryRun = dryRun}
    var finished:Bool {index >= people.count && current == nil}
    mutating func next(day:String,attempts:[String:String])->String? {
        guard current == nil else {return nil}
        while index < people.count {
            let name = people[index];index += 1
            if !dryRun && attempts[name] == day {results.append(BatchResult(name:name,outcome:.skipped));continue}
            current = name;return name
        }
        return nil
    }
    mutating func complete(_ outcome:BatchOutcome) {
        guard let name = current else {return}
        results.append(BatchResult(name:name,outcome:outcome));current = nil
    }
    mutating func cancel() {
        complete(.cancelled)
        while index < people.count {results.append(BatchResult(name:people[index],outcome:.cancelled));index += 1}
    }
}
