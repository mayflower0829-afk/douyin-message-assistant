import Foundation
func check(_ value:Bool,_ description:String) {if !value {fatalError(description)};print("PASS",description)}
check(SendRate.parse("0.1") == 0.1,"accepts minimum interval")
check(SendRate.parse("0.5") == 0.5,"accepts middle speed")
for text in ["0","-1","0.01","nan","inf","abc"] {check(SendRate.parse(text) == nil,"rejects invalid interval: \(text)")}
