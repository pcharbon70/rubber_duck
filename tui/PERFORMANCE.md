# TUI Performance Optimizations

The RubberDuck TUI includes several performance optimizations to ensure smooth operation even with large codebases and frequent updates.

## Performance Features

### 1. View Caching

The TUI implements a view cache system that stores rendered UI components to avoid unnecessary re-rendering.

**Benefits:**
- Reduces CPU usage for static content
- Improves rendering performance for complex layouts
- Maintains responsive UI during intensive operations

**Usage:**
- Automatically caches rendered views with configurable expiration
- Cache keys based on component state and content hash
- Manual cache clearing available via command palette

**Commands:**
- `Clear Cache` in command palette to manually clear view cache

### 2. Debounced Operations

Critical operations like auto-save are debounced to prevent excessive execution during rapid user input.

**Features:**
- **Auto-save debouncing**: File changes trigger auto-save after 500ms of inactivity
- **Input debouncing**: Prevents excessive updates during typing
- **Configurable delays**: Different operations can have different debounce timings

**Benefits:**
- Reduces file I/O operations
- Prevents UI stuttering during rapid input
- Conserves system resources

### 3. Lazy Loading

For large file trees and content lists, the TUI implements lazy loading to improve initial load times.

**Implementation:**
- **Page-based loading**: Load content in configurable page sizes
- **On-demand expansion**: File tree nodes load children when expanded
- **Progressive loading**: Additional content loads as user scrolls

**Benefits:**
- Faster initial application startup
- Reduced memory usage for large projects
- Responsive UI regardless of project size

### 4. Virtual Scrolling

For very large lists (like file trees with thousands of items), virtual scrolling renders only visible items.

**Features:**
- **Visible item calculation**: Only renders items within viewport
- **Buffer zones**: Renders extra items above/below for smooth scrolling
- **Dynamic viewport**: Adjusts to terminal size changes

**Benefits:**
- Constant memory usage regardless of list size
- Smooth scrolling performance
- Handles extremely large file trees efficiently

### 5. Performance Monitoring

Built-in performance monitoring tracks UI performance in real-time.

**Metrics Tracked:**
- **Render time**: Time to render the complete UI
- **Update time**: Time to process state updates
- **Sample history**: Rolling window of recent measurements
- **Average calculations**: Running averages for performance trends

**Access:**
- `Performance Stats` command in command palette
- Displays current performance metrics in output pane
- Includes render and update timing information

### 6. Batch Updates

Multiple UI updates can be batched together to reduce rendering overhead.

**Implementation:**
- **Update batching**: Combines multiple state changes into single render
- **Configurable delays**: Batch window can be adjusted based on needs
- **Automatic flushing**: Ensures updates aren't delayed too long

## Performance Configuration

### Cache Settings

```go
// View cache with 5-minute expiration
cache := NewViewCache()
content, found := cache.Get("component-key", 5*time.Minute)
```

### Debounce Timing

```go
// Auto-save with 500ms debounce
saveDebouncer := NewDebouncer(500 * time.Millisecond)
```

### Lazy Loading Configuration

```go
// Load 50 items per page
loader := NewLazyLoader(items, 50)
```

### Virtual Scrolling Setup

```go
// Virtual scroller for 1000 items, 20px height each, 400px viewport
scroller := NewVirtualScroller(1000, 20, 400)
```

## Performance Best Practices

### For Users

1. **Clear cache periodically**: Use `Clear Cache` command if UI feels sluggish
2. **Monitor performance**: Check `Performance Stats` to identify bottlenecks
3. **Large projects**: Let lazy loading work - don't expand all tree nodes at once
4. **Frequent edits**: Auto-save debouncing will prevent excessive saves

### For Developers

1. **Cache static content**: Use view cache for content that doesn't change frequently
2. **Debounce user input**: Wrap rapid operations in debouncers
3. **Implement lazy loading**: Don't load all data upfront for large datasets
4. **Monitor performance**: Use PerformanceMonitor to track timing
5. **Batch updates**: Group related state changes when possible

## Troubleshooting Performance Issues

### High Render Times

1. Check if view caching is enabled
2. Verify theme complexity (some themes may be more intensive)
3. Consider reducing terminal size if extremely large
4. Clear cache and restart if performance degrades over time

### Slow File Operations

1. Ensure auto-save debouncing is working (watch status bar)
2. Check if large files are causing delays
3. Monitor file I/O in performance stats

### Memory Usage

1. Use virtual scrolling for large lists
2. Implement lazy loading for file trees
3. Clear view cache periodically
4. Monitor performance stats for memory-related metrics

### UI Stuttering

1. Increase debounce delays for rapid operations
2. Enable batch updates for frequent state changes
3. Check terminal emulator performance
4. Reduce update frequency if needed

## Performance Monitoring Commands

Access these through the command palette (Ctrl+P):

- **Performance Stats**: Shows detailed performance metrics
- **Clear Cache**: Manually clears all cached views
- **Toggle Theme**: Switch themes (some may be more performant)

## Implementation Details

### Architecture

The performance system is built around several key components:

- **ViewCache**: LRU-style cache with TTL expiration
- **Debouncer**: Timer-based debouncing with cancellation
- **LazyLoader**: Pagination-based content loading
- **VirtualScroller**: Viewport-based rendering optimization
- **PerformanceMonitor**: Real-time metrics collection
- **BatchUpdate**: Update coalescing and batching

### Memory Management

- Automatic cache cleanup based on TTL
- Sample size limits for performance metrics
- Efficient data structures for large datasets
- Garbage collection friendly patterns

### Thread Safety

All performance components are thread-safe and can be used safely from multiple goroutines:

- Mutex protection for shared state
- Atomic operations where appropriate
- Safe concurrent access to caches and monitors

This performance system ensures the TUI remains responsive and efficient regardless of project size or user interaction patterns.