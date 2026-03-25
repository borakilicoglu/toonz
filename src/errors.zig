pub const ToonError = error{
    InvalidRoot,
    InvalidSyntax,
    InvalidIndentation,
    UnsupportedFeature,
    UnexpectedToken,
    DuplicateKey,
    TrailingData,
    StrictViolation,
};

