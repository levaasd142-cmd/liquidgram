//go:build !windows

package main

func getInitialWindowArgs() []string {
	return []string{"--window-size=1200,800"}
}
