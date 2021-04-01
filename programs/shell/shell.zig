const common = @import("common");
const system_calls = common.system_calls;
const utils = common.utils;

export fn main() void {
    system_calls.print_string("Type \"bin/a.elf\" or \"bin/b.elf\", or \"bin/shell.elf\"\n");
    system_calls.print_string("Type Ctrl-D or \"exit\" to Exit\n");
    var buffer: [128]u8 = undefined;
    var got: usize = 0;
    var running = true;
    while (running) {
        system_calls.print_string("% ");
        while (true) {
            const key = system_calls.get_key();
            if (key.shifted_char()) |c| {
                if (c == 'd' and key.modifiers.control_is_pressed) {
                    got = 0;
                    running = false;
                    break;
                }
                system_calls.print_string(@ptrCast([*]const u8, &c)[0..1]);
                if (c == '\n') {
                    break;
                } else {
                    buffer[got] = c;
                    got += 1;
                }
            }
        }
        if (got > 0) {
            const command = buffer[0..got];
            if (utils.memory_compare(command, "exit")) {
                break;
            }
            if (system_calls.exec(command)) {
                system_calls.print_string("Command: ");
                system_calls.print_string(command);
                system_calls.print_string(" failed\n");
            }
            got = 0;
        }
    }
    system_calls.print_string("<shell about to exit>\n");
    system_calls.exit(0);
}
