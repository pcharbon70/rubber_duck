package ui

import (
	"unicode"
)

// EstimateTokens provides a rough estimate of token count
// This is a simple implementation - for accurate counts, use tiktoken-go
func EstimateTokens(text string) int {
	// Simple heuristic: ~4 characters per token on average
	// This is a rough approximation that works reasonably well for English text
	
	if text == "" {
		return 0
	}
	
	// Count words (split by whitespace and punctuation)
	words := 0
	inWord := false
	
	for _, r := range text {
		if unicode.IsSpace(r) || unicode.IsPunct(r) {
			if inWord {
				words++
				inWord = false
			}
		} else {
			inWord = true
		}
	}
	
	if inWord {
		words++
	}
	
	// Estimate tokens based on words
	// Average English word is about 1.3 tokens
	tokens := int(float64(words) * 1.3)
	
	// Account for special tokens (start/end tokens, etc.)
	tokens += 3
	
	return tokens
}

// EstimateConversationTokens estimates tokens for a full conversation
func EstimateConversationTokens(messages []ChatMessage) int {
	total := 0
	
	for _, msg := range messages {
		// Each message has overhead (role tokens, separators)
		total += 4
		
		// Add content tokens
		total += EstimateTokens(msg.Content)
	}
	
	return total
}

// GetModelTokenLimit returns the token limit for a given model
func GetModelTokenLimit(model string) int {
	switch model {
	case "gpt-4":
		return 8192
	case "gpt-4-32k":
		return 32768
	case "gpt-3.5-turbo":
		return 4096
	case "gpt-3.5-turbo-16k":
		return 16384
	case "claude-3-opus":
		return 200000
	case "claude-3-sonnet":
		return 200000
	case "claude-2.1":
		return 100000
	case "llama2":
		return 4096
	case "mistral":
		return 8192
	case "codellama":
		return 16384
	default:
		return 4096 // Conservative default
	}
}

// GetRemainingTokens calculates remaining tokens for a model
func GetRemainingTokens(model string, usedTokens int) int {
	limit := GetModelTokenLimit(model)
	remaining := limit - usedTokens
	if remaining < 0 {
		return 0
	}
	return remaining
}

// TokenUsageLevel returns the usage level for color coding
type TokenUsageLevel int

const (
	TokenUsageLow TokenUsageLevel = iota
	TokenUsageMedium
	TokenUsageHigh
	TokenUsageCritical
)

// GetTokenUsageLevel returns the usage level based on percentage
func GetTokenUsageLevel(used, limit int) TokenUsageLevel {
	if limit == 0 {
		return TokenUsageLow
	}
	
	percentage := float64(used) / float64(limit)
	
	switch {
	case percentage >= 0.95:
		return TokenUsageCritical
	case percentage >= 0.8:
		return TokenUsageHigh
	case percentage >= 0.6:
		return TokenUsageMedium
	default:
		return TokenUsageLow
	}
}