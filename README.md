# MacAgent

MacAgent is a minimal macOS menu-bar prototype that turns a natural-language request into a validated local action plan, previews side effects, asks for confirmation, executes one of three fixed workflows, and shows a live log plus final summary.

## Supported Commands

- `Find the 3 largest files in ~/Desktop/TestFolder and zip them.`
- `Convert all .docx to .pdf in ~/Documents/TestDocs.`
- `Open Hacker News, grab the top 5 headlines, save to a Markdown file.`

Unsupported requests return a planner error instead of executing arbitrary commands.

## Setup

1. Install Xcode Command Line Tools with Swift 6 or newer.
2. Export an OpenAI API key:

   ```bash
   export OPENAI_API_KEY="sk-..."
   ```

3. Optionally choose a model. The default is `gpt-5.5`.

   ```bash
   export OPENAI_MODEL="gpt-5.5"
   ```

4. Build and run:

   ```bash
   swift build
   swift run MacAgent
   ```

In this Codex sandbox, SwiftPM may need its own package sandbox disabled and its Clang module cache redirected:

```bash
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift build --disable-sandbox
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift run --disable-sandbox MacAgent
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox
```

## macOS Permissions

The app is launched as a SwiftPM executable, so macOS may attribute permissions to Terminal, Codex, or the Swift process.

- Desktop/Documents access may trigger privacy prompts.
- DOCX conversion via Microsoft Word may trigger Automation prompts for controlling Word.
- Hacker News opening uses the default browser via `NSWorkspace`.

If a privacy prompt is denied, allow the relevant host app in System Settings, then relaunch MacAgent.

## Safety Model

- OpenAI receives only the natural-language command and planner instructions, not local directory listings or file contents.
- The model returns strict JSON with a fixed operation enum.
- Swift validates every path against a default whitelist of `~/Desktop` and `~/Documents`.
- All paths are tilde-expanded, canonicalized, and rejected if they resolve outside the whitelist.
- Recursive scans skip symlinks.
- Dry run is on by default and never writes files, opens apps, or converts documents.
- Non-dry-run execution shows every write/open/convert side effect in a confirmation sheet.
- Executors use fixed native adapters only: `/usr/bin/zip`, `/usr/bin/osascript` for Microsoft Word, `NSWorkspace`, and `URLSession`.

## DOCX Conversion

Real conversion uses Microsoft Word through a fixed AppleScript template. Existing PDF outputs are skipped.

If Microsoft Word is not installed, mock conversion is disabled by default. To create clearly marked placeholders for demos:

```bash
export MAC_AGENT_MOCK_DOCX=1
```

Mock mode writes `.mock.pdf` placeholder files and documents that they are not real PDFs.

## Tests

Run:

```bash
swift test
```

On the local Command Line Tools install used for this prototype, SwiftPM needed explicit Swift Testing framework paths:

```bash
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

The tests cover:

- strict planner JSON decoding
- unsupported and malformed plan rejection
- whitelist allow/reject behavior
- symlink rejection when links resolve outside allowed roots
- dry-run no-write behavior
- zip archive integration
- injected DOCX converter behavior
- Hacker News Markdown generation with fixture data

## Manual End-to-End Validation

These checks require your macOS session, an API key, and consent for any privacy prompts.

### 1. Launch With OpenAI

```bash
export OPENAI_API_KEY="sk-..."
env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift run --disable-sandbox MacAgent
```

If your shell supports `OPENAI_MODEL`, leave it unset for `gpt-5.5` or set it explicitly:

```bash
export OPENAI_MODEL="gpt-5.5"
```

After launch, click the `Agent` item in the menu bar.

### 2. Validate Largest Files

Create a Desktop folder with several files of different sizes:

```bash
mkdir -p "$HOME/Desktop/MacAgentDemo"
printf 'small' > "$HOME/Desktop/MacAgentDemo/small.txt"
dd if=/dev/zero of="$HOME/Desktop/MacAgentDemo/medium.bin" bs=1024 count=256
dd if=/dev/zero of="$HOME/Desktop/MacAgentDemo/large.bin" bs=1024 count=512
dd if=/dev/zero of="$HOME/Desktop/MacAgentDemo/larger.bin" bs=1024 count=768
```

Run this in MacAgent with dry run enabled:

```text
Find the 3 largest files in ~/Desktop/MacAgentDemo and zip them.
```

Confirm that the preview lists three files and a zip write. Disable dry run, run again, confirm, and verify a `largest-files-*.zip` appears in the folder.

### 3. Validate DOCX Conversion

Create or copy one or more `.docx` files into:

```bash
mkdir -p ~/Documents/MacAgentDocs
```

To create simple test documents from Terminal:

```bash
printf 'Document one\nThis is a MacAgent DOCX conversion test.\n' > /tmp/macagent-one.txt
printf 'Document two\nThis is another MacAgent DOCX conversion test.\n' > /tmp/macagent-two.txt
textutil -convert docx /tmp/macagent-one.txt -output "$HOME/Documents/MacAgentDocs/one.docx"
textutil -convert docx /tmp/macagent-two.txt -output "$HOME/Documents/MacAgentDocs/two.docx"
```

Run:

```text
Convert all .docx to .pdf in ~/Documents/MacAgentDocs.
```

Expected behavior:

- Dry run lists the PDFs that would be created.
- Non-dry-run asks for confirmation.
- macOS may ask for permission to control Microsoft Word or access Documents.
- Word exports to a temporary PDF first, then MacAgent moves the finished PDF to the requested folder.
- Existing PDFs with matching names are skipped.

If Word is unavailable and you only want to exercise the loop:

```bash
export MAC_AGENT_MOCK_DOCX=1
```

Then relaunch MacAgent. Mock mode creates `.mock.pdf` placeholders, not real PDFs.

### 4. Validate Hacker News

Run:

```text
Open Hacker News, grab the top 5 headlines, save to a Markdown file.
```

Expected behavior:

- Dry run previews the browser open and Markdown write.
- Non-dry-run opens Hacker News in the default browser.
- A `hacker-news-*.md` file appears on Desktop.

### 5. Watch Responsiveness

During zip creation and DOCX conversion, the popover should keep showing the spinner, latest status, and log updates. If the spinner stops for a long time or the popover cannot be interacted with, note the command, folder size, and current log line.

## Architecture

- `MacAgent`: AppKit status item plus SwiftUI popover.
- `MacAgentCore`: planner, safety validation, action previews, executors, and tests.
- `OpenAIPlanner`: calls the Responses API with structured JSON output.
- `AgentActionExecutor`: validates a known plan and runs only the supported workflows.
- `AgentLogStore`: emits plan, validate, preview, confirm, act, observe, and summarize events for the UI.
