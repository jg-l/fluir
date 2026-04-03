#!/usr/bin/env fish

# Migrates inline tags to their own last line (canonical format)
# Before: Some text about life  #philosophy #life
# After:  Some text about life
#
#         #philosophy #life

set FOLDER ~/Documents/Obsidian/vibe/vibe/ideas
set migrated 0

for f in $FOLDER/*.md
    test -f "$f"; or continue
    set content (string collect < "$f")
    set lines (string match -rv '^\s*$' -- "$content")
    test (count $lines) -gt 0; or continue

    set last (string trim -- $lines[-1])

    # Skip if already in canonical format (last line is all tags)
    if string match -qr '^#[a-z]' -- "$last"
        continue
    end

    # Check for inline tags
    if not string match -qr '\s+#[a-z][a-z0-9-]*' -- "$content"
        continue
    end

    # Extract inline tags and strip them from content
    set all_lines (string split \n -- "$content")
    set new_lines
    set found_tags

    for line in $all_lines
        # Find tags in this line
        set tags (string match -ra '#[a-z][a-z0-9-]*' -- "$line")
        if test (count $tags) -gt 0
            # Remove the tag portion from the line
            set cleaned (string replace -r '\s+(#[a-z][a-z0-9-]*(\s+#[a-z][a-z0-9-]*)*)$' '' -- "$line")
            set -a new_lines "$cleaned"
            for t in $tags
                contains -- "$t" $found_tags; or set -a found_tags "$t"
            end
        else
            set -a new_lines "$line"
        end
    end

    if test (count $found_tags) -eq 0
        continue
    end

    set tag_line (string join ' ' -- $found_tags)
    set body (string join \n -- $new_lines | string trim -r)
    printf '%s\n\n%s\n' "$body" "$tag_line" > "$f"
    set migrated (math $migrated + 1)
    echo "  Migrated: "(basename "$f")
    echo "    tags: $tag_line"
end

echo "Migrated $migrated files."
