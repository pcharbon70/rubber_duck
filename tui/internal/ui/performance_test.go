package ui

import (
	"testing"
	"time"
)

func TestViewCache(t *testing.T) {
	cache := NewViewCache()
	
	// Test setting and getting
	cache.Set("test-key", "test-content", 12345)
	
	content, found := cache.Get("test-key", 1*time.Second)
	if !found {
		t.Error("Expected to find cached content")
	}
	
	if content != "test-content" {
		t.Errorf("Expected 'test-content', got '%s'", content)
	}
	
	// Test expiration
	cache.Set("expire-key", "expire-content", 67890)
	time.Sleep(10 * time.Millisecond)
	
	content, found = cache.Get("expire-key", 5*time.Millisecond)
	if found {
		t.Error("Expected cached content to be expired")
	}
	
	// Test clear
	cache.Clear()
	content, found = cache.Get("test-key", 1*time.Second)
	if found {
		t.Error("Expected cache to be cleared")
	}
}

func TestDebouncer(t *testing.T) {
	executed := false
	debouncer := NewDebouncer(50 * time.Millisecond)
	
	// Function should not execute immediately
	debouncer.Debounce(func() {
		executed = true
	})
	
	if executed {
		t.Error("Function should not execute immediately")
	}
	
	// Wait for debounce delay
	time.Sleep(60 * time.Millisecond)
	
	if !executed {
		t.Error("Function should have executed after delay")
	}
	
	// Test that rapid calls are debounced
	counter := 0
	debouncer2 := NewDebouncer(50 * time.Millisecond)
	
	for i := 0; i < 5; i++ {
		debouncer2.Debounce(func() {
			counter++
		})
		time.Sleep(10 * time.Millisecond)
	}
	
	time.Sleep(60 * time.Millisecond)
	
	if counter != 1 {
		t.Errorf("Expected counter to be 1 (debounced), got %d", counter)
	}
}

func TestLazyLoader(t *testing.T) {
	items := make([]interface{}, 20)
	for i := 0; i < 20; i++ {
		items[i] = i
	}
	
	loader := NewLazyLoader(items, 5)
	
	// Test initial state
	if !loader.HasMore() {
		t.Error("Should have more items to load")
	}
	
	if len(loader.GetLoaded()) != 0 {
		t.Error("Should start with no loaded items")
	}
	
	// Load first page
	newItems := loader.LoadNext()
	if len(newItems) != 5 {
		t.Errorf("Expected 5 items, got %d", len(newItems))
	}
	
	loaded := loader.GetLoaded()
	if len(loaded) != 5 {
		t.Errorf("Expected 5 loaded items, got %d", len(loaded))
	}
	
	// Load remaining pages
	pageCount := 1
	for loader.HasMore() {
		loader.LoadNext()
		pageCount++
	}
	
	if pageCount != 4 {
		t.Errorf("Expected 4 pages, got %d", pageCount)
	}
	
	if len(loader.GetLoaded()) != 20 {
		t.Errorf("Expected all 20 items loaded, got %d", len(loader.GetLoaded()))
	}
	
	// Test reset
	loader.Reset()
	if len(loader.GetLoaded()) != 0 {
		t.Error("Reset should clear loaded items")
	}
	
	if !loader.HasMore() {
		t.Error("Reset should make items available again")
	}
}

func TestVirtualScroller(t *testing.T) {
	scroller := NewVirtualScroller(100, 10, 50)
	
	// Test initial state
	start, end := scroller.GetVisibleRange()
	if start != 0 {
		t.Errorf("Expected start 0, got %d", start)
	}
	
	// Should show first visible items plus buffer
	expectedEnd := (50/10 + 1) + 5 + 5 // visible + 1 + buffer before + buffer after
	if end > expectedEnd {
		t.Errorf("Expected end around %d, got %d", expectedEnd, end)
	}
	
	// Test scrolling
	scroller.Scroll(100)
	start, end = scroller.GetVisibleRange()
	
	if start < 5 { // Should have moved down significantly (considering buffer)
		t.Errorf("Expected start to be higher after scrolling, got %d", start)
	}
	
	// Test scroll bounds
	scroller.Scroll(-1000) // Scroll way up
	if scroller.GetScrollPosition() != 0 {
		t.Error("Should not scroll above 0")
	}
	
	scroller.Scroll(10000) // Scroll way down
	start, end = scroller.GetVisibleRange()
	if end > 100 {
		t.Error("Should not scroll beyond total items")
	}
}

func TestPerformanceMonitor(t *testing.T) {
	monitor := NewPerformanceMonitor(10)
	
	// Test initial state
	stats := monitor.GetStats()
	if stats["render_samples"] != 0 {
		t.Error("Should start with no samples")
	}
	
	// Test render timing
	monitor.StartRender()
	time.Sleep(10 * time.Millisecond)
	monitor.EndRender()
	
	stats = monitor.GetStats()
	if stats["render_samples"] != 1 {
		t.Error("Should have one render sample")
	}
	
	avgRender := stats["avg_render_time"].(time.Duration)
	if avgRender < 5*time.Millisecond {
		t.Error("Average render time should be at least 5ms")
	}
	
	// Test update timing
	monitor.StartUpdate()
	time.Sleep(5 * time.Millisecond)
	monitor.EndUpdate()
	
	stats = monitor.GetStats()
	if stats["update_samples"] != 1 {
		t.Error("Should have one update sample")
	}
	
	// Test sample limit
	for i := 0; i < 15; i++ {
		monitor.StartRender()
		monitor.EndRender()
	}
	
	stats = monitor.GetStats()
	if stats["render_samples"].(int) > 10 {
		t.Error("Should not exceed max samples")
	}
}

func TestUtilityFunctions(t *testing.T) {
	// Test max function
	if max(5, 10) != 10 {
		t.Error("max(5, 10) should be 10")
	}
	
	if max(10, 5) != 10 {
		t.Error("max(10, 5) should be 10")
	}
	
	if max(-5, -10) != -5 {
		t.Error("max(-5, -10) should be -5")
	}
	
	// Test min function
	if min(5, 10) != 5 {
		t.Error("min(5, 10) should be 5")
	}
	
	if min(10, 5) != 5 {
		t.Error("min(10, 5) should be 5")
	}
	
	if min(-5, -10) != -10 {
		t.Error("min(-5, -10) should be -10")
	}
}

func TestModelPerformanceIntegration(t *testing.T) {
	model := NewModel()
	
	// Test that performance components are initialized
	if model.performanceMonitor == nil {
		t.Error("Performance monitor should be initialized")
	}
	
	if model.viewCache == nil {
		t.Error("View cache should be initialized")
	}
	
	if model.saveDebouncer == nil {
		t.Error("Save debouncer should be initialized")
	}
	
	// Test performance stats retrieval
	stats := model.GetPerformanceStats()
	if stats == nil {
		t.Error("Should be able to get performance stats")
	}
	
	// Test cache clearing
	model.ClearViewCache() // Should not panic
}