generate_filter :: () {
    now := current_time_consensus();
    calendar_local := to_calendar(now, .LOCAL);
    info("Starting filter generation at: %", calendar_to_string(calendar_local));

    start := get_time();
    filter_filename :: "settings/main.txt";
    filter_data, success := read_entire_file(filter_filename);
    if !success {
        warn("Failed to load filter base: `%`.", filter_filename);
        return;
    }
    defer free(filter_data);

    reset(*table_pool);
    reset(*basic_pool);
    reset(*semi_pool);
    reset(*strict_pool);
    reset(*uber_pool);

    data_allocator = .{flat_pool_allocator_proc, *table_pool};
    data_table     = .{allocator = data_allocator};
    basic_builder  = .{allocator = .{flat_pool_allocator_proc, *basic_pool}};
    semi_builder   = .{allocator = .{flat_pool_allocator_proc, *semi_pool}};
    strict_builder = .{allocator = .{flat_pool_allocator_proc, *strict_pool}};
    uber_builder   = .{allocator = .{flat_pool_allocator_proc, *uber_pool}};

    current_type      = .Basic;
    current_type_cond = .Greater_Equal;
    do_output = true;

    line_count := process_filter(filter_filename, filter_data, 1);

    output_dir: string;
    output_dir, success = table_find(*data_table, "output");
    if !success {
        warn("Failed to save filters: No `output` definition defined.");
    } else if output_dir.count == 0 || !is_directory(output_dir) {
        warn("Failed to save filters: `output` is an invalid path, set it.");
    } else {
        write_entire_file(tprint("%/1.basic.filter",  output_dir),  *basic_builder, do_reset = false);
        write_entire_file(tprint("%/2.semi.filter",   output_dir),   *semi_builder, do_reset = false);
        write_entire_file(tprint("%/3.strict.filter", output_dir), *strict_builder, do_reset = false);
        write_entire_file(tprint("%/4.uber.filter",   output_dir),   *uber_builder, do_reset = false);
    }

    end := (get_time() - start) * 1000;
    info("Finished generating filter in %ms.", end);
}

process_filter :: (filename: string, text_data: string, starting_line_number: s64) -> s64 {
    line_number := starting_line_number;
    local_line  := 1;
    while filter_loop := true {
        defer line_number += 1;
        defer local_line  += 1;

        line, found := consume_next_line(*text_data);
        raw_line := line;
        if !found  break filter_loop;
        line = trim_left(line);
        if !line {
            append_filter("");
            continue filter_loop;
        }
        if line[0] == Pound {
            advance(*line, 1);
            split_found, lhs, rhs := split_from_left(line, Colon);
            if lhs == {
            case "terminate";
                break filter_loop;
            case "type";
                if !split_found    continue filter_loop;
                if rhs.count == 0  continue filter_loop;
                parse_filter_type(rhs);
                continue filter_loop;
            case "def";
                if !split_found  continue filter_loop;
                comma_found, def_lhs, def_rhs := split_from_left(rhs, Comma);
                if !comma_found  continue filter_loop;
                table_add(*data_table, trim(def_lhs), trim(def_rhs));
            case "style";
                if !split_found  continue filter_loop;
                comma_found, style_lhs, style_rhs := split_from_left(rhs, Space);
                if !comma_found  continue filter_loop;
                style_rhs = trim_left(style_rhs);
                style_text := format_style(style_rhs, data_allocator);
                if style_text.count == 0  continue filter_loop;
                table_add(*data_table, style_lhs, style_text);
            case "if";
                if !split_found  continue filter_loop;
                data := table_find_pointer(*data_table, rhs);
                do_output = data != null;
                continue filter_loop;
            case "else";
                do_output = !do_output;
                continue filter_loop;
            case "end";
                do_output = true;
                continue filter_loop;
            case "hide";
                last_type_cond := current_type_cond;
                last_type      := current_type;
                defer {
                    current_type_cond = last_type_cond;
                    current_type      = last_type;
                }
                parse_filter_type(rhs);
                if current_type_cond == .Equal {
                    warn("`hide` directive doesn't support `Equal`: [%:%] %", filename, local_line, raw_line);
                    continue filter_loop;
                }
                append_filter("Hide");
                if current_type_cond == .Greater_Equal {
                    if current_type == .Basic {
                        warn("`hide` directive is already at the highest strictness: [%:%] %", filename, local_line, raw_line);
                        continue filter_loop;
                    }
                    current_type_cond = .Lesser_Equal;
                    current_type -= 1;
                } else if current_type_cond == .Lesser_Equal {
                    if current_type == .Uber {
                        warn("`hide` directive is already at the highest strictness: [%:%] %", filename, local_line, raw_line);
                        continue filter_loop;
                    }
                    current_type_cond = .Greater_Equal;
                    current_type += 1;
                }
                append_filter("Show");
                continue filter_loop;
            case "include";
                if !split_found  continue filter_loop;
                include_data, success := read_entire_file(rhs);
                if !success {
                    warn("Failed to include sub-filter: `%`.", rhs);
                    continue filter_loop;
                }
                append_filter(raw_line);
                line_number = process_filter(rhs, include_data, line_number);
                if line_number == 0  return 0;
                continue filter_loop;
            }
        }

        if do_output {
            index := find_index_from_left(raw_line, Percent);
            if index >= 0 {
                key: string = ---;
                key.data  = raw_line.data  + index + 1;
                key.count = raw_line.count - index - 1;
                data, table_found := table_find(*data_table, key);
                if !table_found {
                    warn("Failed to find definition for `%`: [%:%] %", key, filename, local_line, raw_line);
                    continue filter_loop;
                }

                format: string = ---;
                format.data  = raw_line.data;
                format.count = index + 1;

                append_filter(tprint(format, data));
            } else {
                append_filter(raw_line);
            }
        }
    }

    return line_number;
}

#scope_file

current_type:      Filter_Type;
current_type_cond: Filter_Condition;
do_output:    bool;

data_table: Table(string, string);
basic_builder:  String_Builder;
semi_builder:   String_Builder;
strict_builder: String_Builder;
uber_builder:   String_Builder;

data_allocator: Allocator;
table_pool:  Flat_Pool;
basic_pool:  Flat_Pool;
semi_pool:   Flat_Pool;
strict_pool: Flat_Pool;
uber_pool:   Flat_Pool;

append_filter :: (text: string) #expand {
    if current_type_cond == {
    case .Equal;
        if current_type == {
        case .Basic;
            append(*basic_builder, text);
            append(*basic_builder, "\n");
        case .Semi;
            append(*semi_builder, text);
            append(*semi_builder, "\n");
        case .Strict;
            append(*strict_builder, text);
            append(*strict_builder, "\n");
        case .Uber;
            append(*uber_builder, text);
            append(*uber_builder, "\n");
        }
    case .Greater_Equal;
        if current_type == {
        case .Basic;
            append(*basic_builder, text);
            append(*basic_builder, "\n");
            #through;
        case .Semi;
            append(*semi_builder, text);
            append(*semi_builder, "\n");
            #through;
        case .Strict;
            append(*strict_builder, text);
            append(*strict_builder, "\n");
            #through;
        case .Uber;
            append(*uber_builder, text);
            append(*uber_builder, "\n");
        }
    case .Lesser_Equal;
        if current_type == {
        case .Uber;
            append(*uber_builder, text);
            append(*uber_builder, "\n");
            #through;
        case .Strict;
            append(*strict_builder, text);
            append(*strict_builder, "\n");
            #through;
        case .Semi;
            append(*semi_builder, text);
            append(*semi_builder, "\n");
            #through;
        case .Basic;
            append(*basic_builder, text);
            append(*basic_builder, "\n");
        }
    }
}

Filter_Type :: enum {
    Basic;
    Semi;
    Strict;
    Uber;
}

Filter_Condition :: enum {
    Equal;
    Greater_Equal;
    Lesser_Equal;
}

parse_filter_type :: inline (text: string) {
    if text[0] == {
    case Equal;
        advance(*text, 1);
        current_type_cond = .Equal;
    case Greater;
        advance(*text, 1);
        current_type_cond = .Greater_Equal;
    case Lesser;
        advance(*text, 1);
        current_type_cond = .Lesser_Equal;
    case;
        current_type_cond = .Equal;
    }
    to_lower_in_place(text);
    if text == {
    case "basic";   current_type = .Basic;
    case "semi";    current_type = .Semi;
    case "strict";  current_type = .Strict;
    case "uber";    current_type = .Uber;
    case "default";
        current_type      = .Basic;
        current_type_cond = .Greater_Equal;
    case;  warn("Invalid filter type: `%`.", text);
    }
}

format_style :: inline (text: string, allocator: Allocator) -> string {
    auto_release_temp();
    parts := split(text, Comma);
    if parts.count == 0  return "";

    builder: String_Builder;
    builder.allocator = temp;

    first := true;
    for part: parts {
        found, lhs, rhs := split_from_left(part, Equal);
        if !found  continue;
        if rhs[0] == Pound {
            advance(*rhs, 1);
            value, success := string_to_int(rhs, base = 16);
            if !success  continue;
            r := (value >> 16) & 0xFF;
            g := (value >> 8)  & 0xFF;
            b := (value)       & 0xFF;
            rhs = tprint("% % %", r, g, b);
        }

        if !first  append(*builder, "\n    ");
        first = false;

        lhs = trim_left(lhs);
        if lhs == {
        case "bg";
            print_to_builder(*builder, "SetBackgroundColor %", rhs);
        case "text";
            print_to_builder(*builder, "SetTextColor %", rhs);
        case "border";
            print_to_builder(*builder, "SetBorderColor %", rhs);
        }
    }

    return builder_to_string(*builder, allocator);
}

consume_next_line :: inline (sp: *string) -> string, bool {
    part := << sp;
    if part.count == 0  return "", false;

    index := find_index_from_left(part, LF);
    if index < 0 {
        advance(sp, part.count);
        return part, true;
    }

    part.count = index;
    if part.count > 0 && part[index-1] == CR  part.count -= 1;
    advance(sp, index + 1);
    return part, true;
}

CR    : u8 : #char "\r";
LF    : u8 : #char "\n";
Space : u8 : #char " ";
Slash : u8 : #char "/";
Colon : u8 : #char ":";
Pound : u8 : #char "#";
Comma : u8 : #char ",";
Percent : u8 : #char "%";
Equal   : u8 : #char "=";
Greater : u8 : #char ">";
Lesser  : u8 : #char "<";
