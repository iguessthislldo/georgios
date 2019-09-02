pub inline fn KiB(x: usize) usize {
    return x * (1 << 10);
}

pub inline fn MiB(x: usize) usize {
    return x * (1 << 20);
}

pub inline fn GiB(x: usize) usize {
    return x * (1 << 30);
}

pub inline fn TiB(x: usize) usize {
    return x * (1 << 40);
}
