#!/usr/bin/env fish

set FOLDER ~/Documents/Obsidian/vibe/vibe/ideas
set fixed 0

function clean_tag -a t
    # strip # prefix
    set t (string replace -r '^#' '' -- "$t")
    # lowercase
    set t (string lower -- "$t")
    # replace underscores, dots, apostrophes with hyphens
    set t (string replace -ra "[_.'\"\\s]" '-' -- "$t")
    # strip non alpha/hyphen
    set t (string replace -ra '[^a-z\-]' '' -- "$t")
    # collapse multiple hyphens (use [-] to avoid flag parsing)
    set t (string replace -ra '[-][-]+' '-' -- "$t")
    # trim leading/trailing hyphens
    set t (string replace -r '^[-]+' '' -- "$t")
    set t (string replace -r '[-]+$' '' -- "$t")
    echo "$t"
end

for f in $FOLDER/*.md
    test -f "$f"; or continue
    set content (string collect < "$f")

    # Find inline tags: look for #word patterns
    if not string match -qr '#[a-z]' -- "$content"
        continue
    end

    # Extract everything before the first #tag and the tags themselves
    # Tags appear at the end of a line as #tag1 #tag2 #tag3
    set lines (string split \n -- "$content")
    set changed false

    set new_lines
    for line in $lines
        # Check if this line has tags (one or more #word at the end)
        if string match -qr '\s+#[a-z]' -- "$line"
            # Split line into content part and tags part
            set before (string replace -r '\s+(#[a-z][\-a-zA-Z0-9._\']*(\s+#[a-z][\-a-zA-Z0-9._\']*)*)$' '' -- "$line")
            set tag_str (string match -r '(#[a-z][\-a-zA-Z0-9._\']*(\s+#[a-z][\-a-zA-Z0-9._\']*)*)$' -- "$line")

            if test -n "$tag_str[1]"
                set new_tags
                for t in (string split ' ' -- "$tag_str[1]")
                    string match -qr '^#' -- "$t"; or continue
                    set cleaned (clean_tag "$t")
                    test -n "$cleaned"; or continue
                    set -a new_tags "#$cleaned"
                end

                set new_tag_line (string join ' ' -- $new_tags)
                set new_line "$before  $new_tag_line"

                if test "$new_line" != "$line"
                    set changed true
                end
                set -a new_lines "$new_line"
            else
                set -a new_lines "$line"
            end
        else
            set -a new_lines "$line"
        end
    end

    if test "$changed" = true
        # Write back, trimming trailing blank lines
        set result (string join \n -- $new_lines | string collect)
        set result (string trim -r -- "$result")
        printf '%s\n' "$result" > "$f"
        set fixed (math $fixed + 1)
        echo "  Fixed: "(basename "$f")
    else
        # Still clean up trailing blank lines if present
        set trimmed (string trim -r -- "$content")
        if test "$trimmed" != (string replace -r '\n$' '' -- "$content")
            printf '%s\n' "$trimmed" > "$f"
        end
    end
end

echo "Fixed $fixed files."
