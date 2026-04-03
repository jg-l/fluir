#!/usr/bin/env fish

set FOLDER ~/Documents/Obsidian/vibe/vibe/ideas
set OLLAMA_URL http://100.103.186.65:11434
set MODEL gemma4:e4b
set BATCH_SIZE 5
set SCRIPT_DIR (status dirname)
set PROMPT_TEMPLATE (cat "$SCRIPT_DIR/prompt.txt")

echo "Fluir"
echo "  Folder: $FOLDER"
echo "  Ollama: $OLLAMA_URL"
echo "  Model:  $MODEL"
echo ""

# Extract tags from file content (last line or inline)
function extract_tags -a filepath
    set lines (string match -rv '^\s*$' < "$filepath")
    test (count $lines) -gt 0; or return 1

    set last (string trim -- $lines[-1])
    if string match -qr '^#[a-z]' -- "$last"
        for t in (string split ' ' -- "$last")
            string replace -r '^#' '' -- "$t"
        end
        return 0
    end

    set content (string collect < "$filepath")
    set matches (string match -ra '#[a-z][a-z0-9-]*' -- "$content")
    if test (count $matches) -gt 0
        for t in $matches
            string replace -r '^#' '' -- "$t"
        end
        return 0
    end

    return 1
end

function has_tags -a filepath
    extract_tags "$filepath" >/dev/null 2>&1
end

# Scan files
echo -n "Scanning files..."
set all_files $FOLDER/*.md
echo " found "(count $all_files)" files."

echo -n "Collecting existing tags..."
set existing_tags
for f in $all_files
    test -f "$f"; or continue
    set tags (extract_tags "$f")
    for t in $tags
        if test -n "$t"
            contains -- "$t" $existing_tags; or set -a existing_tags "$t"
        end
    end
end
echo " "(count $existing_tags)" unique tags."

echo -n "Finding untagged notes..."
set untagged
for f in $all_files
    test -f "$f"; or continue
    set content (string match -rv '^\s*$' < "$f")
    test (count $content) -gt 0; or continue
    if not has_tags "$f"
        set -a untagged "$f"
    end
end
echo " "(count $untagged)" untagged."

if test (count $untagged) -eq 0
    echo "All notes are tagged."
    exit 0
end

echo ""

set total_tagged 0
set total_new 0
set total_reused 0
set total_batches (math "ceil("(count $untagged)" / $BATCH_SIZE)")

# Process in batches
set i 1
set batch_num 0
while test $i -le (count $untagged)
    set batch_end (math "min($i + $BATCH_SIZE - 1, "(count $untagged)")")
    set batch $untagged[$i..$batch_end]
    set batch_num (math $batch_num + 1)

    echo "Batch $batch_num/$total_batches ("(count $batch)" notes)"

    # Build numbered ideas list
    set ideas ""
    set n 1
    for f in $batch
        set text (string collect < "$f" | string trim)
        set ideas "$ideas$n. \"$text\"\n"
        set n (math $n + 1)
    end

    set tag_list (string join ', ' -- $existing_tags)
    set ideas_str (printf '%b' "$ideas")

    set prompt (string replace '{{EXISTING_TAGS}}' "$tag_list" -- "$PROMPT_TEMPLATE" | string replace '{{IDEAS}}' "$ideas_str")

    set payload (jq -n --arg model "$MODEL" --arg content "$prompt" \
        '{model: $model, messages: [{role: "user", content: $content}], stream: false, format: "json"}')

    echo -n "  Calling Ollama..."
    set start_time (date +%s)
    set response (curl -s --max-time 300 -X POST "$OLLAMA_URL/api/chat" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1)
    set curl_status $status
    set elapsed (math (date +%s) - $start_time)

    if test $curl_status -ne 0
        echo " FAILED ($elapsed""s) — Ollama not reachable at $OLLAMA_URL"
        set i (math $batch_end + 1)
        continue
    end
    echo " done ($elapsed""s)"

    # Extract the message content
    set llm_output (echo "$response" | jq -r '.message.content // empty')
    if test -z "$llm_output"
        set err (echo "$response" | jq -r '.error // empty')
        if test -n "$err"
            echo "  Error from Ollama: $err"
        else
            echo "  Error: Empty response from Ollama"
        end
        set i (math $batch_end + 1)
        continue
    end

    # Strip markdown fences if present
    set llm_output (echo "$llm_output" | string replace -r '^```(?:json)?\s*\n?' '' | string replace -r '\n?```\s*$' '' | string collect)

    # Validate JSON
    if not echo "$llm_output" | jq empty 2>/dev/null
        echo "  Error: Bad JSON from model, skipping batch"
        echo "  Response: "(string sub -l 200 -- "$llm_output")
        set i (math $batch_end + 1)
        continue
    end

    # Apply tags to each file in batch
    set batch_tagged 0
    set n 1
    for f in $batch
        set file_tags (echo "$llm_output" | jq -r ".[\"$n\"][]?" 2>/dev/null)

        if test (count $file_tags) -gt 0
            set tag_line ""
            for t in $file_tags
                set t (string replace -r '^#' '' -- "$t")
                test -n "$t"; or continue
                if test -n "$tag_line"
                    set tag_line "$tag_line #$t"
                else
                    set tag_line "#$t"
                end

                if contains -- "$t" $existing_tags
                    set total_reused (math $total_reused + 1)
                else
                    set total_new (math $total_new + 1)
                    set -a existing_tags "$t"
                end
            end

            if test -n "$tag_line"
                set current (string collect < "$f")
                set trimmed (string trim -r -- "$current")
                printf '%s\n\n%s\n' "$trimmed" "$tag_line" > "$f"
                set total_tagged (math $total_tagged + 1)
                set batch_tagged (math $batch_tagged + 1)
                echo "  Tagged: "(basename "$f")" → $tag_line"
            end
        else
            echo "  Skipped: "(basename "$f")" (no tags returned)"
        end

        set n (math $n + 1)
    end

    echo "  Batch done: $batch_tagged tagged"
    echo ""

    set i (math $batch_end + 1)
end

echo "Done! Tagged $total_tagged notes. $total_new new tags, $total_reused reused."
