; Draft/final pairs are kept in memory, never written to the INI file.
global AdvancedEnabled := false, AdvancedPairsText := "", AdvancedWindow := 0
global AdvancedUnit := "words", AdvancedEveryMin := 25, AdvancedEveryMax := 45
global AdvancedBackMin := 20, AdvancedBackMax := 30, AdvancedSizeMin := 5, AdvancedSizeMax := 10
global AdvancedEvents := [], AdvancedNext := 0, AdvancedCount := 0
global AdvancedPending := 0
global AdvancedMode := "draft", AdvancedActive := 0, RevisionActions := 0, RevisionPrevious := ""

TextCharacters(text) {
    chars := [], index := 1
    while index <= StrLen(text) {
        char := SubStr(text, index, 1)
        code := Ord(char)
        if code >= 0xD800 && code <= 0xDBFF && index < StrLen(text) {
            low := Ord(SubStr(text, index + 1, 1))
            if low >= 0xDC00 && low <= 0xDFFF
                char .= SubStr(text, ++index, 1)
        }
        chars.Push(char)
        index += 1
    }
    return chars
}

UnitCount(text) {
    pattern := AdvancedUnit = "chars" ? "\S" : "[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"
    count := 0, offset := 1
    while RegExMatch(text, pattern, &match, offset) {
        count += 1
        offset := match.Pos + match.Len
    }
    return count
}

ParseAdvancedPairs(text) {
    pairs := []
    for line in StrSplit(StrReplace(text, "`r", ""), "`n") {
        if Trim(line) = ""
            continue
        parts := StrSplit(line, "=>")
        if parts.Length != 2 || Trim(parts[1]) = "" || Trim(parts[2]) = ""
            throw Error("每行填写：草稿片段 => 定稿片段。片段中不能包含 =>。")
        draft := Trim(parts[1]), final := Trim(parts[2])
        size := UnitCount(final)
        if size < AdvancedSizeMin || size > AdvancedSizeMax
            throw Error("定稿片段长度必须在 " AdvancedSizeMin "～" AdvancedSizeMax " 个所选单位之间。")
        if draft = final
            throw Error("草稿与定稿应有实际文字差异；原样重输请选择定稿删除后重输模式。")
        for existing in pairs
            if existing.Final = final
                throw Error("同一定稿片段不能重复配置。")
        pairs.Push({Draft: draft, Final: final})
    }
    if !pairs.Length
        throw Error("请先填写至少一组草稿与定稿。")
    return pairs
}

PrepareAdvanced(finalText) {
    global AdvancedEvents, AdvancedCount, AdvancedNext, AdvancedPending, AdvancedActive, RevisionActions
    AdvancedEvents := [], AdvancedCount := 0, AdvancedPending := 0, AdvancedActive := 0, RevisionActions := 0
    AdvancedNext := Random(AdvancedEveryMin, AdvancedEveryMax)
    if !AdvancedEnabled
        return finalText
    if AdvancedMode = "repeat" {
        PrepareRepeatEvents(finalText)
        return finalText
    }
    pairs := ParseAdvancedPairs(AdvancedPairsText)
    result := "", offset := 1
    ; Match only original final text, with longest matching phrase taking priority.
    while offset <= StrLen(finalText) {
        selected := 0
        for pair in pairs {
            if SubStr(finalText, offset, StrLen(pair.Final)) == pair.Final
                && (!selected || StrLen(pair.Final) > StrLen(selected.Final))
                selected := pair
        }
        if selected {
            start := TextCharacters(result).Length + 1
            result .= selected.Draft
            ending := TextCharacters(result).Length
            AdvancedEvents.Push({Start: start, End: ending, Draft: selected.Draft,
                Final: selected.Final, Done: false, Back: Random(AdvancedBackMin, AdvancedBackMax)})
            offset += StrLen(selected.Final)
        } else {
            ; Copy a whole Unicode character, including surrogate pairs.
            chars := TextCharacters(SubStr(finalText, offset, 2))
            result .= chars[1]
            offset += StrLen(chars[1])
        }
    }
    if !AdvancedEvents.Length
        throw Error("剪贴板定稿中未找到配置的定稿片段，未开始输入。")
    return result
}

PrepareRepeatEvents(text) {
    offset := 1
    ; Prefer complete sentences. For long sentences choose one word/character span.
    while RegExMatch(text, "[^.!?。！？\r\n]+[.!?。！？]?", &sentence, offset) {
        segment := sentence[0], trimmed := Trim(segment)
        leading := StrLen(segment) - StrLen(LTrim(segment))
        begin := sentence.Pos + leading
        size := UnitCount(trimmed)
        if size >= AdvancedSizeMin {
            if size > AdvancedSizeMax {
                units := [], at := 1
                pattern := AdvancedUnit = "chars" ? "\S" : "[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"
                while RegExMatch(trimmed, pattern, &word, at) {
                    units.Push({Start: word.Pos, End: word.Pos + word.Len - 1})
                    at := word.Pos + word.Len
                }
                width := Random(AdvancedSizeMin, AdvancedSizeMax)
                first := Random(1, units.Length - width + 1)
                startOffset := units[first].Start
                trimmed := SubStr(trimmed, startOffset, units[first + width - 1].End - startOffset + 1)
                begin += startOffset - 1
            }
            start := TextCharacters(SubStr(text, 1, begin - 1)).Length + 1
            ending := start + TextCharacters(trimmed).Length - 1
            AdvancedEvents.Push({Start: start, End: ending, Draft: trimmed, Final: trimmed,
                Done: false, Back: Random(AdvancedBackMin, AdvancedBackMax)})
        }
        offset := sentence.Pos + sentence.Len
    }
}

StreamPart(first, last) {
    result := ""
    if last < first
        return result
    Loop last - first + 1
        result .= Characters[first + A_Index - 1]
    return result
}

MaybeAdvancedRevision(force := false) {
    global AdvancedNext, AdvancedPending
    if !AdvancedEnabled
        return true
    if force && AdvancedMode = "repeat" {
        ; Repeating final text needs no restoration pass over every sentence.
        ; A short task without a periodic revision gets at most one final revisit.
        if AdvancedCount = 0 {
            Loop AdvancedEvents.Length {
                event := AdvancedEvents[AdvancedEvents.Length - A_Index + 1]
                if !event.Done && event.End < Position {
                    AdvancedPending := event
                    break
                }
            }
        }
        return true
    }
    units := UnitCount(StreamPart(1, Position - 1))
    if !force && units < AdvancedNext
        return true
    for event in AdvancedEvents {
        if event.Done || event.End >= Position
            continue
        back := UnitCount(StreamPart(event.Start, Position - 1))
        if !force && (back < event.Back || back > AdvancedBackMax)
            continue
        AdvancedPending := event
        return true
    }
    return true
}

BeginAdvancedRevision(event) {
    global AdvancedActive
    if !WinActive("ahk_id " TargetWindow)
        || (TargetControl && FocusedControl(TargetWindow) != TargetControl)
        return false
    suffix := StreamPart(event.End + 1, Position - 1)
    try {
        native := TargetControl && RegExMatch(WinGetClass("ahk_id " TargetControl), "i)^Edit$")
        if native {
            ; Native Edit caret offsets count CRLF as two UTF-16 units.
            tail := StrReplace(event.Draft suffix, "`n", "`r`n")
            first := Buffer(4), last := Buffer(4)
            SendMessage 0xB0, first.Ptr, last.Ptr, TargetControl
            caret := NumGet(first, 0, "UInt")
            start := caret - StrLen(tail)
            if caret != NumGet(last, 0, "UInt") || start < 0
                return false
            content := ControlGetText(TargetControl)
            if !(SubStr(content, start + 1, StrLen(tail)) == tail)
                return false
            editCaret := start + StrLen(event.Draft)
            SendMessage 0xB1, editCaret, editCaret, TargetControl
        } else {
            ; Unknown editors: only single-unit ASCII/Chinese cursor steps supported.
            if !RegExMatch(event.Draft suffix event.Final, "^[\x{20}-\x{7E}\x{4E00}-\x{9FFF}，。！？；：、]+$")
                return false
            if StrLen(suffix)
                SendEvent "{Left " StrLen(suffix) "}"
        }
        AdvancedActive := {Event: event, Native: native, Phase: "delete",
            DeleteChars: TextCharacters(event.Draft), DeleteIndex: TextCharacters(event.Draft).Length,
            InputChars: TextCharacters(event.Final), InputIndex: 1, Suffix: suffix,
            ExpectedText: native ? content : "", ExpectedCaret: native ? editCaret : 0,
            ReturnCaret: native ? caret + StrLen(event.Final) - StrLen(event.Draft) : 0}
        return true
    } catch {
        return false
    }
}

StepAdvancedRevision() {
    global AdvancedActive, RevisionActions, RevisionPrevious
    state := AdvancedActive
    if !state
        return false
    Critical "On"
    try {
        if state.Native {
            first := Buffer(4), last := Buffer(4)
            SendMessage 0xB0, first.Ptr, last.Ptr, TargetControl
            if NumGet(first, 0, "UInt") != state.ExpectedCaret || NumGet(last, 0, "UInt") != state.ExpectedCaret
                || !(ControlGetText(TargetControl) == state.ExpectedText)
                return false
        }
        RevisionPrevious := ""
        if state.Phase = "delete" {
            char := state.DeleteChars[state.DeleteIndex]
            if state.Native {
                start := state.ExpectedCaret - StrLen(char)
                ; Select only one Unicode character, then send one Backspace.
                SendMessage 0xB1, start, state.ExpectedCaret, TargetControl
                SendMessage 0x102, 8, 1, TargetControl
                state.ExpectedText := SubStr(state.ExpectedText, 1, start) SubStr(state.ExpectedText, state.ExpectedCaret + 1)
                state.ExpectedCaret := start
            } else
                SendEvent "{Backspace}"
            state.DeleteIndex -= 1
            if state.DeleteIndex = 0
                state.Phase := "input"
        } else {
            char := state.InputChars[state.InputIndex]
            SendTargetText(char)
            if state.Native {
                state.ExpectedText := SubStr(state.ExpectedText, 1, state.ExpectedCaret) char SubStr(state.ExpectedText, state.ExpectedCaret + 1)
                state.ExpectedCaret += StrLen(char)
            }
            RevisionPrevious := char
            state.InputIndex += 1
        }
        RevisionActions += 1
        if state.Phase = "input" && state.InputIndex > state.InputChars.Length {
            if state.Native
                SendMessage 0xB1, state.ReturnCaret, state.ReturnCaret, TargetControl
            else if StrLen(state.Suffix)
                SendEvent "{Right " StrLen(state.Suffix) "}"
            CompleteAdvancedRevision(state.Event)
            AdvancedActive := 0
        }
        return true
    } catch {
        return false
    } finally {
        Critical "Off"
    }
}

CompleteAdvancedRevision(event) {
    global Characters, Position, AdvancedCount, AdvancedNext
    replacement := TextCharacters(event.Final)
    delta := replacement.Length - (event.End - event.Start + 1)
    updated := TextCharacters(StreamPart(1, event.Start - 1) event.Final StreamPart(event.End + 1, Characters.Length))
    Characters := updated
    Position += delta
    event.Done := true
    for other in AdvancedEvents {
        if !other.Done && other.Start > event.End {
            other.Start += delta
            other.End += delta
        }
    }
    AdvancedCount += 1
    AdvancedNext := UnitCount(StreamPart(1, Position - 1)) + Random(AdvancedEveryMin, AdvancedEveryMax)
}

ShowAdvancedSettings() {
    global AdvancedWindow
    if Running
        StopTyping()
    if AdvancedWindow {
        AdvancedWindow.Show()
        return
    }
    win := Gui(, "高级句段修订 · 可选")
    AdvancedWindow := win
    win.SetFont("s10", "Microsoft YaHei UI")
    enabled := win.AddCheckbox("w570", "启用高级句段修订（默认关闭；此任务不执行旧版单字重输）")
    enabled.Value := AdvancedEnabled
    win.AddText("y+12", "修订方式")
    mode := win.AddDropDownList("w570", ["草稿句 → 定稿句（逐字删除，再逐字输入定稿）", "定稿句删除后原样重输（自动从剪贴板选句段）"])
    mode.Choose(AdvancedMode = "repeat" ? 2 : 1)
    win.AddText("y+14", "计数方式")
    units := win.AddDropDownList("w280", ["英文词（连续字母／数字为一个词）", "非空白字符（适合中文）"])
    units.Choose(AdvancedUnit = "chars" ? 2 : 1)
    controls := []
    for row in [["两次修订间隔", AdvancedEveryMin, AdvancedEveryMax],
        ["回看距离（从片段起点计算）", AdvancedBackMin, AdvancedBackMax],
        ["定稿片段长度", AdvancedSizeMin, AdvancedSizeMax]] {
        win.AddText("xm y+12", row[1] "：最少／最多（词或字符）")
        low := win.AddEdit("w90 Number", row[2])
        high := win.AddEdit("x+14 yp w90 Number", row[3])
        controls.Push([low, high])
    }
    win.AddText("xm y+14 w570", "每行一组：草稿片段 => 定稿片段。剪贴板应放完整定稿。`n例如：This is a rough first sentence. => This is a clearer final sentence.")
    pairs := win.AddEdit("w570 h115 Multi", AdvancedPairsText)
    mode.OnEvent("Change", (*) => pairs.Enabled := mode.Value = 1)
    pairs.Enabled := mode.Value = 1
    win.AddText("w570 y+12", "两种模式均按主设置逐字删除、逐字输入，不粘贴。重输模式无需填写配对，优先完整句，长句取设定长度片段。F9 中止可能留下删改未完成的文字。数据仅存内存。")
    win.AddButton("w160 y+14 Default", "应用并收起").OnEvent("Click", Save)
    win.OnEvent("Close", (*) => win.Hide())
    win.Show()

    Save(*) {
        global AdvancedEnabled, AdvancedPairsText, AdvancedUnit, AdvancedMode
        global AdvancedEveryMin, AdvancedEveryMax, AdvancedBackMin, AdvancedBackMax, AdvancedSizeMin, AdvancedSizeMax
        for range in controls {
            if !ValidNumber(range[1].Value, 1, 10000) || !ValidNumber(range[2].Value, 1, 10000)
                || Integer(range[1].Value) > Integer(range[2].Value) {
                MsgBox "请输入 1～10000 的整数，下限不能大于上限。"
                return
            }
        }
        oldUnit := AdvancedUnit, oldMin := AdvancedSizeMin, oldMax := AdvancedSizeMax
        AdvancedUnit := units.Value = 2 ? "chars" : "words"
        AdvancedSizeMin := Integer(controls[3][1].Value), AdvancedSizeMax := Integer(controls[3][2].Value)
        try {
            if enabled.Value && mode.Value = 1
                ParseAdvancedPairs(pairs.Value)
        } catch as err {
            AdvancedUnit := oldUnit, AdvancedSizeMin := oldMin, AdvancedSizeMax := oldMax
            MsgBox err.Message, "草稿与定稿检查"
            return
        }
        AdvancedEveryMin := Integer(controls[1][1].Value), AdvancedEveryMax := Integer(controls[1][2].Value)
        AdvancedBackMin := Integer(controls[2][1].Value), AdvancedBackMax := Integer(controls[2][2].Value)
        AdvancedEnabled := enabled.Value, AdvancedPairsText := pairs.Value
        AdvancedMode := mode.Value = 2 ? "repeat" : "draft"
        win.Hide()
        Notify("高级句段修订设置已应用；原有单字重输设置保留。")
    }
}
