import Foundation

struct DailySchedule {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
    }
    static func next(after date: Date, hour: Int, minute: Int) -> Date {
        calendar.nextDate(after:date,matching:DateComponents(hour:hour,minute:minute,second:0),matchingPolicy:.nextTime)!
    }
    static func shouldAttempt(now:Date, scheduled:Date, previousDay:String?) -> Bool {
        now >= scheduled && now.timeIntervalSince(scheduled) < 900 && previousDay != dayKey(now)
    }
    static func display(_ date: Date) -> String {
        let f = DateFormatter(); f.timeZone = calendar.timeZone; f.locale = Locale(identifier:"zh_CN")
        f.dateFormat = "MM月dd日 HH:mm"; return f.string(from:date)
    }
}
