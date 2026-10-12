#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

global Running := false, Cancelled := false, Characters := [], Position := 1
global TargetWindow := 0, TargetControl := 0, DelayMs := 40, NewlineMode := "stop"
global SettingsWindow := 0
global TimingMode := "random", MinDelayMs := 30, MaxDelayMs := 120
global PunctuationPause := true, PauseMinMs := 200, PauseMaxMs := 600
global LastStatus := ""
global Testing := A_Args.Length && A_Args[1] = "--test"
global ConfigFile := A_ScriptDir "\设置.ini"
#Include 行为节奏.ahk
#Include 高级修订.ahk

if !Testing {
    DelayMs := Max(10, Min(500, Integer(IniRead(ConfigFile, "输入", "每字间隔毫秒", "40"))))
    NewlineMode := IniRead(ConfigFile, "输入", "换行方式", "stop")
    TimingMode := IniRead(ConfigFile, "输入", "速度模式", "random")
    MinDelayMs := Max(10, Min(2000, Integer(IniRead(ConfigFile, "输入", "随机最短毫秒", "30"))))
    MaxDelayMs := Max(MinDelayMs, Min(2000, Integer(IniRead(ConfigFile, "输入", "随机最长毫秒", "120"))))
    PunctuationPause := IniRead(ConfigFile, "输入", "标点停顿", "1") = "1"
    PauseMinMs := Max(0, Min(5000, Integer(IniRead(ConfigFile, "输入", "标点最短毫秒", "200"))))
    PauseMaxMs := Max(PauseMinMs, Min(5000, Integer(IniRead(ConfigFile, "输入", "标点最长毫秒", "600"))))
    A_TrayMenu.Delete()
    A_TrayMenu.Add("设置与使用说明", (*) => ShowSettings())
    A_TrayMenu.Add("停止输入", (*) => StopTyping())
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出", (*) => ExitApp())
    A_IconTip := "键盘输入工具 · F8 开始 · F9 停止"
    ShowSettings()
    LoadBehaviorSettings()
}

StartTyping() {
    global Running, Cancelled, Characters, Position, TargetWindow, TargetControl
    if Running
        return
    text := A_Clipboard
    if text = "" {
        Notify("剪贴板没有文字，请先复制。")
        return
    }
    if (SettingsWindow && WinActive("ahk_id " SettingsWindow.Hwnd))
        || (BehaviorWindow && WinActive("ahk_id " BehaviorWindow.Hwnd))
        || (AdvancedWindow && WinActive("ahk_id " AdvancedWindow.Hwnd)) {
        Notify("请先点击要输入文字的目标输入框，再按 F8。")
        return
    }
    ; CRLF is one line break. Preserve surrogate pairs such as emoji.
    text := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
    try {
        text := PrepareAdvanced(text)
    } catch as err {
        Notify(err.Message)
        return
    }
    Characters := []
    offset := 1
    while offset <= StrLen(text) {
        char := SubStr(text, offset, 1)
        code := Ord(char)
        if code >= 0xD800 && code <= 0xDBFF && offset < StrLen(text) {
            low := Ord(SubStr(text, offset + 1, 1))
            if low >= 0xDC00 && low <= 0xDFFF {
                char .= SubStr(text, offset + 1, 1)
                offset += 1
            }
        }
        Characters.Push(char)
        offset += 1
    }
    TargetWindow := WinExist("A")
    if !TargetWindow {
        Notify("没有找到活动窗口，请先点击目标输入框。")
        return
    }
    TargetControl := FocusedControl(TargetWindow)
    Position := 1
    Cancelled := false
    Running := true
    BeginBehavior()
    ; One-shot timers choose a fresh interval after each character.
    SetTimer WatchFocus, 30
    ScheduleNext()
}

PickDelay(previous := "") {
    delay := TimingMode = "random" ? Random(MinDelayMs, MaxDelayMs) : DelayMs
    if PunctuationPause && previous != "" && InStr("，。！？；：、,.!?;:`n", previous)
        delay += Random(PauseMinMs, PauseMaxMs)
    return Max(1, delay)
}

WatchFocus() {
    if Running && !Paused && (!WinActive("ahk_id " TargetWindow)
        || (TargetControl && FocusedControl(TargetWindow) != TargetControl))
        FinishTyping("焦点已改变，输入已停止。")
}

TypeNext() {
    global Running, Cancelled, Position, Characters
    global AdvancedPending, AdvancedNext
    if !Running || Cancelled || Paused
        return
    if !WinActive("ahk_id " TargetWindow)
        || (TargetControl && FocusedControl(TargetWindow) != TargetControl) {
        FinishTyping("焦点已改变，输入已停止。")
        return
    }
    if AdvancedPending {
        pending := AdvancedPending
        AdvancedPending := 0
        if !ApplyAdvancedRevision(pending) {
            FinishTyping("高级修订未完成，已停止；请检查光标和正文中的草稿。")
            return
        }
        AdvancedNext := UnitCount(StreamPart(1, Position - 1)) + Random(AdvancedEveryMin, AdvancedEveryMax)
    }
    if Position > Characters.Length {
        FinishTyping("输入完成。")
        return
    }
    char := Characters[Position]
    Position += 1
    if char = "`n" {
        if NewlineMode = "shift-enter"
            SendEvent "+{Enter}"
        else if NewlineMode = "enter"
            SendEvent "{Enter}"
        else
            FinishTyping("遇到换行，已停止。可在设置中更改换行方式。")
    } else if Ord(char) < 32 || Ord(char) = 127 {
        FinishTyping("遇到制表符或控制字符，已停止。")
    } else {
        SendTargetText(char)
    }
    if Running {
        RecordCharacter(char)
        if AdvancedEnabled && !MaybeAdvancedRevision(Position > Characters.Length) {
            FinishTyping("高级修订未完成，已停止。请检查光标位置和目标编辑器；正文可能仍有草稿。")
            return
        }
        if Position > Characters.Length
            FinishTyping("输入完成。")
        else if BatchEnabled && BatchPrinted >= BatchSize
            PauseTyping("本批已完成，休息后回到原输入框按 F10 继续。")
        else
            ScheduleNext(char)
    }
}

SendTargetText(text) {
    ; Standard edit controls accept text addressed to their HWND. This keeps
    ; already queued text bound to the original field during a focus change.
    if TargetControl {
        try {
            className := WinGetClass("ahk_id " TargetControl)
            if RegExMatch(className, "i)^(Edit|RichEdit)") {
                Loop StrLen(text)
                    SendMessage 0x102, Ord(SubStr(text, A_Index, 1)), 1, TargetControl
                return
            }
        }
    }
    SendText text
}

FocusedControl(window) {
    try {
        name := ControlGetFocus("ahk_id " window)
        return name ? ControlGetHwnd(name, "ahk_id " window) : 0
    } catch {
        return 0
    }
}

StopTyping() {
    global Cancelled
    Cancelled := true
    FinishTyping("已停止输入。")
}

FinishTyping(message) {
    global Running, Characters, Paused
    global AdvancedPending
    SetTimer TypeNext, 0
    SetTimer WatchFocus, 0
    Running := false
    Paused := false
    AdvancedPending := 0
    Characters := []
    Notify(message)
}

Notify(message) {
    global LastStatus
    LastStatus := message
    if !Testing {
        ToolTip message
        SetTimer (() => ToolTip()), -2200
    }
}

ShowSettings() {
    global SettingsWindow
    if Running
        StopTyping()
    if SettingsWindow {
        SettingsWindow.Show()
        return
    }
    win := Gui(, "键盘输入工具")
    SettingsWindow := win
    win.SetFont("s11", "Microsoft YaHei UI")
    win.AddText("w480", "复制文字 → 点击目标输入框 → F8 开始。`nF10 暂停／继续；F9 结束；Ctrl + Alt + F8 设置。")
    win.AddText("y+18", "速度模式（间隔越大，输入越慢）")
    mode := win.AddDropDownList("w240", ["固定间隔", "随机间隔（每字重新随机）"])
    mode.Choose(TimingMode = "random" ? 2 : 1)
    win.AddText("y+12", "固定间隔：10～500 毫秒")
    speed := win.AddEdit("w100 Number", DelayMs)
    win.AddText("y+12", "随机间隔范围：10～2000 毫秒")
    minSpeed := win.AddEdit("w100 Number", MinDelayMs)
    win.AddText("x+10 yp+4", "至")
    maxSpeed := win.AddEdit("x+10 yp-4 w100 Number", MaxDelayMs)
    pause := win.AddCheckbox("xm y+16", "标点后额外停顿（两种速度模式均可使用）")
    pause.Value := PunctuationPause
    win.AddText("y+10", "额外停顿范围：0～5000 毫秒")
    minPause := win.AddEdit("w100 Number", PauseMinMs)
    win.AddText("x+10 yp+4", "至")
    maxPause := win.AddEdit("x+10 yp-4 w100 Number", PauseMaxMs)
    mode.OnEvent("Change", UpdateEnabled)
    pause.OnEvent("Click", UpdateEnabled)
    UpdateEnabled()
    win.AddText("xm y+15", "遇到换行时")
    breaks := win.AddDropDownList("w480", ["停止输入（默认，避免意外提交）", "发送 Shift + Enter（适合部分聊天框）", "发送 Enter（可能提交消息或表单）"])
    breaks.Choose(NewlineMode = "shift-enter" ? 2 : NewlineMode = "enter" ? 3 : 1)
    win.AddText("w480 y+18", "输入时切换窗口会自动停止。普通桌面控件中，切换输入框也会停止；浏览器内切换输入框未必能识别。`n请保持光标位置，必要时按 F9。只能输入纯文字。")
    button := win.AddButton("w160 y+18 Default", "保存并收起")
    button.OnEvent("Click", Save)
    win.AddButton("x+14 yp w180", "更多行为节奏设置").OnEvent("Click", (*) => ShowBehaviorSettings())
    win.OnEvent("Close", (*) => win.Hide())
    win.Show()

    UpdateEnabled(*) {
        speed.Enabled := mode.Value = 1
        minSpeed.Enabled := maxSpeed.Enabled := mode.Value = 2
        minPause.Enabled := maxPause.Enabled := pause.Value
    }

    Save(*) {
        global DelayMs, NewlineMode, TimingMode, MinDelayMs, MaxDelayMs
        global PunctuationPause, PauseMinMs, PauseMaxMs
        if !ValidNumber(speed.Value, 10, 500)
            || !ValidNumber(minSpeed.Value, 10, 2000) || !ValidNumber(maxSpeed.Value, 10, 2000)
            || Integer(minSpeed.Value) > Integer(maxSpeed.Value)
            || !ValidNumber(minPause.Value, 0, 5000) || !ValidNumber(maxPause.Value, 0, 5000)
            || Integer(minPause.Value) > Integer(maxPause.Value) {
            MsgBox "请按标注范围填写整数，范围下限不能大于上限。", "输入间隔"
            return
        }
        DelayMs := Integer(speed.Value)
        TimingMode := mode.Value = 2 ? "random" : "fixed"
        MinDelayMs := Integer(minSpeed.Value), MaxDelayMs := Integer(maxSpeed.Value)
        PunctuationPause := pause.Value
        PauseMinMs := Integer(minPause.Value), PauseMaxMs := Integer(maxPause.Value)
        NewlineMode := ["stop", "shift-enter", "enter"][breaks.Value]
        IniWrite DelayMs, ConfigFile, "输入", "每字间隔毫秒"
        IniWrite NewlineMode, ConfigFile, "输入", "换行方式"
        IniWrite TimingMode, ConfigFile, "输入", "速度模式"
        IniWrite MinDelayMs, ConfigFile, "输入", "随机最短毫秒"
        IniWrite MaxDelayMs, ConfigFile, "输入", "随机最长毫秒"
        IniWrite PunctuationPause, ConfigFile, "输入", "标点停顿"
        IniWrite PauseMinMs, ConfigFile, "输入", "标点最短毫秒"
        IniWrite PauseMaxMs, ConfigFile, "输入", "标点最长毫秒"
        win.Hide()
        Notify("已就绪。点击目标输入框后按 F8，按 F9 停止。")
    }
}

ValidNumber(value, minimum, maximum) {
    return RegExMatch(value, "^\d+$") && Integer(value) >= minimum && Integer(value) <= maximum
}

#HotIf !Testing
F8::{
    KeyWait "F8"
    StartTyping()
}
^!F8::ShowSettings()
#HotIf Running && !Testing
F9::StopTyping()
F10::{
    KeyWait "F10"
    TogglePause()
}
#HotIf
