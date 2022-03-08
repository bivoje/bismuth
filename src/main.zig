const std = @import("std");

const  print = std.io.getStdOut().writer().print;
const eprint = std.io.getStdErr().writer().print;
const assert = std.debug.assert;
const Atomic = std.atomic.Atomic;

fn scatter(n: u64, seed: u64, total_cnt: *Atomic(u64)) anyerror!void {
    try print("scatter({}, {})\n", .{n, seed});
    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();

    var i: u32 = 0;
    var cnt: u32 = 0;
    while (i < n) : (i += 1) {
        // a,b are 31 bit 0 .. 2^31
        const x = random.uintLessThan(u64, 1<<31);
        const y = random.uintLessThan(u64, 1<<31);

        // d2 is 62+1 bit
        const d2 = x*x + y*y;

        //const r = 1 << 30;
        const r2 = 1 << 62;

        // area is open (not includes boundary)
        if (d2 < r2) cnt += 1;
    }

    // access atomic varible in Sequential Consistent mode
    _ = total_cnt.*.fetchAdd(cnt, .SeqCst);
    // returns the value stored in total_cnt before
}

fn run() anyerror!void {
    var prng = std.rand.DefaultPrng.init(1);
    const random = prng.random();

    const total_dots: u64 = 100_000_000;
    var total_cnt: Atomic(u64) = Atomic(u64).init(0);

    const nthread = std.Thread.getCpuCount() catch return;
    var threads = [_]std.Thread{undefined} ** 32;

    try print("running with {d} threads over {d} dots...\n", .{ nthread, total_dots });
    var it: usize = 0;
    while (it < nthread) : (it += 1) {
        const seed = random.int(u64);
        const num = if (it != nthread - 1) total_dots / nthread
                    else total_dots - (total_dots / nthread) * (nthread - 1);
                    // the last thread collects leftovers
        threads[it] = std.Thread.spawn(.{}, scatter, .{num, seed, &total_cnt}) catch |se| {
            try print("spawn error {}\n", .{se});
            return;
        };
    }

    it = 0;
    while (it < nthread) : (it += 1) {
        threads[it].join();
    }

    try print("all: {d}; in: {d}; pi: {}\n", .{
        total_dots, total_cnt.load(.SeqCst),
        4.0*@intToFloat(f32, total_cnt.load(.SeqCst))/@intToFloat(f32, total_dots)
    });
}

fn print_hori_bar(taken8: u32, width: u32) anyerror!void {
    assert(taken8 <= width * 8);

    if (width == 0) return;

    var col8: u32 = 8;

    while (col8 < taken8) : (col8 += 8) {
        try print("\u{2588}", .{});
    }

    try print("{u}", .{
        if (col8 - taken8 != 8)
            @intCast(u21, 0x2588 + (col8 - taken8))
        else
            ' '
    });

    while (col8 < width * 8) : (col8 += 8) {
        try print(" ", .{});
    }
}

test "print_hori_bar" {
    try print(":", .{});
    try print_hori_bar(0,0);
    try print("|\n", .{});

    var i: u32 = 0;
    while (i <= 24) : (i += 1) {
        try print("{d}\t:", .{i});
        try print_hori_bar(i, 3);
        try print("|\n", .{});
    }

    try print(":", .{});
    try print_hori_bar(80,10);
    try print("|\n", .{});
}

// "█▓▒░ "
fn print_hori_shadbar(taken: u32, shadA: u32, shadB: u32, shadC: u32, width: u32) anyerror!void {
    assert(taken <= shadA);
    assert(shadA <= shadB);
    assert(shadB <= shadC);
    assert(shadC <= width * 8);

    //if (width == 0) return;

    var col: u32 = 0;

    while (col < taken) : (col += 1) {
        try print("\u{2588}", .{});
    }
    while (col < shadA) : (col += 1) {
        try print("\u{2593}", .{});
    }
    while (col < shadB) : (col += 1) {
        try print("\u{2592}", .{});
    }
    while (col < shadC) : (col += 1) {
        try print("\u{2591}", .{});
    }
    while (col < width) : (col += 1) {
        try print(" ", .{});
    }
}

test "print_hori_shadbar" {
    try print(":", .{});
    try print_hori_shadbar(0,0,0,0,0);
    try print("|\n", .{});

    var i: u32 = 0;

    i = 0;
    while (i <= 8) : (i += 1) {
        try print("{d}\t:", .{i});
        try print_hori_shadbar(0,0,0,i,8);
        try print("|\n", .{});
    }

    i = 0;
    while (i <= 7) : (i += 1) {
        try print("{d}\t:", .{i});
        try print_hori_shadbar(0,0,i,7,8);
        try print("|\n", .{});
    }

    i = 0;
    while (i <= 6) : (i += 1) {
        try print("{d}\t:", .{i});
        try print_hori_shadbar(0,i,6,7,8);
        try print("|\n", .{});
    }

    i = 0;
    while (i <= 5) : (i += 1) {
        try print("{d}\t:", .{i});
        try print_hori_shadbar(i,5,6,7,8);
        try print("|\n", .{});
    }

    try print(":", .{});
    try print_hori_shadbar(10,10,10,10,10);
    try print("|\n", .{});
}

fn bitmanip(comptime T: type, x: T, key: u8) ?T {
    return switch (key) {
        @intCast(u8,'p') => x ^ 1 << 0,
        @intCast(u8,'o') => x ^ 1 << 1,
        @intCast(u8,'i') => x ^ 1 << 2,
        @intCast(u8,'u') => x ^ 1 << 3,
        @intCast(u8,'y') => x ^ 1 << 4,
        @intCast(u8,'t') => x ^ 1 << 5,
        @intCast(u8,'r') => x ^ 1 << 6,
        @intCast(u8,'e') => x ^ 1 << 7,
        @intCast(u8,'w') => x ^ 1 << 8,
        @intCast(u8,'q') => x ^ 1 << 9,
        else => null,
    };
}

test "bitmanip" {
    const stdin = std.io.getStdIn().reader();
    var x: u8 = 0;
    while (true) {
        try print("{b}\n", .{x});
        const key = stdin.readByte() catch {break;};
        if (key == @intCast(u8,' ')) break;
        x = bitmanip(u8, x, key) orelse x;
    }
}

pub fn main() anyerror!void {
    try print("bismuth!");
}
