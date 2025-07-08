/**
 * Example JavaScript client for RubberDuck Phoenix Channels
 * 
 * This demonstrates how to connect to the WebSocket and use channels
 * for real-time code completions and analysis.
 */

import { Socket } from "phoenix"

// Initialize socket connection
const socket = new Socket("/socket", {
  params: { token: window.userToken },
  logger: (kind, msg, data) => { console.log(`${kind}: ${msg}`, data) }
})

socket.connect()

// Join a project channel
const projectId = "your-project-id"
const channel = socket.channel(`code:project:${projectId}`, {
  cursor_position: { line: 1, column: 1 }
})

// Handle channel join
channel.join()
  .receive("ok", resp => {
    console.log("Joined successfully", resp)
  })
  .receive("error", resp => {
    console.error("Unable to join", resp)
  })

// Request code completion
function requestCompletion(code, cursorPosition, fileType = "elixir") {
  channel.push("request_completion", {
    code: code,
    cursor_position: cursorPosition,
    file_type: fileType,
    options: {
      max_length: 100,
      temperature: 0.7
    }
  })
  .receive("ok", msg => {
    console.log("Completion started:", msg.completion_id)
  })
  .receive("error", err => {
    console.error("Completion error:", err)
  })
}

// Handle completion chunks
channel.on("completion_chunk", payload => {
  console.log("Received chunk:", payload.chunk)
  // Update UI with streaming completion
})

channel.on("completion_done", payload => {
  console.log("Completion finished:", payload)
})

channel.on("completion_error", payload => {
  console.error("Completion error:", payload.error)
})

// Request code analysis
function requestAnalysis(code, fileType = "elixir") {
  channel.push("request_analysis", {
    code: code,
    file_type: fileType
  })
  .receive("ok", msg => {
    console.log("Analysis started:", msg.analysis_id)
  })
}

// Handle analysis results
channel.on("analysis_result", payload => {
  console.log("Analysis complete:", payload.result)
})

// Collaborative features - send cursor position
function updateCursorPosition(line, column) {
  channel.push("cursor_position", {
    position: { line: line, column: column }
  })
}

// Handle other users' cursor updates
channel.on("cursor_update", payload => {
  console.log(`User ${payload.user_id} moved cursor to:`, payload.position)
})

// Send code changes for collaboration
function sendCodeChange(changes) {
  channel.push("code_change", { changes: changes })
    .receive("ok", () => console.log("Changes sent"))
    .receive("error", err => console.error("Failed to send changes:", err))
}

// Handle code updates from other users
channel.on("code_updated", payload => {
  console.log(`User ${payload.user_id} made changes:`, payload.changes)
  // Apply changes to editor
})

// Presence tracking
channel.on("presence_state", state => {
  console.log("Current users:", state)
})

channel.on("presence_diff", diff => {
  console.log("Presence changed:", diff)
})

// Example usage
requestCompletion(
  "defmodule MyModule do\n  def hello do\n    ",
  { line: 3, column: 4 }
)

updateCursorPosition(3, 10)

// Clean up on page leave
window.addEventListener("beforeunload", () => {
  channel.leave()
  socket.disconnect()
})