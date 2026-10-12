; Local pacing settings. The target application decides how events are scored.
global BehaviorWindow := 0, Paused := false, PauseStarted := 0
global BurstEnabled := false, BurstRemaining := 0, BurstFactor := 1.0
global LongPauseEnabled := false, PauseEvery := 100, LongMinMs := 2500, LongMaxMs := 6000
global NextLongPause := 100, LongPauseCount := 0
global CapEnabled := false, CharPerMinute := 240, PaceStarted := 0, HeldTime := 0
global BatchEnabled := false, BatchSize := 300, BatchPrinted := 0, BatchNumber := 1
global RevisionEnabled := false, RevisionEvery := 80, NextRevision := 80, RevisionCount := 0
global Printed := 0, LastDelay := 0

LoadBehaviorSettings() {
    global BurstEnabled, LongPauseEnabled, PauseEvery, LongMinMs, LongMaxMs
    global CapEnabled, CharPerMinute, BatchEnabled, BatchSize, RevisionEnabled, RevisionEvery
    BurstEnabled := ReadSetting("分段变速", 1, 0, 1)
    LongPauseEnabled := ReadSetting("随机长暂停", 1, 0, 1)
    PauseEvery := ReadSetting("平均暂停间隔字符", 100, 10, 10000)
    LongMinMs := ReadSetting("长暂停最短毫秒", 2500, 2100, 60000)
    LongMaxMs := Max(LongMinMs, ReadSetting("长暂停最长毫秒", 6000, 2100, 60000))
    CapEnabled := ReadSetting("平均速度限制", 1, 0, 1)
    CharPerMinute := ReadSetting("每分钟字符上限", 240, 30, 6000)
    BatchEnabled := ReadSetting("分批输入", 0, 0, 1)
    BatchSize := ReadSetting("每批字符数", 300, 10, 10000)
    RevisionEnabled := ReadSetting("前文回选重输", 0, 0, 1)
    RevisionEvery := ReadSetting("平均重输间隔字符", 80, 20, 10000)
}

ReadSetting(key, fallback, minimum, maximum) {
    value := IniRead(ConfigFile, "行为节奏", key, fallback)
    return ValidNumber(value, minimum, maximum) ? Integer(value) : fallback
}

BeginBehavior() {
    global Paused, Printed, BatchPrinted, BatchNumber, RevisionCount, LongPauseCount
    global PaceStarted, HeldTime, NextLongPause, NextRevision, BurstRemaining
    Paused := false, Printed := 0, BatchPrinted := 0, BatchNumber := 1
    RevisionCount := 0, LongPauseCount := 0, HeldTime := 0, BurstRemaining := 0
    PaceStarted := A_TickCount
    NextLongPause := RandomCount(PauseEvery)
    NextRevision := RandomCount(RevisionEvery)
}

RandomCount(average) {
    return Random(Max(1, Round(average * 0.75)), Round(average * 1.25))
}

BehaviorDelay(previous := "") {
    global BurstRemaining, BurstFactor, NextLongPause, LongPauseCount
    delay := PickDelay(previous)
    if BurstEnabled {
        if BurstRemaining <= 0 || previous = " " || previous = "`n" {
            BurstRemaining := Random(5, 14)
            BurstFactor := Random(0.65, 1.7)
        }
        delay := Max(10, Round(delay * BurstFactor))
        BurstRemaining -= 1
    }
    if LongPauseEnabled && Printed >= NextLongPause {
        delay += Random(LongMinMs, LongMaxMs)
        NextLongPause := Printed + RandomCount(PauseEvery)
        LongPauseCount += 1
    }
    if CapEnabled {
        ; Limit the cumulative rate of original output; manual rests are excluded.
        elapsed := A_TickCount - PaceStarted - HeldTime
        delay := Max(delay, Ceil((Printed + 1) * 60000 / CharPerMinute - elapsed))
    }
    return Max(1, delay)
}

ScheduleNext(previous := "") {
    global LastDelay
    if !Running || Paused
        return
    LastDelay := AdvancedPending ? Random(700, 1800) : BehaviorDelay(previous)
    SetTimer TypeNext, -LastDelay
}

RecordCharacter(char) {
    global Printed, BatchPrinted, NextRevision
    Printed += 1
    BatchPrinted += 1
    if RevisionEnabled && !AdvancedEnabled && Printed >= NextRevision {
        RevisitEarlierCharacter()
        NextRevision := Printed + RandomCount(RevisionEvery)
    }
}

RevisitEarlierCharacter() {
    global RevisionCount
    count := Position - 1
    if count < 4 || !WinActive("ahk_id " TargetWindow)
        || (TargetControl && FocusedControl(TargetWindow) != TargetControl)
        return false
    distance := Random(3, Min(12, count))
    index := count - distance + 1
    ; Only single-unit Chinese/ASCII suffixes have predictable cursor movement.
    Loop distance {
        char := Characters[index + A_Index - 1]
        if !RegExMatch(char, "^[A-Za-z0-9\x{4E00}-\x{9FFF} .,!?;:，。！？；：、]$")
            return false
    }
    original := Characters[index]
    if !RegExMatch(original, "^[A-Za-z0-9\x{4E00}-\x{9FFF}]$")
        return false
    ; Finish this short selection-and-replacement transaction before F9 can run.
    Critical "On"
    oldDelay := A_KeyDelay, oldDuration := A_KeyDuration
    try {
        nativeEdit := TargetControl && RegExMatch(WinGetClass("ahk_id " TargetControl), "i)^(Edit|RichEdit)")
        if nativeEdit {
            ; Synchronous selection/replacement avoids mixing queued key events
            ; with control-addressed WM_CHAR messages in standard Windows edits.
            first := Buffer(4), last := Buffer(4)
            SendMessage 0xB0, first.Ptr, last.Ptr, TargetControl
            caret := NumGet(first, 0, "UInt")
            if caret != NumGet(last, 0, "UInt") || caret < distance
                return false
            SendMessage 0xB1, caret - distance, caret - distance + 1, TargetControl
            SendMessage 0xC2, 1, StrPtr(original), TargetControl
            SendMessage 0xB1, caret, caret, TargetControl
        } else {
            SetKeyDelay -1, -1
            SendEvent "{Left " distance "}+{Right}"
            SendText original
            SendEvent "{Right " (distance - 1) "}"
        }
        RevisionCount += 1
    } finally {
        SetKeyDelay oldDelay, oldDuration
        Critical "Off"
    }
    return true
}

PauseTyping(message := "已暂停；保持光标位置，按 F10 继续，F9 结束。") {
    global Paused, PauseStarted
    if !Running || Paused
        return
    Paused := true
    PauseStarted := A_TickCount
    SetTimer TypeNext, 0
    SetTimer WatchFocus, 0
    Notify(message)
}

TogglePause() {
    global Paused, HeldTime, BatchPrinted, BatchNumber
    if !Running
        return
    if !Paused {
        PauseTyping()
        return
    }
    if !WinActive("ahk_id " TargetWindow)
        || (TargetControl && FocusedControl(TargetWindow) != TargetControl) {
        Notify("请回到原输入窗口和输入框，再按 F10。")
        return
    }
    HeldTime += A_TickCount - PauseStarted
    Paused := false
    if BatchEnabled && BatchPrinted >= BatchSize {
        BatchPrinted := 0
        BatchNumber += 1
    }
    SetTimer WatchFocus, 30
    ScheduleNext()
}

ShowBehaviorSettings() {
    global BehaviorWindow
    if Running
        StopTyping()
    if BehaviorWindow {
        BehaviorWindow.Show()
        return
    }
    win := Gui(, "更多行为节奏设置")
    BehaviorWindow := win
    win.SetFont("s10", "Microsoft YaHei UI")
    tabs := win.AddTab3("w550 h410", ["节奏与速度", "长暂停与分批", "前文重输"])
    tabs.UseTab(1)
    burst := win.AddCheckbox("x30 y48", "分段变速：短段内相近，段与段之间快慢变化")
    burst.Value := BurstEnabled
    cap := win.AddCheckbox("x30 y90", "限制从本次开始累计的平均输入速度")
    cap.Value := CapEnabled
    win.AddText("x30 y125", "每分钟原文字符上限（30～6000）")
    rate := win.AddEdit("x30 y152 w110 Number", CharPerMinute)
    win.AddText("x30 y195 w495", "这里按字符计数，中文每字计一字符；英文不按单词计数。`n人工暂停时间不计入平均速度。自动长暂停计入。`nF10 暂停／继续；F9 结束并清除续输位置。")
    win.AddText("x30 y290 w495", "基础固定／随机间隔与标点停顿在主设置中调整。`n分段变速会在基础间隔上乘以随机系数；速度上限可能进一步延长间隔。")
    tabs.UseTab(2)
    longPause := win.AddCheckbox("x30 y48", "随机长暂停（每次严格超过两秒）")
    longPause.Value := LongPauseEnabled
    win.AddText("x30 y80", "平均每多少字符暂停一次（10～10000）")
    frequency := win.AddEdit("x30 y106 w100 Number", PauseEvery)
    win.AddText("x30 y142", "暂停范围，毫秒（2100～60000）")
    minLong := win.AddEdit("x30 y168 w100 Number", LongMinMs)
    win.AddText("x143 y172", "至")
    maxLong := win.AddEdit("x170 y168 w100 Number", LongMaxMs)
    batch := win.AddCheckbox("x30 y215", "分批输入：每批结束等待你按 F10 继续")
    batch.Value := BatchEnabled
    win.AddText("x30 y245", "每批字符数（10～10000）")
    size := win.AddEdit("x30 y271 w100 Number", BatchSize)
    win.AddText("x30 y315 w495", "分批休息不会替目标网站创建新会话。暂停时可以切换窗口，继续前需回到原输入框并保持光标位置。关闭工具后不保留正文或续输位置。")
    tabs.UseTab(3)
    revision := win.AddCheckbox("x30 y48", "前文回选重输（默认关闭，会移动光标）")
    revision.Value := RevisionEnabled
    win.AddText("x30 y84", "平均每多少字符执行一次（20～10000）")
    reviseEvery := win.AddEdit("x30 y110 w100 Number", RevisionEvery)
    win.AddText("x30 y160 w495", "在已输入末尾前 3～12 个字符处，选中一个中英文字符并原样重输，再把光标移回末尾。最终文字应保持一致。`n`n自动跳过含 emoji、组合字符或换行的相关片段。富文本、自动补全及特殊编辑器可能改变光标行为，请先在你的目标软件中用短文本试验。`n`n这是模拟编辑动作，不是实际改写内容；不能保证网站计入修订分数。")
    tabs.UseTab()
    win.AddButton("x15 y440 w170 h32 Default", "保存并收起").OnEvent("Click", SaveBehavior)
    win.AddButton("x200 y440 w200 h32", "高级句段修订（可选）").OnEvent("Click", (*) => ShowAdvancedSettings())
    win.OnEvent("Close", (*) => win.Hide())
    win.Show()

    SaveBehavior(*) {
        global BurstEnabled, CapEnabled, CharPerMinute, LongPauseEnabled, PauseEvery
        global LongMinMs, LongMaxMs, BatchEnabled, BatchSize, RevisionEnabled, RevisionEvery
        if !ValidNumber(rate.Value, 30, 6000) || !ValidNumber(frequency.Value, 10, 10000)
            || !ValidNumber(minLong.Value, 2100, 60000) || !ValidNumber(maxLong.Value, 2100, 60000)
            || Integer(minLong.Value) > Integer(maxLong.Value) || !ValidNumber(size.Value, 10, 10000)
            || !ValidNumber(reviseEvery.Value, 20, 10000) {
            MsgBox "请按标注范围填写整数，暂停下限不能大于上限。", "设置检查"
            return
        }
        BurstEnabled := burst.Value, CapEnabled := cap.Value, CharPerMinute := Integer(rate.Value)
        LongPauseEnabled := longPause.Value, PauseEvery := Integer(frequency.Value)
        LongMinMs := Integer(minLong.Value), LongMaxMs := Integer(maxLong.Value)
        BatchEnabled := batch.Value, BatchSize := Integer(size.Value)
        RevisionEnabled := revision.Value, RevisionEvery := Integer(reviseEvery.Value)
        values := Map("分段变速", BurstEnabled, "随机长暂停", LongPauseEnabled,
            "平均暂停间隔字符", PauseEvery, "长暂停最短毫秒", LongMinMs, "长暂停最长毫秒", LongMaxMs,
            "平均速度限制", CapEnabled, "每分钟字符上限", CharPerMinute,
            "分批输入", BatchEnabled, "每批字符数", BatchSize,
            "前文回选重输", RevisionEnabled, "平均重输间隔字符", RevisionEvery)
        for key, value in values
            IniWrite value, ConfigFile, "行为节奏", key
        win.Hide()
        Notify("行为节奏设置已保存；F8 开始，F10 暂停／继续，F9 结束。")
    }
}
