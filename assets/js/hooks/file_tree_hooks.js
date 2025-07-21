// File tree related hooks for Phoenix LiveView

export const FocusOnMount = {
  mounted() {
    this.el.focus()
    // Select all text for easy replacement
    this.el.select()
  }
}

export const FileTreeKeyboard = {
  mounted() {
    this.handleKeyDown = (e) => {
      // Only handle keys when the file tree has focus
      if (!this.el.contains(document.activeElement)) return
      
      const keys = ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter', ' ']
      
      if (keys.includes(e.key)) {
        e.preventDefault()
        
        // For multi-selection support
        const eventData = {
          key: e.key,
          shiftKey: e.shiftKey,
          ctrlKey: e.ctrlKey,
          metaKey: e.metaKey
        }
        
        this.pushEvent("tree_keydown", eventData)
      }
      
      // Vim-style navigation
      const vimKeys = {
        'j': 'ArrowDown',
        'k': 'ArrowUp',
        'h': 'ArrowLeft', 
        'l': 'ArrowRight',
        'o': 'Enter'
      }
      
      if (vimKeys[e.key] && !e.ctrlKey && !e.metaKey) {
        e.preventDefault()
        
        const eventData = {
          key: vimKeys[e.key],
          shiftKey: e.shiftKey,
          ctrlKey: false,
          metaKey: false
        }
        
        this.pushEvent("tree_keydown", eventData)
      }
    }
    
    document.addEventListener('keydown', this.handleKeyDown)
  },
  
  destroyed() {
    document.removeEventListener('keydown', this.handleKeyDown)
  }
}

export const FileTreeDragDrop = {
  mounted() {
    // Enable drag and drop for file operations
    this.el.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = 'copy'
      this.el.classList.add('drag-over')
    })
    
    this.el.addEventListener('dragleave', (e) => {
      if (!this.el.contains(e.relatedTarget)) {
        this.el.classList.remove('drag-over')
      }
    })
    
    this.el.addEventListener('drop', (e) => {
      e.preventDefault()
      this.el.classList.remove('drag-over')
      
      const files = Array.from(e.dataTransfer.files)
      if (files.length > 0) {
        // Handle file drops
        this.pushEvent("files_dropped", { 
          files: files.map(f => ({
            name: f.name,
            size: f.size,
            type: f.type,
            lastModified: f.lastModified
          }))
        })
      }
    })
  }
}

export const FileTreeVirtualScroll = {
  mounted() {
    // TODO: Implement virtual scrolling for large file trees
    // This would improve performance by only rendering visible nodes
    
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          // Load more items when scrolling near the end
          if (entry.target.dataset.loadMore) {
            this.pushEvent("load_more", { path: entry.target.dataset.path })
          }
        }
      })
    }, {
      root: this.el,
      rootMargin: '100px'
    })
    
    // Observe sentinel elements
    const sentinels = this.el.querySelectorAll('[data-load-more]')
    sentinels.forEach(el => this.observer.observe(el))
  },
  
  updated() {
    // Re-observe after DOM updates
    const sentinels = this.el.querySelectorAll('[data-load-more]')
    sentinels.forEach(el => this.observer.observe(el))
  },
  
  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }
}