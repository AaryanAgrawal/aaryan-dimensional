# C++ — questions I've asked

Spaced repetition. Cover the answer, recall, check. Newest at the bottom.

---

**struct vs class vs Rust struct vs Python dataclass?**
C++: `struct` and `class` are the same construct — members are public by default in one, private in
the other. Both hold data and methods together, and both can inherit. Rust splits that: the struct
is data only, methods go in a separate `impl` block, and there is no inheritance. Python:
`@dataclass` writes the `__init__` and equality boilerplate for an ordinary class. A C++ or Rust
struct is a memory layout fixed at compile time with no field names left at runtime; a Python
object carries a dictionary of its fields, looked up by name while the program runs.
