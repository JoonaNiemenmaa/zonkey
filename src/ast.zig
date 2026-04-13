const Token = @import("scanner.zig").Token;

pub const Program = struct {
    statements: []Statement
};

pub const Statement = union(enum) {
    letStatement: LetStatement,
    returnStatement: ReturnStatement,
    ExpressionStatement: ExpressionStatement,
};

pub const Expression = union(enum) {
    identifier: Identifier,
    integer: Integer,
};

pub const PrefixOperator = enum {
    NOT
};

pub const InfixOperator = enum {
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    EQUALS,
    NOT_EQUALS,
};

pub const Identifier = struct {
    token: Token,
    name: []const u8,
};

pub const Integer = struct {
    token: Token,
    value: i64,
};

pub const Prefix = struct {
    token: Token,
    operator: PrefixOperator,
    operand: Expression,
};

pub const Infix = struct {
    token: Token,
    operator: InfixOperator,
    left_operand: Expression,
    right_operand: Expression,
};

pub const LetStatement = struct {
    token: Token,
    identifier: Identifier,
    expression: Expression,
};

pub const ReturnStatement = struct {
    token: Token,
    expression: Expression,
};

pub const ExpressionStatement = struct {
    token: Token,
    expression: Expression,
};

