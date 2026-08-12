# plugins/obsd.tcl
# ============================================================================
#  obsd.tcl – export project files for OpenBSD
#
#  Exports:
#    1. All .tcl files from the current working directory
#    2. All top-level files from the Tclme plugins directory
#
#  Asks for a destination folder unless one is given as an argument.
#
#  Commands:
#    :openbsd-export
#    :obsd-export
#    :obsd
#
#  Examples:
#    :openbsd-export
#    :openbsd-export /tmp/obsd-export
#    :obsd-export ~/openbsd/tclme
# ============================================================================

namespace eval ::Tclme::OpenBSDExport {
    variable max_text_size 5242880
    variable default_dest ""
}

# ── Helpers ──────────────────────────────────────────────────────────────

proc ::Tclme::OpenBSDExport::Notify {msg} {
    if {[info commands ::Tclme::Message] ne ""} {
        catch { ::Tclme::Message $msg }
    } else {
        puts $msg
    }
}

proc ::Tclme::OpenBSDExport::DefaultDestination {} {
    if {[info exists ::Tclme::scriptfile] && $::Tclme::scriptfile ne ""} {
        return [file normalize [file join [file dirname $::Tclme::scriptfile] obsd]]
    }

    return [file normalize [file join [pwd] obsd]]
}

proc ::Tclme::OpenBSDExport::ShouldSkip {tail} {
    if {[string index $tail 0] eq "."} {
        return 1
    }

    foreach pat {*~ *.bak *.orig *.old *.tmp *.swp *.swo} {
        if {[string match $pat $tail]} {
            return 1
        }
    }

    return 0
}

proc ::Tclme::OpenBSDExport::IsUnderDir {path dir} {
    set path [file normalize $path]
    set dir [file normalize $dir]

    if {$path eq $dir} {
        return 1
    }

    set dlen [string length $dir]

    if {[string length $path] > $dlen && [string equal -length $dlen $dir $path]} {
        set next [string index $path $dlen]

        if {$next eq "/" || $next eq "\\"} {
            return 1
        }
    }

    return 0
}

proc ::Tclme::OpenBSDExport::CompleteDir {txt} {
    if {$txt eq ""} {
        set dir [pwd]
        set base ""
    } elseif {[file isdirectory $txt]} {
        set dir $txt
        set base ""
    } else {
        set dir [file dirname $txt]
        set base [file tail $txt]
    }

    set out {}
    set plen [string length $base]

    foreach m [lsort [glob -nocomplain -directory $dir -- *]] {
        if {![file isdirectory $m]} {
            continue
        }

        set tail [file tail $m]

        if {$base eq "" || [string equal -length $plen $base $tail]} {
            lappend out [file join $m ""]
        }
    }

    return $out
}

proc ::Tclme::OpenBSDExport::ConvertCopy {src dst make_exec} {
    variable max_text_size

    if {[file normalize $src] eq [file normalize $dst]} {
        return "unchanged (same file)"
    }

    if {[catch { file size $src } size]} {
        set size 0
    }

    if {$size > $max_text_size} {
        if {[catch { file copy -force $src $dst }]} {
            return "skipped"
        }

        catch {
            file attributes $dst -permissions [expr {$make_exec ? 0755 : 0644}]
        }

        return "copied unchanged (large)"
    }

    if {[catch { set fp [open $src rb] }]} {
        return "skipped"
    }

    set data [read $fp]
    close $fp

    if {[string first "\x00" $data] >= 0} {
        if {[catch { file copy -force $src $dst }]} {
            return "skipped"
        }

        catch {
            file attributes $dst -permissions [expr {$make_exec ? 0755 : 0644}]
        }

        return "copied unchanged (binary)"
    }

    regsub -all {\r\n} $data "\n" data
    regsub -all {\r}   $data "\n" data

    if {[catch { set out [open $dst wb] }]} {
        return "skipped"
    }

    puts -nonewline $out $data
    close $out

    catch {
        file attributes $dst -permissions [expr {$make_exec ? 0755 : 0644}]
    }

    return "cleaned"
}

proc ::Tclme::OpenBSDExport::UniqueTail {tail usedvar} {
    upvar 1 $usedvar used

    set outtail [string tolower $tail]

    if {![dict exists $used $outtail]} {
        return $outtail
    }

    set ext [file extension $outtail]
    set root [file rootname $outtail]

    set n 1

    while {[dict exists $used "$root-$n$ext"]} {
        incr n
    }

    return "$root-$n$ext"
}

proc ::Tclme::OpenBSDExport::ExportFile {
    f srcdir label destdir donevar usedvar reportvar
} {
    upvar 1 $donevar done
    upvar 1 $usedvar used
    upvar 1 $reportvar report

    if {![file isfile $f]} {
        return
    }

    set norm [file normalize $f]

    if {[dict exists $done $norm]} {
        return
    }

    set tail [file tail $f]

    if {[ShouldSkip $tail]} {
        return
    }

    if {[IsUnderDir $norm $destdir]} {
        return
    }

    dict set done $norm 1

    set outtail [UniqueTail $tail used]
    dict set used $outtail 1

    set outpath [file join $destdir $outtail]

    if {[file normalize $outpath] eq $norm} {
        lappend report "$tail -> $outtail : skipped (same file)"
        return
    }

    set status [ConvertCopy $f $outpath 0]

    if {$label eq ""} {
        set srclabel $tail
    } else {
        set srclabel "$label/$tail"
    }

    lappend report "$srclabel -> $outtail : $status"
}

# ── Core export logic ────────────────────────────────────────────────────

proc ::Tclme::OpenBSDExport::RunExport {destdir} {
    set destdir [string trim $destdir]

    if {$destdir eq ""} {
        set destdir [DefaultDestination]
    }

    set destdir [file normalize $destdir]

    if {[file exists $destdir] && ![file isdirectory $destdir]} {
        Notify "Destination is not a directory: $destdir"
        return
    }

    if {![file isdirectory $destdir]} {
        if {[catch { file mkdir $destdir } err]} {
            Notify "Cannot create destination directory: $err"
            return
        }
    }

    set srcdir [pwd]

    set plugindir ""
    if {[info exists ::Tclme::plugindir]} {
        set plugindir $::Tclme::plugindir
    }

    set report {}
    set used [dict create]
    set done [dict create]

    # ------------------------------------------------------------------
    # 1. Export .tcl files from current directory
    # ------------------------------------------------------------------

    set current_files {}
    catch {
        set current_files [glob -nocomplain -directory $srcdir *.tcl]
    }

    foreach f [lsort $current_files] {
        ExportFile $f $srcdir "" $destdir done used report
    }

    # ------------------------------------------------------------------
    # 2. Export top-level files from plugins directory
    # ------------------------------------------------------------------

    if {$plugindir ne "" && [file isdirectory $plugindir]} {
        set plugin_files {}

        catch {
            set plugin_files [glob -nocomplain -directory $plugindir -- *]
        }

        foreach f [lsort $plugin_files] {
            ExportFile $f $plugindir "plugins" $destdir done used report
        }
    }

    if {[llength $report] == 0} {
        Notify "No files exported"
        return
    }

    set summary [join [list \
        "OpenBSD export" \
        "" \
        "Destination: $destdir" \
        "Current directory: $srcdir" \
        "Plugins directory: $plugindir" \
        "" \
        "Exported [llength $report] files" \
        "" \
        [join $report \n] \
    ] \n]

    if {[info commands ::Tclme::ShowInBuffer] ne ""} {
        catch {
            ::Tclme::ShowInBuffer "*openbsd-export*" $summary 1
        }
    }

    Notify "Exported [llength $report] files to [file tail $destdir]"
}

# ── Prompt callback ─────────────────────────────────────────────────────

proc ::Tclme::OpenBSDExport::ExportPromptCallback {input} {
    variable default_dest

    set dest [string trim $input]

    if {$dest eq ""} {
        set dest $default_dest
    }

    RunExport $dest
}

# ── Command handler ─────────────────────────────────────────────────────

proc ::Tclme::OpenBSDExport::cmd-export {args} {
    set arg [string trim [join $args " "]]

    if {$arg ne ""} {
        RunExport $arg
        return
    }

    if {[info commands ::Tclme::IsHeadless] ne "" && [::Tclme::IsHeadless]} {
        Notify "Usage: :openbsd-export DESTINATION"
        return
    }

    variable default_dest
    set default_dest [DefaultDestination]

    if {[catch {
        ::Tclme::Prompt \
            "Export to folder: " \
            ::Tclme::OpenBSDExport::ExportPromptCallback \
            ::Tclme::OpenBSDExport::CompleteDir
    } err]} {
        Notify "Prompt failed: $err"
        return
    }

    # Prefill the minibuffer with the default destination.
    catch {
        if {[winfo exists .minibar.entry]} {
            .minibar.entry delete 0 end
            .minibar.entry insert 0 $default_dest
            .minibar.entry selection range 0 end
            .minibar.entry icursor end
        }
    }
}

# ── Registration ─────────────────────────────────────────────────────────

if {[info commands ::Tclme::DefCommand] ne ""} {
    ::Tclme::DefCommand openbsd-export \
        ::Tclme::OpenBSDExport::cmd-export \
        "Export current .tcl files and plugin files to an OpenBSD-clean directory"

    catch { ::Tclme::DefAlias obsd-export openbsd-export }
    catch { ::Tclme::DefAlias obsd openbsd-export }
}
