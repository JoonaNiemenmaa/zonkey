const std = @import("std");
const monkey = @import("root.zig");

const Scanner = monkey.scanner.Scanner;
const DebugAllocator = std.heap.DebugAllocator;
const TokenType = monkey.scanner.TokenType;
const Reader = std.io.Reader;

pub fn main() !void {
    var gpa: DebugAllocator(.{}) = .init;

    const allocator = gpa.allocator();

    const reader: Reader = .fixed(
            \\ [ ]{ }  (  )                   
            \\ ;201;ankka let treu true false             
        );

    var scanner: Scanner = try .init(
        allocator,
        reader
    );

    var token = try scanner.nextToken();
    while (token.type != TokenType.EOF) {
        monkey.scanner.printToken(token);

        switch (token.literal) {
            .char => {},
            .string => |s|
                switch (token.type) {
                    TokenType.IDENT => allocator.free(s), 
                    TokenType.INT => allocator.free(s), 
                    else => {} 
                }
        }

        token = try scanner.nextToken();
    }
}
