#!/usr/bin/env fish

set FOLDER ~/Documents/Obsidian/vibe/vibe/ideas
set OLLAMA_URL http://100.103.186.65:11434
set MODEL gemma4:e4b
set BATCH_SIZE 20
set SCRIPT_DIR (status dirname)
set PROMPT_TEMPLATE (cat "$SCRIPT_DIR/prompt.txt")

# Get last non-empty line of a file
function last_nonempty -a filepath
    set lines (string match -rv '^\s*$' < "$filepath")
    if test (count $lines) -gt 0
        string trim -- $lines[-1]
    end
end

# Collect existing tags from already-tagged files
set existing_tags
for f in $FOLDER/*.md
    test -f "$f"; or continue
    set last (last_nonempty "$f")
    if string match -qr '^#' -- "$last"
        for t in (string split ' ' -- "$last")
            set t (string replace -r '^#' '' -- "$t")
            if test -n "$t"
                contains -- "$t" $existing_tags; or set -a existing_tags "$t"
            end
        end
    end
end

# Collect untagged files
set untagged
for f in $FOLDER/*.md
    test -f "$f"; or continue
    set trimmed (string match -rv '^\s*$' < "$f")
    if test (count $trimmed) -eq 0
        continue
    end
    set last (string trim -- $trimmed[-1])
    if not string match -qr '^#' -- "$last"
        set -a untagged "$f"
    end
end

if test (count $untagged) -eq 0
    echo "All notes are tagged."
    exit 0
end

echo "Found "(count $untagged)" untagged notes."

set total_tagged 0
set total_new 0
set total_reused 0

# Process in batches
set i 1
while test $i -le (count $untagged)
    set batch_end (math "min($i + $BATCH_SIZE - 1, "(count $untagged)")")
    set batch $untagged[$i..$batch_end]

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

    # Build prompt from shared template
    set prompt (string replace '{{EXISTING_TAGS}}' "$tag_list" -- "$PROMPT_TEMPLATE" | string replace '{{IDEAS}}' "$ideas_str")

    # Build JSON payload
    set payload (jq -n --arg model "$MODEL" --arg content "$prompt" \
        '{model: $model, messages: [{role: "user", content: $content}], stream: false, format: "json"}')

    # Call Ollama
    set response (curl -s -X POST "$OLLAMA_URL/api/chat" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1)

    if test $status -ne 0
        echo "Error: Ollama not reachable at $OLLAMA_URL"
        set i (math $batch_end + 1)
        continue
    end

    # Extract the message content and parse tags
    set llm_output (echo "$response" | jq -r '.message.content // empty')
    if test -z "$llm_output"
        echo "Error: Empty response from Ollama"
        set i (math $batch_end + 1)
        continue
    end

    # Strip markdown fences if present
    set llm_output (echo "$llm_output" | string replace -r '^```(?:json)?\s*\n?' '' | string replace -r '\n?```\s*$' '' | string collect)

    # Validate JSON
    if not echo "$llm_output" | jq empty 2>/dev/null
        echo "Error: Bad JSON from model, skipping batch"
        set i (math $batch_end + 1)
        continue
    end

    # Apply tags to each file in batch
    set n 1
    for f in $batch
        set file_tags (echo "$llm_output" | jq -r ".[\"$n\"][]?" 2>/dev/null)

        if test (count $file_tags) -gt 0
            # Build tag line
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
                echo "  Tagged: "(basename "$f")
            end
        end

        set n (math $n + 1)
    end

    set i (math $batch_end + 1)
end

echo "Tagged $total_tagged notes. $total_new new tags, $total_reused reused."
