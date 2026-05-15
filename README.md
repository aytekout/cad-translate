# CAD Translate

**Translate Japanese (and other CJK) text in AutoCAD DWG files to English using local or cloud AI.**

Built for architects, engineers, and construction professionals working with Japanese drawings.

![CAD Translate GUI](docs/screenshots/gui-preview.png)

---

## Features

- **Scans all TEXT and MTEXT** entities in the drawing
- **Filters only Japanese text** — ignores English/numbers
- **Translation cache** — duplicate texts translated only once (huge speed boost)
- **Editable translations** — review and correct before applying
- **Selective apply** — tick only the translations you want
- **Cross-platform** — macOS and Windows
- **Multiple AI providers** — local or cloud

## Supported AI Providers

| Provider | Type | Cost |
|---|---|---|
| **LM Studio** | Local | Free |
| **Ollama** | Local | Free |
| **OpenAI** (GPT-4o, GPT-4o-mini) | Cloud | Pay per use |
| **Anthropic** (Claude) | Cloud | Pay per use |
| **Any OpenAI-compatible API** | Cloud | Varies |

---

## Installation

### 1. Download

Download `cad-translate.lsp` from the [releases page](https://github.com/YOUR_USERNAME/cad-translate/releases).

### 2. Load in AutoCAD

**Option A — Load once:**
```
Command: APPLOAD
```
Browse to `cad-translate.lsp` → Load

**Option B — Auto-load on startup:**

Add to your `acad.lsp` or `acaddoc.lsp`:
```lisp
(load "C:/path/to/cad-translate.lsp")
```

---

## Usage

### Translate a drawing

```
Command: CADTRANSLATE
```

1. LISP scans all texts → Japanese-only texts sent to browser GUI
2. Select your AI provider in the GUI
3. Click **"Translate All"** — translations appear automatically
4. Review, edit if needed, tick to approve
5. Click **"Approve & Download"** → `jpt_output.json` downloaded
6. Move `jpt_output.json` to the same folder as your DWG
7. Back in AutoCAD:

```
Command: CADAPPLY
```

### Apply an existing translation file

If you already have a `jpt_output.json`:
```
Command: CADAPPLY
```

---

## AI Provider Setup

### LM Studio (recommended for beginners)

1. Download [LM Studio](https://lmstudio.ai)
2. Download a model (e.g. `Qwen2.5-7B`, `llama-3.2`)
3. Start the local server: **Local Server** tab → **Start Server**
4. In CAD Translate GUI: select **LM Studio**, URL stays as `http://127.0.0.1:1234/v1/chat/completions`

> **macOS users:** If you get a CORS error, start your browser with:
> ```bash
> open -a "Microsoft Edge" --args --disable-web-security --user-data-dir="/tmp/edge-dev" "/path/to/jpt_gui.html"
> ```

### Ollama

1. Install [Ollama](https://ollama.ai)
2. Pull a model: `ollama pull llama3`
3. In GUI: select **Ollama**, URL: `http://127.0.0.1:11434/v1/chat/completions`

### OpenAI

1. Get an API key from [platform.openai.com](https://platform.openai.com)
2. In GUI: select **OpenAI**, enter your API key
3. Recommended model: `gpt-4o-mini` (fast + cheap)

### Anthropic (Claude)

1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
2. In GUI: select **Anthropic**, enter your API key
3. Recommended model: `claude-3-5-haiku-20241022`

---

## Customizing the Prompt

The GUI has a built-in **prompt editor**. Edit it to match your project:

**Example — Stone cladding project:**
```
You are a technical translator for Japanese stone facade cladding drawings.
Translate to English using standard cladding/curtain wall terminology.
Rules:
- Return ONLY the translated text
- 石材=Stone, 笠木=Coping, 目地=Joint, アンカー=Anchor bolt
- Keep part numbers and codes as-is
```

**Example — Structural demolition:**
```
You are a technical translator for Japanese structural demolition drawings.
Translate to English using standard demolition/construction terminology.
Rules:
- Return ONLY the translated text
- 解体=Demolition, 撤去=Removal, 基礎=Foundation, 鉄筋=Rebar
- Keep grid references and dimensions as-is
```

---

## File Structure

When you run `CADTRANSLATE`, three files are created in your DWG folder:

```
your-drawing-folder/
├── your-drawing.dwg
├── jpt_data.json      ← raw data extracted from DWG
├── jpt_data.js        ← same data as JS variable (for browser)
├── jpt_gui.html       ← translation GUI (open in browser)
└── jpt_output.json    ← your approved translations (after GUI)
```

---

## Troubleshooting

**"Failed to fetch" error in GUI**
- Check that LM Studio / Ollama server is running
- Try `localhost` instead of `127.0.0.1` in the URL
- Browser CORS issue: restart browser with `--disable-web-security` flag (see above)

**"File not found" when running CADAPPLY**
- Move `jpt_output.json` to the same folder as your DWG file
- Check the path shown in the error message

**Translations look wrong**
- Edit the system prompt in the GUI for your specific project
- Use "Re-translate Selected" after editing the prompt

**AutoCAD crashes / hangs**
- For very large drawings (+10,000 texts), the scan may take a while — be patient
- The Japanese filter significantly reduces the workload

---

## Contributing

Pull requests welcome! Areas for improvement:
- Support for Korean (한국어) and Chinese (中文) text detection
- Better MTEXT formatting preservation
- Translation memory / glossary support

---

## License

MIT License — free to use, modify, and distribute.

---

## Credits

Built by [@aytekout](https://github.com/aytekout) for real-world use on Japan construction projects.
