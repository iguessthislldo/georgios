export nakedcc fn main() void {
    while (true) {
        asm volatile ("int $100" :: [print_char] "{eax}" (u32(99)), [char] "{ebx}" (u32('+')));
    }
}
