pub fn KiB(x: usize) usize {
    return x * (1 << 10);
}

pub fn MiB(x: usize) usize {
    return x * (1 << 20);
}

pub fn GiB(x: usize) usize {
    return x * (1 << 30);
}

pub fn TiB(x: usize) usize {
    return x * (1 << 40);
}
