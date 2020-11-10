# StringViews

This Julia package implements a new type of `AbstractString`, a `StringView`,
that provides a string representation of any underlying array of bytes
(any `AbstractVector{UInt8}`), interpreted as UTF-8 encoded Unicode data.

Unlike Julia's built-in `String` type (which also wraps UTF-8 data), the
`StringView` type is a copy-free wrap of *any* `AbstractVector{UInt8}`
instance, and does not take "ownership" or modify the arrray.   Otherwise,
a `StringView` is intended to be usable in any context where you might
have otherwise used `String`.

(In particular, as much as possible we try to implement efficient copy-free
`String`-like operations on `StringView`, such as iteration and regular-expression
searching, as long as the underlying `UInt8` array is a contiguous dense array.)
