import Cocoa
import ApplicationServices


let bundleID = "com.bytedance.douyin.desktop"
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

final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var targetName = "请选择会话"
    let contacts = NSPopUpButton(frame:.zero,pullsDown:false)
    let message = NSTextView()
    let refreshButton = NSButton(title:"刷新会话",target:nil,action:nil)
    let saveButton = NSButton(title:"保存设置",target:nil,action:nil)
    let permissionButton = NSButton(title:"授权辅助功能",target:nil,action:nil)
    var contactElements: [String: [AXUIElement]] = [:]
    var sendText = "？"
    let prefs = UserDefaults.standard
    let interval = NSTextField(string:"0.5")
    let presets = NSPopUpButton(frame:.zero,pullsDown:false)
    let speedLabel = NSTextField(labelWithString:SendRate.description(0.5))
    var lastInspection = Date.distantPast
    var pendingSince: Date?
    var generation = 0
    let limit = NSTextField(string:"1")
    let status = NSTextField(wrappingLabelWithString:"已停止。请先在抖音打开指定会话，再点击开始。")
    let progress = NSTextField(labelWithString:"已发送：0")
    let startButton = NSButton(title:"开始",target:nil,action:nil)
    let stopButton = NSButton(title:"停止",target:nil,action:nil)
    var timer: Timer?, editor: AXUIElement?, chat: AXUIElement?, boundHeader: AXUIElement?
    var pid: pid_t = 0, sent = 0, total = 0
    var awaitingConfirmation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs.register(defaults:["recipient":"请选择会话","message":"？","interval":"0.5","count":"1"])
        targetName = prefs.string(forKey:"recipient") ?? "请选择会话"
        interval.stringValue = prefs.string(forKey:"interval") ?? "0.5"
        limit.stringValue = prefs.string(forKey:"count") ?? "1"
        contacts.addItem(withTitle:targetName)
        message.string = prefs.string(forKey:"message") ?? "？"
        message.isRichText = false; message.font = .systemFont(ofSize:15)
        message.isAutomaticQuoteSubstitutionEnabled = false
        message.isAutomaticDashSubstitutionEnabled = false
        message.textContainerInset = NSSize(width:8,height:8)
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:640),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "抖音消息助手 · 高速版"; window.delegate = self; window.center()
        let appMenu = NSMenu(); let item = NSMenuItem(); appMenu.addItem(item)
        let menu = NSMenu(); menu.addItem(withTitle:"退出抖音消息助手 · 高速版",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu = menu
        let editItem = NSMenuItem(); let editMenu = NSMenu(title:"编辑")
        for (title,action,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            editMenu.addItem(withTitle:title,action:NSSelectorFromString(action),keyEquivalent:key)
        }
        editItem.submenu = editMenu; appMenu.addItem(editItem); NSApp.mainMenu = appMenu
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24)])
        let title = NSTextField(labelWithString:"高速发送，自定义节奏"); title.font = .boldSystemFont(ofSize:20); stack.addArrangedSubview(title)
        contacts.widthAnchor.constraint(equalToConstant:280).isActive = true
        contacts.target = self; contacts.action = #selector(selectionChanged)
        refreshButton.target = self; refreshButton.action = #selector(refreshContacts)
        stack.addArrangedSubview(NSStackView(views:[contacts,refreshButton]))
        let hint = NSTextField(wrappingLabelWithString:"先在抖音打开消息面板，再刷新。列表只显示已加载的会话；找不到时可先在抖音搜索对方。")
        hint.widthAnchor.constraint(equalToConstant:550).isActive = true; hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize:12); stack.addArrangedSubview(hint)
        stack.addArrangedSubview(NSTextField(labelWithString:"自定义消息（单行文字，可包含表情）"))
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.documentView = message; scroll.widthAnchor.constraint(equalToConstant:550).isActive = true; scroll.heightAnchor.constraint(equalToConstant:92).isActive = true
        message.isVerticallyResizable = true; message.isHorizontallyResizable = false
        message.autoresizingMask = [.width]; message.textContainer?.widthTracksTextView = true
        stack.addArrangedSubview(scroll)
        func row(_ label:String,_ field:NSTextField,_ suffix:String)->NSStackView {
            field.widthAnchor.constraint(equalToConstant:100).isActive = true
            return NSStackView(views:[NSTextField(labelWithString:label),field,NSTextField(labelWithString:suffix)])
        }
        stack.addArrangedSubview(row("发送间隔",interval,"秒（最低 0.1 秒）"))
        presets.addItems(withTitles:["自定义","10 条/秒 · 0.1 秒","5 条/秒 · 0.2 秒","2 条/秒 · 0.5 秒","1 条/秒 · 1 秒"])
        interval.delegate = self;updateSpeedLabel()
        presets.target = self;presets.action = #selector(selectSpeed)
        speedLabel.font = .systemFont(ofSize:12);speedLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:"快捷速率"),presets]))
        stack.addArrangedSubview(speedLabel)
        stack.addArrangedSubview(row("总发送次数",limit,"次（最多 100000 次）"))
        startButton.target = self; startButton.action = #selector(start)
        stopButton.target = self; stopButton.action = #selector(stopClicked); stopButton.isEnabled = false
        saveButton.target = self; saveButton.action = #selector(saveSettings)
        permissionButton.target = self; permissionButton.action = #selector(requestAccessibility)
        let buttons = NSStackView(views:[startButton,stopButton,saveButton,permissionButton]); buttons.spacing = 14
        stack.addArrangedSubview(buttons); stack.addArrangedSubview(progress); stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalToConstant:550).isActive = true
        let note = NSTextField(wrappingLabelWithString:"独立运行，无需打开 Codex。抖音需保持前台；切换应用、会话或输入框会停止。关闭此窗口即退出。设置会保存在本机，重新打开时保持停止。")
        note.widthAnchor.constraint(equalToConstant:550).isActive = true; note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        status.stringValue = "已停止。选择会话并编辑消息后，点击开始。"
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        if AXIsProcessTrusted() { refreshContacts() }
    }
    @objc func selectSpeed() {
        let choices = [0.0,0.1,0.2,0.5,1.0]
        guard presets.indexOfSelectedItem > 0 else {return}
        interval.stringValue = String(choices[presets.indexOfSelectedItem]);updateSpeedLabel()
    }
    func updateSpeedLabel() {
        guard let value = SendRate.parse(interval.stringValue) else {speedLabel.stringValue = "请输入至少0.1秒的有效间隔";return}
        speedLabel.stringValue = SendRate.description(value)
        presets.selectItem(at:([0.1,0.2,0.5,1.0].firstIndex(of:value).map{$0+1}) ?? 0)
    }
    func controlTextDidChange(_ notification:Notification) {updateSpeedLabel()}
    @objc func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !AXIsProcessTrusted() {
            NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            status.stringValue = "请允许桌面的抖音消息助手 · 高速版使用辅助功能，然后返回点击刷新会话。"
        } else {status.stringValue = "辅助功能已就绪。"}
    }
    @objc func selectionChanged() {targetName = contacts.titleOfSelectedItem ?? ""}
    @objc func saveSettings() {
        targetName = contacts.titleOfSelectedItem ?? targetName
        prefs.set(targetName,forKey:"recipient"); prefs.set(message.string,forKey:"message")
        prefs.set(interval.stringValue,forKey:"interval"); prefs.set(limit.stringValue,forKey:"count")
        prefs.synchronize(); status.stringValue = "设置已保存。重新打开后可以继续使用。"
    }
    func dfs(_ e:AXUIElement,_ depth:Int = 0)->[AXUIElement] {
        if depth > 40 {return []}; return [e] + children(e).flatMap{dfs($0,depth+1)}
    }
    @objc func refreshContacts() {
        guard AXIsProcessTrusted() else {status.stringValue = "请先点击授权辅助功能。"; return}
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).first else {status.stringValue = "请先打开抖音和消息面板。"; return}
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(root,"AXManualAccessibility" as CFString,kCFBooleanTrue)
        let fields = walk(root).filter{ string($0,"AXRole") == "AXTextField" && string($0,"AXPlaceholderValue") == "搜索" }
        guard fields.count == 1 else {status.stringValue = "请先打开抖音右上角的消息面板，再刷新。"; return}
        var scope = fields[0]
        for _ in 0..<3 {if let parent = attribute(scope,"AXParent") {scope = parent as! AXUIElement}}
        var nextIsName = false; var order = [String](); var found = [String:[AXUIElement]]()
        for node in dfs(scope) {
            if string(node,"AXRole") == "AXImage", !string(node,"AXDescription").isEmpty {nextIsName = true}
            else if nextIsName, string(node,"AXRole") == "AXStaticText" {
                nextIsName = false; let name = clean(string(node,"AXValue")); if name.isEmpty {continue}
                if found[name] == nil {order.append(name)}; found[name,default:[]].append(node)
            }
        }
        guard !order.isEmpty else {status.stringValue = "未读到会话，请在抖音打开消息列表再刷新。"; return}
        let old = contacts.titleOfSelectedItem ?? targetName
        contacts.removeAllItems(); contacts.addItems(withTitles:order); contactElements = found
        if order.contains(old) {contacts.selectItem(withTitle:old)}
        selectionChanged(); status.stringValue = "已读取 \(order.count) 个会话。请选择收件人。"
    }
    func openSelected(_ then: @escaping () -> Void) {
        let name = contacts.titleOfSelectedItem ?? ""
        guard let matches = contactElements[name], matches.count == 1 else {status.stringValue = "请刷新会话；同名会话需先在抖音核实身份。"; return}
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).first else {status.stringValue = "请先打开抖音。"; return}
        let node = matches[0]
        guard let pos = attribute(node,"AXPosition"), let size = attribute(node,"AXSize") else {status.stringValue = "会话位置已变化，请刷新。";return}
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(pos as! AXValue,.cgPoint,&point), AXValueGetValue(size as! AXValue,.cgSize,&dimensions), dimensions.width > 0, dimensions.height > 0 else {status.stringValue = "会话不在可见区域，请先在抖音打开该会话。";return}
        NSApp.yieldActivation(to:app);app.activate(options:[.activateAllWindows])
        let token = generation
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [weak self] in
            guard let self = self, self.generation == token else {return}
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {self.finish("请先把抖音切到前台，再重试。");return}
            let center = CGPoint(x:point.x+dimensions.width/2,y:point.y+dimensions.height/2)
            CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:center,mouseButton:.left)?.post(tap:.cghidEventTap)
            CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:center,mouseButton:.left)?.post(tap:.cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [weak self] in guard self?.generation == token else {return};then() }
        }
    }
    func finish(_ message: String) {
        generation += 1;pendingSince = nil;timer?.invalidate(); timer = nil; startButton.isEnabled = true; stopButton.isEnabled = false
        interval.isEnabled = true; limit.isEnabled = true; contacts.isEnabled = true; refreshButton.isEnabled = true; self.message.isEditable = true;presets.isEnabled = true; saveButton.isEnabled = true; status.stringValue = message
        awaitingConfirmation = false
    }
    @objc func stopClicked() { finish("已手动停止。") }
    @objc func start() {
        guard AXIsProcessTrusted() else {requestAccessibility(); return}
        targetName = contacts.titleOfSelectedItem ?? ""
        let text = message.string
        guard !clean(text).isEmpty, text.utf16.count <= 1000, !text.contains("\n"), !text.contains("\r"), !text.unicodeScalars.contains(where:{$0.value < 32}) else {status.stringValue = "请输入 1 到 1000 个 UTF-16 字符的单行消息，不含制表等控制字符。";return}
        guard SendRate.parse(interval.stringValue) != nil, let count = Int(limit.stringValue), count > 0, count <= 100000 else {status.stringValue = "间隔至少0.1秒，总次数为1到100000。";return}
        sendText = text; saveSettings()
        generation += 1;let token = generation
        startButton.isEnabled = false;stopButton.isEnabled = true;contacts.isEnabled = false; refreshButton.isEnabled = false
        openSelected { [weak self] in guard self?.generation == token else {return};self?.bindAndStart() }
        // Binding is read back before any message is sent.
        DispatchQueue.main.asyncAfter(deadline:.now()+8) { [weak self] in
            if let self = self, self.generation == token, self.timer == nil {self.finish("准备超时，未发送。请检查会话并重试。")}
        }
    }
    func bindAndStart() {
        guard let seconds = SendRate.parse(interval.stringValue) else {status.stringValue = "请输入至少 0.1 秒的发送间隔。"; return}
        guard let count = Int(limit.stringValue), count > 0, count <= 100000 else {status.stringValue = "总次数应为 1 到 100000。"; return}
        guard AXIsProcessTrusted() else {
            status.stringValue = "尚无辅助功能权限。请在系统设置 > 隐私与安全性 > 辅助功能中允许此控制器，之后重新打开。"
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options); return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).first else {status.stringValue = "请先打开并登录抖音。"; return}
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let editors = walk(root).filter {string($0,"AXRole") == "AXTextArea"}
        guard editors.count == 1 else {status.stringValue = "请在抖音打开指定会话，并点一下消息输入框。"; return}
        let input = editors[0]
        guard isEmpty(input) else {status.stringValue = "输入框中已有内容，请先清空后再开始。"; return}
        var ancestor = input; var scope: AXUIElement?; var header: AXUIElement?
        for _ in 0..<7 {
            guard let parent = attribute(ancestor,"AXParent") else {break}
            ancestor = parent as! AXUIElement
            let scopeNodes = walk(ancestor,maxNodes:1500)
            if scopeNodes.contains(where:{string($0,"AXRole") == "AXTextField"}) {break}
            for child in children(ancestor) {
                let nodes = walk(child,maxNodes:25)
                if nodes.contains(where:{CFEqual($0,input)}) {continue}
                // The header may also contain unread count and a Follow label.
                // Only inspect a complete small sibling, never a truncated history subtree.
                if nodes.count >= 25 {continue}
                for part in nodes {
                    let leafNodes = walk(part,maxNodes:20)
                    let texts = leafNodes.filter{string($0,"AXRole") == "AXStaticText"}
                    let avatars = leafNodes.filter{string($0,"AXRole") == "AXImage" && !string($0,"AXDescription").isEmpty}
                    if texts.count == 1 && avatars.count == 1 && leafNodes.count < 20 {
                        header = texts[0]; scope = ancestor; break
                    }
                }
                if scope != nil {break}
            }
            if scope != nil {break}
        }
        guard let scope = scope, let header = header, clean(string(header,"AXValue")) == targetName else {finish("当前会话与所选收件人不一致，未启动。请刷新重试。"); return}
        boundHeader = header
        editor = input; chat = scope; pid = app.processIdentifier; total = count; sent = 0; awaitingConfirmation = false
        progress.stringValue = "已发送：0 / \(total)"
        startButton.isEnabled = false; stopButton.isEnabled = true; interval.isEnabled = false; limit.isEnabled = false; contacts.isEnabled = false; refreshButton.isEnabled = false; message.isEditable = false;presets.isEnabled = false; saveButton.isEnabled = false
        lastInspection = Date.distantPast;pendingSince = nil
        speedLabel.stringValue = SendRate.description(seconds)
        status.stringValue = "运行中：每 \(seconds) 秒一次。点击停止或切换应用可停止。"
        AXUIElementSetAttributeValue(input,"AXFocused" as CFString,kCFBooleanTrue)
        NSApp.yieldActivation(to:app);app.activate(options:[.activateAllWindows])
        timer = Timer.scheduledTimer(withTimeInterval:seconds,repeats:true) {[weak self] _ in self?.tick()}
    }
    func isEmpty(_ e: AXUIElement) -> Bool {let text = clean(string(e,"AXValue")); return text.isEmpty || text == "发送消息"}
    func tick() {
        guard let input = editor, let scope = chat else {finish("输入框失效，已停止。"); return}
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {finish("已切换应用，自动停止。"); return}
        let root = AXUIElementCreateApplication(pid)
        guard let focused = attribute(root,"AXFocusedUIElement"), CFEqual(focused,input) else {finish("输入焦点变化，自动停止。"); return}
        guard let header = boundHeader, clean(string(header,"AXValue")) == targetName else {finish("会话变化，自动停止。");return}
        // Check destination and focus on every tick; scan the larger UI at most once a second.
        let now = Date()
        if now.timeIntervalSince(lastInspection) >= 1 {
            lastInspection = now
            let problem = walk(scope,maxNodes:1000).contains { e in
                let text = string(e,"AXValue")
                return ["发送失败","发送频繁","操作频繁","已被限制","发送过于频繁"].contains(where:{text.contains($0)})
            }
            guard !problem else {finish("检测到发送异常或平台限制，已停止。");return}
        }
        if !isEmpty(input) {
            if awaitingConfirmation, let since = pendingSince, now.timeIntervalSince(since) < 5 {return}
            finish("输入框未清空，已停止。请检查上一条消息。");return
        }
        if awaitingConfirmation {
            sent += 1; progress.stringValue = "已发送：\(sent) / \(total)"; awaitingConfirmation = false
        }
        guard sent < total else {finish("已完成 \(sent) 次发送。该计数表示界面发送操作，不代表对方已收取。"); return}
        // Unicode input is sent only to the verified Douyin process.
        let units = Array(sendText.utf16)
        var offset = 0
        while offset < units.count {
            var end = min(offset+20,units.count)
            if end < units.count && units[end-1] >= 0xD800 && units[end-1] <= 0xDBFF {end -= 1}
            var chars = Array(units[offset..<end])
            guard let down = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true), let up = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else {finish("无法创建输入事件，已停止。"); return}
            down.keyboardSetUnicodeString(stringLength:chars.count,unicodeString:&chars)
            up.keyboardSetUnicodeString(stringLength:chars.count,unicodeString:&chars)
            down.postToPid(pid); up.postToPid(pid); offset = end
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            let focusedNow = attribute(root,"AXFocusedUIElement"), CFEqual(focusedNow,input) else {finish("输入焦点变化，未按发送键。"); return}
        CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:true)?.postToPid(pid)
        CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:false)?.postToPid(pid)
        awaitingConfirmation = true;pendingSince = Date()
    }
    func windowWillClose(_ notification: Notification) {finish("已关闭。"); saveSettings(); NSApp.terminate(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {true}
}
let lockPath = NSTemporaryDirectory() + "douyin-message-assistant-fast.lock"
let lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let controller = Controller()
application.delegate = controller
application.run()
