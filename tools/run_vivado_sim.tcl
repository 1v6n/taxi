set_param general.maxThreads 12

if {[info exists SEED]} {
    set sim_seed $SEED
} elseif {[info exists ::env(SEED)]} {
    set sim_seed $::env(SEED)
} else {
    set sim_seed [clock seconds]
}

if {[info exists ARGS]} {
    set sim_args $ARGS
} elseif {[info exists ::env(ARGS)]} {
    set sim_args $::env(ARGS)
} else {
    set sim_args ""
}

set script_path [info script]
if {$script_path ne ""} {
    set tools_dir [file dirname [file normalize $script_path]]
    set verif_dir [file dirname $tools_dir]
    set module_root [file dirname $verif_dir]
    set rtl_dir [file join $module_root "design" "rtl"]
} else {
    set verif_dir [file normalize "."]
    set module_root [file dirname $verif_dir]
    set rtl_dir [file join $module_root "design" "rtl"]
}

set stage 0
if {[info exists ::env(STAGE)]} {
    set stage $::env(STAGE)
}
set tb_dir [file join $verif_dir "stage_$stage"]

set top_module "tb_top"
if {[info exists ::env(TARGET)]} {
    set top_module $::env(TARGET)
}

set project_only 0
if {[info exists PROJECT_ONLY]} {
    set project_only $PROJECT_ONLY
} elseif {[info exists ::env(PROJECT_ONLY)]} {
    set project_only $::env(PROJECT_ONLY)
}

set no_autorun 0
if {[info exists NO_AUTORUN]} {
    set no_autorun $NO_AUTORUN
} elseif {[info exists ::env(NO_AUTORUN)]} {
    set no_autorun $::env(NO_AUTORUN)
}

set proj_name "vivado_sim"
set proj_dir [file join $verif_dir "syn" "vivado_sim"]
file mkdir [file join $verif_dir "syn"]

if {[current_project -quiet] ne ""} {
    close_project
}

if {[file exists $proj_dir/$proj_name.xpr]} {
    puts "Opening existing simulation project..."
    open_project $proj_dir/$proj_name.xpr
} else {
    puts "Creating new simulation project..."
    create_project $proj_name $proj_dir -part xc7a35tcpg236-1 -force
}

remove_files [get_files -quiet]

# Add RTL sources
set rtl_files [glob -nocomplain [file join $rtl_dir "*.sv"]]
if {[llength $rtl_files] > 0} {
    add_files -fileset sources_1 $rtl_files
}

# Add testbench sources (including subdirectories like uvc and tests)
set tb_files [glob -nocomplain [file join $tb_dir "*.sv"] [file join $tb_dir "*" "*.sv"]]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 $tb_files
}

set_property top $top_module [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Disable Incremental Compilation
if {[get_runs -quiet synth_1] ne ""} {
    catch { set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1] }
    catch { set_property INCREMENTAL_CHECKPOINT "" [get_runs synth_1] }
}
if {[get_runs -quiet impl_1] ne ""} {
    catch { set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs impl_1] }
    catch { set_property INCREMENTAL_CHECKPOINT "" [get_runs impl_1] }
}
if {[get_filesets -quiet utils_1] ne ""} {
    set utils_files [get_files -quiet -of_objects [get_filesets utils_1]]
    if {[llength $utils_files] > 0} {
        catch { remove_files -fileset utils_1 $utils_files }
    }
}

if {[info commands stop_gui] ne ""} {
    set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]
} else {
    set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
}

set abs_vcd_path [file join $verif_dir "sim_output.vcd"]
if {[info exists ::env(WAVE_FILE)] && $::env(WAVE_FILE) ne ""} {
    set abs_vcd_path $::env(WAVE_FILE)
    if {[file pathtype $abs_vcd_path] eq "relative"} {
        set abs_vcd_path [file join $verif_dir $abs_vcd_path]
    }
}
file mkdir [file dirname $abs_vcd_path]
set xsim_opts "-nosignalhandlers -sv_seed $sim_seed -testplusarg VCD=$abs_vcd_path -testplusarg SEED=$sim_seed"
if {$sim_args ne ""} {
    foreach arg $sim_args {
        if {[string index $arg 0] eq "+"} {
            set arg [string range $arg 1 end]
        }
        set xsim_opts "$xsim_opts -testplusarg $arg"
    }
}
set_property -name {xsim.simulate.xsim.more_options} -value $xsim_opts -objects [get_filesets sim_1]

if {$project_only} {
    puts "============================================================"
    puts "Vivado Project setup complete. Project opened in GUI."
    puts "============================================================"
    if {[info commands stop_gui] eq ""} {
        exit
    }
    return
}

if {[current_sim -quiet] ne ""} {
    close_sim -force
}

reset_simulation -simset sim_1 -mode behavioral
launch_simulation

if {[info commands stop_gui] ne ""} {
    puts "Vivado GUI detected. Setting up waveforms..."
    
    if {[get_waves -quiet] ne ""} {
        remove_wave [get_waves]
    }
    
    set group_uut [add_wave_group "Serial to Parallel DUT"]
    catch { add_wave -into $group_uut /tb_top/u_serial_to_parallel/* }
    set group_tb [add_wave_group "Testbench"]
    catch { add_wave -into $group_tb /tb_top/* }
    
    if {$no_autorun} {
        puts "Simulation launched and paused at 0ns (autorun disabled). Use GUI controls or 'run all' in Tcl console to simulate."
    } else {
        run -all
        puts "Simulation run complete. Waves ready in GUI. (Tip: Press 'F' or click the 'Zoom Fit' toolbar button in the GUI to fit the timeline)"
    }
} else {
    puts "Vivado Batch Mode simulation complete."
}

catch {
    set xsim_dir [file join $proj_dir "vivado_sim.sim" "sim_1" "behav" "xsim"]
    foreach vcd_file [glob -nocomplain [file join $xsim_dir "*.vcd"]] {
        file copy -force $vcd_file [file dirname $abs_vcd_path]
        file copy -force $vcd_file [file join $verif_dir [file tail $vcd_file]]
    }
}

if {[info commands stop_gui] eq ""} {
    puts "All Vivado Batch Mode simulations complete. Exiting..."
    exit
}

