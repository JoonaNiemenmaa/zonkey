const std = @import("std");
const monkey = @import("root.zig");

const TokenType = monkey.token.TokenType;
const Token = monkey.token.Token;
const lookupKeyword = monkey.token.lookupKeyword;

pub const Scanner = struct {
    code: []const u8,

    current: usize,
    ahead: usize,

    line: usize,
    column: usize,

    fn getCurrent(self: @This()) u8 {
        return if (self.current < self.code.len) self.code[self.current] else 0;
    }

    fn getAhead(self: @This()) u8 {
        return if (self.ahead < self.code.len) self.code[self.ahead] else 0;
    }

    fn nextChar(self: *@This()) void {
        if (self.current < self.code.len) {
            self.current = self.ahead;
            self.ahead += 1;

            self.column += 1;

            if (self.getCurrent() == '\n') {
                self.column = 0;
                self.line += 1;
            }
        }
    }

    pub fn init(code: []const u8) @This() {
        return Scanner{
            .code = code,
            .current = 0,
            .ahead = 1,
            .line = 1,
            .column = 1,
        };
    }

    fn eatWhitespace(self: *@This()) void {
        while (std.ascii.isWhitespace(self.getCurrent())) self.nextChar();
    }

    fn readIdent(self: *@This()) []const u8 {
        const start: usize = self.current;
        var end: usize = self.current;

        while (std.ascii.isAlphanumeric(self.getCurrent())) {
            end += 1;
            self.nextChar();
        }

        return self.code[start..end];
    }

    fn readNumber(self: *@This()) []const u8 {
        const start: usize = self.current;
        var end: usize = self.current;

        while (std.ascii.isDigit(self.getCurrent())) {
            end += 1;
            self.nextChar();
        }

        return self.code[start..end];
    }

    fn readString(self: *@This()) []const u8 {
        const start: usize = self.current;
        var end: usize = self.current;

        while (self.getCurrent() != '"' and self.getCurrent() != 0) {
            end += 1;
            self.nextChar();
        }

        self.nextChar();

        return self.code[start..end];
    }

    fn createToken(self: *@This(), @"type": TokenType, literal: []const u8) Token {
        return Token{ .type = @"type", .literal = literal, .line = self.line, .column = self.column };
    }

    pub fn nextToken(self: *@This()) Token {
        self.eatWhitespace();

        var token: Token = undefined;

        switch (self.getCurrent()) {
            ';' => token = self.createToken(TokenType.SEMICOLON, ";"),
            '{' => token = self.createToken(TokenType.LBRACE, "{"),
            '}' => token = self.createToken(TokenType.RBRACE, "}"),
            '(' => token = self.createToken(TokenType.LPAREN, "("),
            ')' => token = self.createToken(TokenType.RPAREN, ")"),
            '[' => token = self.createToken(TokenType.LBRACKET, "["),
            ']' => token = self.createToken(TokenType.RBRACKET, "]"),
            '+' => token = self.createToken(TokenType.PLUS, "+"),
            '-' => token = self.createToken(TokenType.MINUS, "-"),
            '*' => token = self.createToken(TokenType.ASTERISK, "*"),
            '/' => token = self.createToken(TokenType.SLASH, "/"),
            ',' => token = self.createToken(TokenType.COMMA, ","),
            '<' => token = self.createToken(TokenType.LESS_THAN, "<"),
            '>' => token = self.createToken(TokenType.GREATER_THAN, ">"),
            '"' => {
                token.type = .STRING;
                token.line = self.line;
                token.column = self.column;

                self.nextChar();

                const string = self.readString();

                token.literal = string;

                return token;
            },
            '!' => {
                if (self.getAhead() == '=') {
                    token = self.createToken(TokenType.NOT_EQUALS, "!=");
                    self.nextChar();
                } else {
                    token = self.createToken(TokenType.BANG, "!");
                }
            },
            '=' => {
                if (self.getAhead() == '=') {
                    token = self.createToken(TokenType.EQUALS, "==");
                    self.nextChar();
                } else {
                    token = self.createToken(TokenType.ASSIGN, "=");
                }
            },
            0 => token = self.createToken(TokenType.EOF, ""),
            else => {
                const line: usize = self.line;
                const column: usize = self.column;

                if (std.ascii.isAlphabetic(self.getCurrent())) {
                    const literal = self.readIdent();
                    return Token{ .type = lookupKeyword(literal), .literal = literal, .line = line, .column = column };
                } else if (std.ascii.isDigit(self.getCurrent())) {
                    const literal = self.readNumber();
                    return Token{ .type = TokenType.INT, .literal = literal, .line = line, .column = column };
                }
                token = self.createToken(TokenType.ILLEGAL, "");
            },
        }

        self.nextChar();

        return token;
    }
};

test "test one character tokens" {
    const cases = [_]Token{
        Token{
            .type = TokenType.LBRACKET,
            .literal = "[",
            .line = 1,
            .column = 2,
        },
        Token{
            .type = TokenType.RBRACKET,
            .literal = "]",
            .line = 1,
            .column = 4,
        },
        Token{
            .type = TokenType.LBRACE,
            .literal = "{",
            .line = 1,
            .column = 5,
        },
        Token{
            .type = TokenType.RBRACE,
            .literal = "}",
            .line = 1,
            .column = 7,
        },
        Token{
            .type = TokenType.LPAREN,
            .literal = "(",
            .line = 1,
            .column = 10,
        },
        Token{
            .type = TokenType.RPAREN,
            .literal = ")",
            .line = 1,
            .column = 13,
        },
        Token{
            .type = TokenType.SEMICOLON,
            .literal = ";",
            .line = 2,
            .column = 2,
        },
        Token{
            .type = TokenType.SEMICOLON,
            .literal = ";",
            .line = 2,
            .column = 3,
        },
        Token{
            .type = TokenType.EOF,
            .literal = "",
            .line = 2,
            .column = 4,
        },
    };

    var scanner = Scanner.init(
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
    const cases = [_]Token{
        Token{
            .type = TokenType.EQUALS,
            .literal = "==",
            .line = 1,
            .column = 1,
        },
        Token{
            .type = TokenType.NOT_EQUALS,
            .literal = "!=",
            .line = 2,
            .column = 3,
        },
        Token{
            .type = TokenType.EOF,
            .literal = "",
            .line = 2,
            .column = 5,
        },
    };

    var scanner = Scanner.init(
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
        Token{
            .type = .STRING,
            .literal = "olen ilkeä vampyyrivelho",
            .line = 4,
            .column = 1,
        },
    };

    var scanner = Scanner.init(
        \\joona
        \\  if   true
        \\800
        \\"olen ilkeä vampyyrivelho"
    );

    for (cases) |case| {
        const token = scanner.nextToken();
        try std.testing.expectEqualDeep(case, token);
    }

    const token = scanner.nextToken();
    try std.testing.expect(token.type == TokenType.EOF);
}
