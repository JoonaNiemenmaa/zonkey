pub fn inSlice(T: type, needle: T, haystack: []const T) bool {
    for (haystack) |hay| {
        if (needle == hay) return true;
    }
    return false;
}
