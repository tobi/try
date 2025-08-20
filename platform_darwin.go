//go:build darwin

package main

import (
    "os"
    "syscall"
    "unsafe"
)

type termState struct { old syscall.Termios }

func getTermState(fd int) (syscall.Termios, error) {
    var t syscall.Termios
    _, _, e := syscall.Syscall6(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TIOCGETA), uintptr(unsafe.Pointer(&t)), 0, 0, 0)
    if e != 0 { return t, e }
    return t, nil
}

func setTermState(fd int, t *syscall.Termios) error {
    _, _, e := syscall.Syscall6(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TIOCSETA), uintptr(unsafe.Pointer(t)), 0, 0, 0)
    if e != 0 { return e }
    return nil
}

func enableRaw(fd int) (termState, error) {
    old, err := getTermState(fd)
    if err != nil { return termState{}, err }
    raw := old
    raw.Iflag &^= syscall.IGNBRK | syscall.BRKINT | syscall.PARMRK | syscall.ISTRIP | syscall.INLCR | syscall.IGNCR | syscall.ICRNL | syscall.IXON
    raw.Oflag &^= syscall.OPOST
    raw.Cflag |= syscall.CS8
    raw.Lflag &^= syscall.ECHO | syscall.ECHONL | syscall.ICANON | syscall.ISIG | syscall.IEXTEN
    raw.Cc[syscall.VMIN] = 1
    raw.Cc[syscall.VTIME] = 0
    if err := setTermState(fd, &raw); err != nil { return termState{}, err }
    return termState{old: old}, nil
}

func restoreTerm(fd int, st termState) { _ = setTermState(fd, &st.old) }

type winsize struct { row, col, x, y uint16 }

func getWinSize(fd int) (int, int) {
    var ws winsize
    _, _, e := syscall.Syscall6(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TIOCGWINSZ), uintptr(unsafe.Pointer(&ws)), 0, 0, 0)
    if e != 0 || ws.col == 0 || ws.row == 0 { return 80, 24 }
    return int(ws.col), int(ws.row)
}

func setNonblock(fd int, nb bool) error { return syscall.SetNonblock(fd, nb) }

func extractTimes(fi os.FileInfo) (ctime float64, mtime float64) {
    mtime = float64(fi.ModTime().UnixNano()) / 1e9
    if st, ok := fi.Sys().(*syscall.Stat_t); ok {
        // Prefer Birthtimespec (creation time) if available
        ctime = float64(st.Birthtimespec.Sec) + float64(st.Birthtimespec.Nsec)/1e9
        // Fallback to change time if birth time is zero
        if st.Birthtimespec.Sec == 0 && st.Birthtimespec.Nsec == 0 {
            ctime = float64(st.Ctimespec.Sec) + float64(st.Ctimespec.Nsec)/1e9
        }
    }
    return
}

