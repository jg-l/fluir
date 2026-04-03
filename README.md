# Fluir

An Obsidian plugin that auto-tags notes using a local LLM via Ollama. No cloud, no API keys.

## What it does

- **Auto-tag notes**: Scans a folder for untagged `.md` files, sends them to Ollama in batches, and appends `#tags` to each file
- **Tag-aware**: Collects existing tags from your vault so the LLM can reuse them, connecting ideas across notes
- **Daily Flow**: Ribbon icon shows 7 random notes one at a time, with clickable tags and a bookmark shortcut
- **Tag click modal**: Clicking any `#tag` opens a modal with related notes instead of Obsidian's default search
- **Auto-tag on save**: Optional — tags new notes automatically after a configurable delay

## Usage

1. Add notes to your `ideas` folder — short quotes, highlights, thoughts
2. Run **Fluir: Tag untagged notes** from the command palette to tag them
3. Hit the **Daily Flow** shuffle icon in the ribbon to browse 7 random notes, explore tags, and bookmark what resonates

## Setup

1. Install [Ollama](https://ollama.com) and pull a model (e.g. `ollama pull gemma3:4b`)
2. Install this plugin via [BRAT](https://github.com/TfTHacker/obsidian42-brat) or copy `main.js`, `manifest.json`, and `styles.css` into `.obsidian/plugins/fluir/`
3. Configure the watched folder, Ollama URL, and model in Settings > Fluir

## Settings

| Setting | Default | Description |
|---|---|---|
| Watched folder | `ideas` | Folder to scan for untagged notes |
| Ollama URL | `http://localhost:11434` | Where Ollama is running |
| Model | `gemma4:e4b` | Which model to use |
| Auto-tag on save | off | Tag notes automatically after editing |
| Auto-tag delay | 30s | Seconds of inactivity before auto-tagging |

## CLI

Two standalone fish scripts are included:

- **`tag.fish`** — Same tagging logic as the plugin, runs from the terminal
- **`import-clippings.fish`** — Import Kindle highlights with deduplication

## Tag format

Tags are always lowercase-hyphenated on their own last line:

```
To be or not to be, that is the question.
- Shakespeare

#shakespeare #mortality #existentialism
```
