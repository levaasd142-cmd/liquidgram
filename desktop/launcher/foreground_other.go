//go:build !windows

package main

// Passing on the right to bring a window to the front exists only on Windows
func allowAnyForeground() {}
