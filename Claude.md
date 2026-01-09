# MCPWA - WhatsApp MCP Connector

## Project Overview

MCPWA is a macOS Cocoa application that serves as a WhatsApp Assistant with two main operating modes:
- **MCP Mode**: Gemini-powered chat with WhatsApp integration via Accessibility API
- **RAG Mode**: Query external RAG (Retrieval-Augmented Generation) service

The app provides an MCP (Model Context Protocol) bridge between LLM (Gemini or Claude) and WhatsApp.

## Project Structure

```
mcpwa/
├── mcpwa/                    # Main Cocoa App
│   ├── AppDelegate.m/h       # App entry point, MCP server lifecycle
│   ├── BotChatWindowController.m/h  # Main chat UI & message handling
│   ├── GeminiClient.m/h      # Gemini API client
│   ├── RAGClient.m/h         # RAG API client (NEW)
│   ├── MCPServer.m/h         # MCP protocol server
│   ├── MCPSocketTransport.m/h # Socket transport for MCP
│   ├── MCPStdioTransport.m/h # Stdio transport for MCP
│   ├── SettingsWindowController.m/h # User preferences (theme, mode, RAG URL)
│   ├── DebugConfigWindowController.m/h # Debug configuration
│   ├── WAAccessibility.m/h   # WhatsApp UI automation via Accessibility API
│   ├── WAAccessibilityExplorer.m/h # Accessibility tree explorer
│   ├── WALogger.m/h          # Logging utility
│   └── Assets/               # App icons, images
└── mcp-shim/                 # Separate MCP bridge for Claude Desktop
```

## Architecture

### Chat Modes

The app supports two chat modes, selectable in Settings:

1. **MCP Mode (WAChatModeMCP)**
   - Uses GeminiClient to communicate with Gemini API
   - Provides WhatsApp MCP tools for automation
   - Model selector visible in UI
   - Green "MCP" badge indicator

2. **RAG Mode (WAChatModeRAG)**
   - Uses RAGClient to query external RAG service
   - No WhatsApp tools available
   - Model selector hidden (RAG service handles model)
   - Blue "RAG" badge indicator

### Key Classes

#### BotChatWindowController
Main chat window controller. Handles:
- Message input/display
- Mode switching (listens to `WAChatModeDidChangeNotification`)
- Routes messages to GeminiClient or RAGClient based on mode
- Displays mode indicator badge
- Zoom support (Cmd+/Cmd-)

Protocols: `GeminiClientDelegate`, `RAGClientDelegate`, `NSTextFieldDelegate`

#### GeminiClient
Gemini API wrapper:
- API endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{MODEL_ID}:generateContent`
- Manages conversation history
- Supports function calling (MCP tools)
- Auto tool loop execution
- API key loaded from: env var > NSUserDefaults > config.json

Supported models:
- Gemini 3.0 Flash/Pro (preview)
- Gemini 2.5 Flash/Pro (preview)
- Gemini 2.0 Flash

#### RAGClient
RAG service API client:
- Base URL configurable in Settings (default: `http://localhost:8000`)
- Endpoints:
  - `GET /health` - Health check
  - `POST /query` - RAG query (returns answer + sources)
  - `POST /query/stream` - Streaming RAG query (SSE)
  - `POST /search` - Semantic search without LLM
  - `GET /chats` - List all chats
- Request body uses `query` field (FastAPI convention)
- Handles HTTP errors with detailed parsing (FastAPI validation errors)
- SSE streaming support with proper event parsing

#### SettingsWindowController
User preferences:
- Theme: Light/Dark/Auto
- Chat Mode: MCP/RAG
- RAG URL: Configurable endpoint with "Test" button
- Posts notifications on changes

Keys:
- `WAThemeModeKey` - Theme preference
- `WAChatModeKey` - Chat mode preference
- `WARAGServiceURLKey` - RAG service URL

Notifications:
- `WAThemeDidChangeNotification`
- `WAChatModeDidChangeNotification`

#### MCPServer
MCP protocol implementation for Claude Desktop integration:
- Supports stdio and socket transports
- Exposes WhatsApp tools to external LLM clients

### MCP Tools (WhatsApp)

Available in MCP mode:
- `whatsapp_start_session` / `whatsapp_stop_session` - Session management
- `whatsapp_status` - Check WhatsApp status
- `whatsapp_list_chats` - List chats (filters: all/unread/favorites/groups)
- `whatsapp_get_current_chat` - Get currently open chat
- `whatsapp_open_chat` - Open a specific chat
- `whatsapp_get_messages` - Get messages from chat
- `whatsapp_send_message` - Send message to chat
- `whatsapp_search` - Search in WhatsApp
- `run_shell_command` - Execute local shell command

## Configuration

### API Key Storage (Priority Order)
1. Environment variable: `GEMINI_API_KEY`
2. NSUserDefaults: `GeminiAPIKey`
3. Config file: `~/Library/Application Support/mcpwa/config.json`
   ```json
   {
     "geminiApiKey": "your-key",
     "ragServiceURL": "http://localhost:8000"
   }
   ```

### User Defaults Keys
- `WAThemeMode` - Theme preference (0=Light, 1=Dark, 2=Auto)
- `WAChatMode` - Chat mode (0=MCP, 1=RAG)
- `RAGServiceURL` - RAG service URL
- `GeminiSelectedModel` - Selected Gemini model
- `ChatFontSize` - Chat font size

## RAG API Integration

### Request Format
```json
POST /query or /query/stream
Content-Type: application/json

{
  "query": "your question here"
}
```

### Response Format (non-streaming)
```json
{
  "answer": "The response text...",
  "sources": [
    {"title": "Source 1", "url": "http://..."},
    {"title": "Source 2", "filename": "doc.pdf"}
  ]
}
```

### SSE Streaming Events
```
data: {"type": "chunk", "content": "partial text..."}
data: {"type": "sources", "sources": [...]}
data: {"type": "done"}
data: {"type": "error", "message": "error description"}
```

### Error Handling
- HTTP errors parsed from response body
- FastAPI validation errors (422) show field-level details
- Generic error formats supported: `detail`, `error`, `message`

## UI Components

### Main Window
- Title bar with window title (auto-generated from first message)
- Chat scroll view with message bubbles
- Input area with text view, send/stop buttons
- Bottom bar: status label, mode indicator badge, model selector

### Mode Indicator Badge
- Green "MCP" badge in MCP mode
- Blue "RAG" badge in RAG mode
- Model selector hidden in RAG mode

### Settings Window (400x280)
- Appearance section: Theme selector
- Chat Mode section: Mode selector (MCP/RAG)
- RAG Settings (visible only in RAG mode):
  - URL text field
  - Test connection button
  - Connection status label

## Build & Run

```bash
# Build from command line
xcodebuild -scheme mcpwa -configuration Debug build

# Run
open /path/to/build/Debug/mcpwa.app
```

## Notifications

The app uses `NSNotificationCenter` for internal communication:
- `WAThemeDidChangeNotification` - Theme changed
- `WAChatModeDidChangeNotification` - Chat mode changed (userInfo: `@{@"mode": @(WAChatMode)}`)

## Accessibility Permissions

The app requires Accessibility permissions to interact with WhatsApp:
- System Preferences > Security & Privacy > Privacy > Accessibility
- Add mcpwa.app to allowed apps
