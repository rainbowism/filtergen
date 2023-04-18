#import "Simple_Framework" (
    // Debug = true,
    Default_Log_Level = .Debug,
    Log_File_Paths = true,
    Manually_Swap_Buffer = true,
    // Enable_Profiler = true,
    Disable_ImGui = true,
);

Fontin_Regular_Image   :: #run load_static_data("data/Fontin-Regular.png");
Fontin_Regular_MSDF    :: #run load_static_data("data/Fontin-Regular.msdf");
Fontin_SmallCaps_Image :: #run load_static_data("data/Fontin-SmallCaps.png");
Fontin_SmallCaps_MSDF  :: #run load_static_data("data/Fontin-SmallCaps.msdf");
Minimap_Icons_Image    :: #run load_static_data("data/filter_icons_1.png");

fontin_regular:    *MSDF_Font;
fontin_small_caps: *MSDF_Font;
minimap_icons:     Texture;
icon_lookup: Table(string, *Rect);
icon_rects: [3 * Icon_Shapes.count * Icon_Colors.count] Rect;

test_text :: #string ___poe
Show
    BaseType "Orb of Annulment" "Harbinger's Orb" "Ancient Orb" "Elevated Sextant" "Sacred Orb" "Fracturing Orb"
    SetBackgroundColor 240 0 200
    SetBorderColor 0 0 0
    SetTextColor 0 0 0
    PlayAlertSound 10 250
    SetFontSize 45
    MinimapIcon 1 Pink Circle
    PlayEffect Pink
    DisableDropSound
___poe

Filter_Predicate :: struct {
    show: bool;
    border_color:     Color;
    text_color:       Color;
    background_color: Color;
    icon: *Rect;
}

frame_dirty: bool;
filter_data: [..] Filter_Predicate;
current_predicate: Filter_Predicate;

start_interface :: () {
    init_window();
    defer destroy_window();

    filter_text := test_text;
    while parse_line := true {
        reset_temporary_storage();
        line := filter_text;
        line.count = find_index_from_left(filter_text, #char "\n");
        if line.count == -1  break parse_line;
        advance(*filter_text, line.count + 1);
        line = trim_left(line);
        if line == "Show"  current_predicate.show = true;
        if line == "Hide"  current_predicate.show = false;
        if !current_predicate.show  continue;

        if begins_with(line, "Set") {
            advance(*line, "Set".count);
            if begins_with(line, "BorderColor") {
                advance(*line, "BorderColor".count + 1);
                current_predicate.border_color = parse_color(line);
            } else if begins_with(line, "TextColor") {
                advance(*line, "TextColor".count + 1);
                current_predicate.text_color = parse_color(line);
            } else if begins_with(line, "BackgroundColor") {
                advance(*line, "BackgroundColor".count + 1);
                current_predicate.background_color = parse_color(line);
            } else if begins_with(line, "FontSize") {
                advance(*line, "FontSize".count + 1);
            }
        } else if begins_with(line, "MinimapIcon") {
            advance(*line, "MinimapIcon".count + 1);
            rect, success := table_find(*icon_lookup, line);
            if success  current_predicate.icon = rect;
        }
    }

    while !should_exit() {
        reset_temporary_storage();
        render_frame();
        wait_events(1.0);
    }
}

parse_color :: (text: string) -> Color #expand {
    pars := split(text, cast,no_check(u8) 0x20);
    color: Color = ---;
    color.r = cast(float) string_to_int(pars[0]) / 255.0;
    color.g = cast(float) string_to_int(pars[1]) / 255.0;
    color.b = cast(float) string_to_int(pars[2]) / 255.0;
    if pars.count > 3 {
        color.a = cast(float) string_to_int(pars[3]) / 255.0;
    } else {
        color.a = 1.0;
    }
    return color;
}

render_frame :: () {
    render_begin();
    default_pass_begin();

    imm_begin();

    rect: Rect = ---;
    if current_predicate.icon {
        rect.position = .{100, 100};
        rect.size = Icon_Size;

        imm_set_image(0, minimap_icons.id);
        imm_texture_subrect(<< current_predicate.icon, rect);
    }

    text_position := Vector2.{16, 16};

    text := "Fracturing Orb";

    Padding :: Vector2.{4, 4};
    rect.position = text_position - Padding;
    rect.size = measure_text(fontin_small_caps, text, 24.0) + Padding * 2;
    imm_set_color(current_predicate.background_color);
    imm_filled_rect(rect);

    line_points: [5] Vector2;
    line_points[0] = rect.position;
    line_points[1] = .{rect.position.x + rect.size.x, rect.position.y};
    line_points[2] = rect.position + rect.size;
    line_points[3] = .{rect.position.x, rect.position.y + rect.size.y};
    line_points[4] = line_points[0];
    imm_set_color(current_predicate.border_color);
    imm_line_strip(line_points);

    imm_text(fontin_small_caps, text, text_position, 24.0, color = current_predicate.text_color);

    imm_flush();
    imm_end();

    default_pass_end();
    render_end();

    swap_buffers();
}

init_window :: () {
    sf_result := sf_init();
    check_result(sf_result != .Ok, "Failed to initialize SF: %", sf_result);
    sf_result  = create_window("filtergen", 1280, 720, Window_Flags.VSync, Module_Flags.All);
    check_result(sf_result != .Ok, "Failed to create window: %", sf_result);
    set_clear_color(.{0.04, 0.08, 0.12, 1.0});
    set_vsync(true);

    fontin_regular_image, fontin_small_caps_image: Texture = ---;
    success: bool = ---;
    fontin_regular_image, success = load_texture_from_memory(Fontin_Regular_Image);
    if !success {
        panic("Failed to load Fontin-Regular.");
        exit(-1);
    }
    fontin_regular, success = load_msdf_from_memory(Fontin_Regular_MSDF, fontin_regular_image);
    if !success {
        panic("Failed to load Fontin-Regular.");
        exit(-1);
    }
    fontin_small_caps_image, success = load_texture_from_memory(Fontin_SmallCaps_Image);
    if !success {
        panic("Failed to load Fontin-Regular.");
        exit(-1);
    }
    fontin_small_caps, success = load_msdf_from_memory(Fontin_SmallCaps_MSDF, fontin_small_caps_image);
    if !success {
        panic("Failed to load Fontin-Regular.");
        exit(-1);
    }

    minimap_icons, success = load_texture_from_memory(Minimap_Icons_Image);
    if !success {
        panic("Failed to load Fontin-Regular.");
        exit(-1);
    }
    generate_icon_rects();
}

generate_icon_rects :: () {
    texture_size := Icon_Size / minimap_icons.size;
    uv_position: Vector2;
    rect_index: s64;
    for shape: Icon_Shapes {
        for color, color_index: Icon_Colors {
            for size: Icon_Sizes {
                name := sprint("% % %", size, color, shape);
                icon_rects[rect_index].tl = uv_position;
                icon_rects[rect_index].br = uv_position + texture_size;
                table_add(*icon_lookup, name, *icon_rects[rect_index]);
                rect_index += 1;
                uv_position.x += texture_size.x;
            }
            if color_index == 5 || color_index == 10 {
                uv_position.x = 0.0;
                uv_position.y += texture_size.y;
            }
        }
    }
}

Icon_Size :: Vector2.{64, 64};

Icon_Shapes :: string.[
    "Circle",
    "Diamond",
    "Hexagon",
    "Square",
    "Star",
    "Triangle",
    "Cross",
    "Moon",
    "Raindrop",
    "Kite",
    "Pentagon",
    "UpsideDownHouse",
];

Icon_Colors :: string.[
    "Blue",
    "Green",
    "Brown",
    "Red",
    "White",
    "Yellow",
    "Cyan",
    "Grey",
    "Orange",
    "Pink",
    "Purple",
];

Icon_Sizes :: string.["2", "1", "0"];

load_static_data :: (filepath: string) -> string {
    data, success := read_entire_file(join(#filepath, "../", filepath));
    if !success  assert(false, "Failed to load file.");
    return data;
};
