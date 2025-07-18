package main

import (
	"fmt"
	"log"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rubber_duck/tui/internal/ui"
)

func main() {
	// Create the initial model
	model := ui.NewModel()

	// Create the Bubble Tea program
	p := tea.NewProgram(
		model,
		tea.WithAltScreen(),       // Use alternate screen buffer
		tea.WithMouseCellMotion(), // Enable mouse support
	)

	// Run the program
	if _, err := p.Run(); err != nil {
		log.Fatal(err)
		os.Exit(1)
	}

	fmt.Println("Thanks for using RubberDuck TUI!")
}