# FluxRemote UI Design Conventions

This document outlines the UI/UX design principles and conventions for the FluxRemote iOS application. All developers (including AI agents) should strictly follow these guidelines to ensure consistency and a premium feel.

## 1. General Principles
- **Modern Aesthetic**: Use rich aesthetics, glassmorphism where appropriate, and smooth transitions.
- **Large Titles**: On iPhone, the root navigation views (Dashboard, Processes, etc.) MUST use Large Navigation Titles (`.navigationBarTitleDisplayMode(.large)`).
- **Icons Over Text (Modals)**: Buttons in modal sheets should use pure SF Symbols instead of text wherever possible for a cleaner, modern look.
  - **Cancel/Close**: `Image(systemName: "xmark")`
  - **Confirm/Done/Save**: `Image(systemName: "checkmark")` with `.fontWeight(.bold)`

## 2. Platform-Specific Navigation
### iPhone
- **Overview (Dashboard)**: The Dashboard is the primary "Home" view and the only place where the global **Server Switching Menu** is shown in the toolbar (`.topBarLeading`).
- **Secondary Tabs**: Other main tabs (Processes, Logs, Configs) should NOT show the server switcher to keep the navigation bar clean.
- **Large Titles**: Every main tab navigation stack should have a Large Title.

### iPad
- **Sidebar Swapper**: The global server switcher should be prominently displayed at the TOP of the **Sidebar** as a primary navigation element.
- **No Detail View Swapper**: Detail views (Detail area of `NavigationSplitView`) should NOT have a server switcher in their toolbar, as switching is already accessible via the Sidebar.

## 3. Multi-Server Management
- **Naming**: The feature is officially called **"Server Management"** (服务器管理).
- **Entry Points**: 
  - Sidebar top section (iPad).
  - "More" tab -> Server Management row (iPhone).
  - Settings -> Server row -> pushes Server Management.
- **Interactions**:
  - **Tap**: Switch active server. If not authenticated, automatically show the login modal.
  - **Swipe (trailing)**: Provide `Edit` (orange) and `Delete` (destructive) actions.

## 4. Modal Guidelines
- **Header Structure**: Use a `NavigationStack` inside sheets with `.toolbar` for top actions.
- **Dismissal**: Users should be able to dismiss via an `xmark` icon on the top leading side (or cancellation action).

---
*Maintained by the FluxRemote Development Team.*
