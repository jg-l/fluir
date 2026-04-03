import { App, PluginSettingTab, Setting } from "obsidian";
import type FluirPlugin from "./main";

export interface FluirSettings {
  folder: string;
  ollamaUrl: string;
  model: string;
  autoTag: boolean;
  delay: number;
}

export const DEFAULT_SETTINGS: FluirSettings = {
  folder: "ideas",
  ollamaUrl: "http://100.103.186.65:11434",
  model: "gemma4:e4b",
  autoTag: false,
  delay: 30,
};

export class FluirSettingTab extends PluginSettingTab {
  plugin: FluirPlugin;

  constructor(app: App, plugin: FluirPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;
    containerEl.empty();

    new Setting(containerEl)
      .setName("Watched folder")
      .setDesc("Folder to scan for untagged notes")
      .addText((text) =>
        text
          .setPlaceholder("ideas")
          .setValue(this.plugin.settings.folder)
          .onChange(async (value) => {
            this.plugin.settings.folder = value;
            await this.plugin.saveSettings();
          })
      );

    new Setting(containerEl)
      .setName("Ollama URL")
      .setDesc("Where Ollama is running")
      .addText((text) =>
        text
          .setPlaceholder("http://localhost:11434")
          .setValue(this.plugin.settings.ollamaUrl)
          .onChange(async (value) => {
            this.plugin.settings.ollamaUrl = value;
            await this.plugin.saveSettings();
          })
      );

    new Setting(containerEl)
      .setName("Model")
      .setDesc("Which Ollama model to use")
      .addText((text) =>
        text
          .setPlaceholder("gemma4:e4b")
          .setValue(this.plugin.settings.model)
          .onChange(async (value) => {
            this.plugin.settings.model = value;
            await this.plugin.saveSettings();
          })
      );

    new Setting(containerEl)
      .setName("Auto-tag on save")
      .setDesc("Automatically tag notes after editing")
      .addToggle((toggle) =>
        toggle
          .setValue(this.plugin.settings.autoTag)
          .onChange(async (value) => {
            this.plugin.settings.autoTag = value;
            await this.plugin.saveSettings();
          })
      );

    new Setting(containerEl)
      .setName("Auto-tag delay")
      .setDesc("Seconds of inactivity before auto-tagging")
      .addText((text) =>
        text
          .setPlaceholder("30")
          .setValue(String(this.plugin.settings.delay))
          .onChange(async (value) => {
            const num = parseInt(value, 10);
            if (!isNaN(num) && num >= 5) {
              this.plugin.settings.delay = num;
              await this.plugin.saveSettings();
            }
          })
      );
  }
}
