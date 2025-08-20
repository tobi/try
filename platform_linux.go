//go:build linux

package main

import (
    "os"
    "syscall"
    "unsafe"
)

type termState struct { old syscall.Termios }

func getTermState(fd int) (syscall.Termios, error) {
    var t syscall.Termios
    _, _, e := syscall.Syscall6(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&t)), 0, 0, 0)
    if e != 0 { return t, e }
    return t, nil
}

func setTermState(fd int, t *syscall.Termios) error {
    _, _, e := syscall.Syscall6(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(t)), 0, 0, 0)
    if e != 0 { return e }
    return nil
}

func enableRaw(fd int) (termState, error) {
    old, err := getTermState(fd)
    if err != nil { return termState{}, err }
    raw := old
    raw.Lflag &^= syscall.ECHO | syscall.ICANON | syscall.IEXTEN | syscall.ISIG
    raw.Iflag &^= syscall.IXON | syscall.ICRNL | syscall.INLCR | syscall.IGNCR
    raw.Oflag &^= syscall.OPOST
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
        ctime = float64(st.Ctim.Sec) + float64(st.Ctim.Nsec)/1e9
    }
    return
}

