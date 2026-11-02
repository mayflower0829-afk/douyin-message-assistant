import Foundation
func date(_ text:String)->Date {ISO8601DateFormatter().date(from:text)!}
func check(_ value:Bool,_ description:String) {if !value {fatalError(description)};print("PASS",description)}
let base = date("2026-11-03T11:59:00Z")
let due = DailySchedule.next(after:base,hour:20,minute:0)
check(due == date("2026-11-03T12:00:00Z"),"schedule uses Asia/Shanghai")
check(DailySchedule.next(after:due,hour:20,minute:0) == date("2026-11-04T12:00:00Z"),"next run advances after due instant")
check(DailySchedule.dayKey(date("2026-11-03T16:00:00Z")) == "2026-11-04","ledger day follows Beijing midnight")
check(!DailySchedule.shouldAttempt(now:base,scheduled:due,previousDay:nil),"does not fire early")
check(DailySchedule.shouldAttempt(now:due,scheduled:due,previousDay:nil),"fires once when due")
check(!DailySchedule.shouldAttempt(now:due,scheduled:due,previousDay:"2026-11-03"),"persisted reservation prevents duplicate after restart")
check(DailySchedule.shouldAttempt(now:due,scheduled:due,previousDay:"2026-11-02"),"previous day does not block next day")
check(!DailySchedule.shouldAttempt(now:due.addingTimeInterval(900),scheduled:due,previousDay:nil),"stale wakeup skips catchup")
let leap = DailySchedule.next(after:date("2028-02-28T12:00:00Z"),hour:20,minute:0)
check(DailySchedule.dayKey(leap) == "2028-02-29","handles leap day")

check(SendRate.parse("0.1") == 0.1,"accepts minimum interval")
check(SendRate.parse("0.5") == 0.5,"accepts middle speed")
for text in ["0","-1","0.01","nan","inf","abc"] {check(SendRate.parse(text) == nil,"rejects invalid interval: \(text)")}
