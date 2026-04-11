const std = @import("std");
const utils = @import("root.zig").utils;

pub const TokenType = enum { 
    LPAREN, 
    RPAREN, 
    LBRACE, 
    RBRACE, 
    LBRACKET, 
    RBRACKET, 
    SEMICOLON, 
    PLUS, 
    MINUS, 
    ASTERISK, 
    SLASH, 
    EQUALS, 
    NOT_EQUALS, 
    ASSIGN, 
    BANG, 
    COMMA, 

    TRUE,
    FALSE,
    LET, 
    RETURN, 
    FN, 

    IDENT, 
    INT, 

    EOF, 
    ILLEGAL 
};

pub const Token = struct {
    type: TokenType,
    literal: []const u8,
    line: usize,
    column: usize,
};

const ScannerError = error{EOFError};

pub const Scanner = struct {
    sourceCode: []const u8,

    current: usize,
    ahead: usize,

    line: usize,
    column: usize,

    fn getCurrentChar(self: *@This()) ScannerError!u8 {
        return if (self.current < self.sourceCode.len) self.sourceCode[self.current] else ScannerError.EOFError;
    }

    fn getAheadChar(self: *@This()) ScannerError!u8 {
        return if (self.ahead < self.sourceCode.len) self.sourceCode[self.ahead] else ScannerError.EOFError;
    }

    fn nextChar(self: *@This()) ScannerError!void {
        if (self.current < self.sourceCode.len) {
            self.current += 1;
            self.ahead = self.current + 1;

            self.column += 1;

            if (try self.getCurrentChar() == '\n') {
                self.column = 0;
                self.line += 1;
            }
        }
    }

    pub fn init(source_code: []const u8) @This() {
        return Scanner{
            .sourceCode = source_code,
            .current = 0,
            .ahead = 1,
            .line = 1,
            .column = 1,
        };
    }

    fn eatWhitespace(self: *@This()) ScannerError!void {
        while (std.ascii.isWhitespace(try self.getCurrentChar())) try self.nextChar();
    }

    fn createToken(self: *@This(), @"type": TokenType, literal: []const u8) Token {
        return Token{ .type = @"type", .literal = literal, .line = self.line, .column = self.column };
    }

    pub fn nextToken(self: *@This()) Token {
        self.eatWhitespace() catch {
            return self.createToken(TokenType.EOF, "");
        };

        var token: Token = undefined;

        const current = self.getCurrentChar() catch {
            return self.createToken(TokenType.EOF, "");
        };

        const ahead = self.getAheadChar() catch 0;

        token_switch: switch (current) {
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
            '!' => token = {
                if (ahead == '=') {
                    token = self.createToken(TokenType.NOT_EQUALS, "=");
                    break :token_switch;
                }
                self.createToken(TokenType.BANG, "!");
            },
            '=' => {
                if (ahead == '=') {
                    token = self.createToken(TokenType.EQUALS, "=");
                    break :token_switch;
                }
                token = self.createToken(TokenType.ASSIGN, "=");
            },
            else => {
                token = self.createToken(TokenType.ILLEGAL, &[_]u8{current});
                if (std.ascii.isAlphabetic(current)) {
                    // tokenize a string
                } else if (std.ascii.isDigit(current)) {
                    // tokenize a number
                } else {
                    //token = create_token(TokenType.ILLEGAL, &[_]u8{current});
                }
            },
        }

        self.nextChar() catch {};

        return token;
    }
};

test "scanner test 1" {
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

    var scanner = Scanner.init(
        \\ [ ]{ }  (  )  
        \\ ;;
    );

    for (cases) |case| {
        const token = scanner.nextToken();

        try std.testing.expect(token.type == case.type);
        try std.testing.expect(std.mem.eql(u8, token.literal, case.literal));
        try std.testing.expect(token.line == case.line);
        try std.testing.expect(token.column == case.column);
    }

    const token = scanner.nextToken();
    try std.testing.expect(token.type == TokenType.EOF);
}
