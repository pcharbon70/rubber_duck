/**
 * Conversation Channel Client
 * 
 * Example client for interacting with the RubberDuck conversation channel.
 */

import { Socket } from "phoenix"

class ConversationClient {
  constructor(endpoint, apiKey) {
    this.endpoint = endpoint
    this.apiKey = apiKey
    this.socket = null
    this.channel = null
    this.conversationId = this.generateConversationId()
    this.onMessageCallbacks = []
    this.onThinkingCallbacks = []
    this.onErrorCallbacks = []
  }

  /**
   * Connect to the conversation channel
   */
  connect() {
    return new Promise((resolve, reject) => {
      // Create socket connection
      this.socket = new Socket(this.endpoint, {
        params: { api_key: this.apiKey }
      })

      this.socket.connect()

      // Join conversation channel
      this.channel = this.socket.channel(`conversation:${this.conversationId}`, {
        user_id: null // Will be assigned by server
      })

      // Set up event handlers
      this.setupEventHandlers()

      // Join the channel
      this.channel.join()
        .receive("ok", resp => {
          console.log("Joined conversation", resp)
          resolve(resp)
        })
        .receive("error", resp => {
          console.error("Unable to join conversation", resp)
          reject(resp)
        })
    })
  }

  /**
   * Send a message in the conversation
   */
  sendMessage(content, options = {}) {
    if (!this.channel) {
      throw new Error("Not connected to conversation channel")
    }

    return new Promise((resolve, reject) => {
      this.channel.push("message", {
        content: content,
        context: options.context || {},
        options: options.options || {},
        llm_config: options.llm_config || {}
      })
        .receive("ok", resp => resolve(resp))
        .receive("error", resp => reject(resp))
        .receive("timeout", () => reject(new Error("Request timed out")))
    })
  }

  /**
   * Start a new conversation (clears context)
   */
  newConversation() {
    if (!this.channel) {
      throw new Error("Not connected to conversation channel")
    }

    return new Promise((resolve, reject) => {
      this.channel.push("new_conversation", {})
        .receive("ok", resp => resolve(resp))
        .receive("error", resp => reject(resp))
    })
  }

  /**
   * Update conversation context
   */
  setContext(context) {
    if (!this.channel) {
      throw new Error("Not connected to conversation channel")
    }

    return new Promise((resolve, reject) => {
      this.channel.push("set_context", { context })
        .receive("ok", resp => resolve(resp))
        .receive("error", resp => reject(resp))
    })
  }

  /**
   * Send typing indicator
   */
  setTyping(isTyping) {
    if (!this.channel) {
      throw new Error("Not connected to conversation channel")
    }

    this.channel.push("typing", { typing: isTyping })
  }

  /**
   * Register callback for messages
   */
  onMessage(callback) {
    this.onMessageCallbacks.push(callback)
  }

  /**
   * Register callback for thinking indicator
   */
  onThinking(callback) {
    this.onThinkingCallbacks.push(callback)
  }

  /**
   * Register callback for errors
   */
  onError(callback) {
    this.onErrorCallbacks.push(callback)
  }

  /**
   * Disconnect from the channel
   */
  disconnect() {
    if (this.channel) {
      this.channel.leave()
      this.channel = null
    }
    if (this.socket) {
      this.socket.disconnect()
      this.socket = null
    }
  }

  // Private methods

  setupEventHandlers() {
    // Handle responses
    this.channel.on("response", response => {
      console.log("Received response:", response)
      this.onMessageCallbacks.forEach(cb => cb(response))
    })

    // Handle thinking indicator
    this.channel.on("thinking", () => {
      console.log("AI is thinking...")
      this.onThinkingCallbacks.forEach(cb => cb())
    })

    // Handle errors
    this.channel.on("error", error => {
      console.error("Conversation error:", error)
      this.onErrorCallbacks.forEach(cb => cb(error))
    })

    // Handle conversation reset
    this.channel.on("conversation_reset", data => {
      console.log("Conversation reset:", data)
    })

    // Handle context updates
    this.channel.on("context_updated", data => {
      console.log("Context updated:", data)
    })
  }

  generateConversationId() {
    return `conv_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  }
}

// Example usage:
/*
const client = new ConversationClient("/socket", "your_api_key")

// Set up event handlers
client.onMessage(response => {
  console.log("AI:", response.response)
  console.log("Type:", response.conversation_type)
  console.log("Metadata:", response.metadata)
})

client.onThinking(() => {
  console.log("AI is processing...")
})

client.onError(error => {
  console.error("Error:", error.message)
})

// Connect and start conversation
client.connect().then(() => {
  // Send a message
  client.sendMessage("What is Elixir?")
  
  // Send a message with context
  client.sendMessage("How do I create a GenServer?", {
    context: {
      skill_level: "intermediate",
      project_type: "web_app"
    },
    options: {
      include_examples: true
    }
  })
  
  // Update context
  client.setContext({
    language: "elixir",
    framework: "phoenix"
  })
  
  // Start new conversation
  client.newConversation()
})
*/

export default ConversationClient