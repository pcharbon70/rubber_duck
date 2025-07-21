// Chat-related hooks for the coding session LiveView

export const ChatScroll = {
  mounted() {
    this.scrollToBottom();
    
    // Observe for new messages
    this.observer = new MutationObserver(() => {
      this.scrollToBottom();
    });
    
    this.observer.observe(this.el, { 
      childList: true, 
      subtree: true 
    });
  },
  
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
  
  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  }
};

export const FocusChat = {
  mounted() {
    this.handleEvent("focus_chat", () => {
      const input = this.el.querySelector('input[name="message"]');
      if (input) {
        input.focus();
      }
    });
  }
};