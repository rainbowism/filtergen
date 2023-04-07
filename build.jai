BINARY_NAME  :: "filtergen";
OUTPUT_DIR   :: "bin/";
MAIN_SOURCE  :: "src/main.jai";
MODULE_PATHS :: string.[
    "./third_party"
];

PRINT_BUILD_INFO :: false;

#run build();

build :: () {
    make_directory_if_it_does_not_exist(OUTPUT_DIR);

    options := get_build_options();
    options.output_type = .EXECUTABLE;
    options.output_executable_name = BINARY_NAME;
    options.output_path = OUTPUT_DIR;
    modules_path: [..] string;
    for options.import_path  array_add(*modules_path, it);
    for MODULE_PATHS         array_add(*modules_path, it);
    options.import_path = modules_path;

    args := options.compile_time_command_line;
    release_build := false;
    for arg: args {
        if arg == {
        case "-r";  release_build = true;
        case "-";   break;
        case;       break;
        }
    }

    if release_build {
        options.optimization_level      = .RELEASE;
        options.backend                 = .LLVM;
        options.enable_bytecode_inliner = true;
        options.stack_trace             = false;
        // options.additional_linker_arguments = .["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"];
        set_optimization_level(*options, 2, 0);
    } else {
        options.optimization_level      = .DEBUG;
        options.backend                 = .X64;
        options.enable_bytecode_inliner = true;
        options.text_output_flags       = .OUTPUT_TIMING_INFO;
    }

    ws := compiler_create_workspace("filtergen");
    set_build_options(options, ws);
    add_build_file(MAIN_SOURCE, ws);

    set_build_options_dc(.{do_output=false, write_added_strings=false});
}

#import "Basic";
#import "Compiler";
#import "File";
