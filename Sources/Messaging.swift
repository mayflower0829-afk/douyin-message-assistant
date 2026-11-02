import Foundation

enum MessageRules {
    static func clean(_ value:String)->String {value.replacingOccurrences(of:"\u{200B}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)}
    static func emptyEditor(_ value:String)->Bool {clean(value).isEmpty || value == "发送消息\n\u{200B}"}
    static func valid(_ value:String)->Bool {
        !clean(value).isEmpty && value.utf16.count <= 1000 && !value.unicodeScalars.contains{CharacterSet.newlines.contains($0) || $0.value < 32 || $0.value == 127}
    }
    static func contactName(_ fragments:[String])->String {clean(fragments.joined())}
    static func failureIndicator(role:String,label:String)->Bool {
        ["AXImage","AXButton","AXAlert","AXDialog"].contains(role) && ["发送失败","发送频繁","操作频繁","已被限制","发送过于频繁"].contains{label.contains($0)}
    }
    static func chunks(_ text:String)->[[UInt16]] {
        let units = Array(text.utf16);var result = [[UInt16]]();var offset = 0
        while offset < units.count {
            var end = min(offset+20,units.count)
            if end < units.count && (0xD800...0xDBFF).contains(units[end-1]) {end -= 1}
            result.append(Array(units[offset..<end]));offset = end
        }
        return result
    }
}

struct SendFlow {
    enum Action:Equatable {case type, enter, confirmed, complete, wait, failed(String)}
    private enum Phase {case ready, typing, clearing}
    let message:String, interval:TimeInterval, total:Int
    private var phase = Phase.ready
    private var since:TimeInterval = 0, nextDue:TimeInterval = 0
    private(set) var sent = 0
    mutating func step(now:TimeInterval,editor:String)->Action {
        switch phase {
        case .ready:
            if sent >= total {return .complete}
            guard now >= nextDue else {return .wait}
            guard MessageRules.emptyEditor(editor) else {return .failed("输入框已有文字，已停止。")}
            since = now;nextDue = now + interval;phase = .typing;return .type
        case .typing:
            if !MessageRules.emptyEditor(editor) && MessageRules.clean(editor) == MessageRules.clean(message) {
                phase = .clearing;since = now;return .enter
            }
            if now-since >= 5 {return .failed("消息未完整写入输入框，未按回车。")}
            if !MessageRules.emptyEditor(editor), !MessageRules.clean(message).hasPrefix(MessageRules.clean(editor)) {return .failed("输入框内容与计划消息不一致，未按回车。")}
            return .wait
        case .clearing:
            if MessageRules.emptyEditor(editor) {
                sent += 1;phase = .ready
                return sent >= total ? .complete : .confirmed
            }
            if now-since >= 5 {return .failed("发送后输入框未清空，已停止。")}
            return .wait
        }
    }
}
