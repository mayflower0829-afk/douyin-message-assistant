import Foundation

enum ChatIdentity {
    static func avatarKey(_ description:String)->String {
        let path = description.components(separatedBy:"?")[0].components(separatedBy:"~")[0]
        return path.split(separator:"/").last.map(String.init) ?? ""
    }
    static func matches(name:String,avatar:String,texts:[String],avatars:[String],height:Double)->Bool {
        guard height > 0,height <= 140,!avatar.isEmpty else {return false}
        let keys = avatars.map{avatarKey($0)}.filter{!$0.isEmpty}
        return keys.count == 1 && keys[0] == avatar && texts.contains{MessageRules.clean($0) == name}
    }
}
enum AttemptRules {
    static func recover(attempts:[String:String],phases:[String:[String:String]],results:[[String:String]])->([String:String],[String:[String:String]]) {
        var dates = attempts,states = phases
        for (name,value) in phases where value["phase"] == "typing" && value["day"] == dates[name] {dates.removeValue(forKey:name);states.removeValue(forKey:name)}
        for record in results {
            guard let name = record["name"],states[name] == nil,let result = record["result"],provesNoSubmission(result) else {continue}
            dates.removeValue(forKey:name)
        }
        return (dates,states)
    }
    static func provesNoSubmission(_ result:String)->Bool {
        guard result.hasPrefix("失败：") else {return false}
        return ["当前会话与所选收件人不一致，未启动","未找到唯一匹配的联系人，未发送","准备超时，未发送","尚未确认所选会话标题和头像，未发送","同名联系人不唯一，未发送","无法打开所选会话，未发送"].contains{result.contains($0)}
    }
}
