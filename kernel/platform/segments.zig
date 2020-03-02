const Pointer = packed struct {
    limit: u16,
    base: u32,
};
pub export var gdt_pointer: Pointer = undefined;

pub export var kernel_code_selector: u16 = undefined;
pub export var kernel_data_selector: u16 = undefined;
pub export var user_code_selector: u16 = undefined;
pub export var user_data_selector: u16 = undefined;
pub export var tss_selector: u16 = undefined;
