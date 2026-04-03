import { App, Modal, Notice, TFile } from "obsidian";
import { findTags, getFilesInFolder } from "./tagger";

export interface TagNoteItem {
  file: TFile;
  preview: string;
  tags: string[];
}

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j]!, a[i]!];
  }
  return a;
}

function buildNoteItem(file: TFile, content: string): TagNoteItem {
  const found = findTags(content);
  const lines = content.trimEnd().split("\n");
  const last = lines[lines.length - 1]?.trim() ?? "";
  const previewContent = last.startsWith("#")
    ? lines.slice(0, -1).join("\n")
    : content;
  return { file, preview: previewContent.trim(), tags: found.tags };
}

export async function getFilesWithTag(
  app: App,
  folder: string,
  tag: string
): Promise<TagNoteItem[]> {
  const files = getFilesInFolder(app, folder);
  const results: TagNoteItem[] = [];

  for (const file of files) {
    const content = await app.vault.cachedRead(file);
    const found = findTags(content);
    if (!found.tags.includes(tag)) continue;
    results.push(buildNoteItem(file, content));
  }

  return shuffle(results).slice(0, 5);
}

export async function getRandomNotes(
  app: App,
  folder: string,
  count: number
): Promise<TagNoteItem[]> {
  const files = getFilesInFolder(app, folder);
  const items: TagNoteItem[] = [];

  for (const file of files) {
    const content = await app.vault.cachedRead(file);
    if (content.trim() === "") continue;
    items.push(buildNoteItem(file, content));
  }

  return shuffle(items).slice(0, count);
}

// Tag click modal — shows random notes matching a tag
export class TagNotesModal extends Modal {
  private items: TagNoteItem[];
  private tag: string;
  private onTagClick: (tag: string) => void;

  constructor(
    app: App,
    tag: string,
    items: TagNoteItem[],
    onTagClick: (tag: string) => void
  ) {
    super(app);
    this.tag = tag;
    this.items = items;
    this.onTagClick = onTagClick;
  }

  onOpen(): void {
    const { contentEl } = this;
    contentEl.empty();
    contentEl.addClass("fluir-tag-modal");

    contentEl.createEl("h3", { text: `#${this.tag}`, cls: "fluir-tag-header" });

    if (this.items.length === 0) {
      contentEl.createEl("p", {
        text: `No notes found with #${this.tag}`,
        cls: "fluir-empty",
      });
      return;
    }

    for (const item of this.items) {
      const card = contentEl.createEl("div", { cls: "fluir-card" });
      card.createEl("p", { text: item.preview, cls: "fluir-card-body" });

      const tagRow = card.createEl("div", { cls: "fluir-card-tags" });
      for (const t of item.tags) {
        const tagEl = tagRow.createEl("a", { text: `#${t}`, cls: "fluir-tag-link" });
        tagEl.addEventListener("click", (evt) => {
          evt.stopPropagation();
          this.close();
          this.onTagClick(t);
        });
      }

      card.addEventListener("click", () => {
        this.app.workspace.getLeaf(false).openFile(item.file);
        this.close();
      });
    }
  }

  onClose(): void {
    this.contentEl.empty();
  }
}

// Browse modal — shows one note at a time with nav, tags, bookmark
export class BrowseModal extends Modal {
  private items: TagNoteItem[];
  private index: number = 0;
  private onTagClick: (tag: string) => void;

  constructor(
    app: App,
    items: TagNoteItem[],
    onTagClick: (tag: string) => void
  ) {
    super(app);
    this.items = items;
    this.onTagClick = onTagClick;
  }

  onOpen(): void {
    this.modalEl.addClass("fluir-browse-modal");
    this.renderCurrent();

    // Keyboard nav
    this.scope.register([], "ArrowRight", () => this.next());
    this.scope.register([], "ArrowLeft", () => this.prev());
    this.scope.register([], "b", () => this.bookmarkCurrent());
  }

  private renderCurrent(): void {
    const { contentEl } = this;
    contentEl.empty();

    if (this.items.length === 0) {
      contentEl.createEl("p", { text: "No notes found.", cls: "fluir-empty" });
      return;
    }

    const item = this.items[this.index]!;

    // Top bar: counter + bookmark
    const topBar = contentEl.createEl("div", { cls: "fluir-browse-top" });
    topBar.createEl("span", {
      text: `${this.index + 1} / ${this.items.length}`,
      cls: "fluir-browse-counter",
    });
    const bookmarkBtn = topBar.createEl("button", {
      cls: "fluir-browse-bookmark",
      attr: { "aria-label": "Bookmark (b)" },
    });
    bookmarkBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z"/></svg>`;
    bookmarkBtn.addEventListener("click", () => this.bookmarkCurrent());

    // Note body
    const card = contentEl.createEl("div", { cls: "fluir-browse-card" });
    card.createEl("p", { text: item.preview, cls: "fluir-card-body" });

    // Tags
    const tagRow = contentEl.createEl("div", { cls: "fluir-card-tags" });
    for (const t of item.tags) {
      const tagEl = tagRow.createEl("a", { text: `#${t}`, cls: "fluir-tag-link" });
      tagEl.addEventListener("click", (evt) => {
        evt.stopPropagation();
        this.close();
        this.onTagClick(t);
      });
    }

    // Nav buttons
    const nav = contentEl.createEl("div", { cls: "fluir-browse-nav" });
    const prevBtn = nav.createEl("button", { text: "\u2190", cls: "fluir-browse-btn" });
    prevBtn.addEventListener("click", () => this.prev());
    if (this.index === 0) prevBtn.disabled = true;

    const openBtn = nav.createEl("button", { text: "Open note", cls: "fluir-browse-btn fluir-browse-open" });
    openBtn.addEventListener("click", () => {
      this.app.workspace.getLeaf(false).openFile(item.file);
      this.close();
    });

    const nextBtn = nav.createEl("button", { text: "\u2192", cls: "fluir-browse-btn" });
    nextBtn.addEventListener("click", () => this.next());
    if (this.index === this.items.length - 1) nextBtn.disabled = true;
  }

  private next(): void {
    if (this.index < this.items.length - 1) {
      this.index++;
      this.renderCurrent();
    }
  }

  private prev(): void {
    if (this.index > 0) {
      this.index--;
      this.renderCurrent();
    }
  }

  private bookmarkCurrent(): void {
    const item = this.items[this.index];
    if (!item) return;
    const bookmarks = (this.app as any).internalPlugins?.getPluginById?.("bookmarks");
    if (bookmarks?.enabled && bookmarks.instance) {
      bookmarks.instance.addItem({ type: "file", path: item.file.path });
      new Notice(`Bookmarked: ${item.file.basename}`);
    }
  }

  onClose(): void {
    this.contentEl.empty();
  }
}
