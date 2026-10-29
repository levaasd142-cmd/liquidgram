package main

import "os/exec"

func openExternalURL(target string) error {
	cmd := exec.Command("/usr/bin/open", target)
	if err := cmd.Start(); err != nil {
		return err
	}
	go cmd.Wait()
	return nil
}
