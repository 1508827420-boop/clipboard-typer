#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
if !A_Args.Length || A_Args[1] != "--test"
    ExitApp
if FileExist("验收结果.txt")
    FileDelete "验收结果.txt"
if !FileExist(A_ScriptDir "\输入工具.ahk") {
    FileAppend "FAIL: 输入工具尚未实现`n", "验收结果.txt", "UTF-8"
    ExitApp 1
}
#Include *i 输入工具.ahk

RunChecks() {
    global Running, Cancelled, DelayMs, NewlineMode
    global TimingMode, MinDelayMs, MaxDelayMs, PunctuationPause, PauseMinMs, PauseMaxMs
    global BurstEnabled, LongPauseEnabled, PauseEvery, LongMinMs, LongMaxMs, NextLongPause
    global CapEnabled, CharPerMinute, PaceStarted, HeldTime, Printed, Paused
    global BatchEnabled, BatchSize, BatchNumber, RevisionEnabled, RevisionEvery, RevisionCount
    output := ""
    testGui := Gui(, "键盘输入工具独立验收")
    field := testGui.AddEdit("w500 h150 Multi")
    testGui.Show()
    WinActivate "ahk_id " testGui.Hwnd
    WinWaitActive "ahk_id " testGui.Hwnd, , 3
    field.Focus()
    DelayMs := 20
    NewlineMode := "stop"
    original := ClipboardAll()
    try {
        TimingMode := "random", MinDelayMs := 30, MaxDelayMs := 120
        PunctuationPause := false
        seen := Map(), inRange := true
        Loop 100 {
            delay := PickDelay()
            seen[delay] := true
            inRange := inRange && delay >= 30 && delay <= 120
        }
        Check(inRange && seen.Count > 1, "随机间隔在设定范围内且产生变化", &output)
        TimingMode := "fixed", DelayMs := 40
        Check(PickDelay() = 40, "固定间隔保持准确", &output)
        PunctuationPause := true, PauseMinMs := 200, PauseMaxMs := 600
        pauseOK := true
        Loop 100 {
            delay := PickDelay("。")
            pauseOK := pauseOK && delay >= 240 && delay <= 640
        }
        Check(pauseOK && PickDelay("字") = 40, "仅在标点后添加设定范围的停顿", &output)
        Check(!ValidNumber("120", 10, 100) && !ValidNumber("abc", 10, 100)
            && ValidNumber("40", 10, 100), "速度参数范围校验", &output)
        BeginBehavior()
        PunctuationPause := false, BurstEnabled := true
        burstValues := Map()
        Loop 40
            burstValues[BehaviorDelay("字")] := true
        Check(burstValues.Count > 1, "分段节奏会改变间隔", &output)
        BurstEnabled := false, LongPauseEnabled := true
        LongMinMs := 2100, LongMaxMs := 2200, Printed := 10, NextLongPause := 10
        longDelay := BehaviorDelay("字")
        Check(longDelay >= 2140 && longDelay <= 2240 && NextLongPause > Printed,
            "长暂停超过两秒且重新安排下次暂停", &output)
        LongPauseEnabled := false, CapEnabled := true, CharPerMinute := 240
        PaceStarted := A_TickCount, HeldTime := 0, Printed := 9
        capDelay := BehaviorDelay("字")
        Check(capDelay >= 2400 && capDelay <= 2500, "平均速度限制延长输入间隔", &output)
        CapEnabled := false
        TimingMode := "random", MinDelayMs := 10, MaxDelayMs := 35
        PunctuationPause := false
        sample := "中文 English 123 !^+#{} 😀"
        A_Clipboard := sample
        StartTyping()
        WaitDone()
        Check(field.Value = sample, "中文、英文、符号和 emoji 输入", &output)
        TimingMode := "fixed", DelayMs := 20
        Check(A_Clipboard = sample, "剪贴板保持不变", &output)
        field.Value := ""
        field.Focus()
        A_Clipboard := "第一行`r`n第二行"
        StartTyping()
        WaitDone()
        Check(field.Value = "第一行", "默认遇到换行停止", &output)
        field.Value := ""
        field.Focus()
        A_Clipboard := "甲`t乙"
        StartTyping()
        WaitDone()
        Check(field.Value = "甲", "遇到制表符停止，不切换输入框", &output)
        field.Value := ""
        field.Focus()
        NewlineMode := "enter"
        A_Clipboard := "第一行`n第二行"
        StartTyping()
        WaitDone()
        Check(StrReplace(field.Value, "`r", "") = "第一行`n第二行", "可选 Enter 多行输入", &output)
        NewlineMode := "stop"
        field.Value := ""
        field.Focus()
        A_Clipboard := StrRepeat("停止测试", 40)
        StartTyping()
        Sleep 100
        StopTyping()
        Sleep 50
        saved := field.Value
        Sleep 200
        Check(!Running && field.Value = saved && StrLen(saved) < 160, "停止后不再输入", &output)
        field.Value := ""
        field.Focus()
        LongPauseEnabled := true, LongMinMs := 2100, LongMaxMs := 2200
        A_Clipboard := "长暂停期间停止测试"
        StartTyping()
        NextLongPause := 1
        Sleep 120
        Check(Printed = 1 && Running, "实际长暂停期间不继续输出", &output)
        StopTyping()
        saved := field.Value
        Sleep 100
        Check(!Running && field.Value = saved, "长暂停期间仍可立即停止", &output)
        LongPauseEnabled := false
        field.Value := ""
        field.Focus()
        A_Clipboard := "暂停后继续完整输入"
        StartTyping()
        Sleep 70
        PauseTyping()
        Sleep 50
        pausedValue := field.Value
        Sleep 100
        Check(Paused && field.Value = pausedValue, "暂停期间不输出字符", &output)
        TogglePause()
        WaitDone()
        Check(field.Value = A_Clipboard, "继续输入无丢字无重复", &output)
        field.Value := ""
        field.Focus()
        BatchEnabled := true, BatchSize := 10
        A_Clipboard := "abcdefghijklmnopqrstuvwxyz"
        StartTyping()
        WaitPaused()
        Check(StrLen(field.Value) = 10, "分批输入到指定字数暂停", &output)
        TogglePause()
        WaitPaused()
        TogglePause()
        WaitDone()
        Check(field.Value = A_Clipboard && BatchNumber = 3, "分三批完成且正文保持一致", &output)
        BatchEnabled := false
        field.Value := ""
        field.Focus()
        RevisionEnabled := true, RevisionEvery := 20
        A_Clipboard := StrRepeat("中文English123", 6)
        StartTyping()
        WaitDone()
        Check(RevisionCount > 0 && field.Value = A_Clipboard, "前文回选重输后正文不变且光标归位", &output)
        if field.Value != A_Clipboard
            output .= "重输诊断: [" field.Value "]`n"
        RevisionEnabled := false
        field.Value := ""
        field.Focus()
        A_Clipboard := StrRepeat("窗口测试", 40)
        StartTyping()
        Sleep 100
        other := Gui(, "验收切换窗口")
        otherField := other.AddEdit("w300")
        other.Show()
        WinActivate "ahk_id " other.Hwnd
        WinWaitActive "ahk_id " other.Hwnd, , 3
        otherField.Focus()
        Sleep 200
        Check(!Running && otherField.Value = "", "切换窗口自动停止", &output)
        other.Destroy()
        testGui.Destroy()
        A_Clipboard := original
        FileAppend output, "验收结果.txt", "UTF-8"
        ExitApp InStr(output, "FAIL") ? 1 : 0
    } catch as err {
        A_Clipboard := original
        FileAppend output "FAIL: " err.Message " at " err.Line "`n", "验收结果.txt", "UTF-8"
        ExitApp 1
    } finally {
        A_Clipboard := original
    }
}
WaitPaused() {
    started := A_TickCount
    while Running && !Paused && A_TickCount - started < 4000
        Sleep 20
    if !Paused
        throw Error("分批暂停超时")
    Sleep 50
}
WaitDone() {
    global Running
    started := A_TickCount
    while Running && A_TickCount - started < 6000
        Sleep 20
    if Running
        throw Error("输入超时")
    Sleep 50
}
Check(condition, label, &output) {
    output .= (condition ? "PASS: " : "FAIL: ") label "`n"
}
StrRepeat(value, count) {
    result := ""
    Loop count
        result .= value
    return result
}
RunChecks()
