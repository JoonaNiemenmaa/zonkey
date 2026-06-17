const std = @import("std");
const monkey = @import("root.zig");
const ast = monkey.ast;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Scanner = monkey.scanner.Scanner;
const Token = monkey.token.Token;
const TokenType = monkey.token.TokenType;

const print = std.debug.print;

pub const Parser = struct {
    allocator: Allocator,
    scanner: *Scanner,
    current: Token,
    ahead: Token,
    errors: ArrayList([]const u8),

    pub fn init(allocator: Allocator, scanner: *Scanner) @This() {
        return @This(){
            .allocator = allocator,
            .scanner = scanner,
            .current = scanner.nextToken(),
            .ahead = scanner.nextToken(),
            .errors = ArrayList([]const u8).empty,
        };
    }

    pub fn getErrors(self: *@This()) ![][]const u8 {
        return try self.errors.toOwnedSlice(self.allocator);
    }

    fn appendError(self: *@This(), comptime format: []const u8, args: anytype) !void {
        const errorMsg = try std.fmt.allocPrint(self.allocator, format, args);
        try self.errors.append(self.allocator, errorMsg);
    }

    fn nextToken(self: *@This()) void {
        self.current = self.ahead;
        self.ahead = self.scanner.nextToken();
    }

    fn currentTokenIs(self: *@This(), expect: TokenType) bool {
        return self.current.type == expect;
    }

    fn aheadTokenIs(self: *@This(), expect: TokenType) bool {
        return self.ahead.type == expect;
    }

    fn expectAhead(self: *@This(), expect: TokenType) !bool {
        if (self.aheadTokenIs(expect)) {
            self.nextToken();
            return true;
        } else {
            try self.appendError("{}:{} Unexpected token of type '{}' found when '{}' was expected.", .{ self.ahead.line, self.ahead.column, self.ahead.type, expect });
            return false;
        }
    }

    fn parseIdentifier(self: *@This()) ast.Identifier {
        return ast.Identifier{
            .token = self.current,
            .name = self.current.literal,
        };
    }

    fn parseInteger(self: *@This()) ast.Integer {
        return ast.Integer{
            .token = self.current,
            .value = std.fmt.parseInt(i64, self.current.literal, 0) catch unreachable,
        };
    }

    fn parseString(self: *@This()) ast.String {
        return ast.String{
            .token = self.current,
            .value = self.current.literal,
        };
    }

    fn parseBoolean(self: *@This()) ast.Boolean {
        return ast.Boolean{
            .token = self.current,
            .value = switch (self.current.type) {
                .TRUE => true,
                .FALSE => false,
                else => unreachable,
            },
        };
    }

    fn parseFunction(self: *@This()) !?ast.Function {
        const token = self.current;

        if (!try self.expectAhead(.LPAREN)) return null;

        self.nextToken();

        var parameters: ArrayList(ast.Identifier) = .empty;
        errdefer parameters.deinit(self.allocator);

        while (self.currentTokenIs(.IDENT)) {
            const identifier = self.parseIdentifier();
            try parameters.append(self.allocator, identifier);

            self.nextToken();
            if (self.currentTokenIs(.COMMA)) if (!try self.expectAhead(.IDENT)) return null;
        }

        if (!self.currentTokenIs(.RPAREN)) {
            try self.appendError("{}:{} Unexpected token of type '{}' found when '{}' was expected.", .{ self.current.line, self.current.column, self.current.type, TokenType.RPAREN });
            return null;
        }

        if (!try self.expectAhead(.LBRACE)) return null;

        const body = try self.parseBlock();

        return ast.Function{
            .token = token,
            .parameters = try parameters.toOwnedSlice(self.allocator),
            .body = body,
        };
    }

    fn parseIf(self: *@This()) Allocator.Error!?ast.If {
        const token = self.current;

        if (!try self.expectAhead(.LPAREN)) return null;

        const condition = try self.parseGroupedExpression() orelse return null;

        if (!try self.expectAhead(.LBRACE)) return null;

        const consequence = try self.parseBlock();

        var alternative: ?ast.Block = null;

        if (self.aheadTokenIs(.ELSE)) {
            self.nextToken();

            if (!try self.expectAhead(.LBRACE)) return null;

            alternative = try self.parseBlock();
        }

        return ast.If{
            .token = token,
            .condition = condition,
            .consequence = consequence,
            .alternative = alternative,
        };
    }

    fn parsePrefix(self: *@This(), operator: ast.PrefixOperator) Allocator.Error!?ast.Prefix {
        const token = self.current;

        self.nextToken();

        const expression = try self.parseExpression(.PREFIX) orelse return null;

        return ast.Prefix{
            .token = token,
            .operator = operator,
            .operand = expression,
        };
    }

    fn parseCall(self: *@This(), function: *ast.Expression) Allocator.Error!?ast.Expression {
        const token = self.current;

        var arguments: ArrayList(*const ast.Expression) = .empty;
        errdefer arguments.deinit(self.allocator);

        if (!self.aheadTokenIs(.RPAREN)) {
            self.nextToken();

            var argument = try self.parseExpression(.LOWEST) orelse return null;
            try arguments.append(self.allocator, argument);

            while (self.aheadTokenIs(.COMMA)) {
                self.nextToken();
                self.nextToken();
                argument = try self.parseExpression(.LOWEST) orelse return null;
                try arguments.append(self.allocator, argument);
            }
        }

        if (!try self.expectAhead(.RPAREN)) return null;

        return ast.Expression{ .call = .{
            .token = token,
            .function = function,
            .arguments = try arguments.toOwnedSlice(self.allocator),
        } };
    }

    fn parseInfix(self: *@This(), left: *ast.Expression) Allocator.Error!?ast.Expression {
        const token = self.current;

        const operator = monkey.ast.getInfixOperator(token.type);

        self.nextToken();

        const right = try self.parseExpression(getPrecedence(token.type)) orelse return null;

        return ast.Expression{ .infix = .{
            .token = token,
            .operator = operator,
            .left = left,
            .right = right,
        } };
    }

    fn parseGroupedExpression(self: *@This()) !?*ast.Expression {
        self.nextToken();

        const expression = try self.parseExpression(.LOWEST) orelse return null;

        if (!try self.expectAhead(TokenType.RPAREN)) return null;

        return expression;
    }

    const Precedence = enum(u8) {
        LOWEST = 0,
        EQUALS,
        LESSGREATER,
        SUM,
        PRODUCT,
        PREFIX,
        CALL,
    };

    fn getPrecedence(@"type": TokenType) Precedence {
        return switch (@"type") {
            .PLUS => Precedence.SUM,
            .MINUS => Precedence.SUM,
            .ASTERISK => Precedence.PRODUCT,
            .SLASH => Precedence.PRODUCT,
            .EQUALS => Precedence.EQUALS,
            .NOT_EQUALS => Precedence.EQUALS,
            .LESS_THAN => Precedence.LESSGREATER,
            .GREATER_THAN => Precedence.LESSGREATER,
            .LPAREN => Precedence.CALL,
            else => Precedence.LOWEST,
        };
    }

    fn getInfixFunction(tokenType: TokenType) *const fn (*@This(), *ast.Expression) Allocator.Error!?ast.Expression {
        return switch (tokenType) {
            .PLUS => &parseInfix,
            .MINUS => &parseInfix,
            .ASTERISK => &parseInfix,
            .SLASH => &parseInfix,
            .EQUALS => &parseInfix,
            .NOT_EQUALS => &parseInfix,
            .LESS_THAN => &parseInfix,
            .GREATER_THAN => &parseInfix,
            .LPAREN => &parseCall,
            else => unreachable,
        };
    }

    fn parseExpression(self: *@This(), precedence: Precedence) Allocator.Error!?*ast.Expression {
        var left: *ast.Expression = try self.allocator.create(ast.Expression);
        errdefer self.allocator.destroy(left);

        left.* = switch (self.current.type) {
            .IDENT => ast.Expression{ .identifier = self.parseIdentifier() },
            .INT => ast.Expression{ .integer = self.parseInteger() },
            .STRING => ast.Expression{ .string = self.parseString() },
            .FALSE => ast.Expression{ .boolean = self.parseBoolean() },
            .TRUE => ast.Expression{ .boolean = self.parseBoolean() },
            .MINUS => ast.Expression{ .prefix = try self.parsePrefix(ast.PrefixOperator.MINUS) orelse return null },
            .BANG => ast.Expression{ .prefix = try self.parsePrefix(ast.PrefixOperator.NOT) orelse return null },
            .LPAREN => (try self.parseGroupedExpression() orelse return null).*,
            .IF => ast.Expression{ .@"if" = try self.parseIf() orelse return null },
            .FN => ast.Expression{ .function = try self.parseFunction() orelse return null },
            else => {
                try self.appendError("{}:{} Unexpected token of type '{}' found when expression was expected.", .{
                    self.current.line,
                    self.current.column,
                    self.current.type,
                });
                return null;
            },
        };

        while (!self.aheadTokenIs(TokenType.SEMICOLON) and
            !self.aheadTokenIs(TokenType.EOF) and
            !self.aheadTokenIs(TokenType.RPAREN) and
            !self.aheadTokenIs(TokenType.COMMA) and
            @intFromEnum(precedence) < @intFromEnum(getPrecedence(self.ahead.type)))
        {
            self.nextToken();
            const infix = try self.allocator.create(ast.Expression);
            errdefer self.allocator.destroy(infix);

            infix.* = try getInfixFunction(self.current.type)(self, left) orelse {
                self.allocator.destroy(infix);
                return left;
            };

            left = infix;
        }

        return left;
    }

    fn parseLetStatement(self: *@This()) !?ast.LetStatement {
        const token = self.current;

        if (!try self.expectAhead(TokenType.IDENT)) return null;

        const identifier = self.parseIdentifier();

        if (!try self.expectAhead(TokenType.ASSIGN)) return null;

        self.nextToken();

        const expression = try self.parseExpression(Precedence.LOWEST) orelse return null;

        if (self.aheadTokenIs(TokenType.SEMICOLON)) self.nextToken();

        return ast.LetStatement{
            .token = token,
            .identifier = identifier,
            .expression = expression,
        };
    }

    fn parseReturnStatement(self: *@This()) !?ast.ReturnStatement {
        const token = self.current;

        self.nextToken();

        const expression = try self.parseExpression(Precedence.LOWEST) orelse return null;

        if (self.aheadTokenIs(TokenType.SEMICOLON)) self.nextToken();

        return ast.ReturnStatement{
            .token = token,
            .expression = expression,
        };
    }

    fn parseExpressionStatement(self: *@This()) !?ast.ExpressionStatement {
        const token = self.current;
        const expression = try self.parseExpression(Precedence.LOWEST) orelse return null;

        if (self.aheadTokenIs(TokenType.SEMICOLON)) self.nextToken();

        return ast.ExpressionStatement{
            .token = token,
            .expression = expression,
        };
    }

    fn parseBlock(self: *@This()) !ast.Block {
        const token = self.current;

        self.nextToken();

        var statements: ArrayList(ast.Statement) = .empty;
        errdefer statements.deinit(self.allocator);

        while (!self.currentTokenIs(TokenType.RBRACE) and !self.currentTokenIs(TokenType.EOF)) {
            const statement = try self.parseStatement();

            if (statement) |s| try statements.append(self.allocator, s);

            self.nextToken();
        }

        return ast.Block{
            .token = token,
            .statements = try statements.toOwnedSlice(self.allocator),
        };
    }

    fn parseStatement(self: *@This()) !?ast.Statement {
        switch (self.current.type) {
            TokenType.LET => {
                const letStatement = try self.parseLetStatement();
                if (letStatement) |ls| return ast.Statement{ .letStatement = ls };
            },
            TokenType.RETURN => {
                const returnStatement = try self.parseReturnStatement();
                if (returnStatement) |rs| return ast.Statement{ .returnStatement = rs };
            },
            else => {
                const expressionStatement = try self.parseExpressionStatement();
                if (expressionStatement) |es| return ast.Statement{ .expressionStatement = es };
            },
        }
        return null;
    }

    pub fn parseProgram(self: *@This()) !ast.Program {
        var statements: ArrayList(ast.Statement) = .empty;
        errdefer statements.deinit(self.allocator);

        while (self.current.type != TokenType.EOF) {
            const statement: ?ast.Statement = try self.parseStatement();

            if (statement) |s| try statements.append(self.allocator, s);

            self.nextToken();
        }

        return ast.Program{ .statements = try statements.toOwnedSlice(self.allocator) };
    }

    pub fn printErrors(self: @This()) void {
        for (self.errors.items) |err| {
            std.debug.print("{s}\n", .{err});
        }
    }
};
