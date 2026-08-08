# plugins/openbsd-export.tcl
# ============================================================================
#  openbsd-export.tcl - export a cleaned Tclme tree for OpenBSD
#
#  Commands:
#    :openbsd-export
#    :openbsd-export /path/to/destination
#
#  Alias:
#    :obsd-export
#
#  Behavior:
#    - copies main Tclme script
#    - copies plugin files
#    - lowercases filenames
#    - converts CR/CRLF line endings to LF
#    - skips backup/temporary/hidden files
#    - copies binary or very large files unchanged
#    - writes into a new destination directory
#
#  Example:
#    :openbsd-export ~/tmp/tclme-openbsd
# ============================================================================

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

variable plugin_script ""

if {[info script] ne ""} {
    set plugin_script [file normalize [info script]]
}

# Files larger than this are copied unchanged instead of being text-processed.
variable max_text_size 5242880

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc Notify {msg} {
    if {[info commands ::Tclme::Message] ne ""} {
        catch { ::Tclme::Message $msg }
    } else {
        puts $msg
    }
}

proc PromptMaybe {label cb {completer ""}} {
    if {$completer eq ""} {
        catch { ::Tclme::Prompt $label $cb }
        return
    }

    if {[catch { ::Tclme::Prompt $label $cb $completer }]} {
        catch { ::Tclme::Prompt $label $cb }
    }
}

proc GuessMainFile {} {
    variable plugin_script

    # Preferred: Tclme knows its own script file.
    if {[info exists ::Tclme::scriptfile]} {
        set f $::Tclme::scriptfile

        if {$f ne "" && [file exists $f]} {
            return [file normalize $f]
        }
    }

    # Fallback: derive from this plugin's location.
    set appdir ""

    if {$plugin_script ne ""} {
        set appdir [file dirname [file dirname $plugin_script]]
    } elseif {[info exists ::Tclme::plugindir] && [file isdirectory $::Tclme::plugindir]} {
        set appdir [file dirname [file normalize $::Tclme::plugindir]]
    } else {
        set appdir [pwd]
    }

    set candidates {}

    catch {
        set candidates [glob -nocomplain -directory $appdir -types f *.tcl]
    }

    # Prefer a file named tclme.tcl, case-insensitively.
    foreach f $candidates {
        if {[string equal -nocase [file tail $f] "tclme.tcl"]} {
            return [file normalize $f]
        }
    }

    if {[llength $candidates] > 0} {
        return [file normalize [lindex [lsort $candidates] 0]]
    }

    # Last resort: a file literally named tclme without extension.
    catch {
        set candidates [glob -nocomplain -directory $appdir -types f tclme]
    }

    if {[llength $candidates] > 0} {
        return [file normalize [lindex $candidates 0]]
    }

    return ""
}

proc GuessPluginDir {} {
    variable plugin_script

    if {[info exists ::Tclme::plugindir] && [file isdirectory $::Tclme::plugindir]} {
        return [file normalize $::Tclme::plugindir]
    }

    if {$plugin_script ne ""} {
        return [file dirname $plugin_script]
    }

    return "plugins"
}

proc ShouldSkip {tail} {
    # Skip hidden files.
    if {[string index $tail 0] eq "."} {
        return 1
    }

    # Skip common backup/temp files.
    foreach pat {*~ *.bak *.orig *.old *.tmp *.swp *.swo} {
        if {[string match $pat $tail]} {
            return 1
        }
    }

    return 0
}

proc IsUnder {path dir} {
    set p [file split [file normalize $path]]
    set d [file split [file normalize $dir]]

    if {[llength $p] < [llength $d]} {
        return 0
    }

    set prefix [lrange $p 0 [expr {[llength $d] - 1}]]

    return [expr {$prefix eq $d}]
}

proc SetPermissions {path make_exec} {
    # Best effort. OpenBSD understands Unix permissions.
    #
    # 493 == 0755
    # 420 == 0644

    if {$make_exec} {
        catch { file attributes $path -permissions 493 }
    } else {
        catch { file attributes $path -permissions 420 }
    }
}

proc ConvertCopy {src dst make_exec} {
    variable max_text_size

    if {[catch { file size $src } size]} {
        set size 0
    }

    # Large files: do not load into memory; copy unchanged.
    if {$size > $max_text_size} {
        if {[catch {
            set in  [open $src rb]
            set out [open $dst wb]

            fcopy $in $out

            close $in
            close $out
        } err]} {
            return "skipped: $err"
        }

        SetPermissions $dst $make_exec

        return "copied unchanged (large)"
    }

    if {[catch { set fp [open $src rb] } err]} {
        return "skipped: $err"
    }

    if {[catch { set data [read $fp] } err]} {
        close $fp
        return "skipped: $err"
    }

    close $fp

    # Very simple binary detection.
    set binary 0

    if {[string first "\x00" $data] >= 0} {
        set binary 1
    }

    if {[catch { set out [open $dst wb] } err]} {
        return "skipped: $err"
    }

    if {$binary} {
        if {[catch {
            puts -nonewline $out $data
            close $out
        } err]} {
            return "skipped: $err"
        }

        SetPermissions $dst $make_exec

        return "copied unchanged (binary)"
    }

    # Normalize line endings for OpenBSD:
    #   CRLF -> LF
    #   lone CR -> LF
    if {[catch {
        regsub -all {\r\n} $data "\n" data
        regsub -all {\r}   $data "\n" data

        puts -nonewline $out $data
        close $out
    } err]} {
        return "skipped: $err"
    }

    SetPermissions $dst $make_exec

    return "cleaned line endings"
}

proc ShowReport {dest report} {
    set now [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]

    set text ""
    append text "Tclme OpenBSD export\n"
    append text "Destination: $dest\n"
    append text "Time: $now\n"
    append text "\n"
    append text [join $report "\n"]
    append text "\n"

    if {[info commands ::Tclme::ShowInBuffer] ne ""} {
        catch {
            ::Tclme::ShowInBuffer "*openbsd-export*" $text 1
        }
    }

    Notify "Exported [llength $report] entries to $dest"
}

# ----------------------------------------------------------------------------
# Export logic
# ----------------------------------------------------------------------------

proc RunExport {dest} {
    set dest [string trim $dest]

    if {$dest eq ""} {
        Notify "No destination directory given"
        return
    }

    if {[catch { set dest [file normalize $dest] } err]} {
        Notify "Bad destination: $err"
        return
    }

    set main [GuessMainFile]
    set pdir [GuessPluginDir]

    if {$main eq "" && ![file isdirectory $pdir]} {
        Notify "Cannot find main Tclme script or plugins directory"
        return
    }

    if {[file exists $dest] && ![file isdirectory $dest]} {
        Notify "Destination exists and is not a directory: $dest"
        return
    }

    set srcdir ""

    if {$main ne ""} {
        set srcdir [file dirname $main]
    }

    if {$srcdir ne "" && [string equal $dest $srcdir]} {
        Notify "Destination is the same as the source directory"
        return
    }

    if {[file isdirectory $pdir] && [string equal $dest [file normalize $pdir]]} {
        Notify "Destination is the same as the plugins directory"
        return
    }

    if {[catch { file mkdir $dest } err]} {
        Notify "Cannot create destination directory: $err"
        return
    }

    set out_plugins [file join $dest plugins]

    if {[catch { file mkdir $out_plugins } err]} {
        Notify "Cannot create plugins directory: $err"
        return
    }

    set report {}

    # Main script.
    if {$main ne ""} {
        set outname [string tolower [file tail $main]]

        if {$outname eq ""} {
            set outname "tclme.tcl"
        }

        set outpath [file join $dest $outname]

        set status [ConvertCopy $main $outpath 1]

        lappend report "main: [file tail $main] -> $outname : $status"
    } else {
        lappend report "main: not found"
    }

    # Plugin files.
    if {[file isdirectory $pdir]} {
        set files {}

        catch {
            set files [glob -nocomplain -directory $pdir -types f *]
        }

        set used [dict create]

        foreach f [lsort $files] {
            set tail [file tail $f]

            if {[ShouldSkip $tail]} {
                continue
            }

            # Avoid copying anything from a previous export if dest is inside source.
            if {[IsUnder $f $dest]} {
                continue
            }

            set outtail [string tolower $tail]

            # Handle source-name collisions after lowercasing.
            if {[dict exists $used $outtail]} {
                set ext  [file extension $outtail]
                set root [file rootname $outtail]

                set n 1

                while {[dict exists $used "$root-$n$ext"]} {
                    incr n
                }

                set outtail "$root-$n$ext"
            }

            dict set used $outtail 1

            set outpath [file join $out_plugins $outtail]

            set status [ConvertCopy $f $outpath 0]

            lappend report "plugin: $tail -> plugins/$outtail : $status"
        }
    } else {
        lappend report "plugins: directory not found"
    }

    ShowReport $dest $report
}

# ----------------------------------------------------------------------------
# Command handlers
# ----------------------------------------------------------------------------

proc cmd-export {args} {
    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        set ns [namespace current]

        set completer ""

        if {[info commands ::Tclme::CompleteFile] ne ""} {
            set completer ::Tclme::CompleteFile
        }

        PromptMaybe "Export to new directory: " ${ns}::RunExportFromPrompt $completer
    } else {
        RunExport $arg
    }
}

proc RunExportFromPrompt {dest} {
    RunExport $dest
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::DefCommand openbsd-export cmd-export \
    "Export cleaned Tclme files for OpenBSD (LF endings, lowercase filenames)"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias obsd-export openbsd-export }
}