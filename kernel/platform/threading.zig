pub extern fn setup_process(usermode: bool, ip: u32, sp: u32) u32;
pub extern fn context_switch(old: u32, new: u32) void;
pub extern fn usermode(ip: u32, sp: u32) noreturn;
