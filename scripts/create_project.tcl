set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build]
set project_dir [file join $out synvec]
set rom_file [file normalize [file join $root firmware boot_rom.mem]]
set fixture_file [file normalize [file join $root sim matrix_vectors.mem]]
if {[file exists $project_dir]} {error "Project already exists: $project_dir"}
foreach path [list $rom_file $fixture_file] {
    if {![file isfile $path]} {error "Missing project input: $path"}
}
file mkdir $out
set fh [open [file join $out synvec_paths.svh] w]
puts $fh [format {`define SYNVEC_ROM_PATH "%s"} $rom_file]
puts $fh [format {`define SYNVEC_FIXTURE_PATH "%s"} $fixture_file]
close $fh
create_project synvec $project_dir -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
set rtl_files [list rv32i_pipeline.sv rv32i_decode.sv soc_memory.sv matmul4x4_mmio.sv pwm_unit.sv uart_tx.sv uart_rx.sv sevenseg.sv synvec_top.sv]
foreach name $rtl_files {
    set path [file join $root rtl $name]
    if {![file isfile $path]} {error "Missing RTL: $path"}
    add_files -fileset sources_1 -norecurse $path
}
add_files -fileset sources_1 -norecurse $rom_file
set_property include_dirs [list $out [file join $root rtl]] [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $root constraints basys3.xdc]
set_property top synvec_top [get_filesets sources_1]
add_files -fileset sim_1 -norecurse [file join $root sim tb_synvec_soc.sv]
set_property include_dirs [list $out [file join $root rtl]] [get_filesets sim_1]
set_property top tb_synvec_soc [get_filesets sim_1]
set_property xsim.simulate.runtime {60000us} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "SYNVEC PROJECT CREATED: [file join $project_dir synvec.xpr]"
