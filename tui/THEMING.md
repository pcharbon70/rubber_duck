# TUI Theming System

The RubberDuck TUI supports a comprehensive theming system that allows users to customize the appearance of the interface.

## Available Themes

The following themes are available out of the box:

### 1. Dark Theme (Default)
- **Name**: `dark`
- **Description**: Default dark theme with high contrast
- **Best for**: General use, reduced eye strain in low light

### 2. Light Theme
- **Name**: `light`
- **Description**: Clean light theme for bright environments
- **Best for**: Daytime use, well-lit environments

### 3. Solarized Dark
- **Name**: `solarized-dark`
- **Description**: Popular Solarized Dark color scheme
- **Best for**: Developers familiar with Solarized

### 4. Dracula
- **Name**: `dracula`
- **Description**: Popular Dracula theme with purple accents
- **Best for**: Modern, vibrant interface

## Theme Components

Each theme defines colors for the following UI elements:

### Base Colors
- **Background**: Main background color
- **Foreground**: Main text color
- **Border**: Border and outline colors
- **Cursor**: Cursor highlight color

### UI Elements
- **Status Bar**: Status bar background and text
- **Selection**: Selected item highlighting
- **File Tree**: Directory and file colors
- **Editor**: Editor background, foreground, and line numbers
- **Output Pane**: Output text and status colors
- **Modals**: Modal dialog styling
- **Command Palette**: Command palette styling

### Syntax Highlighting
- **Keywords**: Programming language keywords
- **Strings**: String literals
- **Comments**: Code comments
- **Functions**: Function names
- **Numbers**: Numeric literals

## Switching Themes

### Keyboard Shortcuts
- **Ctrl+Shift+T**: Toggle between dark and light themes
- **Ctrl+P**: Open command palette, then type "Toggle Theme"

### Settings Modal
1. Press **Ctrl+,** to open settings
2. Navigate to the "Theme" field
3. Use **Left/Right arrow keys** or **h/l** to cycle through themes
4. Press **Enter** or **Space** to confirm selection
5. Press **S** to save settings

### Command Palette
1. Press **Ctrl+P** to open command palette
2. Type "Toggle Theme" or "switch theme"
3. Press **Enter** to execute

## Creating Custom Themes

Developers can create custom themes by defining a new `Theme` struct:

```go
customTheme := &Theme{
    Name:        "my-theme",
    Description: "My custom theme",
    
    // Base colors
    Background:    lipgloss.Color("#1a1a1a"),
    Foreground:    lipgloss.Color("#ffffff"),
    Border:        lipgloss.Color("#444444"),
    Cursor:        lipgloss.Color("#00ff00"),
    
    // UI element colors
    StatusBar:     lipgloss.Color("#2a2a2a"),
    StatusBarText: lipgloss.Color("#cccccc"),
    // ... more colors
}

// Register the theme
themeManager.RegisterTheme(customTheme)
```

## Theme Configuration

Themes are automatically loaded on startup and can be persisted through the settings system. The current theme is stored in the user's settings and restored on application restart.

## Technical Details

### Theme Manager
The `ThemeManager` is responsible for:
- Loading and registering themes
- Switching between themes
- Providing theme access to UI components

### Themed Styles
The UI components use a `ThemedStyles` struct that is generated from the current theme. This ensures consistent styling across all interface elements.

### Dynamic Updates
Theme changes are applied immediately without requiring an application restart. The entire interface updates when a new theme is selected.

## Troubleshooting

### Theme Not Changing
1. Ensure you're using the correct keyboard shortcut (Ctrl+Shift+T)
2. Check that the theme exists in the available themes list
3. Try using the settings modal to change themes

### Custom Theme Not Loading
1. Verify the theme is properly registered with the ThemeManager
2. Check that all required color fields are defined
3. Ensure the theme name is unique

### Colors Not Displaying Correctly
1. Check terminal color support (256-color or true color)
2. Verify terminal emulator compatibility
3. Some terminals may not support all color formats (hex vs. ANSI)

## Contributing Themes

To contribute a new theme:
1. Create a new theme definition following existing patterns
2. Test the theme across different UI components
3. Ensure good contrast and accessibility
4. Submit a pull request with the theme implementation

The theming system is designed to be extensible and developer-friendly while providing end users with immediate visual customization options.