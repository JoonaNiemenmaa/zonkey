const std = @import("std");

const StaticStringMap = std.StaticStringMap;

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
    LESS_THAN,
    GREATER_THAN,
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
    IF,
    ELSE,
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

const keywords: StaticStringMap(TokenType) = .initComptime(.{
    .{ "true", .TRUE },
    .{ "false", .FALSE },
    .{ "let", .LET },
    .{ "return", .RETURN },
    .{ "if", .IF },
    .{ "else", .ELSE },
    .{ "fn", .FN },
});

pub fn lookupKeyword(literal: []const u8) TokenType {
    if (keywords.get(literal)) |keyword| return keyword;
    return .IDENT;
}
