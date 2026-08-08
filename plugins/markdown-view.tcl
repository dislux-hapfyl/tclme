# plugins/markdown-view.tcl
# ============================================================================
# markdown-preview.tcl - render Markdown into styled Tclme text
#
# Commands:
#   :markdown-preview
#   :md
#
# Keybinding:
#   C-x m
#
# Supports a practical Markdown subset:
#   # headings
#   **bold**
#   *italic*
#   `inline code`
#   ``` fenced code blocks ```
#   > blockquotes
#   - unordered lists
#   1. ordered lists
#   [links](url)
#   horizontal rules
#
# This is a renderer, not a full CommonMark implementation.
# ============================================================================

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc Theme {key default} {
    if {[catch { set v [::Tclme::GetTheme $key] }]} {
        return $default
    }

    if {$v eq ""} {
        return $default
    }

    return $v
}

proc CurrentText {} {
    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    if {[winfo class $w] ne "Text"} {
        return ""
    }

    return $w
}

proc SetReadonly {bufname val} {
    upvar #0 ::Tclme::buffers buffers

    if {[dict exists $buffers $bufname]} {
        dict set buffers $bufname readonly $val
    }
}

# ----------------------------------------------------------------------------
# Command
# ----------------------------------------------------------------------------

proc cmd-preview {args} {
    set src $::Tclme::current_buffer

    if {[string match "*markdown:*" $src]} {
        ::Tclme::Message "Already a Markdown preview"
        return
    }

    set txt [CurrentText]

    if {$txt eq ""} {
        ::Tclme::Message "No active text buffer"
        return
    }

    set markdown [$txt get 1.0 end-1c]
    set bufname "*markdown: $src*"

    if {[catch { ::Tclme::SwitchToBuffer $bufname } err]} {
        ::Tclme::Message "Cannot open Markdown preview: $err"
        return
    }

    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    SetupTags $w

    $w configure -state normal
    $w delete 1.0 end

    RenderMarkdown $markdown $w

    $w edit modified 0
    $w configure -state disabled

    SetReadonly $bufname 1

    catch { focus $w }

    ::Tclme::Message "Markdown preview: $bufname"
}

# ----------------------------------------------------------------------------
# Styling
# ----------------------------------------------------------------------------

proc SetupTags {w} {
    set base [Theme font {Helvetica 12}]

    if {[llength $base] < 2} {
        set base {Helvetica 12}
    }

    set family [lindex $base 0]
    set size   [lindex $base 1]

    if {![string is integer -strict $size]} {
        set size 12
    }

    set accent [Theme accent      "#4A7CFE"]
    set sep    [Theme separator   "#DDDDDD"]
    set muted  [Theme status_fg   "#666666"]

    $w tag configure h1 \
        -font [list $family [expr {$size + 8}] bold] \
        -spacing1 10 \
        -spacing3 6

    $w tag configure h2 \
        -font [list $family [expr {$size + 5}] bold] \
        -spacing1 8 \
        -spacing3 5

    $w tag configure h3 \
        -font [list $family [expr {$size + 3}] bold] \
        -spacing1 6 \
        -spacing3 4

    $w tag configure h4 \
        -font [list $family [expr {$size + 2}] bold] \
        -spacing1 5 \
        -spacing3 3

    $w tag configure h5 \
        -font [list $family [expr {$size + 1}] bold] \
        -spacing1 4 \
        -spacing3 3

    $w tag configure h6 \
        -font [list $family $size bold] \
        -spacing1 4 \
        -spacing3 3

    $w tag configure bold \
        -font [list $family $size bold]

    $w tag configure italic \
        -font [list $family $size italic]

    $w tag configure code \
        -background $sep \
        -foreground $accent

    $w tag configure codeblock \
        -background $sep \
        -lmargin1 12 \
        -lmargin2 12

    $w tag configure quote \
        -foreground $muted \
        -lmargin1 18 \
        -lmargin2 18

    $w tag configure bullet \
        -foreground $accent

    $w tag configure list \
        -lmargin1 10 \
        -lmargin2 24

    $w tag configure link \
        -foreground $accent \
        -underline 1

    $w tag configure hr \
        -foreground $sep

    # Priority.
    #
    # Headings are raised high so heading fonts dominate inline bold/italic.
    # Link/code colors still apply because headings do not set those options.
    foreach tag {quote bullet list code link} {
        $w tag raise $tag
    }

    foreach tag {h6 h5 h4 h3 h2 h1} {
        $w tag raise $tag
    }
}

# ----------------------------------------------------------------------------
# Markdown rendering
# ----------------------------------------------------------------------------

proc RenderMarkdown {text w} {
    set lines [split $text \n]

    set in_code 0

    foreach line $lines {
        # Fenced code blocks.
        if {[regexp {^\s*```\s*(.*)$} $line -> lang]} {
            if {$in_code} {
                set in_code 0
                $w insert end "\n"
            } else {
                set in_code 1
                $w insert end "\n"
            }

            continue
        }

        if {$in_code} {
            $w insert end "$line\n" codeblock
            continue
        }

        # Blank line.
        if {[string trim $line] eq ""} {
            $w insert end "\n"
            continue
        }

        # Headings.
        if {[regexp {^(#{1,6})\s+(.*)$} $line -> hashes content]} {
            set level [string length $hashes]

            RenderInline $w [string trim $content] [list h$level]
            $w insert end "\n"

            continue
        }

        # Horizontal rule.
        if {[regexp {^\s*(-{3,}|\*{3,}|_{3,})\s*$} $line]} {
            $w insert end "────────────────────────────────\n" hr
            continue
        }

        # Blockquote.
        if {[regexp {^\s*>\s?(.*)$} $line -> content]} {
            $w insert end "> " quote
            RenderInline $w $content quote
            $w insert end "\n"

            continue
        }

        # Unordered list.
        if {[regexp {^\s*[-*+]\s+(.*)$} $line -> content]} {
            $w insert end "  • " [list bullet list]
            RenderInline $w $content list
            $w insert end "\n"

            continue
        }

        # Ordered list.
        if {[regexp {^\s*(\d+)[.)]\s+(.*)$} $line -> num content]} {
            $w insert end "  $num. " [list bullet list]
            RenderInline $w $content list
            $w insert end "\n"

            continue
        }

        # Normal paragraph line.
        RenderInline $w $line {}
        $w insert end "\n"
    }
}

proc RenderInline {w text basetags} {
    # Simple inline Markdown scanner.
    #
    # Order matters:
    #   inline code first
    #   bold before italic
    #   links last
    set inline_re {`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*|\[[^\]]+\]\([^)]+\)}

    set rest $text

    while {[regexp -indices $inline_re $rest match]} {
        set start [lindex $match 0]
        set end   [lindex $match 1]

        if {$start > 0} {
            InsertWithTags $w [string range $rest 0 [expr {$start - 1}]] $basetags
        }

        set token [string range $rest $start $end]

        InsertInlineToken $w $token $basetags

        set rest [string range $rest [expr {$end + 1}] end]
    }

    if {$rest ne ""} {
        InsertWithTags $w $rest $basetags
    }
}

proc InsertInlineToken {w token basetags} {
    set first [string index $token 0]
    set two   [string range $token 0 1]

    # Inline code.
    if {$first eq "`" && [string length $token] >= 2} {
        set content [string range $token 1 end-1]
        InsertWithTags $w $content [concat $basetags code]
        return
    }

    # Bold with **.
    if {$two eq "**" && [string length $token] >= 4} {
        set content [string range $token 2 end-2]
        InsertWithTags $w $content [concat $basetags bold]
        return
    }

    # Italic with *.
    if {$first eq "*" && [string length $token] >= 2} {
        set content [string range $token 1 end-1]
        InsertWithTags $w $content [concat $basetags italic]
        return
    }

    # Link.
    if {[regexp {^\[([^\]]+)\]\(([^)]+)\)$} $token -> label url]} {
        InsertWithTags $w $label [concat $basetags link]
        return
    }

    # Fallback.
    InsertWithTags $w $token $basetags
}

proc InsertWithTags {w text tags} {
    if {$text eq ""} {
        return
    }

    if {[llength $tags] == 0} {
        $w insert end $text
    } else {
        $w insert end $text $tags
    }
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::DefCommand markdown-preview cmd-preview \
    "Render Markdown from current buffer into styled preview"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias md markdown-preview }
}

if {[info commands ::Tclme::BindKey] ne ""} {
    catch { ::Tclme::BindKey markdown-preview <Control-x>m }

    # Optional: make the binding visible in :help if your Tclme stores keys.
    catch {
        upvar #0 ::Tclme::commands commands

        if {[dict exists $commands markdown-preview]} {
            dict set commands markdown-preview keys <Control-x>m
        }
    }
}