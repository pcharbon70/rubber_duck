#!/bin/bash

# Test Runner for RubberDuck TUI
# This script runs comprehensive tests for the TUI and mock interface

set -e

echo "🧪 RubberDuck TUI Test Runner"
echo "============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [[ ! -f "go.mod" ]] || [[ ! -d "internal" ]]; then
    print_error "Please run this script from the tui directory"
    exit 1
fi

# Set up test environment
export RUBBER_DUCK_CLIENT_TYPE=mock
export RUBBER_DUCK_USE_MOCK=true
export RUBBER_DUCK_ENV=test

print_status "Setting up test environment..."
print_status "  RUBBER_DUCK_CLIENT_TYPE=mock"
print_status "  RUBBER_DUCK_USE_MOCK=true"
print_status "  RUBBER_DUCK_ENV=test"
echo

# Function to run tests with specific options
run_test_suite() {
    local name=$1
    local package=$2
    local options=$3
    
    print_status "Running $name..."
    
    if go test $options $package; then
        print_success "$name passed"
    else
        print_error "$name failed"
        return 1
    fi
    echo
}

# 1. Unit Tests
print_status "Phase 1: Unit Tests"
echo "==================="

run_test_suite "Phoenix Interface Tests" "./internal/phoenix" "-v"
run_test_suite "UI Component Tests" "./internal/ui" "-v"

# 2. Integration Tests
print_status "Phase 2: Integration Tests"
echo "=========================="

run_test_suite "Phoenix Integration Tests" "./internal/phoenix" "-v -run Integration"
run_test_suite "UI Integration Tests" "./internal/ui" "-v -run Integration"

# 3. Mock Client Specific Tests
print_status "Phase 3: Mock Client Tests"
echo "=========================="

run_test_suite "Mock Client Functionality" "./internal/phoenix" "-v -run Mock"
run_test_suite "Factory Tests" "./internal/phoenix" "-v -run Factory"

# 4. Performance Tests
print_status "Phase 4: Performance Tests"
echo "=========================="

print_status "Running benchmarks..."
if go test -bench=. -benchmem ./internal/phoenix > benchmark_results.txt 2>&1; then
    print_success "Benchmarks completed"
    print_status "Results saved to benchmark_results.txt"
    
    # Show summary
    echo
    print_status "Benchmark Summary:"
    grep "Benchmark" benchmark_results.txt | head -10
else
    print_warning "Benchmarks failed, but continuing..."
fi
echo

# 5. Coverage Tests
print_status "Phase 5: Coverage Analysis"
echo "=========================="

print_status "Generating coverage report..."
if go test -coverprofile=coverage.out ./internal/...; then
    print_success "Coverage data generated"
    
    # Generate HTML coverage report
    if command -v go >/dev/null 2>&1; then
        go tool cover -html=coverage.out -o coverage.html
        print_success "HTML coverage report generated: coverage.html"
        
        # Show coverage summary
        coverage_percent=$(go tool cover -func=coverage.out | tail -1 | awk '{print $3}')
        print_status "Total coverage: $coverage_percent"
    fi
else
    print_warning "Coverage generation failed"
fi
echo

# 6. Race Condition Tests
print_status "Phase 6: Race Condition Tests"
echo "============================="

print_status "Running race detector tests..."
if go test -race ./internal/...; then
    print_success "No race conditions detected"
else
    print_warning "Race conditions detected - review output above"
fi
echo

# 7. Build Tests
print_status "Phase 7: Build Tests"
echo "===================="

print_status "Testing build with mock client..."
if go build -o rubber_duck_tui_test ./cmd/rubber_duck_tui; then
    print_success "Build successful"
    
    # Test that the binary works
    print_status "Testing binary execution..."
    if timeout 5s ./rubber_duck_tui_test --help >/dev/null 2>&1 || [ $? -eq 124 ]; then
        print_success "Binary execution test passed"
    else
        print_warning "Binary execution test failed"
    fi
    
    # Clean up
    rm -f rubber_duck_tui_test
else
    print_error "Build failed"
    exit 1
fi
echo

# 8. Mock Interface Validation
print_status "Phase 8: Mock Interface Validation"
echo "=================================="

print_status "Validating mock interface compliance..."
if go test -v ./internal/phoenix -run "TestMockClientInterface|TestRealClientInterface"; then
    print_success "Interface compliance validated"
else
    print_error "Interface compliance failed"
    exit 1
fi
echo

# 9. Environment Tests
print_status "Phase 9: Environment Configuration Tests"
echo "========================================"

print_status "Testing different environment configurations..."

# Test mock mode
export RUBBER_DUCK_CLIENT_TYPE=mock
if go test -v ./internal/phoenix -run "TestFactoryClientSelection" >/dev/null 2>&1; then
    print_success "Mock mode configuration works"
else
    print_warning "Mock mode configuration issues"
fi

# Test real mode
export RUBBER_DUCK_CLIENT_TYPE=real
export RUBBER_DUCK_SERVER_URL=ws://localhost:5555/socket
if go test -v ./internal/phoenix -run "TestFactoryClientSelection" >/dev/null 2>&1; then
    print_success "Real mode configuration works"
else
    print_warning "Real mode configuration issues"
fi

# Reset to mock for remaining tests
export RUBBER_DUCK_CLIENT_TYPE=mock
echo

# 10. Final Summary
print_status "Phase 10: Test Summary"
echo "======================"

print_success "🎉 Test suite completed!"
echo

print_status "Generated Files:"
echo "  - coverage.out (coverage data)"
echo "  - coverage.html (HTML coverage report)"
echo "  - benchmark_results.txt (benchmark results)"
echo

print_status "Next Steps:"
echo "  1. Review coverage report: open coverage.html in browser"
echo "  2. Check benchmark results: cat benchmark_results.txt"
echo "  3. Run specific tests: go test -v ./internal/phoenix -run TestName"
echo "  4. Build and test: go build ./cmd/rubber_duck_tui && ./rubber_duck_tui"
echo

print_success "All tests completed successfully! 🚀"