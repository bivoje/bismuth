const std = @import("std");

const print = std.debug.print;
const Atomic = std.atomic.Atomic;

fn scatter(n: u64, seed: u64, total_cnt :*Atomic(u64)) void {
    print("scatter({}, {})\n", .{n, seed});
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

pub fn main() anyerror!void {
    var prng = std.rand.DefaultPrng.init(1);
    const random = prng.random();

    const total_dots: u64 = 100_000_000;
    var total_cnt: Atomic(u64) = Atomic(u64).init(0);

    const nthread = std.Thread.getCpuCount() catch return;
    var threads = [_]std.Thread{undefined} ** 32;

    print("running with {d} threads over {d} dots...\n", .{nthread, total_dots});
    var it: usize = 0;
    while (it < nthread) : (it += 1) {
        const seed = random.int(u64);
        const num = if (it != nthread-1) total_dots / nthread
                    else total_dots - (total_dots / nthread) * (nthread-1);
                    // the last thread collects leftovers
        threads[it] = std.Thread.spawn(.{}, scatter, .{num, seed, &total_cnt}) catch |se| {
            print("spawn error {}\n", .{se});
            return;
        };
    }

    it = 0;
    while (it < nthread) : (it += 1) {
        threads[it].join();
    }

    print("all: {d}; in: {d}; pi: {}\n", .{
        total_dots, total_cnt.load(.SeqCst),
        4.0*@intToFloat(f32,total_cnt.load(.SeqCst))/@intToFloat(f32,total_dots)
    });
}
