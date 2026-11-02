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
    let searchField = NSSearchField()
    let searchButton = NSButton(title:"搜索抖音",target:nil,action:nil)
    let moreButton = NSButton(title:"加载更多",target:nil,action:nil)
    var knownNames = [String]()
    var flow: SendFlow?

    let isPreview = CommandLine.arguments.contains("--check-layout")
    let ratePresets = NSPopUpButton(frame:.zero,pullsDown:false)
    var pendingSince:Date?, lastInspection = Date.distantPast
    let mode = NSSegmentedControl(labels:["定时发送","每日续火花"],trackingMode:.selectOne,target:nil,action:nil)
    let timePicker = NSDatePicker()
    let modeHint = NSTextField(wrappingLabelWithString:"")
    let stateBadge = NSTextField(labelWithString:"● 已停止")
    let nextLabel = NSTextField(labelWithString:"尚未启用每日计划")
    let previewButton = NSButton(title:"预检（不发送）",target:nil,action:nil)
    var dailyTimer: Timer?, nextRun: Date?
    var dailyActive = false, dailySending = false, previewOnly = false
    var generation = 0

    var targetName = "请选择会话"
    let contacts = NSPopUpButton(frame:.zero,pullsDown:false)
    let message = NSTextView()
    let refreshButton = NSButton(title:"刷新会话",target:nil,action:nil)
    let saveButton = NSButton(title:"保存设置",target:nil,action:nil)
    let permissionButton = NSButton(title:"授权辅助功能",target:nil,action:nil)
    var contactElements: [String: [AXUIElement]] = [:]
    var contactOpeners = [String:AXUIElement]()
    var sendText = "？"
    let prefs = UserDefaults.standard
    let interval = NSTextField(string:"0.5")
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
        if isPreview {targetName = "示例好友";message.string = "今天也要开心呀 👋";interval.stringValue = "0.5";limit.stringValue = "1"}
        contacts.addItem(withTitle:targetName)
        message.string = prefs.string(forKey:"message") ?? "？"
        message.isRichText = false; message.font = .systemFont(ofSize:15)
        message.isAutomaticQuoteSubstitutionEnabled = false
        message.isAutomaticDashSubstitutionEnabled = false
        message.textContainerInset = NSSize(width:8,height:8)
        if isPreview {message.string = "今天也要开心呀 👋"}
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:780),styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "抖音消息助手"; window.titlebarAppearsTransparent = true; window.delegate = self; window.center()
        window.backgroundColor = NSColor.windowBackgroundColor
        let appMenu = NSMenu(); let item = NSMenuItem(); appMenu.addItem(item)
        let menu = NSMenu(); menu.addItem(withTitle:"退出抖音消息助手",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu = menu
        let editItem = NSMenuItem(); let editMenu = NSMenu(title:"编辑")
        for (title,action,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {editMenu.addItem(withTitle:title,action:NSSelectorFromString(action),keyEquivalent:key)}
        editItem.submenu = editMenu; appMenu.addItem(editItem); NSApp.mainMenu = appMenu
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        let outer = NSScrollView(frame:NSRect(x:0,y:120,width:window.contentView!.bounds.width,height:window.contentView!.bounds.height-120));outer.autoresizingMask = [.width,.height];outer.hasVerticalScroller = true;outer.drawsBackground = false
        let document = NSView();document.translatesAutoresizingMaskIntoConstraints = false;outer.documentView = document;window.contentView!.addSubview(outer)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:outer.contentView.widthAnchor)])
        stack.translatesAutoresizingMaskIntoConstraints = false;document.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:48),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-28)])
        let flame = NSImageView(image:NSImage(systemSymbolName:"flame.fill",accessibilityDescription:"火花")!)
        flame.contentTintColor = .systemOrange; flame.widthAnchor.constraint(equalToConstant:35).isActive = true; flame.heightAnchor.constraint(equalToConstant:38).isActive = true
        let title = NSTextField(labelWithString:"抖音消息助手"); title.font = .boldSystemFont(ofSize:26)
        let subtitle = NSTextField(labelWithString:"让日常问候，按时发生。"); subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views:[title,subtitle]); heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 5
        let head = NSStackView(views:[flame,heading]); head.spacing = 14; stack.addArrangedSubview(head)
        stateBadge.font = .systemFont(ofSize:12,weight:.semibold); stateBadge.textColor = .secondaryLabelColor
        stack.addArrangedSubview(stateBadge)
        func label(_ text:String)->NSTextField {let field = NSTextField(labelWithString:text);field.font = .systemFont(ofSize:13,weight:.semibold);return field}
        func card(_ views:[NSView])->NSBox {
            let box = NSBox();box.boxType = .custom;box.cornerRadius = 14;box.borderColor = .separatorColor;box.borderWidth = 0.5;box.fillColor = .controlBackgroundColor
            let content = NSStackView(views:views);content.orientation = .vertical;content.alignment = .leading;content.spacing = 12
            content.translatesAutoresizingMaskIntoConstraints = false; box.contentView = NSView();box.contentView!.addSubview(content)
            NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo:box.contentView!.leadingAnchor,constant:16),content.trailingAnchor.constraint(equalTo:box.contentView!.trailingAnchor,constant:-16),content.topAnchor.constraint(equalTo:box.contentView!.topAnchor,constant:16),content.bottomAnchor.constraint(equalTo:box.contentView!.bottomAnchor,constant:-16),box.widthAnchor.constraint(equalToConstant:604)])
            return box
        }
        contacts.widthAnchor.constraint(equalToConstant:400).isActive = true;contacts.target = self;contacts.action = #selector(selectionChanged)
        refreshButton.target = self;refreshButton.action = #selector(refreshContacts)
        searchField.placeholderString = "输入昵称，搜索列表外的联系人";searchField.widthAnchor.constraint(equalToConstant:350).isActive = true
        searchField.target = self;searchField.action = #selector(searchContacts)
        searchButton.target = self;searchButton.action = #selector(searchContacts)
        moreButton.target = self;moreButton.action = #selector(loadMore)
        stack.addArrangedSubview(card([label("01  收件会话"),NSStackView(views:[contacts,refreshButton]),NSStackView(views:[searchField,searchButton,moreButton])]))
        mode.selectedSegment = prefs.integer(forKey:"mode") == 1 ? 1 : 0; mode.target = self;mode.action = #selector(modeChanged)
        timePicker.datePickerStyle = .textFieldAndStepper;timePicker.datePickerElements = [.hourMinute];timePicker.timeZone = DailySchedule.calendar.timeZone
        let savedHour = prefs.object(forKey:"dailyHour") as? Int ?? 20;let savedMinute = prefs.integer(forKey:"dailyMinute")
        let hour = (0...23).contains(savedHour) ? savedHour : 20;let minute = (0...59).contains(savedMinute) ? savedMinute : 0
        timePicker.dateValue = DailySchedule.calendar.date(bySettingHour:hour,minute:minute,second:0,of:Date())!
        interval.widthAnchor.constraint(equalToConstant:72).isActive = true;limit.widthAnchor.constraint(equalToConstant:90).isActive = true
        ratePresets.addItems(withTitles:["自定义","0.1秒 · 10条/秒","0.2秒 · 5条/秒","0.5秒 · 2条/秒","1秒 · 1条/秒"])
        ratePresets.target = self;ratePresets.action = #selector(rateChanged)
        interval.delegate = self;syncRatePreset()
        let repeatRow = NSStackView(views:[NSTextField(labelWithString:"间隔"),interval,NSTextField(labelWithString:"秒 · 总共"),limit,NSTextField(labelWithString:"次")]);repeatRow.spacing = 8
        let dailyRow = NSStackView(views:[NSTextField(labelWithString:"每天"),timePicker,NSTextField(labelWithString:"北京时间 · 每天最多尝试一次")]);dailyRow.spacing = 10
        modeHint.widthAnchor.constraint(equalToConstant:560).isActive = true;modeHint.font = .systemFont(ofSize:12);modeHint.textColor = .secondaryLabelColor
        nextLabel.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium);nextLabel.textColor = .systemOrange
        stack.addArrangedSubview(card([label("02  发送计划"),mode,repeatRow,ratePresets,dailyRow,modeHint,nextLabel]))
        let scroll = NSScrollView();scroll.hasVerticalScroller = true;scroll.drawsBackground = false;scroll.borderType = .noBorder
        scroll.documentView = message;scroll.widthAnchor.constraint(equalToConstant:560).isActive = true;scroll.heightAnchor.constraint(equalToConstant:80).isActive = true
        message.isVerticallyResizable = true;message.isHorizontallyResizable = false;message.autoresizingMask = [.width];message.textContainer?.widthTracksTextView = true
        stack.addArrangedSubview(card([label("03  自定义消息"),scroll]))
        startButton.target = self;startButton.action = #selector(start);startButton.bezelStyle = .rounded;startButton.bezelColor = .systemOrange;startButton.contentTintColor = .white
        stopButton.target = self;stopButton.action = #selector(stopClicked);stopButton.isEnabled = false
        saveButton.target = self;saveButton.action = #selector(saveSettings)
        previewButton.target = self;previewButton.action = #selector(preview)
        permissionButton.title = "连接授权";permissionButton.target = self;permissionButton.action = #selector(requestAccessibility)
        let buttons = NSStackView(views:[startButton,stopButton,previewButton,saveButton,permissionButton]);buttons.spacing = 10
        let footer = NSStackView(views:[buttons,progress,status]);footer.orientation = .vertical;footer.alignment = .leading;footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false;window.contentView!.addSubview(footer)
        NSLayoutConstraint.activate([footer.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:28),footer.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-28),footer.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-16)])
        status.widthAnchor.constraint(equalToConstant:604).isActive = true;status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor

        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in
            if let self = self, self.timer != nil {self.finish("电脑即将休眠，已停止正在执行的发送。")}
        }
        modeChanged();status.stringValue = "先在抖音打开消息面板，然后刷新会话。退出 Codex 后本应用仍可运行。"
        if isPreview {
            window.setFrameOrigin(NSPoint(x:-10000,y:-10000));window.orderBack(nil)
            window.contentView!.layoutSubtreeIfNeeded();window.contentView!.displayIfNeeded()
            print("LAYOUT",window.contentView!.frame,outer.frame,document.frame,stack.frame)
            for card in stack.arrangedSubviews {print("ROW",card.frame)}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { NSApp.terminate(nil) }
        } else {
            window.makeKeyAndOrderFront(nil);window.contentView!.layoutSubtreeIfNeeded()
            outer.contentView.scroll(to:NSPoint(x:0,y:max(0,document.bounds.height-outer.contentView.bounds.height)));outer.reflectScrolledClipView(outer.contentView)
            NSApp.activate(ignoringOtherApps:true)
            if AXIsProcessTrusted() {refreshContacts()}
        }
    }
    func syncRatePreset() {
        let index = SendRate.parse(interval.stringValue).flatMap{[0.1,0.2,0.5,1.0].firstIndex(of:$0)}
        ratePresets.selectItem(at:index.map{$0+1} ?? 0)
    }
    func controlTextDidChange(_ notification:Notification) {syncRatePreset()}
    @objc func rateChanged() {
        let rates = [0.0,0.1,0.2,0.5,1.0]
        if ratePresets.indexOfSelectedItem > 0 {interval.stringValue = String(rates[ratePresets.indexOfSelectedItem])};syncRatePreset()
    }
    @objc func modeChanged() {
        let daily = mode.selectedSegment == 1
        interval.isEnabled = !daily;limit.isEnabled = !daily;ratePresets.isEnabled = !daily;timePicker.isEnabled = daily
        startButton.title = daily ? "启用每日续火花" : "开始发送"
        modeHint.stringValue = daily ? "应用保持运行；到点打开所选会话。休眠超过15分钟不补发；需双方互动才可能保持火花。" : "单行文字支持表情；间隔至少0.1秒。切换应用或会话会停止正在进行的发送。"
    }
    @objc func preview() {previewOnly = true;start();previewOnly = false}
    func armDaily() {
        let parts = DailySchedule.calendar.dateComponents([.hour,.minute],from:timePicker.dateValue)
        nextRun = DailySchedule.next(after:Date(),hour:parts.hour!,minute:parts.minute!)
        dailyActive = true;dailySending = false;setEditing(false);stateBadge.stringValue = "● 每日计划已启用";stateBadge.textColor = .systemOrange
        nextLabel.stringValue = "下次：" + DailySchedule.display(nextRun!)
        status.stringValue = "计划待命。应用需保持运行；停止按钮会取消每日计划。"
        dailyTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.checkDaily() }
    }
    func checkDaily() {
        guard dailyActive, !dailySending, let scheduled = nextRun, Date() >= scheduled else {return}
        let now = Date();let parts = DailySchedule.calendar.dateComponents([.hour,.minute],from:timePicker.dateValue)
        nextRun = DailySchedule.next(after:now,hour:parts.hour!,minute:parts.minute!)
        nextLabel.stringValue = "下次：" + DailySchedule.display(nextRun!)
        var ledger = prefs.dictionary(forKey:"dailyAttempts") as? [String:String] ?? [:]
        guard DailySchedule.shouldAttempt(now:now,scheduled:scheduled,previousDay:ledger[targetName]) else {status.stringValue = "今日已尝试或错过执行窗口，等待下次计划。";return}
        ledger[targetName] = DailySchedule.dayKey(now);prefs.set(ledger,forKey:"dailyAttempts");prefs.synchronize()
        dailySending = true
        let selected = targetName
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).first else {finish("抖音未运行，今日计划未发送。");return}
        NSApp.yieldActivation(to:app);app.activate(options:[.activateAllWindows])
        let token = generation
        DispatchQueue.main.asyncAfter(deadline:.now()+0.6) { [weak self] in
            guard let self = self, self.dailyActive, token == self.generation else {return}
            self.targetName = selected
            self.prepareSend()
        }
    }
    func setEditing(_ enabled: Bool) {
        startButton.isEnabled = enabled;stopButton.isEnabled = !enabled;contacts.isEnabled = enabled;refreshButton.isEnabled = enabled
        searchField.isEnabled = enabled;searchButton.isEnabled = enabled;moreButton.isEnabled = enabled
        message.isEditable = enabled;saveButton.isEnabled = enabled;previewButton.isEnabled = enabled;mode.isEnabled = enabled;timePicker.isEnabled = enabled && mode.selectedSegment == 1
        ratePresets.isEnabled = enabled && mode.selectedSegment == 0
        interval.isEnabled = enabled && mode.selectedSegment == 0;limit.isEnabled = enabled && mode.selectedSegment == 0
    }
    @objc func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !AXIsProcessTrusted() {
            NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            status.stringValue = "请允许桌面的抖音消息助手使用辅助功能，然后返回点击刷新会话。"
        } else {status.stringValue = "辅助功能已就绪。"}
    }
    @objc func selectionChanged() {targetName = contacts.titleOfSelectedItem ?? ""}
    @objc func saveSettings() {
        targetName = contacts.titleOfSelectedItem ?? targetName
        prefs.set(targetName,forKey:"recipient"); prefs.set(message.string,forKey:"message")
        prefs.set(interval.stringValue,forKey:"interval"); prefs.set(limit.stringValue,forKey:"count")
        prefs.set(mode.selectedSegment,forKey:"mode")
        let clock = DailySchedule.calendar.dateComponents([.hour,.minute],from:timePicker.dateValue)
        prefs.set(clock.hour!,forKey:"dailyHour");prefs.set(clock.minute!,forKey:"dailyMinute")
        prefs.synchronize(); status.stringValue = "设置已保存。重新打开后可以继续使用。"
    }
    func dfs(_ root:AXUIElement)->[AXUIElement] {
        var result = [AXUIElement](), stack = [(root,0)]
        while let (node,depth) = stack.popLast(), result.count < 6000 {
            result.append(node)
            if depth < 40 {stack.append(contentsOf:children(node).reversed().map{($0,depth+1)})}
        }
        return result
    }
    func searchContext()->(NSRunningApplication,AXUIElement,AXUIElement)? {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).first else {return nil}
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(root,"AXManualAccessibility" as CFString,kCFBooleanTrue)
        let fields = walk(root).filter{string($0,"AXRole") == "AXTextField" && string($0,"AXPlaceholderValue") == "搜索"}
        guard fields.count == 1 else {return nil}
        var scope = fields[0]
        for _ in 0..<3 {if let parent = attribute(scope,"AXParent") {scope = parent as! AXUIElement}}
        return (app,fields[0],scope)
    }
    @discardableResult func collectContacts(preserving previous:String? = nil)->Bool {
        contactElements.removeAll();contactOpeners.removeAll()
        guard let (_,_,scope) = searchContext() else {status.stringValue = AXIsProcessTrusted() ? "请先在抖音打开消息面板。" : "请先点击连接授权。";return false}
        var lastName:String?;var nextIsName = false;var found = [String:[AXUIElement]]();var order = [String]()
        for node in dfs(scope) {
            if string(node,"AXRole") == "AXImage", !string(node,"AXDescription").isEmpty {nextIsName = true}
            else if nextIsName, string(node,"AXRole") == "AXStaticText" {
                nextIsName = false
                let nameNode = attribute(node,"AXParent").map{$0 as! AXUIElement} ?? node
                let parts = dfs(nameNode).filter{string($0,"AXRole") == "AXStaticText"}.map{string($0,"AXValue")}
                let name = MessageRules.contactName(parts)
                guard !name.isEmpty else {continue}
                if found[name] == nil {order.append(name)}
                found[name,default:[]].append(nameNode);lastName = name
            } else if string(node,"AXRole") == "AXStaticText",string(node,"AXValue") == "发消息",let name = lastName {
                contactOpeners[name] = node
            }
        }
        contactElements = found
        for name in order where !knownNames.contains(name) {knownNames.append(name)}
        let old = previous ?? contacts.titleOfSelectedItem ?? targetName
        contacts.removeAllItems();contacts.addItem(withTitle:"请选择会话");contacts.addItems(withTitles:knownNames)
        if knownNames.contains(old) {contacts.selectItem(withTitle:old)}
        else {contacts.selectItem(at:0)}
        selectionChanged()
        status.stringValue = "本页 \(order.count) 个，累计 \(knownNames.count) 个。可搜索昵称或加载更多；不会自动改选他人。"
        return true
    }
    @objc func refreshContacts() {
        guard timer == nil, !dailyActive else {return}
        _ = collectContacts()
    }
    func point(_ node:AXUIElement)->CGPoint? {
        guard let pos = attribute(node,"AXPosition"),let size = attribute(node,"AXSize") else {return nil}
        var p = CGPoint.zero;var dimensions = CGSize.zero
        guard AXValueGetValue(pos as! AXValue,.cgPoint,&p),AXValueGetValue(size as! AXValue,.cgSize,&dimensions),dimensions.width > 0,dimensions.height > 0 else {return nil}
        return CGPoint(x:p.x+dimensions.width/2,y:p.y+dimensions.height/2)
    }
    func clickPoint(_ p:CGPoint) {
        CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
        CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:p,mouseButton:.left)?.post(tap:.cghidEventTap)
    }
    @discardableResult func typeText(_ text:String,to pid:pid_t)->Bool {
        for var units in MessageRules.chunks(text) {
            guard let down = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),let up = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else {return false}
            down.keyboardSetUnicodeString(stringLength:units.count,unicodeString:&units);up.keyboardSetUnicodeString(stringLength:units.count,unicodeString:&units)
            down.postToPid(pid);up.postToPid(pid)
        }
        return true
    }
    func searchInDouyin(_ query:String,token:Int,completion:@escaping ()->Void) {
        guard let (app,field,_) = searchContext(),let position = point(field) else {finish("请先授权并打开抖音消息面板。");return}
        NSApp.yieldActivation(to:app);app.activate(options:[.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3) { [weak self] in
            guard let self = self,token == self.generation else {return}
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {self.finish("抖音未切到前台，请先打开抖音。");return}
            self.clickPoint(position)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { [weak self] in
                guard let self = self,token == self.generation else {return}
                let root = AXUIElementCreateApplication(app.processIdentifier)
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,let focus = attribute(root,"AXFocusedUIElement"),CFEqual(focus,field) else {self.finish("搜索框未获得焦点，未输入。");return}
                let down = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true);down?.flags = .maskCommand;down?.postToPid(app.processIdentifier)
                let up = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false);up?.flags = .maskCommand;up?.postToPid(app.processIdentifier)
                CGEvent(keyboardEventSource:nil,virtualKey:51,keyDown:true)?.postToPid(app.processIdentifier)
                CGEvent(keyboardEventSource:nil,virtualKey:51,keyDown:false)?.postToPid(app.processIdentifier)
                guard self.typeText(query,to:app.processIdentifier) else {self.finish("无法输入搜索内容。");return}
                DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { [weak self] in
                    guard let self = self,token == self.generation else {return}
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,let (_,current,_) = self.searchContext(),string(current,"AXValue") == query else {self.finish("搜索内容已变化，请重新搜索。");return}
                    completion()
                }
            }
        }
    }
    @objc func searchContacts() {
        let query = clean(searchField.stringValue)
        guard MessageRules.valid(query) else {status.stringValue = "请输入有效的单行昵称。";return}
        generation += 1;let token = generation;let old = targetName;setEditing(false)
        status.stringValue = "正在搜索抖音联系人…"
        searchInDouyin(query,token:token) { [weak self] in
            guard let self = self else {return}
            _ = self.collectContacts(preserving:old);self.setEditing(true)
        }
    }
    @objc func loadMore() {
        generation += 1;let token = generation;let old = targetName;setEditing(false)
        searchInDouyin("",token:token) { [weak self] in
            guard let self = self,let (app,_,scope) = self.searchContext(),let center = self.point(scope) else {self?.finish("未找到消息列表。");return}
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {self.finish("抖音已离开前台，停止加载。");return}
            CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:center,mouseButton:.left)?.post(tap:.cghidEventTap)
            let wheel = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:-550,wheel2:0,wheel3:0);wheel?.location = center;wheel?.post(tap:.cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.6) { [weak self] in
                guard let self = self,token == self.generation else {return}
                _ = self.collectContacts(preserving:old);self.setEditing(true)
            }
        }
    }
    func openSelected(_ then:@escaping ()->Void) {
        let name = targetName;let token = generation
        searchInDouyin(name,token:token) { [weak self] in
            guard let self = self else {return}
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID,self.collectContacts(preserving:name),let matches = self.contactElements[name],matches.count == 1,let position = self.point(self.contactOpeners[name] ?? matches[0]) else {self.targetName = name;self.finish("未找到唯一匹配的联系人，未发送。请搜索并核实同名会话。");return}
            self.targetName = name;self.clickPoint(position)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { [weak self] in guard self?.generation == token else {return};then() }
        }
    }
    func finish(_ result: String) {
        generation += 1;flow = nil;pendingSince = nil;timer?.invalidate();timer = nil;awaitingConfirmation = false;dailySending = false
        setEditing(!dailyActive)
        stateBadge.stringValue = dailyActive ? "● 每日计划待命" : "● 已停止"
        stateBadge.textColor = dailyActive ? .systemOrange : .secondaryLabelColor
        status.stringValue = result
    }
    @objc func stopClicked() {
        dailyActive = false;dailyTimer?.invalidate();dailyTimer = nil;nextRun = nil;nextLabel.stringValue = "每日计划已停止"
        finish("已手动停止。")
    }
    @objc func start() {
        guard AXIsProcessTrusted() else {requestAccessibility(); return}
        targetName = contacts.titleOfSelectedItem ?? ""
        let text = message.string
        guard MessageRules.valid(text) else {status.stringValue = "请输入 1 到 1000 个 UTF-16 字符的单行消息，不含制表等控制字符。";return}
        guard mode.selectedSegment == 1 || (SendRate.parse(interval.stringValue) != nil && (Int(limit.stringValue).map{(1...100000).contains($0)} ?? false)) else {status.stringValue = "间隔至少0.1秒，总次数为1到100000。";return}
        sendText = text; saveSettings()
        guard targetName != "请选择会话", !targetName.isEmpty, knownNames.contains(targetName) else {status.stringValue = "请先刷新并选择唯一的会话。";return}
        if mode.selectedSegment == 1 && !previewOnly {armDaily();return}
        prepareSend()
    }
    func prepareSend() {
        generation += 1;let token = generation
        setEditing(false);stateBadge.stringValue = previewOnly ? "● 正在预检" : "● 准备发送"
        status.stringValue = "正在打开并核对所选会话…"
        let preview = previewOnly
        openSelected { [weak self] in
            guard let self = self, self.generation == token else {return}
            self.bindAndStart(preview:preview)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+8) { [weak self] in
            if let self = self, self.generation == token, self.timer == nil {self.finish("准备超时，未发送。请检查抖音是否在前台。")}
        }
    }
    func bindAndStart(preview: Bool = false) {
        guard let seconds = (mode.selectedSegment == 1 ? 1 : SendRate.parse(interval.stringValue)) else {finish("请输入至少0.1秒的发送间隔。");return}
        guard let count = (mode.selectedSegment == 1 ? 1 : Int(limit.stringValue)), (1...100000).contains(count) else {finish("总次数应为1到100000。");return}
        guard AXIsProcessTrusted() else {
            status.stringValue = "尚无辅助功能权限。请在系统设置 > 隐私与安全性 > 辅助功能中允许此控制器，之后重新打开。"
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options); return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).first else {status.stringValue = "请先打开并登录抖音。"; return}
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let editors = walk(root).filter {string($0,"AXRole") == "AXTextArea"}
        guard editors.count == 1 else {finish("请在抖音打开指定会话，并点一下消息输入框。");return}
        let input = editors[0]
        guard isEmpty(input) else {finish("输入框中已有内容，请先清空后再开始。");return}
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
        editor = input; chat = scope; pid = app.processIdentifier; total = dailySending ? 1 : count; sent = 0; awaitingConfirmation = false
        if preview {finish("预检通过：已定位所选会话，未输入、未发送消息。");return}
        lastInspection = Date.distantPast;pendingSince = nil
        progress.stringValue = "已发送：0 / \(total)"
        startButton.isEnabled = false; stopButton.isEnabled = true; interval.isEnabled = false; limit.isEnabled = false; contacts.isEnabled = false; refreshButton.isEnabled = false; message.isEditable = false; saveButton.isEnabled = false
        setEditing(false);stateBadge.stringValue = "● 正在发送";stateBadge.textColor = .systemGreen
        status.stringValue = "运行中：每 \(seconds) 秒一次。点击停止或切换应用可停止。"
        AXUIElementSetAttributeValue(input,"AXFocused" as CFString,kCFBooleanTrue)
        NSApp.yieldActivation(to:app);app.activate(options:[.activateAllWindows])
        flow = SendFlow(message:sendText,interval:seconds,total:total)
        timer = Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) {[weak self] _ in self?.tick()}
    }
    func isEmpty(_ e:AXUIElement)->Bool {MessageRules.emptyEditor(string(e,"AXValue"))}
    func tick() {
        guard let input = editor,let scope = chat,var state = flow else {finish("输入框失效，已停止。");return}
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {finish("已切换应用，自动停止。");return}
        let root = AXUIElementCreateApplication(pid)
        guard let focused = attribute(root,"AXFocusedUIElement"),CFEqual(focused,input),let header = boundHeader,clean(string(header,"AXValue")) == targetName else {finish("输入焦点或会话变化，自动停止。");return}
        let now = Date()
        if now.timeIntervalSince(lastInspection) >= 1 {
            lastInspection = now
            let problem = walk(scope,maxNodes:1000).contains { node in
                MessageRules.failureIndicator(role:string(node,"AXRole"),label:string(node,"AXTitle")+string(node,"AXDescription")+string(node,"AXValue"))
            }
            guard !problem else {finish("检测到发送异常或平台限制，已停止。");return}
        }
        let action = state.step(now:ProcessInfo.processInfo.systemUptime,editor:string(input,"AXValue"));flow = state;sent = state.sent
        switch action {
        case .type:
            guard typeText(sendText,to:pid) else {finish("无法输入消息，已停止。");return}
        case .enter:
            CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:true)?.postToPid(pid)
            CGEvent(keyboardEventSource:nil,virtualKey:36,keyDown:false)?.postToPid(pid)
        case .confirmed: progress.stringValue = "界面发送操作：\(sent) / \(total)"
        case .complete:
            progress.stringValue = "界面发送操作：\(sent) / \(total)";finish("已完成\(sent)次界面发送操作，不代表对方已收取。")
        case .failed(let reason): finish(reason)
        case .wait: break
        }
    }
    func applicationWillTerminate(_ notification:Notification) {if !isPreview {stopClicked();saveSettings()}}
    func windowWillClose(_ notification: Notification) {NSApp.terminate(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {true}
}
let lockPath = NSTemporaryDirectory() + (CommandLine.arguments.contains("--check-layout") ? "douyin-message-assistant-layout.lock" : "douyin-message-assistant.lock")
let lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    exit(0)
}
let application = NSApplication.shared
application.setActivationPolicy(CommandLine.arguments.contains("--check-layout") ? .accessory : .regular)
let controller = Controller()
application.delegate = controller
application.run()
