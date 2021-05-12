pub const AllocError = error {
    OutOfMemory,
    ZeroSizedAlloc,
};
pub const FreeError = error {
    InvalidFree,
};
pub const MemoryError = AllocError || FreeError;
