#!/usr/bin/env tclsh
# tclme.tcl

namespace eval Tclme {
    variable headless 1
    variable listeners      [dict create]   ;# event -> list of {priority cb owner}
    variable commands       [dict create]   ;# name  -> dict(script doc owner keys)
    variable aliases        [dict create]   ;# alias -> command
    variable log            {}              ;# list of {time level msg}
    variable _owner         ""              ;# plugin currently being sourced

    variable scriptfile [file normalize [info script]]
    variable plugindir  [file join [file dirname $scriptfile] plugins]
    catch { file mkdir $plugindir }

    variable buffer_order    {}
    variable buffers         [dict create]  ;# name -> dict(path wid readonly)
    variable path_to_buffer  [dict create]
    variable buffer_seq      0
    variable current_buffer  ""
    variable active_widget   ""

    variable transcript         {}
    variable transcript_limit   5000
    variable output_sink        ""

    variable status_job  ""
    variable echo_input  1

    variable plugin_meta     [dict create]
    variable initfile
    variable ifilename
    set ifilename ".tclmerc"
    if {[info exists ::env(HOME)]} {
        set initfile [file join $::env(HOME) $ifilename]
    } elseif {[info exists ::env(USERPROFILE)]} {
        set initfile [file join $::env(USERPROFILE) $ifilename]
    } else {
        set initfile [file join [file dirname $scriptfile] $ifilename]
    }
}

#  Utilities

proc Tclme::NamespaceOwner {ns} {
    if {[regexp {^::Tclme::Plugin::([^:]+)} $ns -> owner]} {
        return $owner
    }
    return ""
}

proc Tclme::QualifyScript {script owner} {
    if {$owner eq "" || [llength $script] == 0} {
        return $script
    }

    set first [lindex $script 0]
    if {[string match ::* $first]} {
        return $script
    }

    set qual "::Tclme::Plugin::${owner}::$first"

    if {[info commands $qual] ne ""} {
        return [lreplace $script 0 0 $qual]
    }

    if {[info commands ::$first] ne ""} {
        return [lreplace $script 0 0 ::$first]
    }

    return [lreplace $script 0 0 $qual]
}

proc Tclme::Log {level msg} {
    variable log

    set stamp [clock format [clock seconds] -format {%H:%M:%S}]
    lappend log [list $stamp $level $msg]

    if {[llength $log] > 300} {
        set log [lrange $log end-299 end]
    }

    if {$level eq "error"} {
        catch { Tclme::Message "! $msg" }
    }
}

proc Tclme::Print {text {tag ""}} {
    variable transcript
    variable transcript_limit
    variable output_sink

    lappend transcript [list $tag $text]

    if {[llength $transcript] > $transcript_limit} {
        set transcript [lrange $transcript end-[expr {$transcript_limit - 1}] end]
    }

    if {$output_sink ne ""} {
        catch {
            uplevel #0 [list {*}$output_sink $text $tag]
        }
    } else {
        catch { puts stdout $text }
    }
}

proc Tclme::IsHeadless {} {
    variable headless
    return $headless
}

# Headless output defaults.

proc Tclme::Message {msg {tag message}} {
    Tclme::Print $msg $tag
}

proc Tclme::Note {msg} {
    Tclme::Print $msg note
}

proc Tclme::UpdateStatus {msg} {
}

proc Tclme::Prompt {label callback {completer ""}} {
    Tclme::Print "prompt not available in headless mode: $label" repl_error
}

proc Tclme::BindKey {name keys {tag TclmeText}} {
    variable commands

    if {$keys ne "" && [dict exists $commands $name]} {
        dict set commands $name keys $keys
    }
}

proc Tclme::WidgetForBuffer {name} {
    return ""
}

proc Tclme::GetBufferContent {name} {
    variable buffers

    if {[dict exists $buffers $name model text]} {
        return [dict get $buffers $name model text]
    }

    return ""
}

proc Tclme::SetBufferContent {name text} {
    variable buffers

    if {![dict exists $buffers $name]} {
        dict set buffers $name [dict create path "" wid "" readonly 0]
    }

    dict set buffers $name model text $text
}

proc Tclme::SwitchToBuffer {name} {
    variable buffers
    variable buffer_order
    variable current_buffer

    if {![dict exists $buffers $name]} {
        dict set buffers $name [dict create path "" wid "" readonly 0]
        lappend buffer_order $name
        Tclme::Emit buffer-created $name
    }

    set current_buffer $name

    Tclme::Emit buffer-switched $name
}

proc Tclme::ShowInBuffer {name content {readonly 0}} {
    Tclme::SwitchToBuffer $name
    Tclme::SetBufferContent $name $content
    Tclme::Print $name
    Tclme::Print $content
}

proc Tclme::RunExCommand {line} {
    set line [string trim $line]
    if {$line eq ""} {
        return
    }

    if {![regexp {^\s*(\S+)\s*(.*)$} $line -> name rest]} {
        return
    }

    Tclme::Invoke $name $rest
}

proc Tclme::EvalInput {code} {
    if {[string trim $code] eq ""} {
        return
    }
 
    if {[catch {uplevel #0 $code} result]} {
        Tclme::Message "Error: $result" repl_error
    } else {
        Tclme::Message "=> $result" repl_result
    }
}

proc Tclme::DispatchLine {line} {
    variable echo_input

    set line [string trim $line]

    if {$line eq ""} {
        return
    }

    if {$echo_input} {
        Tclme::Print "> $line" repl_input
    }

    if {[string index $line 0] eq ":"} {
        Tclme::RunExCommand [string range $line 1 end]
    } else {
        Tclme::EvalInput $line
    }
}

#  Event bus

proc Tclme::On {event cb {priority 50}} {
    variable listeners
    variable _owner
    variable plugin_meta

    set owner $_owner
    if {$owner eq ""} {
        set owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }

    if {[dict exists $listeners $event]} {
        foreach entry [dict get $listeners $event] {
            lassign $entry existing_priority existing_cb existing_owner

            if {$existing_cb eq $cb && $existing_owner eq $owner} {
                return
            }
        }
    }

    dict lappend listeners $event [list $priority $cb $owner]

    if {$owner ne "" && [dict exists $plugin_meta $owner]} {
        dict lappend plugin_meta $owner hooks [list $event $cb]
    }
}

proc Tclme::Off {event cb} {
    variable listeners

    if {![dict exists $listeners $event]} {
        return
    }

    set entries [dict get $listeners $event]
    set kept {}

    foreach e $entries {
        lassign $e priority stored_cb owner
        if {$stored_cb ne $cb} {
            lappend kept $e
        }
    }

    dict set listeners $event $kept
}

proc Tclme::ListenersSorted {event} {
    variable listeners

    if {![dict exists $listeners $event]} {
        return {}
    }

    return [lsort -integer -index 0 [dict get $listeners $event]]
}

# Fire-and-forget. Every listener runs; errors are logged.
proc Tclme::Emit {event args} {
    foreach entry [Tclme::ListenersSorted $event] {
        lassign $entry priority cb owner
        set script [Tclme::QualifyScript $cb $owner]

        if {[catch {uplevel #0 [list {*}$script {*}$args]} err]} {
            Tclme::Log error "hook '$event' ([lindex $script 0]): $err"
        }
    }
}

# First non-empty/non-continue result wins. Used for veto-style events.
proc Tclme::EmitCancelable {event args} {
    foreach entry [Tclme::ListenersSorted $event] {
        lassign $entry priority cb owner
        set script [Tclme::QualifyScript $cb $owner]

        if {[catch {uplevel #0 [list {*}$script {*}$args]} result]} {
            Tclme::Log error "hook '$event' ([lindex $script 0]): $result"
            continue
        }

        if {$result ne "" && $result ne "continue"} {
            return $result
        }
    }

    return ""
}

# All non-empty results joined. Used for status-line-style events.
proc Tclme::Collect {event args} {
    set out {}

    foreach entry [Tclme::ListenersSorted $event] {
        lassign $entry priority cb owner
        set script [Tclme::QualifyScript $cb $owner]

        if {[catch {uplevel #0 [list {*}$script {*}$args]} result]} {
            Tclme::Log error "hook '$event' ([lindex $script 0]): $result"
            continue
        }

        if {$result ne ""} {
            lappend out $result
        }
    }

    return [join $out "  "]
}

#  Command registry

proc Tclme::DefCommand {name script {doc ""}} {
    variable commands
    variable _owner
    variable plugin_meta

    set owner $_owner
    if {$owner eq ""} {
        set owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }

    dict set commands $name [dict create \
        script $script \
        doc $doc \
        owner $owner \
        keys "" \
    ]

    if {$owner ne "" && [dict exists $plugin_meta $owner]} {
        dict lappend plugin_meta $owner commands $name
    }
}

proc Tclme::DefAlias {short full} {
    variable aliases
    variable _owner
    variable plugin_meta

    set owner $_owner
    if {$owner eq ""} {
        set owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }

    dict set aliases $short $full

    if {$owner ne "" && [dict exists $plugin_meta $owner]} {
        dict lappend plugin_meta $owner aliases $short
    }
}

proc Tclme::DefCommandAndBind {name script keys {doc ""}} {
    variable _owner

    set old $_owner
    if {$_owner eq ""} {
        set _owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }

    Tclme::DefCommand $name $script $doc
    Tclme::BindKey $name $keys

    set _owner $old

    variable commands
    if {[dict exists $commands $name]} {
        dict set commands $name keys $keys
    }
}

proc Tclme::Invoke {name args} {
    variable commands
    variable aliases

    if {[dict exists $aliases $name]} {
        set name [dict get $aliases $name]
    }

    Tclme::Emit before-command $name {*}$args

    if {[dict exists $commands $name]} {
        set entry [dict get $commands $name]
        set script [Tclme::QualifyScript [dict get $entry script] [dict get $entry owner]]

        if {[catch {uplevel #0 [list {*}$script {*}$args]} err]} {
            Tclme::Log error "command '$name': $err"
        }
    } else {
        Tclme::Message "Undefined command: $name" repl_error
    }

    Tclme::Emit after-command $name
}

#  Plugins

proc Tclme::After {ms script} {
    variable _owner
    variable plugin_meta

    set owner $_owner
    if {$owner eq ""} {
        set owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }

    set script [Tclme::QualifyScript $script $owner]
    set id [after $ms [list Tclme::RunAfter $script]]

    if {$owner ne "" && [dict exists $plugin_meta $owner]} {
        dict lappend plugin_meta $owner afters $id
    }

    return $id
}

proc Tclme::RunAfter {script} {
    if {[catch {uplevel #0 [list {*}$script]} err]} {
        Tclme::Log error "after: $err"
    }

}

proc Tclme::LoadUserInit {} {
    variable initfile

    if {[file exists $initfile]} {
        if {[catch { uplevel #0 [list source $initfile] } err]} {
            Tclme::Log error "init file: $err"
        }
    }
}

proc Tclme::ReloadUserInit {} {
    variable initfile
    Tclme::LoadUserInit
    Tclme::Message "Reloaded [file tail $initfile]"
}

proc Tclme::LoadPlugin {name file {saved ""}} {
    variable plugin_meta
    variable _owner

    if {[dict exists $plugin_meta $name]} {
        Tclme::UnloadPlugin $name
    }

    if {![file exists $file]} {
        Tclme::Log error "plugin '$name': missing file $file"
        return 0
    }

    set ns [Tclme::PluginNamespace $name]

    # Create fresh plugin metadata.
    dict set plugin_meta $name [dict create \
        file     $file     \
        commands {}        \
        aliases  {}        \
        binds    {}        \
        hooks    {}        \
        afters   {}        \
    ]

    # Create a fresh namespace.
    catch { namespace delete $ns }
    namespace eval $ns {}

    # Source the plugin file.
    set _owner $name
    set rc [catch {
        namespace eval $ns [list source $file]
    } err]
    set _owner ""

    if {$rc} {
        Tclme::Log error "loading plugin '$name': $err"
        catch { Tclme::UnloadPlugin $name }
        return 0
    }

    # Decide whether this plugin uses the new lifecycle.
    set has_init [expr {[info commands ${ns}::init] ne ""}]

    if {$has_init} {
        # New lifecycle:
        #
        #   restore before init
        #
        # This allows init to inspect restored state.

        if {$saved ne ""} {
            if {[catch {
                Tclme::PluginCallFirst $ns [list restore restore-state] $saved
            } err]} {
                Tclme::Log error "plugin '$name' restore failed: $err"
            }
        }

        set _owner $name
        set rc [catch {
            Tclme::PluginCallFirst $ns [list init]
        } err]
        set _owner ""

        if {$rc} {
            Tclme::Log error "plugin '$name' init failed: $err"
            catch { Tclme::UnloadPlugin $name }
            return 0
        }
    } else {
        # Legacy lifecycle:
        #
        #   load first
        #   restore-state after load
        #
        # This preserves the behavior older plugins may depend on.

        set _owner $name
        set rc [catch {
            Tclme::PluginCallFirst $ns [list load]
        } err]
        set _owner ""

        if {$rc} {
            Tclme::Log error "plugin '$name' load failed: $err"
            catch { Tclme::UnloadPlugin $name }
            return 0
        }

        if {$saved ne ""} {
            if {[catch {
                Tclme::PluginCallFirst $ns [list restore-state restore] $saved
            } err]} {
                Tclme::Log error "plugin '$name' restore-state failed: $err"
            }
        }
    }

    Tclme::Emit plugin-loaded $name

    return 1
}

proc Tclme::UnloadPlugin {name} {
    variable plugin_meta
    variable commands
    variable aliases

    if {![dict exists $plugin_meta $name]} {
        return
    }

    set ns [Tclme::PluginNamespace $name]

    if {[catch {
        Tclme::PluginCallFirst $ns [list cleanup unload]
    } err]} {
        Tclme::Log error "plugin '$name' cleanup failed: $err"
    }

    set meta [dict get $plugin_meta $name]
    # Remove commands, but only if this plugin still owns them.
    foreach cmd [dict get $meta commands] {
       if {[dict exists $commands $cmd]} {
          set entry [dict get $commands $cmd]

          if {[dict exists $entry owner] && [dict get $entry owner] eq $name} {
              catch { dict unset commands $cmd }
          }
       }
    }

    # Remove aliases, but only if they still point to commands owned by this plugin.
    foreach alias [dict get $meta aliases] {
        if {[dict exists $aliases $alias]} {
            set target [dict get $aliases $alias]

            if {[dict exists $commands $target]} {
                set entry [dict get $commands $target]

                if {[dict exists $entry owner] && [dict get $entry owner] eq $name} {
                    catch { dict unset aliases $alias }
                }
            } else {
                catch { dict unset aliases $alias }
            }
        }
    }

    # Remove bindings.
    foreach entry [dict get $meta binds] {
        lassign $entry tag keys

        catch { bind $tag $keys {} }
    }

    # Remove event hooks.
    foreach entry [dict get $meta hooks] {
        lassign $entry event cb

        catch { Tclme::Off $event $cb }
    }

    # Cancel tracked after callbacks.
    if {[dict exists $meta afters]} {
        foreach id [dict get $meta afters] {
            catch { after cancel $id }
        }
    }

    # Delete the plugin namespace.
    catch { namespace delete $ns }

    # Remove metadata.
    dict unset plugin_meta $name

    Tclme::Emit plugin-unloaded $name
}

# Plugin lifecycle helpers

proc Tclme::PluginNamespace {name} {
    return "::Tclme::Plugin::$name"
}

proc Tclme::PluginCallFirst {ns proclist args} {
    foreach procname $proclist {
        set cmd ${ns}::$procname

        if {[info commands $cmd] ne ""} {
            return [uplevel #0 [list $cmd {*}$args]]
        }
    }

    return {}
}

# Save plugin state using the new `state` hook if present,
# otherwise the old `save-state` hook.

proc Tclme::PluginSaveState {name} {
    set ns [Tclme::PluginNamespace $name]
    set saved ""

    catch {
        set saved [Tclme::PluginCallFirst $ns [list state save-state]]
    }

    return $saved
}

proc Tclme::ReloadPlugin {name {quiet 0}} {
    variable plugin_meta

    if {![dict exists $plugin_meta $name]} {
        Tclme::Message "Not loaded: $name"
        return
    }

    set file [dict get [dict get $plugin_meta $name] file]
    set saved [Tclme::PluginSaveState $name]

    Tclme::UnloadPlugin $name
    Tclme::LoadPlugin $name $file $saved

    if {!$quiet} {
        Tclme::Message "Reloaded plugin: $name"
    }
}

proc Tclme::PluginAfter {ms script} {
    variable _owner
    variable plugin_meta

    set owner $_owner

    if {$owner eq ""} {
        set owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }

    set script [Tclme::QualifyScript $script $owner]

    set id [after $ms [list Tclme::RunAfter $script]]

    if {$owner ne "" && [dict exists $plugin_meta $owner]} {
        dict lappend plugin_meta $owner afters $id
    }

    return $id
}

proc Tclme::ReloadPlugins {{name ""}} {
    variable plugindir
    variable plugin_meta

    set name [string trim $name]

    if {$name ne ""} {
        Tclme::ReloadPlugin $name
        return
    }

    set files [lsort [glob -nocomplain -directory $plugindir *.tcl]]
    set names {}

    foreach f $files {
        lappend names [file rootname [file tail $f]]
    }

    foreach old [dict keys $plugin_meta] {
        if {[lsearch -exact $names $old] < 0} {
            Tclme::UnloadPlugin $old
        }
    }

    foreach f $files {
        set nm [file rootname [file tail $f]]

        if {[dict exists $plugin_meta $nm]} {
            Tclme::ReloadPlugin $nm 1
        } else {
            Tclme::LoadPlugin $nm $f
        }
    }

    Tclme::Message "Plugins reloaded."
}

proc Tclme::LoadAllPlugins {} {
    variable plugindir

    foreach f [lsort [glob -nocomplain -directory $plugindir *.tcl]] {
        Tclme::LoadPlugin [file rootname [file tail $f]] $f
    }
}


proc Tclme::LoadPluginByName {name} {
    variable plugindir

    set file [file join $plugindir "$name.tcl"]

    if {![file exists $file]} {
        Tclme::Message "No such plugin file: $file"
        return
    }

    Tclme::LoadPlugin $name $file
}


proc Tclme::CmdEvalKernel {args} {
    set code [string trim [join $args " "]]

    if {$code eq ""} {
        Tclme::Message "Usage: :eval CODE"
        return
    }

    Tclme::EvalInput $code
}
 
proc Tclme::CmdLogKernel {args} {
    variable log
 
    if {[llength $log] == 0} {
        Tclme::Message "Log empty."
        return
    }
 
    foreach entry $log {
        lassign $entry stamp level msg
        Tclme::Print "$stamp \[$level\] $msg" log
    }
}

proc Tclme::CmdHelpKernel {args} {
    variable commands
    variable aliases

    Tclme::Print "Tclme commands"

    foreach name [lsort [dict keys $commands]] {
        set entry [dict get $commands $name]
        set doc   [dict get $entry doc]
        set keys  [dict get $entry keys]

        if {$keys eq ""} {
            set keys "-"
        }

        Tclme::Print [format "%-16s %-24s %s" $name $keys $doc]
    }

    Tclme::Print ""
    Tclme::Print "Aliases:"

    foreach a [lsort [dict keys $aliases]] {
        Tclme::Print [format "  %-8s -> %s" $a [dict get $aliases $a]]
    }
}

proc Tclme::CmdReloadkPlugins {args} {
    set arg [string trim [join $args " "]]
    Tclme::ReloadPlugins $arg
}

proc Tclme::CmdLoadPlugin {args} {
    set name [string trim [join $args " "]]

    if {$name eq ""} {
        Tclme::Message "Usage: :load NAME"
        return
    }
    
    Tclme::LoadPluginByName $name
    Tclme::Print "Loaded plugin: $name"
}

proc Tclme::CmdUnloadPlugin {args} {
    set name [string trim [join $args " "]]

    if {$name eq ""} {
        Tclme::Message "Usage: :unload NAME"
        return
    }

    Tclme::UnloadPlugin $name
    Tclme::Print "Unloaded plugin: $name"
}

proc Tclme::CmdListPlugins {args} {
    variable plugin_meta

    if {[dict size $plugin_meta] == 0} {
        Tclme::Print "No plugins loaded."
        return
    }

    Tclme::Print "Loaded plugins:"

    foreach name [lsort [dict keys $plugin_meta]] {
        set file [dict get [dict get $plugin_meta $name] file]
        Tclme::Print "  $name  ($file)"
    }
}

proc Tclme::InitKernel {} {
    Tclme::DefCommand eval        Tclme::CmdEvalKernel        "Evaluate Tcl code"
    Tclme::DefCommand help        Tclme::CmdHelpKernel        "Show available commands"
    Tclme::DefCommand log         Tclme::CmdLogKernel         "Show the diagnostic log"
    Tclme::DefCommand reload          "Reload plugins"
    Tclme::DefCommand unload      Tclme::CmdUnloadPlugin        "Unload a plugin by name"
    Tclme::DefCommand load        Tclme::CmdLoadPlugin        "Load a plugin by name"
    Tclme::DefCommand plugins     Tclme::CmdListPlugins           "List loaded plugins"

    Tclme::DefAlias e eval
    Tclme::DefAlias l load
    Tclme::DefAlias u unload
    Tclme::DefAlias r reload
    Tclme::DefAlias h help
}
