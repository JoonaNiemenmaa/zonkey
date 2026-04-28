const std = @import("std");
const token_zig = @import("token.zig");
const scanner_zig = @import("scanner.zig");

const Token = token_zig.Token;
const TokenType = token_zig.TokenType;
const Scanner = scanner_zig.Scanner;

test "test one character tokens" {
    const cases = [_]Token{ Token{
        .type = TokenType.LBRACKET,
        .literal = "[",
        .line = 1,
        .column = 2,
    }, Token{
        .type = TokenType.RBRACKET,
        .literal = "]",
        .line = 1,
        .column = 4,
    }, Token{
        .type = TokenType.LBRACE,
        .literal = "{",
        .line = 1,
        .column = 5,
    }, Token{
        .type = TokenType.RBRACE,
        .literal = "}",
        .line = 1,
        .column = 7,
    }, Token{
        .type = TokenType.LPAREN,
        .literal = "(",
        .line = 1,
        .column = 10,
    }, Token{
        .type = TokenType.RPAREN,
        .literal = ")",
        .line = 1,
        .column = 13,
    }, Token{
        .type = TokenType.SEMICOLON,
        .literal = ";",
        .line = 2,
        .column = 2,
    }, Token{
        .type = TokenType.SEMICOLON,
        .literal = ";",
        .line = 2,
        .column = 3,
    }, Token{
        .type = TokenType.EOF,
        .literal = "",
        .line = 2,
        .column = 4,
    } };

    var scanner = try Scanner.init(
        \\ [ ]{ }  (  )
        \\ ;;
    );

    for (cases) |case| {
        const token = scanner.nextToken();
        try std.testing.expectEqualDeep(case, token);
    }

    const token = scanner.nextToken();
    try std.testing.expect(token.type == TokenType.EOF);
}

test "test two character tokens" {
    const cases = [_]Token{ Token{
        .type = TokenType.EQUALS,
        .literal = "==",
        .line = 1,
        .column = 1,
    }, Token{
        .type = TokenType.NOT_EQUALS,
        .literal = "!=",
        .line = 2,
        .column = 3,
    }, Token{
        .type = TokenType.EOF,
        .literal = "",
        .line = 2,
        .column = 5,
    } };

    var scanner = try Scanner.init(
        \\==
        \\  !=
    );

    for (cases) |case| {
        const token = scanner.nextToken();
        try std.testing.expectEqualDeep(case, token);
    }

    const token = scanner.nextToken();
    try std.testing.expect(token.type == TokenType.EOF);
}

test "test long tokens" {

    const cases = [_]Token{
        Token{
            .type = .IDENT,
            .literal = "joona",
            .line = 1,
            .column = 1,
        },
        Token{
            .type = .IF,
            .literal = "if",
            .line = 2,
            .column = 3,
        },
        Token{
            .type = .TRUE,
            .literal = "true",
            .line = 2,
            .column = 8,
        },
        Token{
            .type = .INT,
            .literal = "800",
            .line = 3,
            .column = 1,
        },
    };

    var scanner = try Scanner.init(
        \\joona
        \\  if   true
        \\800
    );

    for (cases) |case| {
        const token = scanner.nextToken();
        try std.testing.expectEqualDeep(case, token);
    }

    const token = scanner.nextToken();
    try std.testing.expect(token.type == TokenType.EOF);

}
