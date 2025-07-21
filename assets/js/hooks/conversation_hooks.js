// Conversation Channel Hooks for Phoenix LiveView

import { Socket } from "phoenix"

export const ConversationChannel = {
  mounted() {
    this.channel = null
    this.socket = null
    this.authSocket = null
    this.authChannel = null
    this.apiKeyChannel = null
    this.conversationId = null
    this.authToken = null
    
    // Listen for join event from server
    this.handleEvent("join_conversation", ({ conversation_id, project_id }) => {
      this.conversationId = conversation_id
      this.connectToChannel(conversation_id)
    })
    
    // Listen for send message event
    this.handleEvent("send_to_conversation", ({ content, conversation_id }) => {
      if (this.channel && this.channel.state === "joined") {
        this.channel.push("message", { content: content })
          .receive("ok", resp => console.log("Message sent", resp))
          .receive("error", resp => console.error("Failed to send message", resp))
      }
    })
    
    // Listen for LLM preferences update
    this.handleEvent("update_llm_preferences", ({ provider, model }) => {
      if (this.channel && this.channel.state === "joined") {
        this.channel.push("set_llm_preference", { 
          provider: provider, 
          model: model,
          is_default: true 
        })
          .receive("ok", resp => console.log("LLM preferences updated", resp))
          .receive("error", resp => console.error("Failed to update preferences", resp))
      }
    })
    
    // Auth events
    this.handleEvent("auth_login", ({ username, password }) => {
      this.connectToAuthChannel()
      if (this.authChannel) {
        this.authChannel.push("login", { username, password })
          .receive("ok", resp => console.log("Login request sent", resp))
          .receive("error", resp => this.pushEvent("auth_error", { message: "Failed to send login request" }))
      }
    })
    
    this.handleEvent("auth_logout", () => {
      if (this.authChannel) {
        this.authChannel.push("logout", {})
          .receive("ok", resp => console.log("Logout request sent", resp))
      }
      // Disconnect all channels on logout
      this.disconnect()
    })
    
    // API Key events
    this.handleEvent("api_key_generate", ({ name }) => {
      this.connectToApiKeyChannel()
      if (this.apiKeyChannel) {
        this.apiKeyChannel.push("generate", { name, expires_at: null })
          .receive("ok", resp => console.log("API key generation requested", resp))
      }
    })
    
    this.handleEvent("api_key_list", () => {
      this.connectToApiKeyChannel()
      if (this.apiKeyChannel) {
        this.apiKeyChannel.push("list", {})
          .receive("ok", resp => console.log("API key list requested", resp))
      }
    })
    
    this.handleEvent("api_key_revoke", ({ key_id }) => {
      this.connectToApiKeyChannel()
      if (this.apiKeyChannel) {
        this.apiKeyChannel.push("revoke", { api_key_id: key_id })
          .receive("ok", resp => console.log("API key revocation requested", resp))
      }
    })
  },
  
  connectToChannel(conversationId) {
    // Create socket if not exists
    if (!this.socket) {
      // Use auth token if available, otherwise use CSRF token
      const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
      const socketParams = this.authToken ? { token: this.authToken } : { token: csrfToken }
      
      this.socket = new Socket("/socket", {
        params: socketParams,
        logger: (kind, msg, data) => { console.log(`${kind}: ${msg}`, data) }
      })
      
      this.socket.connect()
    }
    
    // Join conversation channel
    this.channel = this.socket.channel(`conversation:${conversationId}`, {
      preferences: {
        provider: "openai", // This should come from user preferences
        model: "gpt-4"
      }
    })
    
    // Set up channel event handlers
    this.channel.on("response", (payload) => {
      this.pushEvent("conversation_response", {
        response: {
          content: payload.response,
          id: payload.id,
          model: payload.model_used,
          provider: payload.provider,
          tokens: payload.tokens
        }
      })
    })
    
    this.channel.on("thinking", () => {
      this.pushEvent("conversation_thinking", {})
    })
    
    this.channel.on("error", (payload) => {
      this.pushEvent("conversation_error", {
        error: {
          message: payload.message,
          details: payload.details
        }
      })
    })
    
    this.channel.on("conversation_reset", (payload) => {
      console.log("Conversation reset", payload)
    })
    
    // Join the channel
    this.channel.join()
      .receive("ok", resp => {
        console.log("Joined conversation successfully", resp)
        this.pushEvent("conversation_joined", { conversation_id: conversationId })
      })
      .receive("error", resp => {
        console.error("Unable to join conversation", resp)
        this.pushEvent("conversation_error", {
          error: {
            message: "Failed to connect to conversation",
            details: resp
          }
        })
      })
  },
  
  connectToAuthChannel() {
    // Create separate socket for auth channel
    if (!this.authSocket) {
      this.authSocket = new Socket("/auth_socket", {
        params: {},
        logger: (kind, msg, data) => { console.log(`${kind}: ${msg}`, data) }
      })
      
      this.authSocket.connect()
    }
    
    // Join auth channel
    this.authChannel = this.authSocket.channel("auth:lobby", {})
    
    // Set up auth channel event handlers
    this.authChannel.on("login_success", (payload) => {
      this.authToken = payload.token
      this.pushEvent("auth_success", {
        user: payload.user,
        token: payload.token
      })
      
      // Now that we're authenticated, reconnect to conversation channel with auth
      if (this.conversationId && this.channel) {
        this.channel.leave()
        this.connectToChannel(this.conversationId)
      }
    })
    
    this.authChannel.on("login_error", (payload) => {
      this.pushEvent("auth_error", {
        message: payload.message || "Authentication failed"
      })
    })
    
    this.authChannel.on("logout_success", () => {
      this.authToken = null
      this.disconnect()
      this.pushEvent("auth_success", {
        user: null,
        token: null
      })
    })
    
    // Join the auth channel
    this.authChannel.join()
      .receive("ok", resp => console.log("Joined auth channel", resp))
      .receive("error", resp => {
        console.error("Unable to join auth channel", resp)
        this.pushEvent("auth_error", {
          message: "Failed to connect to authentication service"
        })
      })
  },
  
  connectToApiKeyChannel() {
    if (!this.socket) {
      // Create socket if not exists  
      const token = document.querySelector("meta[name='csrf-token']").getAttribute("content")
      
      this.socket = new Socket("/socket", {
        params: { token: this.authToken || token },
        logger: (kind, msg, data) => { console.log(`${kind}: ${msg}`, data) }
      })
      
      this.socket.connect()
    }
    
    // Join API key management channel
    this.apiKeyChannel = this.socket.channel("api_keys:manage", {})
    
    // Set up API key channel event handlers
    this.apiKeyChannel.on("key_generated", (payload) => {
      this.pushEvent("api_key_generated", payload)
    })
    
    this.apiKeyChannel.on("key_list", (payload) => {
      this.pushEvent("api_key_list", payload)
    })
    
    this.apiKeyChannel.on("key_revoked", (payload) => {
      this.pushEvent("api_key_revoked", payload)
    })
    
    this.apiKeyChannel.on("error", (payload) => {
      this.pushEvent("api_key_error", {
        message: payload.message || "API key operation failed",
        details: payload.details
      })
    })
    
    // Join the channel
    this.apiKeyChannel.join()
      .receive("ok", resp => console.log("Joined API key channel", resp))
      .receive("error", resp => {
        console.error("Unable to join API key channel", resp)
        this.pushEvent("api_key_error", {
          message: "Failed to connect to API key service"
        })
      })
  },
  
  disconnect() {
    if (this.channel) {
      this.channel.leave()
      this.channel = null
    }
    if (this.authChannel) {
      this.authChannel.leave() 
      this.authChannel = null
    }
    if (this.apiKeyChannel) {
      this.apiKeyChannel.leave()
      this.apiKeyChannel = null
    }
  },
  
  destroyed() {
    this.disconnect()
    if (this.socket) {
      this.socket.disconnect()
    }
    if (this.authSocket) {
      this.authSocket.disconnect()
    }
  }
}