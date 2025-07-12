package ui

import (
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// ViewCache caches rendered views to avoid unnecessary re-rendering
type ViewCache struct {
	cache map[string]CachedView
	mutex sync.RWMutex
}

// CachedView represents a cached rendered view
type CachedView struct {
	Content   string
	Timestamp time.Time
	Hash      uint64
}

// NewViewCache creates a new view cache
func NewViewCache() *ViewCache {
	return &ViewCache{
		cache: make(map[string]CachedView),
	}
}

// Get retrieves a cached view if it exists and is still valid
func (vc *ViewCache) Get(key string, maxAge time.Duration) (string, bool) {
	vc.mutex.RLock()
	defer vc.mutex.RUnlock()
	
	cached, exists := vc.cache[key]
	if !exists {
		return "", false
	}
	
	// Check if cache is still valid
	if time.Since(cached.Timestamp) > maxAge {
		return "", false
	}
	
	return cached.Content, true
}

// Set stores a rendered view in the cache
func (vc *ViewCache) Set(key, content string, hash uint64) {
	vc.mutex.Lock()
	defer vc.mutex.Unlock()
	
	vc.cache[key] = CachedView{
		Content:   content,
		Timestamp: time.Now(),
		Hash:      hash,
	}
}

// Clear removes all cached views
func (vc *ViewCache) Clear() {
	vc.mutex.Lock()
	defer vc.mutex.Unlock()
	
	vc.cache = make(map[string]CachedView)
}

// Remove removes a specific cached view
func (vc *ViewCache) Remove(key string) {
	vc.mutex.Lock()
	defer vc.mutex.Unlock()
	
	delete(vc.cache, key)
}

// Debouncer helps prevent excessive updates by debouncing rapid events
type Debouncer struct {
	timer   *time.Timer
	mutex   sync.Mutex
	delay   time.Duration
	pending func()
}

// NewDebouncer creates a new debouncer with the specified delay
func NewDebouncer(delay time.Duration) *Debouncer {
	return &Debouncer{
		delay: delay,
	}
}

// Debounce debounces a function call - only the last call within the delay period will execute
func (d *Debouncer) Debounce(fn func()) {
	d.mutex.Lock()
	defer d.mutex.Unlock()
	
	d.pending = fn
	
	if d.timer != nil {
		d.timer.Stop()
	}
	
	d.timer = time.AfterFunc(d.delay, func() {
		d.mutex.Lock()
		defer d.mutex.Unlock()
		
		if d.pending != nil {
			d.pending()
			d.pending = nil
		}
	})
}

// Stop cancels any pending debounced function call
func (d *Debouncer) Stop() {
	d.mutex.Lock()
	defer d.mutex.Unlock()
	
	if d.timer != nil {
		d.timer.Stop()
		d.timer = nil
	}
	d.pending = nil
}

// LazyLoader handles lazy loading of large content
type LazyLoader struct {
	items       []interface{}
	loadedItems []interface{}
	pageSize    int
	currentPage int
	totalPages  int
}

// NewLazyLoader creates a new lazy loader
func NewLazyLoader(items []interface{}, pageSize int) *LazyLoader {
	totalPages := (len(items) + pageSize - 1) / pageSize
	if totalPages == 0 {
		totalPages = 1
	}
	
	return &LazyLoader{
		items:       items,
		loadedItems: make([]interface{}, 0),
		pageSize:    pageSize,
		currentPage: 0,
		totalPages:  totalPages,
	}
}

// LoadNext loads the next page of items
func (ll *LazyLoader) LoadNext() []interface{} {
	if ll.currentPage >= ll.totalPages {
		return nil
	}
	
	start := ll.currentPage * ll.pageSize
	end := start + ll.pageSize
	if end > len(ll.items) {
		end = len(ll.items)
	}
	
	newItems := ll.items[start:end]
	ll.loadedItems = append(ll.loadedItems, newItems...)
	ll.currentPage++
	
	return newItems
}

// GetLoaded returns all currently loaded items
func (ll *LazyLoader) GetLoaded() []interface{} {
	return ll.loadedItems
}

// HasMore returns true if there are more items to load
func (ll *LazyLoader) HasMore() bool {
	return ll.currentPage < ll.totalPages
}

// Reset resets the lazy loader to the beginning
func (ll *LazyLoader) Reset() {
	ll.currentPage = 0
	ll.loadedItems = make([]interface{}, 0)
}

// VirtualScroller implements virtual scrolling for large lists
type VirtualScroller struct {
	totalItems  int
	itemHeight  int
	viewHeight  int
	scrollPos   int
	visibleStart int
	visibleEnd   int
	bufferSize   int // Extra items to render for smooth scrolling
}

// NewVirtualScroller creates a new virtual scroller
func NewVirtualScroller(totalItems, itemHeight, viewHeight int) *VirtualScroller {
	vs := &VirtualScroller{
		totalItems: totalItems,
		itemHeight: itemHeight,
		viewHeight: viewHeight,
		bufferSize: 5, // Default buffer
	}
	vs.updateVisibleRange()
	return vs
}

// Scroll scrolls the view by the specified offset
func (vs *VirtualScroller) Scroll(offset int) {
	vs.scrollPos += offset
	if vs.scrollPos < 0 {
		vs.scrollPos = 0
	}
	
	maxScroll := (vs.totalItems * vs.itemHeight) - vs.viewHeight
	if maxScroll < 0 {
		maxScroll = 0
	}
	if vs.scrollPos > maxScroll {
		vs.scrollPos = maxScroll
	}
	
	vs.updateVisibleRange()
}

// SetScrollPosition sets the absolute scroll position
func (vs *VirtualScroller) SetScrollPosition(pos int) {
	vs.scrollPos = pos
	vs.updateVisibleRange()
}

// GetVisibleRange returns the range of items that should be rendered
func (vs *VirtualScroller) GetVisibleRange() (start, end int) {
	return vs.visibleStart, vs.visibleEnd
}

// GetScrollPosition returns the current scroll position
func (vs *VirtualScroller) GetScrollPosition() int {
	return vs.scrollPos
}

// updateVisibleRange calculates which items should be visible
func (vs *VirtualScroller) updateVisibleRange() {
	if vs.itemHeight == 0 {
		vs.visibleStart = 0
		vs.visibleEnd = vs.totalItems
		return
	}
	
	// Calculate visible range
	vs.visibleStart = vs.scrollPos / vs.itemHeight
	visibleItems := vs.viewHeight / vs.itemHeight
	vs.visibleEnd = vs.visibleStart + visibleItems + 1
	
	// Add buffer for smooth scrolling
	vs.visibleStart = max(0, vs.visibleStart-vs.bufferSize)
	vs.visibleEnd = min(vs.totalItems, vs.visibleEnd+vs.bufferSize)
}

// max returns the maximum of two integers
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

// min returns the minimum of two integers
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// PerformanceMonitor tracks UI performance metrics
type PerformanceMonitor struct {
	renderTimes   []time.Duration
	updateTimes   []time.Duration
	maxSamples    int
	mutex         sync.RWMutex
	lastRenderTime time.Time
	lastUpdateTime time.Time
}

// NewPerformanceMonitor creates a new performance monitor
func NewPerformanceMonitor(maxSamples int) *PerformanceMonitor {
	return &PerformanceMonitor{
		renderTimes: make([]time.Duration, 0, maxSamples),
		updateTimes: make([]time.Duration, 0, maxSamples),
		maxSamples:  maxSamples,
	}
}

// StartRender marks the start of a render operation
func (pm *PerformanceMonitor) StartRender() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	pm.lastRenderTime = time.Now()
}

// EndRender marks the end of a render operation and records the duration
func (pm *PerformanceMonitor) EndRender() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	if !pm.lastRenderTime.IsZero() {
		duration := time.Since(pm.lastRenderTime)
		pm.addRenderTime(duration)
		pm.lastRenderTime = time.Time{}
	}
}

// StartUpdate marks the start of an update operation
func (pm *PerformanceMonitor) StartUpdate() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	pm.lastUpdateTime = time.Now()
}

// EndUpdate marks the end of an update operation and records the duration
func (pm *PerformanceMonitor) EndUpdate() {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	if !pm.lastUpdateTime.IsZero() {
		duration := time.Since(pm.lastUpdateTime)
		pm.addUpdateTime(duration)
		pm.lastUpdateTime = time.Time{}
	}
}

// addRenderTime adds a render time sample
func (pm *PerformanceMonitor) addRenderTime(duration time.Duration) {
	if len(pm.renderTimes) >= pm.maxSamples {
		// Remove oldest sample
		pm.renderTimes = pm.renderTimes[1:]
	}
	pm.renderTimes = append(pm.renderTimes, duration)
}

// addUpdateTime adds an update time sample
func (pm *PerformanceMonitor) addUpdateTime(duration time.Duration) {
	if len(pm.updateTimes) >= pm.maxSamples {
		// Remove oldest sample
		pm.updateTimes = pm.updateTimes[1:]
	}
	pm.updateTimes = append(pm.updateTimes, duration)
}

// GetAverageRenderTime returns the average render time
func (pm *PerformanceMonitor) GetAverageRenderTime() time.Duration {
	pm.mutex.RLock()
	defer pm.mutex.RUnlock()
	
	if len(pm.renderTimes) == 0 {
		return 0
	}
	
	var total time.Duration
	for _, t := range pm.renderTimes {
		total += t
	}
	return total / time.Duration(len(pm.renderTimes))
}

// GetAverageUpdateTime returns the average update time
func (pm *PerformanceMonitor) GetAverageUpdateTime() time.Duration {
	pm.mutex.RLock()
	defer pm.mutex.RUnlock()
	
	if len(pm.updateTimes) == 0 {
		return 0
	}
	
	var total time.Duration
	for _, t := range pm.updateTimes {
		total += t
	}
	return total / time.Duration(len(pm.updateTimes))
}

// GetStats returns performance statistics
func (pm *PerformanceMonitor) GetStats() map[string]interface{} {
	pm.mutex.RLock()
	defer pm.mutex.RUnlock()
	
	stats := map[string]interface{}{
		"avg_render_time": pm.GetAverageRenderTime(),
		"avg_update_time": pm.GetAverageUpdateTime(),
		"render_samples":  len(pm.renderTimes),
		"update_samples":  len(pm.updateTimes),
	}
	
	if len(pm.renderTimes) > 0 {
		stats["last_render_time"] = pm.renderTimes[len(pm.renderTimes)-1]
	}
	
	if len(pm.updateTimes) > 0 {
		stats["last_update_time"] = pm.updateTimes[len(pm.updateTimes)-1]
	}
	
	return stats
}

// BatchUpdate allows batching multiple UI updates into a single operation
type BatchUpdate struct {
	updates []tea.Cmd
	mutex   sync.Mutex
	timer   *time.Timer
	delay   time.Duration
	program *tea.Program
}

// NewBatchUpdate creates a new batch update manager
func NewBatchUpdate(delay time.Duration, program *tea.Program) *BatchUpdate {
	return &BatchUpdate{
		updates: make([]tea.Cmd, 0),
		delay:   delay,
		program: program,
	}
}

// Add adds an update command to the batch
func (bu *BatchUpdate) Add(cmd tea.Cmd) {
	bu.mutex.Lock()
	defer bu.mutex.Unlock()
	
	bu.updates = append(bu.updates, cmd)
	
	if bu.timer != nil {
		bu.timer.Stop()
	}
	
	bu.timer = time.AfterFunc(bu.delay, bu.flush)
}

// flush executes all batched updates
func (bu *BatchUpdate) flush() {
	bu.mutex.Lock()
	defer bu.mutex.Unlock()
	
	if len(bu.updates) == 0 {
		return
	}
	
	// Execute all batched commands
	for _, cmd := range bu.updates {
		if cmd != nil && bu.program != nil {
			bu.program.Send(cmd())
		}
	}
	
	// Clear the batch
	bu.updates = bu.updates[:0]
	bu.timer = nil
}