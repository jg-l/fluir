#!/usr/bin/env fish

# Import Kindle highlights into Obsidian vault, skipping duplicates.
# Usage: ./import-clippings.fish <path-to-My-Clippings.txt>

set FOLDER ~/Documents/Obsidian/vibe/vibe/ideas

if test (count $argv) -eq 0
    echo "Usage: import-clippings.fish <path-to-My-Clippings.txt>"
    exit 1
end

set CLIPPINGS_FILE $argv[1]
if not test -f "$CLIPPINGS_FILE"
    echo "File not found: $CLIPPINGS_FILE"
    exit 1
end

# Build list of normalized existing note content for dedup (substring matching)
set existing_bodies
for f in $FOLDER/*.md
    test -f "$f"; or continue
    set lines (string match -rv '^\s*$' < "$f")
    test (count $lines) -gt 0; or continue
    set last (string trim -- $lines[-1])
    if string match -qr '^#' -- "$last"
        set lines $lines[1..-2]
    end
    set body (string join ' ' -- $lines | string lower | string replace -ra '[^a-z0-9]' '')
    if test -n "$body"
        set -a existing_bodies "$body"
    end
end

echo "Indexed "(count $existing_bodies)" existing notes."

# Check if normalized text is contained in any existing note (or vice versa)
function is_duplicate -a normalized
    for body in $existing_bodies
        if string match -q "*$normalized*" -- "$body"; or string match -q "*$body*" -- "$normalized"
            return 0
        end
    end
    return 1
end

# Parse My Clippings.txt
# Format:
#   Book Title (Author Name)
#   - Your Highlight on page X | Location Y-Z | Added on ...
#   <blank line>
#   Highlighted text (may be multi-line)
#   ==========

set imported 0
set skipped_dupes 0
set skipped_empty 0

set current_title ""
set current_author ""
set current_text ""
set in_highlight false
set line_num 0

# Read the file line by line
set all_lines
while read -l line
    set -a all_lines "$line"
end < "$CLIPPINGS_FILE"

set i 1
while test $i -le (count $all_lines)
    set line $all_lines[$i]

    # Check for separator
    if string match -q '==========' -- "$line"
        # Process the collected highlight
        set text (string trim -- "$current_text")

        if test -n "$text"
            # Build attribution line
            set attribution ""
            if test -n "$current_author"
                set attribution "- $current_author, $current_title"
            else if test -n "$current_title"
                set attribution "- $current_title"
            end

            # Build full note content
            set note_content "$text"
            if test -n "$attribution"
                set note_content "$text
$attribution"
            end

            # Normalize highlight text for dedup
            set normalized_text (echo -n "$text" | string lower | string replace -ra '[^a-z0-9]' '' | string collect)

            if is_duplicate "$normalized_text"
                set skipped_dupes (math $skipped_dupes + 1)
            else
                # Generate filename from first few words
                set slug (echo "$text" | string lower | string replace -ra '[^a-z0-9 ]' '' | string split ' ' | head -8 | string join '-')
                set filename "$slug.md"

                # Ensure unique filename
                set counter 1
                while test -f "$FOLDER/$filename"
                    set filename "$slug-$counter.md"
                    set counter (math $counter + 1)
                end

                printf '%s\n' "$note_content" > "$FOLDER/$filename"
                set imported (math $imported + 1)
                # Add to existing bodies so later clippings in same file dedup against it
                set -a existing_bodies "$normalized_text"
                echo "  Imported: $filename"
            end
        else
            set skipped_empty (math $skipped_empty + 1)
        end

        # Reset for next clipping
        set current_title ""
        set current_author ""
        set current_text ""
        set in_highlight false
        set i (math $i + 1)
        continue
    end

    # First line after separator: book title (Author)
    if test -z "$current_title"; and test "$in_highlight" != true
        # Extract author from parentheses if present
        if string match -qr '\(([^)]+)\)\s*$' -- "$line"
            set current_author (string match -r '\(([^)]+)\)\s*$' -- "$line")[2]
            set current_title (string replace -r '\s*\([^)]+\)\s*$' '' -- "$line")
        else
            set current_title (string trim -- "$line")
        end
        set i (math $i + 1)
        continue
    end

    # Second line: metadata (- Your Highlight on ...)
    if string match -qr '^- Your ' -- "$line"
        # Skip bookmarks, only import highlights
        if string match -qr 'Your Bookmark' -- "$line"
            # Fast-forward to next separator
            while test $i -le (count $all_lines); and not string match -q '==========' -- $all_lines[$i]
                set i (math $i + 1)
            end
            continue
        end
        set in_highlight true
        set i (math $i + 1)
        continue
    end

    # Blank line between metadata and highlight text
    if test "$in_highlight" = true; and test -z (string trim -- "$line")
        if test -z "$current_text"
            set i (math $i + 1)
            continue
        end
    end

    # Highlight text (may be multi-line)
    if test "$in_highlight" = true
        set trimmed (string trim -- "$line")
        if test -n "$trimmed"
            if test -n "$current_text"
                set current_text "$current_text
$trimmed"
            else
                set current_text "$trimmed"
            end
        end
    end

    set i (math $i + 1)
end

echo ""
echo "Imported $imported new highlights. Skipped $skipped_dupes duplicates, $skipped_empty empty."
