# WhatsApp MCP Commands (WAAccessibility)

Full list of commands available for controlling WhatsApp Desktop via the Accessibility API.

## Status & Activation

- **`isWhatsAppAvailable`** — Check if WhatsApp is running and accessible
- **`activateWhatsApp`** — Bring WhatsApp window to foreground
- **`ensureWhatsAppVisible`** — Unminimize/unhide WhatsApp if needed

## Search

- **`isInSearchMode`** — Check if search bar is currently active
- **`globalSearch:`** — Search across all chats & messages, returns `WASearchResults` (chat matches + message matches)
- **`searchFor:`** — Enter a query into WhatsApp's search field
- **`clearSearch`** — Clear search and return to normal chat list

## Chat List & Filters

- **`getSelectedChatFilter`** — Get current filter (All/Unread/Favorites/Groups)
- **`selectChatFilter:`** — Switch to a filter (WAChatFilterAll, WAChatFilterUnread, WAChatFilterFavorites, WAChatFilterGroups)
- **`getRecentChats`** — Get visible chats
- **`getRecentChatsWithFilter:`** — Get chats with a specific filter applied
- **`scrollChatListDown`** / **`scrollChatListUp`** — Page through the chat list, returns visible chats after scrolling
- **`findChatWithName:`** — Smart chat search (checks search results, chat list, then does global search)

## Chat Navigation

- **`openChat:`** — Open a specific `WAChat` object
- **`openChatWithName:`** — Open chat by name (convenience)
- **`navigateToChat:nearDate:searchSnippet:`** — Navigate to a chat and find a specific message using global search with snippet (used by clickable source references)

## Current Chat

- **`getCurrentChat`** — Get info about the currently open chat (name, lastSeen, messages)
- **`getMessages`** — Get messages from the current chat
- **`getMessagesWithLimit:`** — Get messages with a count limit

## Actions

- **`sendMessage:`** — Send a message to the current chat

## Tab Navigation

- **`navigateToChats`** — Switch to the Chats tab
- **`navigateToCalls`** — Switch to the Calls tab
- **`navigateToArchived`** — Switch to the Archived tab
- **`navigateToSettings`** — Switch to the Settings tab

## Low-Level Helpers

- **`getMainWindow`** — Get the AXUIElementRef for WhatsApp's main window
- **`pressKey:withFlags:toProcess:`** — Send a keypress to WhatsApp
- **`typeString:toProcess:`** — Type a string into WhatsApp

## Data Models

### WAChat
- `name`, `lastMessage`, `timestamp`, `sender` (group chats)
- `isPinned`, `isGroup`, `isUnread`, `isSelected`, `index`

### WAMessage
- `text`, `sender`, `timestamp`
- `direction` (Incoming/Outgoing/System)
- `replyTo`, `replyText`, `reactions`, `isRead`

### WACurrentChat
- `name`, `lastSeen`, `messages` (array of WAMessage)

### WASearchResults
- `query`
- `chatMatches` (array of WASearchChatResult: `chatName`, `lastMessagePreview`)
- `messageMatches` (array of WASearchMessageResult: `chatName`, `sender`, `messagePreview`)

### WAChatFilter
- `WAChatFilterAll`, `WAChatFilterUnread`, `WAChatFilterFavorites`, `WAChatFilterGroups`
