package main

import (
	"embed"
	"io/fs"
)

// The production web build, copied here without source maps by `dev/buildDesktop.mjs`
//
//go:embed all:webapp
var webappEmbed embed.FS

func webappFiles() fs.FS {
	files, err := fs.Sub(webappEmbed, "webapp")
	if err != nil {
		panic(err)
	}
	return files
}
