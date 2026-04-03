import { Notice, Plugin, TFile } from "obsidian";

import {
  DEFAULT_SETTINGS,
  FluirSettingTab,
  type FluirSettings,
} from "./settings";
import { tagFiles, tagSingleFile } from "./tagger";
import { TagNotesModal, BrowseModal, getFilesWithTag, getRandomNotes } from "./tag-modal";

export default class FluirPlugin extends Plugin {
  settings: FluirSettings = DEFAULT_SETTINGS;
  timers: Map<string, ReturnType<typeof setTimeout>> = new Map();

  async onload() {
    await this.loadSettings();

    this.addCommand({
      id: "tag-untagged-notes",
      name: "Tag untagged notes",
      callback: async () => {
        new Notice("Fluir: Scanning...");
        try {
          const result = await tagFiles(this.app, this.settings);
          new Notice(
            `Tagged ${result.tagged} notes. ${result.newTags} new tags, ${result.reused} reused.`
          );
        } catch (e) {
          console.error("Fluir:", e);
          new Notice(
            `Fluir: ${e instanceof Error ? e.message : "Unknown error"}`
          );
        }
      },
    });

    // Reading view: intercept tag clicks
    this.registerMarkdownPostProcessor((el) => {
      for (const link of Array.from(el.querySelectorAll("a.tag"))) {
        const href = link.getAttribute("href");
        if (!href) continue;
        const tag = href.replace(/^#/, "");
        link.addEventListener("click", (evt) => {
          evt.preventDefault();
          evt.stopImmediatePropagation();
          this.openTagModal(tag);
        });
      }
    });

    // Live preview: intercept tag clicks on cm-hashtag spans (capture phase for mobile)
    this.registerDomEvent(document, 'click', (evt: MouseEvent) => {
      const target = evt.target as HTMLElement;
      if (!target.classList.contains('cm-hashtag')) return;

      let tag = '';
      if (target.classList.contains('cm-hashtag-end')) {
        tag = target.textContent ?? '';
      } else if (target.classList.contains('cm-hashtag-begin')) {
        const next = target.nextElementSibling;
        if (next?.classList.contains('cm-hashtag-end')) {
          tag = next.textContent ?? '';
        }
      }

      if (tag) {
        evt.preventDefault();
        evt.stopPropagation();
        this.openTagModal(tag);
      }
    }, { capture: true } as AddEventListenerOptions);

    this.registerEvent(
      this.app.vault.on("modify", (file) => {
        if (!this.settings.autoTag) return;
        if (!(file instanceof TFile)) return;
        if (file.extension !== "md") return;
        if (!file.path.startsWith(this.settings.folder + "/")) return;

        const existing = this.timers.get(file.path);
        if (existing) clearTimeout(existing);

        this.timers.set(
          file.path,
          setTimeout(async () => {
            this.timers.delete(file.path);
            try {
              const tagged = await tagSingleFile(
                this.app,
                this.settings,
                file
              );
              if (tagged) {
                new Notice(`Fluir: Auto-tagged ${file.basename}`);
              }
            } catch (e) {
              console.error("Fluir auto-tag:", e);
            }
          }, this.settings.delay * 1000)
        );
      })
    );

    this.addRibbonIcon("shuffle", "Fluir: Daily Flow", async () => {
      const items = await getRandomNotes(this.app, this.settings.folder, 7);
      new BrowseModal(this.app, items, (tag) => this.openTagModal(tag)).open();
    });

    this.addSettingTab(new FluirSettingTab(this.app, this));
  }

  async openTagModal(tag: string): Promise<void> {
    const items = await getFilesWithTag(this.app, this.settings.folder, tag);
    new TagNotesModal(this.app, tag, items, (t) => this.openTagModal(t)).open();
  }

  onunload() {
    for (const timer of this.timers.values()) {
      clearTimeout(timer);
    }
    this.timers.clear();
  }

  async loadSettings() {
    this.settings = Object.assign(
      {},
      DEFAULT_SETTINGS,
      await this.loadData()
    );
  }

  async saveSettings() {
    await this.saveData(this.settings);
  }
}
