import { Notice, Plugin, TFile } from "obsidian";
import {
  DEFAULT_SETTINGS,
  NapkinTaggerSettingTab,
  type NapkinTaggerSettings,
} from "./settings";
import { tagFiles, tagSingleFile, collectExistingTags } from "./tagger";

export default class NapkinTaggerPlugin extends Plugin {
  settings: NapkinTaggerSettings = DEFAULT_SETTINGS;
  timers: Map<string, ReturnType<typeof setTimeout>> = new Map();

  async onload() {
    await this.loadSettings();

    this.addCommand({
      id: "tag-untagged-notes",
      name: "Tag untagged notes",
      callback: async () => {
        new Notice("Napkin Tagger: Scanning...");
        try {
          const result = await tagFiles(this.app, this.settings);
          new Notice(
            `Tagged ${result.tagged} notes. ${result.newTags} new tags, ${result.reused} reused.`
          );
        } catch (e) {
          console.error("Napkin Tagger:", e);
          new Notice(
            `Napkin Tagger: ${e instanceof Error ? e.message : "Unknown error"}`
          );
        }
      },
    });

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
                new Notice(`Napkin Tagger: Auto-tagged ${file.basename}`);
              }
            } catch (e) {
              console.error("Napkin Tagger auto-tag:", e);
            }
          }, this.settings.delay * 1000)
        );
      })
    );

    this.addSettingTab(new NapkinTaggerSettingTab(this.app, this));
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
