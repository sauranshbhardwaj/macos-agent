# Sonny

Sonny is a macOS menu-bar agent prototype that turns typed or spoken natural-language requests into validated local actions. It plans with OpenAI, previews side effects, executes only registered local tools, and streams logs plus a final summary.

https://github.com/user-attachments/assets/16a27d55-868f-48a6-9583-6a4d5231a1f5

## What Sonny Can Do

- Find the largest files in a whitelisted folder and zip them.
- Convert `.docx` files to `.pdf` with Microsoft Word, or explicit mock mode.
- Open Hacker News, fetch the top 5 headlines, and save them to Markdown.
- Open safe web URLs with `http` or `https`.
- Open allowlisted Mac apps: Safari, Chrome, Finder, Notes, Calendar, Mail, Messages, Apple Music, Spotify, Slack, VS Code, and Terminal.
- Open song or album results in Apple Music or Spotify. Apple Music opens the best matching catalog album result when found, and Spotify opens a supplied result URI or search.
- Ask a clarification question when a command is missing a folder, app, URL, count, or output detail.
- Take push-to-talk voice commands from the `Speak` button or by holding `Control-Option-Space`. Release the hotkey to transcribe, plan, validate, and execute automatically.

## Setup

```bash
export OPENAI_API_KEY="sk-..."
export OPENAI_MODEL="gpt-5.5"
export OPENAI_TRANSCRIBE_MODEL="gpt-4o-mini-transcribe"
swift build
swift run MacAgent
```

In the Codex sandbox, use:

```bash
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift build --disable-sandbox
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift run --disable-sandbox MacAgent
```

The visible product name is Sonny. The SwiftPM executable is still `MacAgent`.

## Permissions

macOS may attribute prompts to Terminal, Codex, or the Swift process.

- Desktop/Documents access for file workflows.
- Automation permission for Microsoft Word DOCX conversion.
- Microphone permission for voice input.
- Keyboard shortcut registration for global push-to-talk. If `Control-Option-Space` is already claimed by another app, Sonny will still work from the `Speak` button.
- Browser/app opening through `NSWorkspace`.
- Apple Music or Spotify may ask to open provider links.

If a prompt is denied, allow the launching host app in System Settings, then relaunch Sonny.

## Safety Model

- OpenAI receives only the natural-language command and planner instructions, not local directory listings or file contents.
- The planner prompt is generated from a local `ToolRegistry`; the model can choose registered tools but cannot invent tools.
- Swift validates every plan against strict JSON, fixed operations, path whitelist rules, URL scheme rules, and the app allowlist.
- Dry run is on by default for typed commands and never writes files, opens apps, or converts documents.
- Typed non-dry-run commands skip extra confirmation clicks, but still plan, validate, preview internally, and log before acting.
- Voice commands from the button or `Control-Option-Space` also skip extra confirmation clicks after transcription.
- Executors use fixed native adapters only: `/usr/bin/zip`, `/usr/bin/osascript`, `NSWorkspace`, `AVFoundation`, and `URLSession`.
- Music result opening uses fixed provider templates; Sonny never accepts generated AppleScript from the model.

## DOCX Conversion

Real conversion uses Microsoft Word through a fixed AppleScript template. Existing matching PDFs are skipped.

If Word is unavailable and you only need to exercise the loop:

```bash
export MAC_AGENT_MOCK_DOCX=1
```

Mock mode writes clearly marked `.mock.pdf` placeholders, not real PDFs.

## Tests

```bash
swift test
```

On this local Command Line Tools install:

```bash
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

Coverage includes strict plan decoding, tool registry prompt generation, app allowlisting, URL validation, media result planning, clarification handling, transcription fixtures, whitelist rules, dry-run behavior, zip integration, injected DOCX conversion, and Hacker News Markdown generation.

## Manual Smoke Test

1. Launch Sonny from SwiftPM and click the `Sonny` menu-bar item.
2. Typed dry run and real run:
   - `Find the 3 largest files in ~/Desktop/MacAgentDemo and zip them.`
   - `Convert all .docx to .pdf in ~/Documents/MacAgentDocs.`
   - `Open Hacker News, grab the top 5 headlines, save to a Markdown file.`
   - `Open Safari.`
   - `Open https://github.com.`
   - `Open Jimmy Cooks by Drake on Apple Music.`
   - `Open Jimmy Cooks by Drake on Spotify.`
3. Press Enter from the command field to preview typed commands in dry run or execute them when dry run is off.
4. Try an incomplete request, such as `Find the 3 largest files and zip them.`, then answer Sonny's clarification.
5. Click `Speak`, say `Open Safari`, click `Stop`, and confirm Sonny transcribes and acts without another manual execute click.
6. Hold `Control-Option-Space`, say `Open Notes`, release the keys, and confirm Sonny transcribes and acts automatically.
7. Use generated result buttons such as reveal zip, open Markdown, reveal Markdown, or reveal PDFs.

## Architecture

- `MacAgent`: AppKit status item plus SwiftUI popover.
- `MacAgentCore`: planner schema, tool registry, safety validation, previews, executors, and tests.
- `OpenAIPlanner`: Responses API structured JSON planner.
- `OpenAITranscriber`: audio transcription client.
- `AgentActionExecutor`: validates and executes only registered workflows.
- `AgentLogStore`: realtime plan, validate, preview, confirm, act, observe, and summarize events.
