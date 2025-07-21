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
    
    this.handleEvent("focus_input", ({ id }) => {
      const input = document.getElementById(id);
      if (input) {
        input.focus();
        // Move cursor to end
        input.setSelectionRange(input.value.length, input.value.length);
      }
    });
  }
};

export const AutoResize = {
  mounted() {
    this.resize();
    
    this.el.addEventListener('input', () => {
      this.resize();
    });
  },
  
  updated() {
    this.resize();
  },
  
  resize() {
    // Reset height to auto to get the correct scrollHeight
    this.el.style.height = 'auto';
    // Set the height to the scrollHeight
    this.el.style.height = this.el.scrollHeight + 'px';
    
    // Limit max height (10 rows approximately)
    const lineHeight = parseInt(window.getComputedStyle(this.el).lineHeight);
    const maxHeight = lineHeight * 10;
    
    if (this.el.scrollHeight > maxHeight) {
      this.el.style.height = maxHeight + 'px';
      this.el.style.overflowY = 'auto';
    } else {
      this.el.style.overflowY = 'hidden';
    }
  }
};

export const CopyToClipboard = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({ text }) => {
      navigator.clipboard.writeText(text).then(() => {
        // Show a brief success message
        const notification = document.createElement('div');
        notification.textContent = 'Copied to clipboard!';
        notification.className = 'fixed bottom-4 right-4 bg-green-500 text-white px-4 py-2 rounded shadow-lg z-50';
        document.body.appendChild(notification);
        
        setTimeout(() => {
          notification.remove();
        }, 2000);
      }).catch(err => {
        console.error('Failed to copy text: ', err);
      });
    });
  }
};