package ui

import tea "github.com/charmbracelet/bubbletea"

// programHolder is used to store the tea.Program reference
var programHolder *tea.Program

// SetProgramHolder sets the global program holder
func SetProgramHolder(p *tea.Program) {
	programHolder = p
}

// ProgramHolder returns the tea.Program for the model
func (m Model) ProgramHolder() *tea.Program {
	return programHolder
}