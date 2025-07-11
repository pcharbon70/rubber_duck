package ui

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// FileTree represents the file tree component
type FileTree struct {
	root     FileNode
	selected int
	expanded map[string]bool
	items    []FileItem // Flattened for display
	width    int
	height   int
}

// FileItem represents a flattened file tree item for display
type FileItem struct {
	node   FileNode
	depth  int
	isLast bool
	parent string
}

// NewFileTree creates a new file tree component
func NewFileTree() FileTree {
	return FileTree{
		expanded: make(map[string]bool),
		items:    []FileItem{},
	}
}

// Update handles file tree updates
func (ft FileTree) Update(msg tea.Msg) (FileTree, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if ft.selected > 0 {
				ft.selected--
			}
		case "down", "j":
			if ft.selected < len(ft.items)-1 {
				ft.selected++
			}
		case "enter", " ":
			if ft.selected < len(ft.items) {
				item := ft.items[ft.selected]
				if item.node.IsDir {
					// Toggle expansion
					ft.expanded[item.node.Path] = !ft.expanded[item.node.Path]
					ft.items = ft.flatten()
				} else {
					// Select file
					return ft, selectFile(item.node.Path)
				}
			}
		case "h", "left":
			// Collapse current directory or go to parent
			if ft.selected < len(ft.items) {
				item := ft.items[ft.selected]
				if item.node.IsDir && ft.expanded[item.node.Path] {
					ft.expanded[item.node.Path] = false
					ft.items = ft.flatten()
				} else if item.parent != "" {
					// Select parent directory
					for i, it := range ft.items {
						if it.node.Path == item.parent {
							ft.selected = i
							break
						}
					}
				}
			}
		case "l", "right":
			// Expand directory
			if ft.selected < len(ft.items) {
				item := ft.items[ft.selected]
				if item.node.IsDir && !ft.expanded[item.node.Path] {
					ft.expanded[item.node.Path] = true
					ft.items = ft.flatten()
				}
			}
		case "g":
			// Go to top
			ft.selected = 0
		case "G":
			// Go to bottom
			ft.selected = len(ft.items) - 1
		}
	case WindowSizeMsg:
		ft.width = msg.Width
		ft.height = msg.Height
	case FileTreeLoadedMsg:
		ft.root = msg.Root
		ft.items = ft.flatten()
		ft.selected = 0
	}
	return ft, nil
}

// View renders the file tree
func (ft FileTree) View() string {
	if len(ft.items) == 0 {
		return "No files loaded"
	}

	var b strings.Builder
	
	// Calculate visible range with scrolling
	visibleHeight := ft.height - 2 // Account for borders
	scrollOffset := 0
	
	if ft.selected >= visibleHeight {
		scrollOffset = ft.selected - visibleHeight + 1
	}
	
	startIdx := scrollOffset
	endIdx := scrollOffset + visibleHeight
	if endIdx > len(ft.items) {
		endIdx = len(ft.items)
	}

	// Render visible items
	for i := startIdx; i < endIdx; i++ {
		item := ft.items[i]
		line := ft.renderItem(item, i == ft.selected)
		b.WriteString(line)
		if i < endIdx-1 {
			b.WriteString("\n")
		}
	}

	// Add scroll indicators if needed
	if scrollOffset > 0 {
		b.WriteString("\n↑ more...")
	}
	if endIdx < len(ft.items) {
		b.WriteString("\n↓ more...")
	}

	return b.String()
}

// renderItem renders a single file tree item
func (ft FileTree) renderItem(item FileItem, selected bool) string {
	// Build indentation and tree characters
	indent := strings.Repeat("  ", item.depth)
	
	prefix := "├─ "
	if item.isLast {
		prefix = "└─ "
	}
	if item.depth == 0 {
		prefix = ""
	}

	// Choose icon
	icon := ft.getFileIcon(item.node)
	
	// Build the line
	line := fmt.Sprintf("%s%s%s %s", indent, prefix, icon, item.node.Name)
	
	// Apply styling
	if selected {
		line = selectedFileStyle.Render(line)
	} else if item.node.IsDir {
		line = dirStyle.Render(line)
	} else {
		line = fileStyle.Render(line)
	}
	
	return line
}

// getFileIcon returns an appropriate icon for the file
func (ft FileTree) getFileIcon(node FileNode) string {
	if node.IsDir {
		if ft.expanded[node.Path] {
			return "📂"
		}
		return "📁"
	}

	// File icons based on extension
	ext := strings.ToLower(filepath.Ext(node.Name))
	switch ext {
	case ".go":
		return "🐹"
	case ".ex", ".exs":
		return "💧"
	case ".js", ".ts", ".jsx", ".tsx":
		return "📜"
	case ".py":
		return "🐍"
	case ".rb":
		return "💎"
	case ".rs":
		return "🦀"
	case ".md", ".markdown":
		return "📝"
	case ".json":
		return "📋"
	case ".yaml", ".yml":
		return "⚙️"
	case ".toml":
		return "🔧"
	case ".sh", ".bash":
		return "🐚"
	case ".dockerfile", ".containerfile":
		return "🐳"
	case ".gitignore":
		return "🚫"
	default:
		return "📄"
	}
}

// flatten converts the tree structure to a flat list for display
func (ft FileTree) flatten() []FileItem {
	items := []FileItem{}
	ft.flattenNode(ft.root, 0, "", &items)
	return items
}

// flattenNode recursively flattens a node and its children
func (ft FileTree) flattenNode(node FileNode, depth int, parent string, items *[]FileItem) {
	// Add the current node
	*items = append(*items, FileItem{
		node:   node,
		depth:  depth,
		parent: parent,
		isLast: false, // Will be updated later
	})

	// Add children if directory is expanded
	if node.IsDir && ft.expanded[node.Path] {
		// Sort children by type (dirs first) then name
		children := make([]FileNode, len(node.Children))
		copy(children, node.Children)
		sort.Slice(children, func(i, j int) bool {
			if children[i].IsDir != children[j].IsDir {
				return children[i].IsDir
			}
			return children[i].Name < children[j].Name
		})

		for i, child := range children {
			child.depth = depth + 1
			// Mark last child
			if i == len(children)-1 {
				(*items)[len(*items)-1].isLast = true
			}
			ft.flattenNode(child, depth+1, node.Path, items)
		}
	}
}

// LoadFileTree creates a command to load the file tree
func LoadFileTree(rootPath string) tea.Cmd {
	return func() tea.Msg {
		// TODO: Load from Phoenix channel
		// For now, return mock data
		root := FileNode{
			Name:  "rubber_duck",
			Path:  rootPath,
			IsDir: true,
			Children: []FileNode{
				{
					Name:  "lib",
					Path:  filepath.Join(rootPath, "lib"),
					IsDir: true,
					Children: []FileNode{
						{
							Name:  "rubber_duck",
							Path:  filepath.Join(rootPath, "lib", "rubber_duck"),
							IsDir: true,
							Children: []FileNode{
								{
									Name:  "engine.ex",
									Path:  filepath.Join(rootPath, "lib", "rubber_duck", "engine.ex"),
									IsDir: false,
								},
								{
									Name:  "llm",
									Path:  filepath.Join(rootPath, "lib", "rubber_duck", "llm"),
									IsDir: true,
									Children: []FileNode{
										{
											Name:  "client.ex",
											Path:  filepath.Join(rootPath, "lib", "rubber_duck", "llm", "client.ex"),
											IsDir: false,
										},
										{
											Name:  "memory.ex",
											Path:  filepath.Join(rootPath, "lib", "rubber_duck", "llm", "memory.ex"),
											IsDir: false,
										},
									},
								},
							},
						},
					},
				},
				{
					Name:  "test",
					Path:  filepath.Join(rootPath, "test"),
					IsDir: true,
					Children: []FileNode{
						{
							Name:  "engine_test.exs",
							Path:  filepath.Join(rootPath, "test", "engine_test.exs"),
							IsDir: false,
						},
					},
				},
				{
					Name:  "README.md",
					Path:  filepath.Join(rootPath, "README.md"),
					IsDir: false,
				},
			},
		}

		return FileTreeLoadedMsg{Root: root}
	}
}

// Helper functions

func selectFile(path string) tea.Cmd {
	return func() tea.Msg {
		return FileSelectedMsg{Path: path}
	}
}

// Additional message types for file tree
type FileTreeLoadedMsg struct {
	Root FileNode
}