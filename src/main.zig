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

const curses = @import("zig-curses");
const Window = curses.Window(ColorPair);
const Screen = curses.Screen(ColorPair);

const ColorPair = enum {
    Normal,
};

const CursesUI = struct {
    const Self = @This();

    win: Window,
    game: *const Game,


    pub fn init(game: Game, win: Window) Self {
        return .{ .game = game, .win = win };
    }


    pub fn bit_input(self: Self) u8 {
        const c = try self.win.getch();

        return switch (c) {
            'p' => 0,
            'o' => 1,
            'i' => 2,
            'u' => 3,
            'y' => 4,
            't' => 5,
            'r' => 6,
            'e' => 7,
            'w' => 8,
            'q' => 9,
            else => null,
        };
    }


    pub fn print_hori_bar(self: Self, x: u32, y: u32, taken8: u32, width: u32) anyerror!void {
        assert(taken8 <= width * 8);

        if (width == 0) return;

        var col8: u32 = 8;
        var i: u16 = x;

        while (col8 < taken8) : (col8 += 8) {
            try self.win.puts_at(i,y,"\u{2588}");
            i+=1;
        }

        try self.win.print_at(i,y,"{u}", .{
            if (col8 - taken8 != 8)
                @intCast(u21, 0x2588 + (col8 - taken8))
            else
                ' '
        });
        i+=1;

        while (col8 < width * 8) : (col8 += 8) {
            try self.win.puts_at(i,y," "); // TODO putchar?
            i+=1;
        }
    }
};
const TextUI = struct {
    const Self = @This();
    const IOError = std.os.ReadError || std.os.WriteError || error{EndOfStream};

    game: *Game,

    pub fn init(game: *Game) Self {
        return .{ .game = game };
    }

    pub fn run(self: Self) IOError!void {
        const reader = std.io.getStdIn().reader();

        while (true) {
            const gauge = self.game.gauge;
            const num = self.game.num;
            const nom = self.game.nom;
            try print("[|{:3}|] <- |{:3}|\tHP: {}\n", .{num, nom, gauge});

            const key = while (true) {
                const b = try reader.readByte();
                if (self.keymap(b)) |key| break key;
            } else unreachable;

            if (!self.game.input(key)) break;
        }
    }

    fn keymap(_: Self, c: u8) ?Game.Control {
        return switch (c) {
            ';' => .BIT_0,
            'l' => .BIT_1,
            'k' => .BIT_2,
            'j' => .BIT_3,
            'f' => .BIT_4,
            'd' => .BIT_5,
            's' => .BIT_6,
            'a' => .BIT_7,
            //'w' => .BIT_8,
            //'q' => .BIT_9,
            'q' => .EXIT,
            else => null,
        };
    }
};

const Game = struct {
    const Self = @This();

    const Control = enum {
        BIT_0, BIT_1, BIT_2, BIT_3,
        BIT_4, BIT_5, BIT_6, BIT_7,
        BIT_8, BIT_9,
        EXIT,
    };

    // FIXME we need atomic!
    updater: std.Thread,
    halt_updating: bool = false,
    random: std.rand.Random,
    gauge: u8 = 255,
    num: u16,
    nom: u16 = 0,

    pub fn alloc(
        allocator: std.mem.Allocator,
        prng: *std.rand.DefaultPrng
    ) !*Self {
        var self = try allocator.create(Self);

        const random = prng.random();
        const num = random.int(u8);
        const updater = try std.Thread.spawn(.{}, Self.update, .{self});
        self.* = .{
            .random = random,
            .num = num,
            .updater = updater,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.halt_updating = true;
        self.updater.join();
    }

    fn update(self: *Self) void {
        while (!self.halt_updating) {
            std.time.sleep(100_000_000);
            self.gauge -|= 1;
        }
    }

    pub fn input(self: *Self, key: Self.Control) bool {
        // FIXME return type
        if (key == .EXIT) return false;
        self.nom ^= @shlExact(@as(u16, 1), @enumToInt(key));
        if (self.num == self.nom) {
            self.num = self.random.int(u8);
            self.gauge +|= 200;
        }
        return true;
    }
};

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

const c_locale = @cImport(@cInclude("locale.h"));

pub fn main_curses() anyerror!void {
    _ = c_locale.setlocale(c_locale.LC_ALL, "");
    var alloc = std.testing.allocator;

    var scr = try Screen.init(alloc, null, null, null);
    defer scr._deinit();
    var win = scr.std_window();
    defer win._deinit();

    _ = try scr.curs_set(.Invisible);
    //_ = try win.keypad(true);

    var i: u32 = 0;
    while (i <= 7*8) : (i += 1) {
        try win.erase();
        try win.puts_at(0,0,"=|");
        //try print_hori_bar(win, i, 7);
        try win.puts_at(8,0,"=");
        try win.refresh();
        std.time.sleep(100000000); // `sleep` uses nanoseconds,
    }
    _ = try win.getch();
}

pub fn main() anyerror!void {
    var alloc = std.testing.allocator;
    var prng = std.rand.DefaultPrng.init(1);
    var game = try Game.alloc(alloc, &prng);
    defer alloc.destroy(game);
    defer game.deinit();
    var ui = TextUI.init(game);

    try ui.run();
}
