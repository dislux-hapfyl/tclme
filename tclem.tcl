# tclem.tcl
# ============================================================================
# Tclme Plugin DSL v1
#
# A tiny declarative layer for writing Tclme plugins.
#
# Source this after ktclme.tcl and before loading plugins:
#
#   source tclme.tcl
#   source tclem.tcl
#
# Example plugin:
#
#   Tclme::Plugin hello {
#       description "Example plugin"
#       version 0.1.0
#
#       state {
#           enabled 1
#           count 0
#       }
#
#       command hello {args} {
#           variable state
#           dict incr state count
#           Tclme::Message "Hello, count: [dict get $state count]"
#       }
#
#       bind <Control-x><Control-h> hello
#
#       on after-save {path} {
#           Tclme::Print "saved: $path"
#       }
#
#       init {
#           # Called after state has been restored.
#       }
#
#       cleanup {
#           # Destroy widgets, cancel timers, close sockets.
#       }
#   }
#
# The DSL is deliberately small.
# Raw Tcl is always available through the `do` directive.
# ============================================================================

namespace eval ::Tclme::DSL {
    variable version 1
    variable seq 0
    variable pending [dict create]
}

# ----------------------------------------------------------------------------
# Helper: sanitize names for generated proc names
# ----------------------------------------------------------------------------

if {[info commands ::Tclme::SanitizeName] eq ""} {
    proc ::Tclme::SanitizeName {s} {
        regsub -all {[^A-Za-z0-9_]} $s _ s
        return $s
    }
}

# ----------------------------------------------------------------------------
# DSL entry point
# ----------------------------------------------------------------------------

proc ::Tclme::Plugin {body} {
    # ------------------------------------------------------------------------
    # Tclme::Plugin
    #
    # Strict DSL entry point.
    #
    # Correct usage inside a plugin file:
    #
    #   Tclme::Plugin {
    #       description "..."
    #       version 0.1.0
    #
    #       command hello {args} {
    #           ::Tclme::Message "Hello"
    #       }
    #   }
    #
    # The plugin name is derived from the namespace created by the loader.
    # The plugin file must not supply its own name.
    # ------------------------------------------------------------------------

    if {[info commands ::Tclme::DSL::Finish] eq "" ||
        [info commands ::Tclme::DSL::Forget] eq ""} {
        error "Tclme DSL runtime is missing: need ::Tclme::DSL::Finish and ::Tclme::DSL::Forget"
    }

    # The plugin file is sourced inside the plugin namespace created by
    # Tclme::LoadPlugin. That namespace is the source of truth.

    set ns [uplevel 1 {namespace current}]

    if {![string match "::Tclme::Plugin::*" $ns]} {
        error "Tclme::Plugin must be called from inside a plugin namespace (::Tclme::Plugin::*)"
    }

    set name [namespace tail $ns]

    if {$name eq ""} {
        error "Cannot determine plugin name from namespace '$ns'"
    }

    # Tclme::LoadPlugin sets ::Tclme::_owner while sourcing a plugin.
    # If this is missing, the DSL is being used outside the plugin loader.

    if {![info exists ::Tclme::_owner] || $::Tclme::_owner eq ""} {
        error "Tclme::Plugin must be used while Tclme is loading a plugin"
    }

    # The loader's plugin name must match the namespace we are inside.

    if {$::Tclme::_owner ne $name} {
        error "plugin owner mismatch: loader is loading '$::Tclme::_owner', but plugin namespace is '$name'"
    }

    # Reject empty DSL blocks.

    if {[string trim $body] eq ""} {
        error "plugin '$name' has an empty Tclme::Plugin body"
    }

    # Reject multiple DSL blocks in the same plugin file.

    if {[info exists ${ns}::__dsl_body]} {
        error "plugin '$name' already contains a Tclme::Plugin block"
    }

    # Store DSL metadata in the actual plugin namespace.

    namespace eval $ns [list variable __dsl_version 2]
    namespace eval $ns [list variable __dsl_name $name]
    namespace eval $ns [list variable __dsl_body $body]

    # Temporarily expose DSL directives inside the plugin namespace.

    set old_path [namespace path $ns]

    if {[lsearch -exact $old_path ::Tclme::DSL] < 0} {
        namespace path $ns [linsert $old_path 0 ::Tclme::DSL]
    }

    # Make plugin ownership explicit while the DSL body is evaluated.

    set old_owner $::Tclme::_owner
    set ::Tclme::_owner $name

    set rc [catch {
        namespace eval $ns $body
    } err]

    set ::Tclme::_owner $old_owner
    namespace path $ns $old_path

    if {$rc} {
        ::Tclme::DSL::Forget $ns

        catch {
            namespace eval $ns [list unset -nocomplain \
                __dsl_version \
                __dsl_name \
                __dsl_body \
            ]
        }

        error "plugin '$name' DSL: $err" $::errorInfo
    }

    if {[catch {
        ::Tclme::DSL::Finish $ns
    } err]} {
        ::Tclme::DSL::Forget $ns

        catch {
            namespace eval $ns [list unset -nocomplain \
                __dsl_version \
                __dsl_name \
                __dsl_body \
            ]
        }

        error "plugin '$name' DSL finalization failed: $err" $::errorInfo
    }

    return $ns
}
# ----------------------------------------------------------------------------
# Internal DSL state helpers
# ----------------------------------------------------------------------------

proc ::Tclme::DSL::MetaSetNs {ns key value} {
    set var ${ns}::__plugin_meta

    if {[info exists $var]} {
        set meta [set $var]
    } else {
        set meta [dict create]
    }

    dict set meta $key $value

    namespace eval $ns [list variable __plugin_meta $meta]
}

proc ::Tclme::DSL::PendingGet {ns} {
    variable pending

    if {[dict exists $pending $ns]} {
        return [dict get $pending $ns]
    }

    return [dict create \
        state_used 0 \
        state {} \
        init {} \
        cleanup {} \
    ]
}

proc ::Tclme::DSL::PendingSet {ns data} {
    variable pending
    dict set pending $ns $data
}

proc ::Tclme::DSL::Forget {ns} {
    variable pending
    catch { dict unset pending $ns }
}

# ----------------------------------------------------------------------------
# Finish DSL processing.
#
# Generates lifecycle procs after the DSL body has been evaluated.
# This avoids the DSL command names colliding with generated procs.
# ----------------------------------------------------------------------------

proc ::Tclme::DSL::Finish {ns} {
    variable pending

    if {![dict exists $pending $ns]} {
        return
    }

    set p [dict get $pending $ns]

    set state_used    [dict get $p state_used]
    set state_default [dict get $p state]
    set init_bodies   [dict get $p init]
    set cleanup_bodies [dict get $p cleanup]

    # State support.
    #
    # The DSL state model is a dict stored in:
    #
    #   variable state
    #
    # The generated state/restore procedures are compatible with the Tclme
    # plugin lifecycle.

    if {$state_used} {
        if {![info exists ${ns}::state]} {
            namespace eval $ns [list variable state $state_default]
        }

        if {[info commands ${ns}::state] eq ""} {
            namespace eval $ns {
                proc state {} {
                    variable state
                    return $state
                }
            }
        }

        if {[info commands ${ns}::restore] eq ""} {
            namespace eval $ns {
                proc restore {saved} {
                    variable state
                    set state $saved
                }
            }
        }
    }

    # Init support.

    if {[llength $init_bodies] > 0 && [info commands ${ns}::init] eq ""} {
        namespace eval $ns [list proc init {} [join $init_bodies \n]]
    }

    # Cleanup support.

    if {[llength $cleanup_bodies] > 0 && [info commands ${ns}::cleanup] eq ""} {
        namespace eval $ns [list proc cleanup {} [join $cleanup_bodies \n]]
    }

    dict unset pending $ns
}

# ----------------------------------------------------------------------------
# DSL directives
# ----------------------------------------------------------------------------

proc ::Tclme::DSL::description {text} {
    set ns [uplevel 1 {namespace current}]
    MetaSetNs $ns description $text
}

proc ::Tclme::DSL::version {value} {
    set ns [uplevel 1 {namespace current}]
    MetaSetNs $ns version $value
}

# Metadata only in DSL v1.
#
# Suggested values:
#
#   headless safe
#   headless ui
#
# This does not currently prevent loading in headless mode.
# It is metadata for humans and future tooling.

proc ::Tclme::DSL::headless {mode} {
    set ns [uplevel 1 {namespace current}]
    MetaSetNs $ns headless $mode
}

# Declare plugin state.
#
# The value must be a dict.
#
# Multiple state directives are merged.

proc ::Tclme::DSL::state {dict} {
    set ns [uplevel 1 {namespace current}]

    if {[catch { dict size $dict }]} {
        error "state must be a dict"
    }

    set p [PendingGet $ns]

    dict set p state_used 1

    set current [dict get $p state]

    if {[dict size $current] == 0} {
        set merged $dict
    } else {
        set merged [dict merge $current $dict]
    }

    dict set p state $merged

    PendingSet $ns $p
}

# Define a Tclme command.
#
# Usage:
#
#   command NAME ARGSPEC BODY ?DOC?

proc ::Tclme::DSL::command {cmdname argspec body args} {
    set ns [uplevel 1 {namespace current}]

    set doc ""

    if {[llength $args] > 0} {
        set doc [lindex $args 0]
    }

    set procname "__cmd_[::Tclme::SanitizeName $cmdname]"

    uplevel 1 [list proc $procname $argspec $body]
    uplevel 1 [list ::Tclme::DefCommand $cmdname $procname $doc]
}

# Bind a key to a Tclme command.
#
# Usage:
#
#   bind KEYS COMMAND ?TAG?

proc ::Tclme::DSL::bind {keys cmdname args} {
    if {[llength $args] > 0} {
        set tag [lindex $args 0]
        uplevel 1 [list ::Tclme::BindKey $cmdname $keys $tag]
    } else {
        uplevel 1 [list ::Tclme::BindKey $cmdname $keys]
    }
}

# Register an event hook.
#
# Usage:
#
#   on EVENT ARGSPEC BODY ?PRIORITY?

proc ::Tclme::DSL::on {event argspec body args} {
    variable seq

    incr seq

    set ns [uplevel 1 {namespace current}]

    set procname "__hook_[::Tclme::SanitizeName $event]_$seq"

    uplevel 1 [list proc $procname $argspec $body]

    if {[llength $args] > 0} {
        set priority [lindex $args 0]
        uplevel 1 [list ::Tclme::On $event $procname $priority]
    } else {
        uplevel 1 [list ::Tclme::On $event $procname]
    }
}

# Define plugin init behavior.
#
# Multiple init blocks are joined together unless the plugin already defines
# a raw `init` procedure.

proc ::Tclme::DSL::init {body} {
    set ns [uplevel 1 {namespace current}]

    set p [PendingGet $ns]

    dict lappend p init $body

    PendingSet $ns $p
}

# Define plugin cleanup behavior.
#
# Multiple cleanup blocks are joined together unless the plugin already defines
# a raw `cleanup` procedure.

proc ::Tclme::DSL::cleanup {body} {
    set ns [uplevel 1 {namespace current}]

    set p [PendingGet $ns]

    dict lappend p cleanup $body

    PendingSet $ns $p
}

# Raw Tcl escape hatch.
#
# The body is evaluated in the plugin namespace at plugin load time.

proc ::Tclme::DSL::do {body} {
    uplevel 1 $body
}

# ----------------------------------------------------------------------------
# Introspection helpers
# ----------------------------------------------------------------------------

proc ::Tclme::PluginMeta {name} {
    set ns [::Tclme::PluginNamespace $name]
    set var ${ns}::__plugin_meta

    if {[info exists $var]} {
        return [set $var]
    }

    return [dict create]
}

proc ::Tclme::PluginBody {name} {
    set ns [::Tclme::PluginNamespace $name]
    set var ${ns}::__dsl_body

    if {[info exists $var]} {
        return [set $var]
    }

    return ""
}

proc ::Tclme::CmdPluginShow {args} {
    set name [string trim [join $args " "]]

    if {$name eq ""} {
        set names [lsort [dict keys $::Tclme::plugin_meta]]

        if {[llength $names] == 0} {
            ::Tclme::Print "No plugins loaded."
        } else {
            ::Tclme::Print "Loaded plugins: [join $names {, }]"
        }

        return
    }

    if {![dict exists $::Tclme::plugin_meta $name]} {
        ::Tclme::Message "Not loaded: $name"
        return
    }

    set meta [::Tclme::PluginMeta $name]
    set info [dict get $::Tclme::plugin_meta $name]

    set lines [list "Plugin: $name"]

    if {[dict exists $info file]} {
        lappend lines "File: [dict get $info file]"
    }

    foreach key {description version headless} {
        if {[dict exists $meta $key]} {
            lappend lines "[string totitle $key]: [dict get $meta $key]"
        }
    }

    set body [::Tclme::PluginBody $name]

    if {$body ne ""} {
        lappend lines ""
        lappend lines "DSL body:"
        lappend lines $body
    }

    ::Tclme::Print [join $lines \n]
}

# ----------------------------------------------------------------------------
# Plugin template generator
# ----------------------------------------------------------------------------
proc ::Tclme::PluginTemplate {name} {
    return [join [list \
        "Tclme::Plugin {" \
        "    description \"TODO: describe $name\"" \
        "    version 0.1.0" \
        "    headless safe" \
        "" \
        "    state {" \
        "        enabled 1" \
        "    }" \
        "" \
        "    command $name {args} {" \
        "        variable state" \
        "        ::Tclme::Message \"Hello from $name\"" \
        "    }" \
        "" \
        "    init {" \
        "        # Called after state has been restored." \
        "    }" \
        "" \
        "    cleanup {" \
        "        # Cancel timers, destroy widgets, close sockets." \
        "    }" \
        "}" \
    ] \n]
}

proc ::Tclme::CmdPluginNew {args} {
    set name [string trim [join $args " "]]

    if {$name eq ""} {
        ::Tclme::Message "Usage: :plugin-new NAME"
        return
    }

    # Keep the name but remove path-like characters.
    set safe [regsub -all {[/\\]} $name _]

    if {$safe eq ""} {
        ::Tclme::Message "Invalid plugin name"
        return
    }

    set file [file join $::Tclme::plugindir "$safe.tcl"]

    if {[file exists $file]} {
        ::Tclme::Message "Already exists: $file"
        return
    }

    if {[catch {
        set fp [open $file w]
        puts $fp [::Tclme::PluginTemplate $safe]
        close $fp
    } err]} {
        ::Tclme::Log error "plugin-new: $err"
        return
    }

    ::Tclme::Message "Created $file"
}

# ----------------------------------------------------------------------------
# Register DSL utility commands
# ----------------------------------------------------------------------------

if {[info commands ::Tclme::DefCommand] ne ""} {
    catch { ::Tclme::DefCommand plugin-new  ::Tclme::CmdPluginNew  "Create a new DSL plugin file" }
    catch { ::Tclme::DefCommand plugin-show ::Tclme::CmdPluginShow "Show plugin metadata" }

    catch { ::Tclme::DefAlias pn plugin-new }
    catch { ::Tclme::DefAlias ps plugin-show }
}