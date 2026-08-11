# plugins/persist.tcl

Tclme::Plugin {
    description "Persist open file buffers, log, and REPL transcript"
    version 0.1.0

    state {
        save_on_quit 1
        restore_on_startup 1
        save_log 1
        save_repl 1
        restore_log 1
        restore_repl 1
        last_saved ""
    }

    command session-save {args} {
        if {[catch { save_session } err]} {
            ::Tclme::Log error "persist save: $err"
            ::Tclme::Message "Session save failed: $err"
            return
        }

        ::Tclme::Message "Session saved"
    } "Save open file buffers, log, and REPL"

    command session-restore {args} {
        if {[catch { restore_session } err]} {
            ::Tclme::Log error "persist restore: $err"
            ::Tclme::Message "Session restore failed: $err"
            return
        }

        ::Tclme::Message "Session restored"
    } "Restore saved session"

    command clear-log {args} {
        clear_log
    } "Clear the diagnostic log"

    command clear-repl {args} {
        clear_repl
    } "Clear the REPL transcript"

    command clear-saved-session {args} {
        clear_saved_session
    } "Delete saved session files"



    init {
        variable state

        foreach {k v} {
            save_on_quit 1
            restore_on_startup 1
            save_log 1
            save_repl 1
            restore_log 1
            restore_repl 1
            last_saved ""
        } {
            if {![dict exists $state $k]} {
                dict set state $k $v
            }
        }

        set ns [namespace current]

        # Avoid duplicates if init is run again.
        catch { ::Tclme::Off editor-started ${ns}::handle_editor_started }
        catch { ::Tclme::Off editor-quit ${ns}::handle_editor_quit }

        # Register explicit named hooks.
        ::Tclme::On editor-started ${ns}::handle_editor_started
        ::Tclme::On editor-quit ${ns}::handle_editor_quit

        # If the GUI already exists, make the close button trigger Tclme::Quit.
        if {![::Tclme::IsHeadless] && [winfo exists .]} {
            catch { wm protocol . WM_DELETE_WINDOW ::Tclme::Quit }
        }
    }

    cleanup {
        set ns [namespace current]

        catch { ::Tclme::Off editor-started ${ns}::handle_editor_started }
        catch { ::Tclme::Off editor-quit ${ns}::handle_editor_quit }
    }

    do {
        proc handle_editor_started {} {
            variable state

            # Make sure the window-close button uses Tclme's quit path.
            if {![::Tclme::IsHeadless] && [winfo exists .]} {
                catch { wm protocol . WM_DELETE_WINDOW ::Tclme::Quit }
            }

            if {[dict get $state restore_on_startup]} {
                catch { restore_session }
            }
        }

        proc handle_editor_quit {} {
            variable state

            if {[dict get $state save_on_quit]} {
                catch { save_session }
            }
        }
        proc session_dir {} {
            set base ""

            if {[info exists ::env(HOME)]} {
                set base $::env(HOME)
            } elseif {[info exists ::env(USERPROFILE)]} {
                set base $::env(USERPROFILE)
            } else {
                set base [pwd]
            }

            set dir [file join $base .tclme]

            catch { file mkdir $dir }

            return $dir
        }

        proc session_file {} {
            return [file join [session_dir] session.tcl]
        }

        proc log_file {} {
            return [file join [session_dir] log.tcl]
        }

        proc repl_file {} {
            return [file join [session_dir] repl.tcl]
        }

        proc write_data_file {file cmd} {
            set fp [open $file w]
            fconfigure $fp -encoding utf-8

            puts $fp "# Saved by Tclme persistence plugin"
            puts $fp $cmd

            close $fp
        }

        proc save_session {} {
            variable state

            set paths {}
            set current_path ""

            # ------------------------------------------------------------
            # Collect open file buffers.
            # ------------------------------------------------------------

            if {[info exists ::Tclme::buffer_order] && [info exists ::Tclme::buffers]} {
                foreach name $::Tclme::buffer_order {
                    if {![dict exists $::Tclme::buffers $name]} {
                        continue
                    }

                    set info [dict get $::Tclme::buffers $name]
                    set path ""

                    if {[dict exists $info path]} {
                        set path [dict get $info path]
                    }

                    if {$path eq ""} {
                        continue
                    }

                    set norm [file normalize $path]

                    if {[file isfile $norm]} {
                        lappend paths $norm
                    }
                }
            }

            # ------------------------------------------------------------
            # Current buffer.
            # ------------------------------------------------------------

            if {
                [info exists ::Tclme::current_buffer] &&
                $::Tclme::current_buffer ne "" &&
                [dict exists $::Tclme::buffers $::Tclme::current_buffer]
            } {
                set info [dict get $::Tclme::buffers $::Tclme::current_buffer]

                if {[dict exists $info path]} {
                    set p [file normalize [dict get $info path]]

                    if {$p ne "" && [file isfile $p]} {
                        set current_path $p
                    }
                }
            }

            set session [dict create \
                version 1 \
                saved_at [clock seconds] \
                current $current_path \
                buffers $paths \
            ]

            write_data_file [session_file] [list set ::TclmePersistSession $session]

            # ------------------------------------------------------------
            # Log and REPL.
            # ------------------------------------------------------------

            save_log
            save_repl

            dict set state last_saved [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]
        }

        proc save_log {} {
            variable state

            if {![dict get $state save_log]} {
                return
            }

            set log {}

            if {[info exists ::Tclme::log]} {
                set log $::Tclme::log
            }

            if {[llength $log] > 300} {
                set log [lrange $log end-299 end]
            }

            write_data_file [log_file] [list set ::Tclme::log $log]
        }

        proc save_repl {} {
            variable state

            if {![dict get $state save_repl]} {
                return
            }

            set transcript {}

            if {[info exists ::Tclme::transcript]} {
                set transcript $::Tclme::transcript
            }

            set limit 5000

            if {[info exists ::Tclme::transcript_limit]} {
                set limit $::Tclme::transcript_limit
            }

            if {$limit > 0 && [llength $transcript] > $limit} {
                set transcript [lrange $transcript end-[expr {$limit - 1}] end]
            }

            write_data_file [repl_file] [list set ::Tclme::transcript $transcript]
        }

        proc restore_session {} {
            variable state

            restore_log
            restore_repl

            set file [session_file]

            if {![file exists $file]} {
                return
            }

            catch { unset ::TclmePersistSession }

            if {[catch { source $file } err]} {
                ::Tclme::Log error "persist: cannot source session file: $err"
                return
            }

            if {![info exists ::TclmePersistSession]} {
                return
            }

            set session $::TclmePersistSession

            set paths {}
            if {[dict exists $session buffers]} {
                set paths [dict get $session buffers]
            }

            # ------------------------------------------------------------
            # Restore file buffers in saved order.
            # ------------------------------------------------------------

            if {![::Tclme::IsHeadless]} {
                foreach path $paths {
                    if {[file isfile $path]} {
                        catch { ::Tclme::OpenFile $path }
                    }
                }
            }

            # ------------------------------------------------------------
            # Restore current buffer.
            # ------------------------------------------------------------

            set current ""
            if {[dict exists $session current]} {
                set current [dict get $session current]
            }

            if {$current ne "" && ![::Tclme::IsHeadless]} {
                set norm [file normalize $current]
                set buf [::Tclme::FindBufferForPath $norm]

                if {$buf ne ""} {
                    catch { ::Tclme::SwitchToBuffer $buf }
                }
            }

            catch { unset ::TclmePersistSession }
        }

        proc restore_log {} {
            variable state

            if {![dict get $state restore_log]} {
                return
            }

            set file [log_file]

            if {[file exists $file]} {
                if {[catch { source $file } err]} {
                    ::Tclme::Log error "persist: cannot source log file: $err"
                }
            }

            if {[info exists ::Tclme::log] && [llength $::Tclme::log] > 300} {
                set ::Tclme::log [lrange $::Tclme::log end-299 end]
            }

            refresh_log_buffer
        }

        proc restore_repl {} {
            variable state

            if {![dict get $state restore_repl]} {
                return
            }

            set file [repl_file]

            if {[file exists $file]} {
                if {[catch { source $file } err]} {
                    ::Tclme::Log error "persist: cannot source REPL file: $err"
                }
            }

            if {![info exists ::Tclme::transcript]} {
                set ::Tclme::transcript {}
            }

            set limit 5000

            if {[info exists ::Tclme::transcript_limit]} {
                set limit $::Tclme::transcript_limit
            }

            if {$limit > 0 && [llength $::Tclme::transcript] > $limit} {
                set ::Tclme::transcript [lrange $::Tclme::transcript end-[expr {$limit - 1}] end]
            }

            refresh_repl_buffer
        }

        proc refresh_log_buffer {} {
            set w [::Tclme::WidgetForBuffer "*Log*"]

            if {$w eq ""} {
                return
            }

            set old [$w cget -state]

            catch { $w configure -state normal }

            $w delete 1.0 end

            if {[llength $::Tclme::log] == 0} {
                $w insert end "Log empty.\n"
            } else {
                foreach entry $::Tclme::log {
                    lassign $entry stamp level msg
                    $w insert end "$stamp \[$level\] $msg\n"
                }
            }

            catch { $w edit modified 0 }
            catch { $w see end }
            catch { $w configure -state $old }
        }

        proc refresh_repl_buffer {} {
            set w [::Tclme::WidgetForBuffer "*repl*"]

            if {$w eq ""} {
                return
            }

            set old [$w cget -state]

            catch { $w configure -state normal }

            $w delete 1.0 end

            foreach entry $::Tclme::transcript {
                lassign $entry tag text

                if {$tag eq ""} {
                    $w insert end "$text\n"
                } else {
                    $w insert end "$text\n" [list $tag]
                }
            }

            catch { $w edit modified 0 }
            catch { $w see end }
            catch { $w configure -state $old }
        }

        proc clear_log {} {
            set ::Tclme::log {}

            refresh_log_buffer

            # Also clear the saved log file so the cleared state survives restart.
            catch {
                write_data_file [log_file] [list set ::Tclme::log {}]
            }

            ::Tclme::Message "Log cleared"
        }

        proc clear_repl {} {
            set ::Tclme::transcript {}

            refresh_repl_buffer

            # Also clear the saved REPL file so the cleared state survives restart.
            catch {
                write_data_file [repl_file] [list set ::Tclme::transcript {}]
            }

            ::Tclme::Message "REPL cleared"
        }

        proc clear_saved_session {} {
            foreach f [list [session_file] [log_file] [repl_file]] {
                catch { file delete $f }
            }

            ::Tclme::Message "Saved session deleted"
        }
    }

    do {
        catch { ::Tclme::DefAlias ss session-save }
        catch { ::Tclme::DefAlias sr session-restore }
        catch { ::Tclme::DefAlias cl clear-log }
        catch { ::Tclme::DefAlias cr clear-repl }
        catch { ::Tclme::DefAlias css clear-saved-session }
    }
}