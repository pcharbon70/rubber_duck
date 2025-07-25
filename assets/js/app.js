// We import the CSS which includes Tailwind and any custom styles.
import "../css/app.css"

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"

// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar.js"

// Import our custom hooks
import {ConversationChannel} from "./hooks/conversation_hooks"
import {AutoResize, ChatScroll, CopyToClipboard} from "./hooks/chat_hooks"
import {FocusOnMount, FileTreeKeyboard, FileTreeDragDrop, FileTreeVirtualScroll} from "./hooks/file_tree_hooks"
import {MonacoEditor} from "./hooks/monaco_editor"

// Define all hooks
let Hooks = {
  ConversationChannel: ConversationChannel,
  AutoResize: AutoResize,
  ChatScroll: ChatScroll,
  CopyToClipboard: CopyToClipboard,
  FocusOnMount: FocusOnMount,
  FileTreeKeyboard: FileTreeKeyboard,
  FileTreeDragDrop: FileTreeDragDrop,
  FileTreeVirtualScroll: FileTreeVirtualScroll,
  MonacoEditor: MonacoEditor
}

// Get CSRF token
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Create LiveSocket instance
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket