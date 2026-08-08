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
    # Remove dynamic table tags from previous renders.
    foreach tag [$w tag names] {
        if {[string match "__md_table_*" $tag]} {
            catch {$w tag delete $tag}
        }
    }

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

    # Table tags.
    #
    # table_header  : first row
    # table_cell    : normal body cells
    # table_rule    : horizontal/vertical separators
    #
    # Dynamic per-table tags named __md_table_N carry the actual tab stops.
    $w tag configure table_header \
        -font [list $family [expr {$size + 1}] bold] \
        -spacing1 6 \
        -spacing3 3

    $w tag configure table_cell \
        -spacing1 2 \
        -spacing3 2

    $w tag configure table_rule \
        -foreground $sep

    # Priority.
    #
    # Headings are raised high so heading fonts dominate inline bold/italic.
    # Link/code colors still apply because headings do not set those options.
    foreach tag {quote bullet list code link table_header table_cell table_rule} {
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
    set n [llength $lines]
    set in_code 0

    for {set i 0} {$i < $n} {incr i} {
        set line [lindex $lines $i]

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

        # Table.
        #
        # Require:
        #   current line contains |
        #   next line is a Markdown separator line
        #
        # Example:
        #   | Area | Plugin |
        #   |------|--------|
        #   | foo  | bar    |
        if {[string match "*|*" $line] && ($i + 1) < $n &&
            [IsTableSeparatorLine [lindex $lines [expr {$i + 1}]]]} {
            set table_lines {}
            set j $i

            while {$j < $n} {
                set l [lindex $lines $j]

                if {[string trim $l] eq ""} {
                    break
                }

                if {![string match "*|*" $l]} {
                    break
                }

                lappend table_lines $l
                incr j
            }

            RenderTable $w $table_lines

            # for-loop will incr i once more.
            set i [expr {$j - 1}]
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

# ----------------------------------------------------------------------------
# Table helpers
# ----------------------------------------------------------------------------

proc IsTableSeparatorLine {line} {
    set t [string trim $line]

    if {$t eq ""} {
        return 0
    }

    if {[string first "|" $t] == -1} {
        return 0
    }

    if {[string first "-" $t] == -1} {
        return 0
    }

    # Separator lines may contain only:
    #   spaces, tabs, pipes, colons, dashes
    #
    # Example:
    #   |---|:---:|---:|
    set stripped [string map [list " " "" "\t" "" "|" "" ":" "" "-" ""] $t]

    return [expr {$stripped eq ""}]
}

proc ParseTableRow {line} {
    set t [string trim $line]

    # Remove one leading and one trailing pipe if present.
    if {[string index $t 0] eq "|"} {
        set t [string range $t 1 end]
    }

    if {[string index $t end] eq "|"} {
        set t [string range $t 0 end-1]
    }

    # Temporarily protect escaped pipes: \|
    set sentinel "\u0001"
    regsub -all {\\\|} $t $sentinel t

    set cells [split $t |]
    set out {}

    foreach c $cells {
        # Restore escaped pipes.
        regsub -all $sentinel $c "|" c

        # Tabs would interfere with the table tab layout.
        regsub -all "\t" $c " " c

        lappend out [string trim $c]
    }

    return $out
}

proc PlainInlineText {text} {
    # Return the visible text that RenderInline would produce.
    #
    # This is used for measuring column widths. It strips Markdown markers
    # but keeps code contents intact, even if code contains * or **.

    set inline_re {`[^`]+`|\*\*[^*]+\*\*|\*[^*]+\*|\[[^\]]+\]\([^)]+\)}

    set out ""
    set rest $text

    while {[regexp -indices $inline_re $rest match]} {
        set start [lindex $match 0]
        set end   [lindex $match 1]

        if {$start > 0} {
            append out [string range $rest 0 [expr {$start - 1}]]
        }

        set token [string range $rest $start $end]
        append out [PlainInlineTokenText $token]

        set rest [string range $rest [expr {$end + 1}] end]
    }

    append out $rest

    return $out
}

proc PlainInlineTokenText {token} {
    set first [string index $token 0]
    set two   [string range $token 0 1]

    # Inline code.
    if {$first eq "`" && [string length $token] >= 2} {
        return [string range $token 1 end-1]
    }

    # Bold with **.
    if {$two eq "**" && [string length $token] >= 4} {
        return [string range $token 2 end-2]
    }

    # Italic with *.
    if {$first eq "*" && [string length $token] >= 2} {
        return [string range $token 1 end-1]
    }

    # Link.
    if {[regexp {^\[([^\]]+)\]\(([^)]+)\)$} $token -> label url]} {
        return $label
    }

    return $token
}

proc MeasurePixels {font text} {
    if {$text eq ""} {
        return 0
    }

    if {[catch {font measure $font $text} px]} {
        # Very rough fallback.
        return [expr {[string length $text] * 7}]
    }

    return $px
}

proc MakePixelRule {font width} {
    # Build a horizontal rule string that fits inside the given pixel width.

    if {$width <= 0} {
        return ""
    }

    set unit [MeasurePixels $font "─"]

    if {$unit <= 0} {
        set unit 6
    }

    set n [expr {$width / $unit}]

    if {$n < 1} {
        set n 1
    }

    set rule [string repeat "─" $n]

    # If we overshot, shrink until it fits.
    while {$n > 1 && [MeasurePixels $font $rule] > $width} {
        incr n -1
        set rule [string repeat "─" $n]
    }

    if {[MeasurePixels $font $rule] > $width} {
        return ""
    }

    return $rule
}

proc InsertTableRule {w tabletag widths ncols font} {
    set tags [list $tabletag table_rule]

    for {set c 0} {$c < $ncols} {incr c} {
        set rule [MakePixelRule $font [lindex $widths $c]]

        if {$rule ne ""} {
            $w insert end $rule $tags
        }

        if {$c < $ncols - 1} {
            $w insert end "\t" $tags
            $w insert end "┼" $tags
            $w insert end "\t" $tags
        }
    }

    $w insert end "\n" [list $tabletag]
}

proc RenderTable {w lines} {
    if {[llength $lines] == 0} {
        return
    }

    # Parse rows.
    #
    # The second line is normally the Markdown separator:
    #
    #   | Area | Plugin |
    #   |------|--------|
    #   | foo  | bar    |
    #
    # We skip that separator line and keep header/body rows.

    set rows {}
    set lineno 0

    foreach line $lines {
        if {$lineno == 1 && [IsTableSeparatorLine $line]} {
            incr lineno
            continue
        }

        lappend rows [ParseTableRow $line]
        incr lineno
    }

    if {[llength $rows] == 0} {
        return
    }

    # Determine column count.
    set ncols 0

    foreach row $rows {
        set len [llength $row]

        if {$len > $ncols} {
            set ncols $len
        }
    }

    if {$ncols == 0} {
        return
    }

    # Normalize rows to the same number of cells.
    set normalized {}

    foreach row $rows {
        set nr {}

        for {set c 0} {$c < $ncols} {incr c} {
            if {$c < [llength $row]} {
                lappend nr [lindex $row $c]
            } else {
                lappend nr ""
            }
        }

        lappend normalized $nr
    }

    # Font information for measuring.
    set base [Theme font {Helvetica 12}]

    if {[llength $base] < 2} {
        set base {Helvetica 12}
    }

    set family [lindex $base 0]
    set size   [lindex $base 1]

    if {![string is integer -strict $size]} {
        set size 12
    }

    set normal_font $base
    set bold_font   [list $family $size bold]
    set italic_font [list $family $size italic]

    # Compute pixel widths for each column.
    set widths {}

    for {set c 0} {$c < $ncols} {incr c} {
        lappend widths 0
    }

    foreach row $normalized {
        set c 0

        foreach cell $row {
            set plain [PlainInlineText $cell]
            set best 0

            foreach f [list $normal_font $bold_font $italic_font] {
                set px [MeasurePixels $f $plain]

                if {$px > $best} {
                    set best $px
                }
            }

            if {$best > [lindex $widths $c]} {
                lset widths $c $best
            }

            incr c
        }
    }

    # Padding around columns.
    set pad [MeasurePixels $normal_font "  "]

    if {$pad < 8} {
        set pad 8
    }

    # Separator glyph width.
    set sepw 0

    foreach s [list "│" "┼"] {
        set px [MeasurePixels $normal_font $s]

        if {$px > $sepw} {
            set sepw $px
        }
    }

    if {$sepw <= 0} {
        set sepw 8
    }

    # Build tab stops.
    #
    # For each data column except the last, we create two tab stops:
    #
    #   1. where the vertical separator goes
    #   2. where the next column starts
    #
    # Row layout becomes:
    #
    #   cell0 <tab> │ <tab> cell1 <tab> │ <tab> cell2

    set tabs {}
    set x 0

    for {set c 0} {$c < $ncols - 1} {incr c} {
        incr x [expr {[lindex $widths $c] + $pad}]
        lappend tabs $x left

        incr x [expr {$sepw + $pad}]
        lappend tabs $x left
    }

    # Create a dynamic tag carrying this table's tab stops.
    set tabletag "__md_table_[incr ::markdown_view_table_seq]"

    catch {$w tag configure $tabletag -tabs $tabs}
    catch {$w tag configure $tabletag -wrap none}
    catch {$w tag raise $tabletag}

    # Insert table rows.
    set first 1

    foreach row $normalized {
        if {$first} {
            set celltags [list $tabletag table_header]
        } else {
            set celltags [list $tabletag table_cell]
        }

        for {set c 0} {$c < $ncols} {incr c} {
            set cell [lindex $row $c]

            RenderInline $w $cell $celltags

            if {$c < $ncols - 1} {
                $w insert end "\t" [list $tabletag]
                $w insert end "│" [list $tabletag table_rule]
                $w insert end "\t" [list $tabletag]
            }
        }

        $w insert end "\n" [list $tabletag]

        # After the header row, draw the horizontal rule.
        if {$first} {
            InsertTableRule $w $tabletag $widths $ncols $normal_font
            set first 0
        }
    }
}

# ----------------------------------------------------------------------------
# Inline rendering
# ----------------------------------------------------------------------------

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
