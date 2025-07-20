# Chat UI Layout Update

## Overview
Updated the chat UI layout to reverse the position of status messages and conversation history, with rounded borders for better visual separation.

## Layout Changes

### Before:
```
┌─────────────────────────────────────┐
│ Header                              │
├─────────────────────────────────────┤
│                                     │
│     Conversation History            │
│                                     │
├─────────────────────────────────────┤
│     Status Messages                 │
└─────────────────────────────────────┘
```

### After:
```
┌─────────────────────────────────────┐
│ Header                              │
├─────────────────────────────────────┤
│ ╭───────────────────────────────╮   │
│ │  ◆ AI Status Messages ◆      │   │
│ │  [Status content area]        │   │
│ ╰───────────────────────────────╯   │
│                                     │
│ ╭───────────────────────────────╮   │
│ │  ◆ Conversation History ◆    │   │
│ │  [Chat messages area]         │   │
│ │  [Input area]                 │   │
│ ╰───────────────────────────────╯   │
└─────────────────────────────────────┘
```

## Implementation Details

1. **Reversed Layout**:
   - Status messages now appear at the top (30% of space)
   - Conversation history at the bottom (70% of space)
   - Better for scanning AI work progress while typing

2. **Rounded Borders**:
   - Each section has its own rounded border
   - Status messages: Purple border (color 63)
   - Conversation history: Green border (color 62)
   - Clear visual separation between sections

3. **Section Labels**:
   - "◆ AI Status Messages ◆" - centered at top of status section
   - "◆ Conversation History ◆" - centered at top of chat section
   - Makes purpose of each section immediately clear

4. **Size Adjustments**:
   - Components account for border padding (4px horizontal, 2px vertical)
   - Title heights accounted for in viewport calculations
   - Proper spacing between sections

## Benefits

1. **Better Workflow**: Status messages at top are easier to monitor while typing
2. **Visual Clarity**: Rounded borders create clear section boundaries
3. **Professional Look**: More polished appearance with proper styling
4. **Clear Purpose**: Labels make each section's function obvious

## Technical Notes

- Uses lipgloss RoundedBorder style
- Border colors chosen for good contrast
- Padding adjusted to prevent text touching borders
- Viewport heights adjusted for titles and borders