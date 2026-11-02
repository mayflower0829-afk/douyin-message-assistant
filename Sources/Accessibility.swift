import Cocoa
import ApplicationServices

func attribute(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, key as CFString, &value) == .success else { return nil }
    return value
}
func string(_ e: AXUIElement, _ key: String) -> String { attribute(e,key) as? String ?? "" }
func children(_ e: AXUIElement) -> [AXUIElement] { attribute(e,"AXChildren") as? [AXUIElement] ?? [] }
func walk(_ root: AXUIElement, maxNodes: Int = 5000) -> [AXUIElement] {
    var queue = [root], result = [AXUIElement](), i = 0
    while i < queue.count && i < maxNodes {
        let e = queue[i]; i += 1; result.append(e); queue.append(contentsOf: children(e))
    }
    return result
}
func clean(_ s: String) -> String {
    s.replacingOccurrences(of:"\u{200B}",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
}


struct ChatBinding {
    let input:AXUIElement, scope:AXUIElement, header:AXUIElement, avatar:AXUIElement
}
func findChatBinding(root:AXUIElement,name:String,avatarKey:String)->ChatBinding? {
    guard !avatarKey.isEmpty else {return nil}
    let editors = walk(root).filter{string($0,"AXRole") == "AXTextArea"}
    guard editors.count == 1 else {return nil}
    let input = editors[0];var ancestor = input
    for _ in 0..<8 {
        guard let parent = attribute(ancestor,"AXParent") else {break};ancestor = parent as! AXUIElement
        if walk(ancestor,maxNodes:1500).contains(where:{string($0,"AXRole") == "AXTextField"}) {break}
        for branch in children(ancestor) {
            let nodes = walk(branch,maxNodes:80)
            guard nodes.count < 80,!nodes.contains(where:{CFEqual($0,input)}),let size = attribute(branch,"AXSize") else {continue}
            var dimensions = CGSize.zero
            guard AXValueGetValue(size as! AXValue,.cgSize,&dimensions) else {continue}
            let avatars = nodes.filter{string($0,"AXRole") == "AXImage" && !string($0,"AXDescription").isEmpty}
            let texts = nodes.filter{string($0,"AXRole") == "AXStaticText"}
            guard ChatIdentity.matches(name:name,avatar:avatarKey,texts:texts.map{string($0,"AXValue")},avatars:avatars.map{string($0,"AXDescription")},height:Double(dimensions.height)),
                  let header = texts.first(where:{clean(string($0,"AXValue")) == name}),
                  let avatar = avatars.first(where:{ChatIdentity.avatarKey(string($0,"AXDescription")) == avatarKey}) else {continue}
            return ChatBinding(input:input,scope:ancestor,header:header,avatar:avatar)
        }
    }
    return nil
}
