package ui

import (
	tea "github.com/charmbracelet/bubbletea"
)

// programRef holds a reference to the Bubble Tea program for Phoenix client usage
var programRef *tea.Program

// SetProgram stores the program reference
func SetProgram(p *tea.Program) {
	programRef = p
}

// GetProgram retrieves the stored program reference
func GetProgram() *tea.Program {
	return programRef
}