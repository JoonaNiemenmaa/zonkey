const std = @import("std");
const monkey = @import("root.zig");

const TokenType = monkey.scanner.TokenType;

pub fn main() void {
    var scanner = monkey.scanner.Scanner.init(
        \\ [ ]{ }  (  )  
        \\ ;;
    );

    var token = scanner.nextToken();
    while (token.type != TokenType.EOF) {
        std.debug.print("{}\n", .{token});
        token = scanner.nextToken();
    }
}
