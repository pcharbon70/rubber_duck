package main

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// Example Go code for testing syntax highlighting
type User struct {
	ID       int       `json:"id"`
	Name     string    `json:"name"`
	Email    string    `json:"email"`
	Created  time.Time `json:"created"`
	Active   bool      `json:"active"`
}

// CreateUser creates a new user with validation
func CreateUser(name, email string) (*User, error) {
	if name == "" {
		return nil, fmt.Errorf("name cannot be empty")
	}
	
	if !strings.Contains(email, "@") {
		return nil, fmt.Errorf("invalid email format")
	}
	
	user := &User{
		ID:      generateID(),
		Name:    name,
		Email:   email,
		Created: time.Now(),
		Active:  true,
	}
	
	return user, nil
}

// generateID generates a unique ID
func generateID() int {
	// Simple ID generation - in real world use UUID
	return int(time.Now().UnixNano())
}

// ProcessUsers processes a list of users with various operations
func ProcessUsers(users []User) {
	const maxUsers = 100
	
	for i, user := range users {
		if i >= maxUsers {
			fmt.Printf("Reached maximum users: %d\n", maxUsers)
			break
		}
		
		// Print user information
		fmt.Printf("User %d: %s (%s) - Active: %t\n", 
			user.ID, user.Name, user.Email, user.Active)
		
		// Check if user needs activation
		if !user.Active {
			fmt.Printf("  -> User %s needs activation\n", user.Name)
		}
		
		// Check user age
		age := time.Since(user.Created)
		if age > 30*24*time.Hour { // 30 days
			fmt.Printf("  -> User %s is older than 30 days\n", user.Name)
		}
	}
}

func main() {
	// Create some test users
	users := []User{}
	
	testData := []struct{
		name  string
		email string
	}{
		{"Alice Johnson", "alice@example.com"},
		{"Bob Smith", "bob@test.org"},
		{"Charlie Brown", "charlie@demo.net"},
		{"Diana Prince", "diana@amazon.com"},
	}
	
	for _, data := range testData {
		user, err := CreateUser(data.name, data.email)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error creating user: %v\n", err)
			continue
		}
		users = append(users, *user)
	}
	
	// Process all users
	fmt.Println("Processing users:")
	fmt.Println("=================")
	ProcessUsers(users)
	
	// Demonstrate some string operations
	message := "Hello, World! This is a test message."
	words := strings.Fields(message)
	
	fmt.Printf("\nMessage: %s\n", message)
	fmt.Printf("Word count: %d\n", len(words))
	fmt.Printf("Uppercase: %s\n", strings.ToUpper(message))
	
	// Demonstrate channel operations
	ch := make(chan string, 3)
	ch <- "first"
	ch <- "second"
	ch <- "third"
	close(ch)
	
	fmt.Println("\nChannel contents:")
	for msg := range ch {
		fmt.Printf("  - %s\n", msg)
	}
	
	// Demonstrate map operations
	scores := map[string]int{
		"alice":   95,
		"bob":     87,
		"charlie": 92,
		"diana":   98,
	}
	
	fmt.Println("\nUser scores:")
	for name, score := range scores {
		letter := getLetterGrade(score)
		fmt.Printf("  %s: %d (%s)\n", name, score, letter)
	}
}

// getLetterGrade converts numeric score to letter grade
func getLetterGrade(score int) string {
	switch {
	case score >= 90:
		return "A"
	case score >= 80:
		return "B"
	case score >= 70:
		return "C"
	case score >= 60:
		return "D"
	default:
		return "F"
	}
}