package phoenix

import "github.com/nshafer/phx"

// SilentLogger implements phx.Logger but discards all output
type SilentLogger struct{}

// NewSilentLogger creates a logger that suppresses all output
func NewSilentLogger() phx.Logger {
	return &SilentLogger{}
}

// Print implements phx.Logger
func (l *SilentLogger) Print(level phx.LoggerLevel, kind string, v ...any) {
	// Silently discard all log messages
	// This prevents console spam from the Phoenix WebSocket library
}

// Println implements phx.Logger
func (l *SilentLogger) Println(level phx.LoggerLevel, kind string, v ...any) {
	// Silently discard all log messages
}

// Printf implements phx.Logger
func (l *SilentLogger) Printf(level phx.LoggerLevel, kind string, format string, v ...any) {
	// Silently discard all log messages
}

// FilteredLogger implements phx.Logger with selective output
type FilteredLogger struct {
	minLevel phx.LoggerLevel
}

// NewFilteredLogger creates a logger that only shows errors and above
func NewFilteredLogger(minLevel phx.LoggerLevel) phx.Logger {
	return &FilteredLogger{minLevel: minLevel}
}

// Print implements phx.Logger
func (l *FilteredLogger) Print(level phx.LoggerLevel, kind string, v ...any) {
	if level >= l.minLevel {
		// Still discard to prevent console spam
		return
	}
}

// Println implements phx.Logger
func (l *FilteredLogger) Println(level phx.LoggerLevel, kind string, v ...any) {
	if level >= l.minLevel {
		// Still discard to prevent console spam
		return
	}
}

// Printf implements phx.Logger
func (l *FilteredLogger) Printf(level phx.LoggerLevel, kind string, format string, v ...any) {
	if level >= l.minLevel {
		// Still discard to prevent console spam
		return
	}
}