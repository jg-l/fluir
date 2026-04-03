import { App, Notice, TFile, requestUrl } from "obsidian";
import type { NapkinTaggerSettings } from "./settings";
import PROMPT_TEMPLATE from "../prompt.txt";

function isTagged(content: string): boolean {
  const lines = content.trimEnd().split("\n");
  const last = lines[lines.length - 1]?.trim() ?? "";
  return last.startsWith("#");
}

function chunk<T>(arr: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

function getFilesInFolder(app: App, folder: string): TFile[] {
  return app.vault
    .getMarkdownFiles()
    .filter(
      (f) => f.path.startsWith(folder + "/") || f.path === folder
    );
}

export async function collectExistingTags(
  app: App,
  folder: string
): Promise<Set<string>> {
  const tags = new Set<string>();
  const files = getFilesInFolder(app, folder);

  for (const file of files) {
    const content = await app.vault.cachedRead(file);
    const lines = content.trimEnd().split("\n");
    const last = lines[lines.length - 1]?.trim() ?? "";
    if (last.startsWith("#")) {
      last.split(/\s+/).forEach((t) => tags.add(t.replace(/^#/, "")));
    }
  }

  return tags;
}

async function getUntaggedFiles(
  app: App,
  folder: string
): Promise<TFile[]> {
  const files = getFilesInFolder(app, folder);
  const untagged: TFile[] = [];

  for (const file of files) {
    const content = await app.vault.cachedRead(file);
    if (content.trim() === "") continue;
    if (!isTagged(content)) {
      untagged.push(file);
    }
  }

  return untagged;
}

function buildPrompt(ideas: string[], existingTags: Set<string>): string {
  return PROMPT_TEMPLATE
    .replace("{{EXISTING_TAGS}}", [...existingTags].join(", "))
    .replace("{{IDEAS}}", ideas.join("\n"));
}

async function callOllama(
  settings: NapkinTaggerSettings,
  prompt: string
): Promise<Record<string, string[]>> {
  const response = await requestUrl({
    url: `${settings.ollamaUrl}/api/chat`,
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: settings.model,
      messages: [{ role: "user", content: prompt }],
      stream: false,
      format: "json",
    }),
  });

  let text: string = response.json.message.content;

  // Strip markdown fences if model wraps response
  text = text.replace(/^```(?:json)?\s*\n?/, "").replace(/\n?```\s*$/, "");

  return JSON.parse(text) as Record<string, string[]>;
}

export async function tagFiles(
  app: App,
  settings: NapkinTaggerSettings
): Promise<{ tagged: number; newTags: number; reused: number }> {
  const existingTags = await collectExistingTags(app, settings.folder);
  const untagged = await getUntaggedFiles(app, settings.folder);

  if (untagged.length === 0) {
    new Notice("All notes are tagged.");
    return { tagged: 0, newTags: 0, reused: 0 };
  }

  let tagged = 0;
  let newTags = 0;
  let reused = 0;

  for (const batch of chunk(untagged, 20)) {
    const ideas = await Promise.all(
      batch.map(async (f, i) => {
        const text = (await app.vault.cachedRead(f)).trim();
        return `${i + 1}. "${text}"`;
      })
    );

    const prompt = buildPrompt(ideas, existingTags);

    let tags: Record<string, string[]>;
    try {
      tags = await callOllama(settings, prompt);
    } catch (e) {
      console.error("Napkin Tagger: Ollama error", e);
      const msg =
        e instanceof Error ? e.message : "Unknown error";
      new Notice(`Napkin Tagger: Ollama error — ${msg}`);
      continue;
    }

    for (let i = 0; i < batch.length; i++) {
      const fileTags = tags[String(i + 1)];
      if (!fileTags || !Array.isArray(fileTags)) continue;

      const file = batch[i];
      if (!file) continue;

      // Check file still exists
      if (!app.vault.getFileByPath(file.path)) continue;

      const tagLine = fileTags
        .map((t: string) => `#${t.replace(/^#/, "")}`)
        .join(" ");

      try {
        await app.vault.process(file, (content) => {
          return content.trimEnd() + "\n\n" + tagLine;
        });

        tagged++;
        for (const t of fileTags) {
          const clean = t.replace(/^#/, "");
          if (existingTags.has(clean)) {
            reused++;
          } else {
            newTags++;
            existingTags.add(clean);
          }
        }
      } catch (e) {
        console.error(`Napkin Tagger: failed to tag ${file.path}`, e);
      }
    }
  }

  return { tagged, newTags, reused };
}

export async function tagSingleFile(
  app: App,
  settings: NapkinTaggerSettings,
  file: TFile
): Promise<boolean> {
  const content = await app.vault.cachedRead(file);
  if (content.trim() === "" || isTagged(content)) return false;

  const existingTags = await collectExistingTags(app, settings.folder);
  const ideas = [`1. "${content.trim()}"`];
  const prompt = buildPrompt(ideas, existingTags);

  const tags = await callOllama(settings, prompt);
  const fileTags = tags["1"];
  if (!fileTags || !Array.isArray(fileTags)) return false;

  if (!app.vault.getFileByPath(file.path)) return false;

  const tagLine = fileTags
    .map((t: string) => `#${t.replace(/^#/, "")}`)
    .join(" ");

  await app.vault.process(file, (c) => c.trimEnd() + "\n\n" + tagLine);
  return true;
}
