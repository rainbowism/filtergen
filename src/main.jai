#import "Basic";
#import "Math";
#import "File";
#import "String";
#import "Hash_Table";
#import "Flat_Pool";
#import "File_Watcher";
#import "File_Utilities";

#load "generate.jai";

main :: () {
    cmd_args := get_command_line_arguments();
    only_generate: bool;
    for arg: cmd_args {
        if arg == {
        case "gen"; only_generate = true;
        }
    }

    generate_filter();
    if only_generate  exit(0);

    file_change_callback :: (watcher: *File_Watcher(void), change: *File_Change, user_data: *void) {
        generate_filter();
    }

    watcher: File_Watcher(void);
    init(*watcher, file_change_callback, null, events_to_watch = .ALL_EVENTS);
    add_directories(*watcher, ".");

    while true {
        changed, needs_wait, wait_seconds := process_changes(*watcher);
        reset_temporary_storage();
        sleep_milliseconds(100);
    }
}

warn :: (fmt: string, args: .. Any, flags := Log_Flags.NONE, loc := #caller_location) #expand {
    partial_path := path_filename(loc.fully_pathed_filename);
    log(tprint("[WARN][%:%,%] %\n", partial_path, loc.line_number, loc.character_number, fmt), ..args, flags = flags);
}

info :: (fmt: string, args: .. Any, flags := Log_Flags.NONE, loc := #caller_location) #expand {
    partial_path := path_filename(loc.fully_pathed_filename);
    log(tprint("[INFO][%:%,%] %\n", partial_path, loc.line_number, loc.character_number, fmt), ..args, flags = flags);
}
