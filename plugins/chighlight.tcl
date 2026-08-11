# plugins/chighlight.tcl
# ============================================================================
# chighlight.tcl - C syntax highlighting for Tclme
#
# Uses the new plugin lifecycle:
#
#   init
#   cleanup
#   state
#   restore
#
# Commands:
#   :c-highlight          toggle C highlighting
#   :c-highlight-refresh  refresh current buffer
#
# Alias:
#   :ch
#
# Highlighted items:
#   comments
#   strings
#   character literals
#   keywords
#   common C types
#   preprocessor lines
#   numbers
#   likely function calls
#
# Default extensions:
#   .c .h
#
# You can extend the file extensions like this:
#
#   set ::Tclme::Plugin::chighlight::extensions {.c .h .cpp .hpp .cc}
#
# ============================================================================

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

variable enabled 1
variable refresh_after ""
variable extensions {.c .h}
variable max_lines 10000

# ----------------------------------------------------------------------------
# C keyword and type tables
# ----------------------------------------------------------------------------

variable keywords [dict create]

foreach k {
    auto break case const continue default do else enum extern
    for goto if inline register restrict return sizeof static
    struct switch typedef union volatile while
    _Alignas _Alignof _Atomic _Generic _Noreturn _Static_assert
    _Thread_local
} {
    dict set keywords $k 1
}

variable types [dict create]

foreach t {
    char double float int long short signed unsigned void
    _Bool _Complex _Imaginary
    size_t ssize_t ptrdiff_t wchar_t
    int8_t int16_t int32_t int64_t
    uint8_t uint16_t uint32_t uint64_t
    intptr_t uintptr_t
    FILE bool
} {
    dict set types $t 1
}

variable number_re {^(?:0[xX][0-9a-fA-F]+|[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[uUlLfF]*}

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

proc IsDark {} {
    set bg [Theme editor_bg "#FFFFFF"]

    if {[catch { scan $bg "#%2x%2x%2x" r g b }]} {
        return 0
    }

    set luminance [expr {0.2126 * $r + 0.7152 * $g + 0.0722 * $b}]

    return [expr {$luminance < 128}]
}

proc WidgetForBuffer {name} {
    # Prefer the new buffer-model helper if it exists.
    if {[info commands ::Tclme::WidgetForBuffer] ne ""} {
        return [::Tclme::WidgetForBuffer $name]
    }

    # Fallback for older Tclme versions.
    if {![info exists ::Tclme::buffers]} {
        return ""
    }

    if {![dict exists $::Tclme::buffers $name]} {
        return ""
    }

    set info [dict get $::Tclme::buffers $name]

    if {![dict exists $info wid]} {
        return ""
    }

    set w ".ws.[dict get $info wid].txt"

    if {[winfo exists $w]} {
        return $w
    }

    return ""
}

proc ShouldHighlightBuffer {name} {
    variable extensions

    if {![info exists ::Tclme::buffers]} {
        return 0
    }

    if {![dict exists $::Tclme::buffers $name]} {
        return 0
    }

    set info [dict get $::Tclme::buffers $name]
    set path [dict get $info path]

    if {$path eq ""} {
        set path $name
    }

    set ext [string tolower [file extension $path]]

    if {$ext eq ""} {
        return 0
    }

    return [expr {[lsearch -exact $extensions $ext] >= 0}]
}

# ----------------------------------------------------------------------------
# Tag styling
# ----------------------------------------------------------------------------

proc EnsureTags {w} {
    if {![winfo exists $w]} {
        return
    }

    set dark [IsDark]

    set base_font [Theme font {Consolas 11}]

    if {[llength $base_font] < 2} {
        set base_font {Consolas 11}
    }

    set family [lindex $base_font 0]
    set size   [lindex $base_font 1]

    if {![string is integer -strict $size]} {
        set size 11
    }

    set italic_font [list $family $size italic]

    if {$dark} {
        set comment  "#6A9955"
        set string   "#CE9178"
        set char     "#CE9178"
        set keyword  "#569CD6"
        set type     "#4EC9B0"
        set preproc  "#C586C0"
        set number   "#B5CEA8"
        set func     "#DCDCAA"
    } else {
        set comment  "#008000"
        set string   "#A31515"
        set char     "#A31515"
        set keyword  "#0000FF"
        set type     "#267F99"
        set preproc  "#AF00DB"
        set number   "#098658"
        set func     "#795E26"
    }

    $w tag configure c_comment -foreground $comment -font $italic_font
    $w tag configure c_string  -foreground $string
    $w tag configure c_char    -foreground $char
    $w tag configure c_keyword -foreground $keyword
    $w tag configure c_type    -foreground $type
    $w tag configure c_preproc -foreground $preproc
    $w tag configure c_number  -foreground $number
    $w tag configure c_func    -foreground $func
}

proc RemoveTags {w} {
    if {![winfo exists $w]} {
        return
    }

    foreach tag {
        c_comment
        c_string
        c_char
        c_keyword
        c_type
        c_preproc
        c_number
        c_func
    } {
        catch { $w tag remove $tag 1.0 end }
    }
}

proc RemoveAllTags {} {
    catch {
        foreach name [dict keys $::Tclme::buffers] {
            set w [WidgetForBuffer $name]

            if {$w ne ""} {
                RemoveTags $w
            }
        }
    }
}

# ----------------------------------------------------------------------------
# Highlight engine
# ----------------------------------------------------------------------------

proc HighlightBuffer {name} {
    variable enabled
    variable max_lines

    if {!$enabled} {
        return
    }

    set w [WidgetForBuffer $name]

    if {$w eq ""} {
        return
    }

    if {![ShouldHighlightBuffer $name]} {
        RemoveTags $w
        return
    }

    # Avoid very large buffers.
    set last_line [lindex [split [$w index end] .] 0]

    if {$last_line > $max_lines} {
        RemoveTags $w
        return
    }

    EnsureTags $w
    RemoveTags $w

    if {[catch {
        set text [$w get 1.0 end-1c]
        set lines [split $text \n]

        set in_comment 0
        set lineno 1

        foreach line $lines {
            set in_comment [HighlightLine $w $lineno $line $in_comment]
            incr lineno
        }
    } err]} {
        catch { ::Tclme::Log error "chighlight: $err" }
    }
}

proc HighlightLine {w lineno line in_comment} {
    variable keywords
    variable types
    variable number_re

    set len [string length $line]

    # Continue a block comment from the previous line.
    if {$in_comment} {
        set close [string first "*/" $line]

        if {$close >= 0} {
            set end [expr {$close + 2}]

            $w tag add c_comment "$lineno.0" "$lineno.$end"

            set i $end
            set in_comment 0
        } else {
            if {$len > 0} {
                $w tag add c_comment "$lineno.0" "$lineno.end"
            }

            return 1
        }
    } else {
        set i 0
    }

    # Preprocessor line.
    if {!$in_comment} {
        set trimmed [string trimleft $line]

        if {[string match "#*" $trimmed]} {
            set lead [expr {[string length $line] - [string length $trimmed]}]

            $w tag add c_preproc "$lineno.$lead" "$lineno.end"

            # Crude handling of a block comment opened by a preprocessor line.
            if {[string first "/*" $line $lead] >= 0 &&
                [string first "*/" $line $lead] < 0} {
                return 1
            }

            return 0
        }
    }

    while {$i < $len} {
        set ch [string index $line $i]

        set two ""

        if {$i + 1 < $len} {
            set two [string range $line $i [expr {$i + 1}]]
        }

        # Line comment.
        if {$two eq "//"} {
            $w tag add c_comment "$lineno.$i" "$lineno.end"
            return 0
        }

        # Block comment.
        if {$two eq "/*"} {
            set close [string first "*/" $line [expr {$i + 2}]]

            if {$close >= 0} {
                set end [expr {$close + 2}]

                $w tag add c_comment "$lineno.$i" "$lineno.$end"

                set i $end
                continue
            } else {
                $w tag add c_comment "$lineno.$i" "$lineno.end"
                return 1
            }
        }

        # String literal.
        if {$ch eq "\""} {
            set j [expr {$i + 1}]

            while {$j < $len} {
                set c [string index $line $j]

                if {$c eq "\\"} {
                    incr j 2
                    continue
                }

                if {$c eq "\""} {
                    incr j
                    break
                }

                incr j
            }

            if {$j > $len} {
                set j $len
            }

            if {$j > $i} {
                $w tag add c_string "$lineno.$i" "$lineno.$j"
            }

            set i $j
            continue
        }

        # Character literal.
        if {$ch eq "'"} {
            set j [expr {$i + 1}]

            while {$j < $len} {
                set c [string index $line $j]

                if {$c eq "\\"} {
                    incr j 2
                    continue
                }

                if {$c eq "'"} {
                    incr j
                    break
                }

                incr j
            }

            if {$j > $len} {
                set j $len
            }

            if {$j > $i} {
                $w tag add c_char "$lineno.$i" "$lineno.$j"
            }

            set i $j
            continue
        }

        # Identifier, keyword, type, or function call.
        if {[string match {[A-Za-z_]} $ch]} {
            set j [expr {$i + 1}]

            while {$j < $len && [string match {[A-Za-z0-9_]} [string index $line $j]]} {
                incr j
            }

            set word [string range $line $i [expr {$j - 1}]]

            set is_keyword [dict exists $keywords $word]
            set is_type    [dict exists $types $word]

            set k $j

            while {$k < $len && [regexp {^[ \t]$} [string index $line $k]]} {
                incr k
            }

            if {$is_keyword} {
                $w tag add c_keyword "$lineno.$i" "$lineno.$j"
            } elseif {$is_type} {
                $w tag add c_type "$lineno.$i" "$lineno.$j"
            } elseif {$k < $len && [string index $line $k] eq "("} {
                $w tag add c_func "$lineno.$i" "$lineno.$j"
            }

            set i $j
            continue
        }

        # Numeric literal.
        if {[string match {[0-9]} $ch] ||
            ($ch eq "." && $i + 1 < $len && [string match {[0-9]} [string index $line [expr {$i + 1}]]])} {
            set rest [string range $line $i end]

            set m [regexp -inline -- $number_re $rest]

            if {[llength $m] > 0} {
                set num [lindex $m 0]
                set j [expr {$i + [string length $num]}]

                $w tag add c_number "$lineno.$i" "$lineno.$j"

                set i $j
                continue
            }
        }

        incr i
    }

    return $in_comment
}

# ----------------------------------------------------------------------------
# Refresh scheduling
# ----------------------------------------------------------------------------

proc ScheduleRefresh {{delay 250}} {
    variable refresh_after

    if {$refresh_after ne ""} {
        catch { after cancel $refresh_after }
    }

    set ns [namespace current]

    set refresh_after [after $delay [list ${ns}::RefreshCurrent]]
}

proc RefreshCurrent {} {
    variable refresh_after ""

    set name $::Tclme::current_buffer

    if {$name eq ""} {
        return
    }

    HighlightBuffer $name
}

proc RefreshAll {} {
    variable enabled

    if {!$enabled} {
        return
    }

    catch {
        foreach name [dict keys $::Tclme::buffers] {
            if {[ShouldHighlightBuffer $name]} {
                HighlightBuffer $name
            }
        }
    }
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

proc cmd-toggle {args} {
    variable enabled

    set enabled [expr {!$enabled}]

    if {$enabled} {
        RefreshAll
        ::Tclme::Message "C highlighting enabled"
    } else {
        RemoveAllTags
        ::Tclme::Message "C highlighting disabled"
    }
}

proc cmd-refresh {args} {
    RefreshCurrent
}

# ----------------------------------------------------------------------------
# Event handlers
# ----------------------------------------------------------------------------

proc OnBufferSwitched {args} {
    ScheduleRefresh 50
}

proc OnAfterFileRead {args} {
    ScheduleRefresh 50
}

proc OnAfterSave {args} {
    ScheduleRefresh 50
}

proc OnCursorMoved {args} {
    variable enabled

    if {!$enabled} {
        return
    }

    set name $::Tclme::current_buffer

    if {$name eq ""} {
        return
    }

    if {[ShouldHighlightBuffer $name]} {
        ScheduleRefresh 300
    }
}

proc OnThemeChanged {args} {
    RefreshAll
}

# ----------------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------------

proc init {} {
    ::Tclme::DefCommand c-highlight cmd-toggle "Toggle C syntax highlighting"
    ::Tclme::DefCommand c-highlight-refresh cmd-refresh "Refresh C syntax highlighting"

    catch { ::Tclme::DefAlias ch c-highlight }

    ::Tclme::On buffer-switched [namespace current]::OnBufferSwitched
    ::Tclme::On after-file-read [namespace current]::OnAfterFileRead
    ::Tclme::On after-save      [namespace current]::OnAfterSave
    ::Tclme::On cursor-moved    [namespace current]::OnCursorMoved
    ::Tclme::On theme-changed   [namespace current]::OnThemeChanged

    # Highlight whatever is already open.
    ScheduleRefresh 50
}

proc cleanup {} {
    variable refresh_after

    if {$refresh_after ne ""} {
        catch { after cancel $refresh_after }
        set refresh_after ""
    }

    RemoveAllTags
}

proc state {} {
    variable enabled
    variable extensions

    return [dict create \
        enabled $enabled \
        extensions $extensions \
    ]
}

proc restore {saved} {
    variable enabled
    variable extensions

    if {[dict exists $saved enabled]} {
        set enabled [dict get $saved enabled]
    }

    if {[dict exists $saved extensions]} {
        set extensions [dict get $saved extensions]
    }
}