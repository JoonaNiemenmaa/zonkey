const std = @import("std");
const token_zig = @import("token.zig");

const TokenType = token_zig.TokenType;
const Token = token_zig.Token;
const lookupKeyword = token_zig.lookupKeyword;

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

    pub fn init(code: []const u8) !@This() {
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

