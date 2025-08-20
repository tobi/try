package main

import (
    "bufio"
    "errors"
    "fmt"
    "os"
    "path/filepath"
    "sort"
    "strconv"
    "strings"
    "time"
    "unicode"
)

// ANSI token printer (mirrors Ruby/Python tokens)
func uiPrint(text string, w *os.File) {
    if w == nil {
        w = os.Stderr
    }
    replacer := strings.NewReplacer(
        "{text}", "\x1b[39m",
        "{dim_text}", "\x1b[90m",
        "{h1}", "\x1b[1;33m",
        "{h2}", "\x1b[1;36m",
        "{highlight}", "\x1b[1;33m",
        "{reset}", "\x1b[0m",
        "{reset_bg}", "\x1b[49m",
        "{clear_screen}", "\x1b[2J",
        "{clear_line}", "\x1b[2K",
        "{home}", "\x1b[H",
        "{hide_cursor}", "\x1b[?25l",
        "{show_cursor}", "\x1b[?25h",
        "{start_selected}", "\x1b[6m",
        "{end_selected}", "\x1b[0m",
    )
    _, _ = w.WriteString(replacer.Replace(text))
}

func printGlobalHelp(defaultPath string) {
    uiPrint("{h1}try something!{text}\n\n", nil)
    uiPrint("Lightweight experiments for people with ADHD\n\n", nil)
    uiPrint("this tool is not meant to be used directly,\n", nil)
    uiPrint("but added to your ~/.zshrc or ~/.bashrc:\n\n", nil)
    uiPrint("  {highlight}eval \"$(#$0 init ~/src/tries)\"{text}\n\n", nil)
    uiPrint("{h2}Usage:{text}\n", nil)
    uiPrint("  init [--path PATH]  # Initialize shell function for aliasing\n", nil)
    uiPrint("  cd [QUERY]          # Interactive selector; prints shell cd commands\n\n\n", nil)
    uiPrint("{h2}Defaults:{text}\n", nil)
    uiPrint("  Default path: {dim_text}~/src/tries{text} (override with --path on commands)\n", nil)
    uiPrint("  Current default: {dim_text}"+defaultPath+"{text}\n", nil)
}

func isTTY(f *os.File) bool {
    fi, err := f.Stat()
    if err != nil {
        return false
    }
    return (fi.Mode() & os.ModeCharDevice) != 0
}

type tryDir struct {
    Basename string
    Path     string
    Ctime    float64
    Mtime    float64
    Score    float64
}

type selector struct {
    basePath     string
    inputBuffer  string
    cursorPos    int
    scrollOffset int
    termW        int
    termH        int
    tries        []tryDir
    selected     *result
}

type result struct {
    Type string // "cd" or "mkdir"
    Path string
}

func newSelector(search, basePath string) *selector {
    s := &selector{
        basePath:     basePath,
        inputBuffer:  strings.ReplaceAll(strings.TrimSpace(strings.ReplaceAll(search, "\t", " ")), " ", "-"),
        cursorPos:    0,
        scrollOffset: 0,
        termW:        80,
        termH:        24,
    }
    if err := os.MkdirAll(basePath, 0o755); err != nil {
        _ = err
    }
    return s
}

func (s *selector) run() (*result, error) {
    if !isTTY(os.Stdin) || !isTTY(os.Stderr) {
        fmt.Fprintln(os.Stderr, "Error: try requires an interactive terminal")
        return nil, errors.New("no tty")
    }

    s.updateTermSize()
    uiPrint("{hide_cursor}{clear_screen}{home}", nil)

    fd := int(os.Stdin.Fd())
    st, err := enableRaw(fd)
    if err != nil {
        return nil, err
    }
    defer restoreTerm(fd, st)
    defer uiPrint("{clear_screen}{home}{show_cursor}", nil)

    for {
        s.render()
        key := s.readKey()
        totalItems := len(s.getTries()) + 1
        switch key {
        case "\x1b[A", "\x10": // Up or Ctrl-P
            if s.cursorPos > 0 {
                s.cursorPos--
            }
        case "\x1b[B", "\x0e": // Down or Ctrl-N
            if s.cursorPos < totalItems-1 {
                s.cursorPos++
            }
        case "\r", "\n":
            tries := s.getTries()
            if s.cursorPos < len(tries) {
                s.handleSelection(tries[s.cursorPos])
            } else {
                s.handleCreateNew(fd, st)
            }
            if s.selected != nil {
                return s.selected, nil
            }
        case "\x7f", "\b":
            if len(s.inputBuffer) > 0 {
                s.inputBuffer = s.inputBuffer[:len(s.inputBuffer)-1]
            }
            s.cursorPos = 0
        case "\x03", "\x1b": // Ctrl-C or ESC
            return nil, nil
        default:
            if len(key) == 1 {
                r := []rune(key)[0]
                if (unicode.IsLetter(r) || unicode.IsDigit(r) || strings.ContainsRune("-_. ", r)) && r >= 32 {
                    s.inputBuffer += string(r)
                    s.cursorPos = 0
                }
            }
        }
    }
}

func (s *selector) updateTermSize() {
    w, h := getWinSize(int(os.Stdin.Fd()))
    if w <= 0 {
        w = 80
    }
    if h <= 0 {
        h = 24
    }
    s.termW, s.termH = w, h
}

func (s *selector) loadTries() []tryDir {
    if s.tries != nil {
        return s.tries
    }
    entries, err := os.ReadDir(s.basePath)
    if err != nil {
        return nil
    }
    var out []tryDir
    for _, e := range entries {
        name := e.Name()
        if name == "." || name == ".." {
            continue
        }
        p := filepath.Join(s.basePath, name)
        fi, err := os.Stat(p)
        if err != nil {
            continue
        }
        if !fi.IsDir() {
            continue
        }
        ctime, mtime := extractTimes(fi)
        out = append(out, tryDir{Basename: name, Path: p, Ctime: ctime, Mtime: mtime})
    }
    s.tries = out
    return out
}

func (s *selector) getTries() []tryDir {
    base := s.loadTries()
    list := make([]tryDir, 0, len(base))
    for _, t := range base {
        tt := t
        tt.Score = calculateScore(t.Basename, s.inputBuffer, t.Ctime, t.Mtime)
        list = append(list, tt)
    }
    if s.inputBuffer == "" {
        sort.Slice(list, func(i, j int) bool { return list[i].Score > list[j].Score })
        return list
    }
    filtered := make([]tryDir, 0, len(list))
    for _, t := range list {
        if t.Score > 0 {
            filtered = append(filtered, t)
        }
    }
    sort.Slice(filtered, func(i, j int) bool { return filtered[i].Score > filtered[j].Score })
    return filtered
}

func calculateScore(text, query string, ctime, mtime float64) float64 {
    score := 0.0
    if len(text) >= 11 && text[4] == '-' && text[7] == '-' && text[10] == '-' {
        if _, err := strconv.Atoi(text[0:4]); err == nil {
            score += 2.0
        }
    }
    if query != "" {
        tl := strings.ToLower(text)
        ql := strings.ToLower(query)
        qchars := []rune(ql)
        lastPos := -1
        qidx := 0
        for pos, r := range []rune(tl) {
            if qidx >= len(qchars) {
                break
            }
            if r != qchars[qidx] {
                continue
            }
            score += 1.0
            if pos == 0 || !isAlphaNumRune([]rune(tl)[pos-1]) {
                score += 1.0
            }
            if lastPos >= 0 {
                gap := pos - lastPos - 1
                score += 1.0 / sqrt(float64(gap+1))
            }
            lastPos = pos
            qidx++
        }
        if qidx < len(qchars) {
            return 0.0
        }
        if lastPos >= 0 {
            score *= float64(len(qchars)) / float64(lastPos+1)
        }
        score *= 10.0 / (float64(len(text)) + 10.0)
    }
    now := float64(time.Now().UnixNano()) / 1e9
    if ctime > 0 {
        days := (now - ctime) / 86400.0
        score += 2.0 / sqrt(days+1)
    }
    if mtime > 0 {
        hours := (now - mtime) / 3600.0
        score += 3.0 / sqrt(hours+1)
    }
    return score
}

func isAlphaNumRune(r rune) bool {
    return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
}

func sqrt(x float64) float64 { // small inline sqrt via Newton's method to avoid math import
    if x <= 0 {
        return 0
    }
    z := x
    for i := 0; i < 10; i++ {
        z = 0.5 * (z + x/z)
    }
    return z
}

func (s *selector) readKey() string {
    buf := make([]byte, 1)
    n, _ := os.Stdin.Read(buf)
    if n == 0 {
        return ""
    }
    if buf[0] == 0x1b { // ESC
        // Try to read a few more bytes without blocking
        _ = setNonblock(int(os.Stdin.Fd()), true)
        defer setNonblock(int(os.Stdin.Fd()), false)
        seq := []byte{buf[0]}
        tmp := make([]byte, 4)
        for i := 0; i < 4; i++ {
            n2, err := os.Stdin.Read(tmp[i : i+1])
            if err != nil || n2 == 0 {
                break
            }
            seq = append(seq, tmp[i])
        }
        return string(seq)
    }
    return string(buf)
}

func (s *selector) render() {
    s.updateTermSize()
    uiPrint("{clear_screen}{home}", nil)
    sep := strings.Repeat("─", max(1, s.termW-1))
    uiPrint("{h1}📁 Try Directory Selection{text}\r\n", nil)
    uiPrint("{dim_text}"+sep+"{text}\r\n", nil)
    uiPrint("{highlight}Search: {text}"+s.inputBuffer+"\r\n", nil)
    uiPrint("{dim_text}"+sep+"{text}\r\n", nil)

    tries := s.getTries()
    total := len(tries) + 1
    maxVisible := max(3, s.termH-8)
    if s.cursorPos < s.scrollOffset {
        s.scrollOffset = s.cursorPos
    } else if s.cursorPos >= s.scrollOffset+maxVisible {
        s.scrollOffset = s.cursorPos - maxVisible + 1
    }
    end := min(s.scrollOffset+maxVisible, total)
    for idx := s.scrollOffset; idx < end; idx++ {
        if idx == len(tries) && len(tries) > 0 && idx >= s.scrollOffset {
            uiPrint("\r\n", nil)
        }
        isSel := idx == s.cursorPos
        if isSel {
            uiPrint("{highlight}→ {text}", nil)
        } else {
            uiPrint("  ", nil)
        }
        if idx < len(tries) {
            td := tries[idx]
            uiPrint("📁 ", nil)
            if isSel {
                uiPrint("{start_selected}", nil)
            }
            base := td.Basename
            display := base
            if m := splitDateName(base); m != nil {
                datePart := m[0]
                namePart := m[1]
                uiPrint("{dim_text}"+datePart+"{text}", nil)
                if s.inputBuffer != "" && strings.Contains(s.inputBuffer, "-") {
                    uiPrint("{highlight}-{text}", nil)
                } else {
                    uiPrint("{dim_text}-{text}", nil)
                }
                if s.inputBuffer != "" {
                    uiPrint(highlightMatches(namePart, s.inputBuffer), nil)
                } else {
                    uiPrint(namePart, nil)
                }
                display = datePart + "-" + namePart
            } else {
                if s.inputBuffer != "" {
                    uiPrint(highlightMatches(base, s.inputBuffer), nil)
                } else {
                    uiPrint(base, nil)
                }
            }
            timeText := formatRelativeTime(td.Mtime)
            scoreText := fmt.Sprintf("%.1f", td.Score)
            meta := timeText + ", " + scoreText
            metaWidth := len(meta) + 1
            textWidth := len(display)
            padding := max(1, s.termW-5-textWidth-metaWidth)
            uiPrint(strings.Repeat(" ", padding), nil)
            uiPrint(" {dim_text}"+meta+"{text}", nil)
        } else {
            uiPrint("+ ", nil)
            if isSel {
                uiPrint("{start_selected}", nil)
            }
            display := "Create new"
            if s.inputBuffer != "" {
                display = "Create new: " + s.inputBuffer
            }
            uiPrint(display, nil)
            padding := max(1, s.termW-5-len(display))
            uiPrint(strings.Repeat(" ", padding), nil)
        }
        uiPrint("{end_selected}{text}\r\n", nil)
    }
    if total > maxVisible {
        uiPrint("{dim_text}"+sep+"{text}\r\n", nil)
        uiPrint(fmt.Sprintf("{dim_text}[%d-%d/%d]{text}\r\n", s.scrollOffset+1, end, total), nil)
    }
    uiPrint("{dim_text}"+sep+"{text}\r\n", nil)
    uiPrint("{dim_text}↑↓: Navigate  Enter: Select  ESC: Cancel{text}", nil)
    os.Stderr.Sync()
}

func splitDateName(s string) []string {
    if len(s) >= 11 && s[4] == '-' && s[7] == '-' && s[10] == '-' {
        return []string{s[:10], s[11:]}
    }
    return nil
}

func formatRelativeTime(mtime float64) string {
    if mtime <= 0 {
        return "?"
    }
    secs := float64(time.Now().UnixNano())/1e9 - mtime
    mins := secs / 60
    hrs := mins / 60
    days := hrs / 24
    if secs < 10 {
        return "just now"
    } else if mins < 60 {
        return fmt.Sprintf("%dm ago", int(mins))
    } else if hrs < 24 {
        return fmt.Sprintf("%dh ago", int(hrs))
    } else if days < 30 {
        return fmt.Sprintf("%dd ago", int(days))
    } else if days < 365 {
        return fmt.Sprintf("%dmo ago", int(days/30))
    }
    return fmt.Sprintf("%dy ago", int(days/365))
}

func highlightMatches(text, query string) string {
    if query == "" {
        return text
    }
    tl := strings.ToLower(text)
    ql := strings.ToLower(query)
    q := []rune(ql)
    qi := 0
    var b strings.Builder
    tr := []rune(text)
    for i, ch := range tr {
        if qi < len(q) && []rune(tl)[i] == q[qi] {
            b.WriteString("{highlight}")
            b.WriteRune(ch)
            b.WriteString("{text}")
            qi++
        } else {
            b.WriteRune(ch)
        }
    }
    return b.String()
}

func (s *selector) handleSelection(td tryDir) {
    s.selected = &result{Type: "cd", Path: td.Path}
}

func (s *selector) handleCreateNew(fd int, st termState) {
    datePrefix := time.Now().Format("2006-01-02")
    if s.inputBuffer != "" {
        name := datePrefix + "-" + s.inputBuffer
        name = strings.ReplaceAll(name, " ", "-")
        s.selected = &result{Type: "mkdir", Path: filepath.Join(s.basePath, name)}
        return
    }
    // prompt in cooked mode
    uiPrint("{clear_screen}{home}", nil)
    uiPrint("{h2}Enter new try name{text}\r\n", nil)
    uiPrint("> {dim_text}"+datePrefix+"-{text}", nil)
    uiPrint("{show_cursor}", nil)
    os.Stdout.Sync()

    // restore cooked
    _ = setTermState(fd, &st.old)
    reader := bufio.NewReader(os.Stdin)
    line, _ := reader.ReadString('\n')
    // back to raw
    _, _ = enableRaw(fd)

    line = strings.TrimSpace(line)
    if line == "" {
        return
    }
    name := datePrefix + "-" + line
    name = strings.ReplaceAll(name, " ", "-")
    s.selected = &result{Type: "mkdir", Path: filepath.Join(s.basePath, name)}
}

func getenv(k, def string) string {
    if v := os.Getenv(k); v != "" {
        return v
    }
    return def
}

func extractOptionWithValue(args *[]string, opt string) string {
    a := *args
    var val string
    for i := len(a) - 1; i >= 0; i-- {
        if a[i] == opt || strings.HasPrefix(a[i], opt+"=") {
            if strings.Contains(a[i], "=") {
                parts := strings.SplitN(a[i], "=", 2)
                val = parts[1]
            } else if i+1 < len(a) {
                val = a[i+1]
                // remove following value
                a = append(a[:i+1], a[i+2:]...)
            }
            // remove opt itself
            a = append(a[:i], a[i+1:]...)
            break
        }
    }
    *args = a
    return val
}

func main() {
    // Determine default path
    tryPath := getenv("TRY_PATH", filepath.Join(os.Getenv("HOME"), "src", "tries"))
    tryPath, _ = filepath.Abs(tryPath)

    // Global help
    for _, a := range os.Args[1:] {
        if a == "--help" || a == "-h" {
            printGlobalHelp(tryPath)
            os.Exit(0)
        }
    }

    if len(os.Args) < 2 {
        printGlobalHelp(tryPath)
        os.Exit(2)
    }

    args := append([]string{}, os.Args[1:]...)
    cmd := args[0]
    args = args[1:]
    pathOpt := extractOptionWithValue(&args, "--path")
    if pathOpt != "" {
        tryPath = pathOpt
    }
    tryPath, _ = filepath.Abs(tryPath)

    switch cmd {
    case "init":
        scriptPath, _ := filepath.Abs(os.Args[0])
        if len(args) > 0 && strings.HasPrefix(args[0], "/") {
            tryPath, _ = filepath.Abs(args[0])
            args = args[1:]
        }
        pathArg := ""
        if tryPath != "" {
            pathArg = " --path \"" + tryPath + "\""
        }
        fmt.Printf("try() {\n  script_path='%s';\n  cmd=$(\"$script_path\" cd%s \"$@\" 2>/dev/tty);\n  [ $? -eq 0 ] && eval \"$cmd\" || echo \"$cmd\";\n}\n", scriptPath, pathArg)
    case "cd":
        search := strings.Join(args, " ")
        sel := newSelector(search, tryPath)
        res, _ := sel.run()
        if res != nil {
            parts := []string{}
            parts = append(parts, "dir='"+res.Path+"'")
            if res.Type == "mkdir" {
                parts = append(parts, "mkdir -p \"$dir\"")
            }
            parts = append(parts, "touch \"$dir\"")
            parts = append(parts, "cd \"$dir\"")
            fmt.Print(strings.Join(parts, " && "))
        }
    default:
        fmt.Fprintln(os.Stderr, "Unknown command:", cmd)
        printGlobalHelp(tryPath)
        os.Exit(2)
    }
}

func max(a, b int) int { if a > b { return a }; return b }
func min(a, b int) int { if a < b { return a }; return b }
