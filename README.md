# ScreenScribe

*Capture. Extract. Format.*

<img src="Assets/Icon.png" alt="ScreenScribe Icon" width="64"/>

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-brightgreen)](https://github.com/fredrir/screen-scribe/releases/latest)
[![GitHub all releases](https://img.shields.io/github/downloads/fredrir/screen-scribe/total)](https://github.com/fredrir/screen-scribe/releases)
[![License](https://img.shields.io/github/license/fredrir/screen-scribe)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/fredrir/screen-scribe)](https://github.com/fredrir/screen-scribe/releases/latest)

A macOS menu bar application for capturing screen regions and extracting content using AI-powered prompts. Features built-in support for LaTeX and Markdown extraction, plus the ability to create your own custom prompts.

## Demo

Watch the application in action:

![ScreenScribe Demo GIF](Assets/demo.gif)

### Menu Bar Access
<img src="Assets/Menu_Bar.png" alt="ScreenScribe Menu Bar" width="200"/>

### Settings Panel
<img src="Assets/Settings_Panel.png" alt="ScreenScribe Settings Window" width="400"/>

## Features

* **Menu Bar Convenience:** Lives in your menu bar for quick access.
* **Screen Capture:** Use global keyboard shortcuts or the menu bar to capture any portion of your screen.
* **Text Extraction (Vision OCR):** Uses Apple's built-in Vision framework for fast, offline text recognition.
* **AI-Powered Extraction:** Works with Google Gemini and any OpenAI-compatible endpoint, with customizable prompts for intelligent content extraction.
* **Built-in Prompts:**
  * **LaTeX:** Convert mathematical equations and formatted content to LaTeX code.
  * **Markdown:** Extract and convert content to clean Markdown format.
* **Custom Prompts:** Create, edit, and save your own prompts for specialized extraction needs.
* **Per-Prompt Output Format:** Configure how each prompt formats output (line breaks, spaces, or LaTeX newlines).
* **Default Prompt:** Set any prompt as the default for quick keyboard access.
* **Multiple Providers:** Gemini, or any OpenAI-compatible endpoint (OpenAI, OpenRouter, Groq, Ollama, LM Studio, self-hosted), switchable from the menu bar.
* **Model Selection:** Free-text model identifier, or load the endpoint's `/models` list and pick from it.
* **Clipboard Integration:** Automatically copies extracted content to your clipboard.
* **Customizable Shortcuts:** Set global keyboard shortcuts for text extraction and your default prompt.
* **Recent History:** Access recently captured results directly from the menu bar.

## Requirements

* **macOS:** Version 14.0 (Sonoma) or later.
* **AI Provider:** An API key for [Google AI Studio](https://makersuite.google.com/app/apikey), an OpenAI-compatible endpoint, or a local server such as [Ollama](https://ollama.com) or [LM Studio](https://lmstudio.ai). Required for AI-powered extraction (LaTeX, Markdown, and custom prompts); local endpoints can run without a key.
* **Xcode:** Version 16.0 or later (if building from source).

## Gemini API Models and Rate Limits

ScreenScribe allows you to choose between the following Gemini models to optimize for your specific needs:

| Model                     | Description                               |
| ------------------------- | ----------------------------------------- |
| **Gemini 3.7 Flash**      | Best balance of speed, cost, and accuracy |
| **Gemini 3.1 Pro**        | Most capable model for complex content    |
| **Gemini 3.5 Flash-Lite** | Fastest and most cost-effective option    |

> Note: Availability and quotas can change; see Google's current [usage limits](https://ai.google.dev/gemini-api/docs/rate-limits) for details.

When a Gemini model is retired, ScreenScribe migrates the stored model to its replacement automatically.

## AI Providers

Configured in **Settings > API Configuration**. `Google Gemini` speaks Google's `generateContent` API; `OpenAI-compatible` speaks `/chat/completions`.

| Field | Value |
| ----- | ----- |
| Provider | Active provider; **+** adds a preset, **−** removes the selection |
| Name | Label used in the menu bar switcher |
| Type | `Google Gemini`, `OpenAI-compatible` |
| Base URL | API root, e.g. `https://api.openai.com/v1` |
| API Key | Gemini: required. OpenAI-compatible: optional |
| Model | Any identifier the endpoint accepts; **Load Models** fills the picker from `/models` |

### Base URL resolution

| Base URL | Request URL |
| -------- | ----------- |
| `https://api.openai.com/v1` | `https://api.openai.com/v1/chat/completions` |
| `https://api.openai.com/v1/` | `https://api.openai.com/v1/chat/completions` |
| `https://api.groq.com/openai/v1` | `https://api.groq.com/openai/v1/chat/completions` |
| `http://localhost:1234/v1/chat/completions` | unchanged |
| `http://localhost:1234` | `http://localhost:1234/v1/chat/completions` |

An API key on an OpenAI-compatible provider is sent as `Authorization: Bearer <key>`; empty keys omit the header.

### Presets

| Preset | Base URL | Example model |
| ------ | -------- | ------------- |
| Gemini | `https://generativelanguage.googleapis.com` | `gemini-3.7-flash` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o` |
| OpenRouter | `https://openrouter.ai/api/v1` | `openai/gpt-4o` |
| Groq | `https://api.groq.com/openai/v1` | `llama-3.3-70b-versatile` |
| Ollama | `http://localhost:11434/v1` | `llama3.2` |
| LM Studio | `http://localhost:1234/v1` | `local-model` |
| Custom | — | — |

Preset values are starting points; every field stays editable.

### Local servers

Plain-http endpoints on the local machine are allowed through the app's App Transport Security settings. The model must already be loaded in the local server.

### Switching

| Providers | Menu bar |
| --------- | -------- |
| 1 | No switcher |
| 2+ | **Provider** submenu |

## Installation

### Quick Install

1. **Download** the latest `.dmg` from [Releases](https://github.com/fredrir/screen-scribe/releases/latest)
2. **Open** the DMG and drag ScreenScribe to Applications
3. **Right-click** the app and select "Open" (required for first launch)

### Opening for the First Time

Since this app is not notarized with Apple, macOS will show a security warning. Here's how to open it:

> Note: "Not notarized" is separate from "unsigned". Screen Recording permission relies on the app having a stable code signature, even if Gatekeeper still requires the right-click "Open" flow.

**Option 1: Right-click to Open (Recommended)**
1. Open Finder and go to Applications
2. Right-click (or Control-click) on ScreenScribe
3. Select "Open" from the context menu
4. Click "Open" in the dialog that appears

**Option 2: System Settings**
1. Try to open the app normally (it will be blocked)
2. Go to **System Settings > Privacy & Security**
3. Scroll down to find the message about ScreenScribe being blocked
4. Click "Open Anyway"

> This only needs to be done once. After the first successful launch, the app will open normally.

### First Launch

ScreenScribe launches directly in your menu bar.

On the first capture attempt, ScreenScribe will request **Screen Recording** permission.  
If you deny it, you can enable it later in **System Settings > Privacy & Security > Screen Recording**.

Provider setup is optional and is configured from **Settings**.

## Usage

**Capture:**
* Click the menu bar icon and select "Extract Text" for offline OCR, or choose a prompt (LaTeX, Markdown, or custom)
* Use keyboard shortcuts: **Cmd+T** for text, **Cmd+L** for your default AI prompt
* If Screen Recording permission is missing, ScreenScribe asks for it when you trigger capture

**Select Area:** Your cursor will turn into a crosshair. Click and drag to select the screen region.

**Result:**
* A sound plays on successful capture
* Content is automatically copied to your clipboard
* Menu bar icon briefly shows a checkmark

**History:** Access recent captures from the menu bar under "Recent Captures"

**Settings:**
* **Provider:** Choose the active provider, edit its base URL, API key and model, or add new ones
* **Shortcuts:** Customize keyboard shortcuts
* **Prompts:** Create custom prompts, edit copy formats, set your default

## Custom Prompts

Create your own prompts for specialized extraction:

1. Open **Settings** from the menu bar.
2. In the **Prompts** section, click the **+** button.
3. Enter a name and write your prompt instructions.
4. Choose your preferred copy format (line breaks, spaces, or LaTeX newlines).
5. Click **Create** to save.

You can set any prompt as your default by selecting it and clicking **Set as Default**. The default prompt will be triggered by the keyboard shortcut (Cmd+L by default).

**Note:** Built-in prompts (LaTeX and Markdown) cannot be deleted or have their content modified, but you can change their copy format.

## Building from Source

If you prefer to build the application yourself:

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/fredrir/screen-scribe.git
    cd screen-scribe
    ```
2.  **Open in Xcode:**
    ```bash
    open ScreenScribe.xcodeproj
    ```
3.  **Select Scheme:** Ensure the `ScreenScribe` scheme is selected.
4.  **Build/Run:** Press `Cmd+B` to build or `Cmd+R` to run the application directly on your Mac. (Apps you build yourself typically don't trigger the same Gatekeeper warnings on your own machine).
5.  **(Required for AI extraction)** **Configure a provider:** After running the built app, open its Settings panel from the menu bar icon and add a provider — a Google Gemini API key, or the base URL and model of any OpenAI-compatible endpoint.

## Code Structure Overview

* `ScreenScribe/Sources/App.swift`: Main application delegate, menu bar setup, capture initiation, and result handling.
* `ScreenScribe/Sources/Recognizer.swift`: Handles text OCR using Apple's Vision framework.
* `ScreenScribe/Sources/Models/Prompt.swift`: Prompt data model with built-in LaTeX and Markdown prompts.
* `ScreenScribe/Sources/Models/AIProvider.swift`: Provider kinds, saved provider configuration, validation and presets.
* `ScreenScribe/Sources/Services/AIProviderClient.swift`: Routes extraction and model lookups to the client matching the active provider.
* `ScreenScribe/Sources/Services/GeminiService.swift`: Manages interaction with the Google Gemini API.
* `ScreenScribe/Sources/Services/OpenAICompatibleService.swift`: Manages interaction with OpenAI-compatible endpoints.
* `ScreenScribe/Sources/Services/ProviderStore.swift`: Stores providers and the active selection, and migrates the previous Gemini-only settings.
* `ScreenScribe/Sources/Services/PromptManager.swift`: CRUD operations for prompts and persistence.
* `ScreenScribe/Sources/Settings/`: Contains SwiftUI views for settings and prompt management.
* `ScreenScribe/Sources/Extensions/`: Utility extensions for various AppKit/Foundation classes.
* `ScreenScribe/Info.plist`: Application metadata and permission descriptions.
* `ScreenScribe.xcodeproj`: Xcode project file.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built on top of [TextGrabber2](https://github.com/TextGrabber2-app/TextGrabber2) by cyanzhong
