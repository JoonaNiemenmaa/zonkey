const std = @import("std");
const monkey = @import("root.zig");

const Scanner = monkey.scanner.Scanner;
const DebugAllocator = std.heap.DebugAllocator;
const TokenType = monkey.scanner.TokenType;

pub fn main() !void {
    var gpa: DebugAllocator(.{}) = .init;

    const allocator = gpa.allocator();

    var scanner: Scanner = try .init(
        allocator,
        \\ [ ]{ }  (  )  
        \\ ;;ankka let treu true false
    );

    var token = try scanner.nextToken();
    while (token.type != TokenType.EOF) {
        monkey.scanner.printToken(token);
        token = try scanner.nextToken();
    }
}
