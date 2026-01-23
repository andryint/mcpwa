# MCPWA - WhatsApp Assistant

## Project Overview

MCPWA is a macOS Cocoa application that serves as a WhatsApp Assistant. The app connects to a backend service that provides LLM-powered chat capabilities and can interact with WhatsApp via the Accessibility API through the MCP protocol.

The architecture is:
- **Frontend (this app)**: macOS native UI for chat interaction
- **Backend service**: Handles LLM queries, RAG, and MCP tool execution
- **WhatsApp integration**: Via Accessibility API, accessible through the backend's MCP tools

## Project Structure

```
mcpwa/
├── mcpwa/                    # Main Cocoa App
│   ├── AppDelegate.m/h       # App entry point
│   ├── BotChatWindowController.m/h  # Main chat UI & message handling
│   ├── RAGClient.m/h         # Backend API client
│   ├── SettingsWindowController.m/h # User preferences (theme, backend URL)
│   ├── DebugConfigWindowController.m/h # Debug configuration
│   ├── WAAccessibility.m/h   # WhatsApp UI automation via Accessibility API
│   ├── WAAccessibilityExplorer.m/h # Accessibility tree explorer
│   ├── WALogger.m/h          # Logging utility
│   └── Assets/               # App icons, images
└── mcp-shim/                 # Separate MCP bridge for Claude Desktop
```

## Architecture

### Backend Connection

The app always connects to a backend service (configurable in Settings). The backend provides:
- LLM-powered chat responses
- Model selection (fetched from `/models` endpoint)
- Streaming responses via SSE
- MCP tools execution for WhatsApp integration

### Key Classes

#### BotChatWindowController
Main chat window controller. Handles:
- Message input/display
- Routes messages to backend via RAGClient
- Model selector dropdown (models fetched from backend)
- Streaming response display
- Zoom support (Cmd+/Cmd-)

Protocols: `RAGClientDelegate`, `NSTextFieldDelegate`

#### RAGClient
Backend API client:
- Base URL configurable in Settings (default: `http://localhost:8000`)
- Endpoints:
  - `GET /health` - Health check
  - `GET /models` - List available models
  - `POST /query` - Query (returns answer + sources)
  - `POST /query/stream` - Streaming query (SSE)
  - `POST /search` - Semantic search without LLM
  - `GET /chats` - List all chats
  - `POST /generate-title` - Generate chat title from message
- Request body uses `query` field (FastAPI convention)
- Handles HTTP errors with detailed parsing (FastAPI validation errors)
- SSE streaming support with proper event parsing

#### SettingsWindowController
User preferences:
- Theme: Light/Dark/Auto
- Environment: Production (:8000) / Development (:8001)
- Backend URL: Configurable endpoint with "Test" button
- Posts notifications on changes

Keys:
- `WAThemeModeKey` - Theme preference
- `WARAGServiceURLKey` - Backend service URL
- `WARAGEnvironmentKey` - Environment (Production/Development)

Notifications:
- `WAThemeDidChangeNotification`

#### WAAccessibility
WhatsApp UI automation via Accessibility API. The backend calls these tools via MCP protocol:
- `whatsapp_start_session` / `whatsapp_stop_session` - Session management
- `whatsapp_status` - Check WhatsApp status
- `whatsapp_list_chats` - List chats (filters: all/unread/favorites/groups)
- `whatsapp_get_current_chat` - Get currently open chat
- `whatsapp_open_chat` - Open a specific chat
- `whatsapp_get_messages` - Get messages from chat
- `whatsapp_send_message` - Send message to chat
- `whatsapp_search` - Search in WhatsApp

## Configuration

### Backend URL
Configurable in Settings:
- Production: `http://localhost:8000`
- Development: `http://localhost:8001`
- Or custom URL

### User Defaults Keys
- `WAThemeMode` - Theme preference (0=Light, 1=Dark, 2=Auto)
- `RAGServiceURL` - Backend service URL
- `RAGEnvironment` - Environment (0=Production, 1=Development)
- `RAGSelectedModel` - Selected model ID
- `ChatFontSize` - Chat font size

## Backend API Integration

### Request Format
```json
POST /query or /query/stream
Content-Type: application/json

{
  "query": "your question here",
  "model": "model-id"
}
```

### Response Format (non-streaming)
```json
{
  "answer": "The response text...",
  "sources": [
    {"chat_name": "Chat 1", "time_start": "2025-12-24T17:18:00"},
    {"chat_name": "Chat 2", "time_start": "2025-12-20T10:30:00"}
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

### Models Endpoint
```json
GET /models

Response:
{
  "models": [
    {"id": "gemini-3-pro", "name": "Gemini 3 Pro", "provider": "gemini"},
    {"id": "claude-3-opus", "name": "Claude 3 Opus", "provider": "anthropic"}
  ]
}
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
- Bottom bar: status label, model selector

### Settings Window (400x240)
- Appearance section: Theme selector
- Backend Connection section:
  - Environment selector (Production/Development)
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

## Accessibility Permissions

The app requires Accessibility permissions to interact with WhatsApp:
- System Preferences > Security & Privacy > Privacy > Accessibility
- Add mcpwa.app to allowed apps
