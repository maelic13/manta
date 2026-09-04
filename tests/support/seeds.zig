//! Named deterministic seeds shared by reproducible test campaigns.

pub const protocol_properties: u64 = 0x6d61_6e74_615f_7563;
pub const chess_state_properties: u64 = 0x6d61_6e74_615f_6368;
pub const search_properties: u64 = 0x6d61_6e74_615f_7365;

comptime {
    if (protocol_properties == chess_state_properties or
        protocol_properties == search_properties or
        chess_state_properties == search_properties)
    {
        @compileError("deterministic test seeds must be distinct");
    }
}
