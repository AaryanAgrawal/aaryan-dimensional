# Python — questions I've asked

Spaced repetition. Cover the answer, recall, check. Newest at the bottom.

---

**dataclass vs Rust struct vs C++ struct?**
Python: `@dataclass` is a decorator on an ordinary class that writes the `__init__` and equality
boilerplate for you. Fields and methods live in the same class body. Rust: data only, no
inheritance, methods in a separate `impl` block. C++: `struct` and `class` are the same thing,
differing only in default visibility. A Python object carries a dictionary of its fields, looked up
by name while the program runs; Rust and C++ structs are memory layouts fixed at compile time with
no field names left at runtime.
