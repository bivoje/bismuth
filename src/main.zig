const std = @import("std");

const  print = std.io.getStdOut().writer().print;
const eprint = std.io.getStdErr().writer().print;
const assert = std.debug.assert;
const Atomic = std.atomic.Atomic;

const curses = @import("zig-curses");
const Window = curses.Window(ColorPair);
const Screen = curses.Screen(ColorPair);

const ColorPair = enum {
    Normal,
};


// may not reder properly with some fonts.
// verified with Cascadida Mono
// https://docs.microsoft.com/ko-kr/windows/terminal/cascadia-code
const CursesUI = struct {
    const Self = @This();

    win: Window,
    game: *Game,

    width: u16,
    height: u16,

    pub fn init(game: *Game, win: Window) Self {
        return .{ .game = game, .win = win, .width = 30, .height = 7 };
    }

    fn keymap(_: Self, c: c_int) ?Game.Control {
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

    pub fn run(self: Self) !void {
        self.win.timeout(0); // nonblocking
        while (true) {
            try self.draw_all();
            try self.win.refresh();

            const b = self.win.getch() orelse continue;
            if (self.keymap(b)) |key|
                if (!self.game.input(key)) break;

            std.time.sleep(100_000_000);
        }
    }

    pub fn draw_all(self: Self) !void {
        try curses.painter.unicode_draw_box(self.win, 0, 0, self.width-3, self.height-3);
        try self.win.puts_at(self.width-1, 1, "ਊ");
        try self.draw_number();
        try self.draw_gauge();
        try self.draw_bits();
    }

    fn draw_gauge(self: Self) !void {
        const gauge = @intCast(u16, self.game.gauge);
        const width = (self.width-3) * 8 * gauge / 255;

        try curses.painter.draw_line(self.win, 1, self.height-1, self.width-3, " ", " ", " ");
        try curses.painter.unicode_draw_hori_bar(self.win, 1, self.height-1, width);
    }

    fn draw_number(self: Self) !void {
        var buf: [4]u4 = undefined;
        buf[0] = @intCast(u4, self.game.num);
        try Self.smbraille_font.renders_atmid(self.win, (self.width-1)/2, (self.height-1)/2, buf[0..1]);
    }

    fn draw_bits(self: Self) !void {
        const x = (self.width-1)/2 - 2;
        const y = self.height-2;
        var i: u16 = 0;
        const nom = self.game.nom;
        while (i < 4) : (i+=1) {
            try self.win.puts_at(x+i, y, if ((nom >> 3-@intCast(u4,i)) & 1 == 1) "x" else " ");
        }
    }

    const NumFont = struct {
        charmap: []const u8,
        width: u16,
        height: u16,
        charwidth: u16 = 3,

        fn render_at(self: NumFont, win: Window, x: u16, y: u16, n: u4) !void  {
            var k: u16 = 0;
            while (k < self.height) : (k += 1) {
                const s = (self.width*self.charwidth*16+1)*k + self.width*self.charwidth*n;
                try win.puts_at(x, y+k, self.charmap[s .. s+self.charwidth*self.width]);
            }
        }

        fn renders_atmid(self: NumFont, win: Window, mx:u16, my: u16, ns: []const u4) !void {
            var x = mx - (@intCast(u16,ns.len) * self.width) / 2;
            var y = my - (self.height) / 2;

            for (ns) |n| {
                try self.render_at(win, x, y, n);
                x += self.width;
            }
        }
    };

    const future_font = NumFont {
        .width = 3, .height = 3,
        .charmap = // figlet font future.tlf, using FIGURE SPACE (U+2007) for space
        \\┏━┓╺┓ ┏━┓┏━┓╻ ╻┏━╸┏━┓┏━┓┏━┓┏━┓┏━┓┏┓ ┏━╸╺┳┓┏━╸┏━╸
        \\┃┃┃ ┃ ┏━┛╺━┫┗━┫┗━┓┣━┓  ┃┣━┫┗━┫┣━┫┣┻┓┃   ┃┃┣╸ ┣╸ 
        \\┗━┛╺┻╸┗━╸┗━┛  ╹┗━┛┗━┛  ╹┗━┛┗━┛╹ ╹┗━┛┗━╸╺┻┛┗━╸╹  
        \\
    };

    const smbraille_font = NumFont {
        .width = 3, .height = 2,
        .charmap = // figlet font smbraille.tlf, using FIGURE SPACE (U+2007) for space
        \\⣎⣵ ⢺  ⠊⡱ ⢉⡹ ⢇⣸ ⣏⡉ ⣎⡁ ⠉⡹ ⢎⡱ ⢎⣱ ⢀⣀ ⣇⡀ ⢀⣀ ⢀⣸ ⢀⡀ ⣰⡁ 
        \\⠫⠜ ⠼⠄ ⠮⠤ ⠤⠜  ⠸ ⠤⠜ ⠣⠜ ⠸  ⠣⠜ ⠠⠜ ⠣⠼ ⠧⠜ ⠣⠤ ⠣⠼ ⠣⠭ ⢸  
        \\
    };

    const broadwaykb_font = NumFont {
        .width = 5, .height = 4, .charwidth = 1,
        .charmap = // figlet font broadway_kb.flf, using FIGURE SPACE (U+2007) for space
        \\ ___   _  ??????????????????????????????????????????????????????????????????????
        \\/ / \ / | ??????????????????????????????????????????????????????????????????????
        \\\_\_/ |_| ??????????????????????????????????????????????????????????????????????
        \\          ??????????????????????????????????????????????????????????????????????
        \\
    };
};

const AnsiUI = struct {
    const Self = @This();
    const IOError = std.os.ReadError || std.os.WriteError || error{EndOfStream};

    game: *Game,

    pub fn init(game: *Game) Self {
        return .{ .game = game };
    }

    fn show_quark(q: Game.Quark) []const u8{
        return switch (q) {
            .NO_CLEAR => "ਊ",
        };
    }

    pub fn run(self: Self) IOError!void {
        const reader = std.io.getStdIn().reader();

        while (true) {
            const gauge = self.game.gauge;
            const num = self.game.num;
            const nom = self.game.nom;
            try print("\x1b[0G\x1b[K[|{:3}|] <- |{b:0>8}|\tHP: {}", .{num, nom, gauge});

            const key = while (true) {
                const b = try reader.readByte();
                if (self.keymap(b)) |key| break key;
            } else unreachable;

            if (!self.game.input(key)) break;
        }
        try print("\n", .{});
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

const TextUI = struct {
    const Self = @This();
    const IOError = std.os.ReadError || std.os.WriteError || error {EndOfStream, StreamTooLong};

    game: *Game,

    pub fn init(game: *Game) Self {
        return .{ .game = game };
    }

    //pub fn run(self: Self) IOError!void {
    pub fn run(self: Self) anyerror!void {
        const reader = std.io.getStdIn().reader();
        var buf :[128]u8 = undefined;

        while (true) {
            const gauge = self.game.gauge;
            const num = self.game.num;
            const nom = self.game.nom;
            try print("[|{:3}|] <- |{b:0>8}|\tHP: {}\n> ", .{num, nom, gauge});

            const line = reader.readUntilDelimiter(&buf, '\n')
                catch |err| switch (err) {
                    error.EndOfStream => return,
                    error.StreamTooLong => {
                        try print(":P command too long\n", .{});
                        continue;
                    },
                    else => |e| return e,
                }
            ;

            const cmd = Self.parse_command(line) catch |e| {
                try print(":O Error - {}", .{e});
                continue;
            };

            const key = switch (cmd) {
                .Quit => Game.Control.EXIT,
                .Bit  => |x| blk: {
                    if (x > 7) {
                        try print(":v bit index too big", .{});
                        continue;
                    }
                    break :blk @intToEnum(Game.Control, @enumToInt(Game.Control.BIT_0) + x);
                },
            };

            if (!self.game.input(key)) break;
        }
    }

    const Command = union(enum) {
        Quit: void,
        Bit: u8,
    };

    fn parse_command(line: []u8) !Command {
        const cmd = for (line) |c, i| {
            if (c == ' ') break line[0..i];
        } else line[0..];

        if (std.mem.eql(u8,cmd,"quit")) {
            return Command { .Quit = undefined };
        } else if(std.mem.eql(u8,cmd,"b")) {
            const x = try std.fmt.parseUnsigned(u8, line[cmd.len+1..], 10);
            return Command { .Bit = x };
        } else {
            return error.UnrecognizedCommand;
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

    // input sequence component to drive the game.
    // any user input should be translated into Control by UI.
    // generally, UI implements configurable keymaps for these values.
    pub const Control = enum {
        BIT_0, BIT_1, BIT_2, BIT_3,
        BIT_4, BIT_5, BIT_6, BIT_7,
        BIT_8, BIT_9,
        EXIT,
    };

    pub const Quark = enum {
        NO_CLEAR
    };

    // FIXME we need atomic!
    updater: std.Thread,
    halt_updating: bool = false,
    random: std.rand.Random,
    gauge: u8 = 255,
    num: u16,
    nom: u16 = 0,
    quarks: u2 = 0,

    fn hasquark(self: Self, q: Self.Quark) bool {
        return (self.quarks >> @enumToInt(q)) & 1 == 1;
    }

    // allocates Game instance,
    // this is neccessary to ensure that the updator thread gets
    // correct instance. if `game` were not pointer, it would be
    // on the stack and it's address may be different with what is
    // given to the spawned thread after return.
    // and thus, the caller owns the memory, which has to be freed manually.
    pub fn alloc(
        allocator: std.mem.Allocator,
        prng: *std.rand.DefaultPrng
    ) !*Self {
        var self = try allocator.create(Self);

        const random = prng.random();
        const num = 0xF & random.int(u8);
        const updater = try std.Thread.spawn(.{}, Self.update, .{self});
        self.* = .{
            .random = random,
            .num = num,
            .updater = updater,
        };
        return self;
    }

    // halts update routine & joins updator thread.
    // must be called before destroying..
    // FIXME can't deinit call destroy by itself?
    pub fn deinit(self: *Self) void {
        self.halt_updating = true;
        self.updater.join();
    }

    fn update(self: *Self) void {
        while (!self.halt_updating) {
            std.time.sleep(80_000_000);
            self.gauge -|= 1;
        }
    }

    pub fn input(self: *Self, key: Self.Control) bool {
        // FIXME return type
        if (key == .EXIT) return false;
        self.nom ^= @shlExact(@as(u16, 1), @enumToInt(key));
        if (self.num == self.nom) {
            self.num = 0xf & @intCast(u8,self.random.int(u6));
            self.gauge +|= 20;
            if (!self.hasquark(.NO_CLEAR)) {
                self.nom = 0;
            }
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

    const mode = 2;

    switch (mode) {
        0 => {
            var ui = TextUI.init(game);
            try ui.run();
        },
        1 => {
            var ui = AnsiUI.init(game);
            try ui.run();
        },
        2 => {
            _ = c_locale.setlocale(c_locale.LC_ALL, "");

            var scr = try Screen.init(alloc, null, null, null);
            defer scr._deinit();
            var win = scr.std_window();
            defer win._deinit();

            _ = try scr.curs_set(.Invisible);
            _ = try win.keypad(true);
            _ = try scr.echo(false);

            var ui = CursesUI.init(game, win);
            try ui.run();
        },
        else => unreachable,
    }
}
