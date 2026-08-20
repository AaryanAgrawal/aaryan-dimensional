# Rust

Concepts and one example each. Cover the example, read the concept, reconstruct it.

---

## Reading a parameter

Name first, then type. The type may be a path through modules.

    fn run(cli: &cli::Cli) -> Result<()>
           ───  ─ ─── ───
            │   │  │   └── the type's name
            │   │  └────── the module it lives in
            │   └───────── borrowed, not owned
            └───────────── the parameter's name

## Capitalisation tells you what a name is

Types are CapitalCase. Modules, variables and functions are lowercase.

    cli::Cli
    ───  ───
     │    └── a type
     └─────── a module

## `mod` vs `use`

`mod` says the module exists and compiles it. `use` shortens names from it. Rust never
auto-discovers files — an undeclared `.rs` is not compiled at all.

    mod cli;              // there is a module `cli` — find src/cli.rs
    use cli::Cli;         // now `Cli` can be written without the prefix

## Crate, package, module

A crate is one unit of compilation producing one output. Modules are structure inside it.

    package                     Cargo.toml, name "test-rs-cross"
    └── crate                   binary, rooted at src/main.rs, produces "dim"
        ├── module cli          src/cli.rs
        └── module setup        src/setup/mod.rs
            └── module boot     src/setup/boot.rs

`src/main.rs` roots an executable and needs `fn main()`. `src/lib.rs` roots a library, which is the
only kind another crate can import. Multiple modules by default; a second crate when something
outside must depend on the code, or when build times hurt.

## struct

Data only. No methods inside, no inheritance.

    struct Machine {
        disk_gb: u64,
        ram_gb: u64,
    }

## `impl`

Where functions attach to a type. Written separately from the struct.

    impl Machine {
        fn new(disk_gb: u64) -> Self { Self { disk_gb, ram_gb: 0 } }
        //     ───────────      ────
        //          │            └── Self = the type this block is for
        //          └─────────────── no `self` parameter → an associated function,
        //                           called as Machine::new(...). `new` is convention,
        //                           not a keyword.

        fn is_installable(&self) -> bool { self.disk_gb >= 12 }
        //                ─────
        //                  └── takes self → a method, called as machine.is_installable()
    }

## The three forms of `self`

Which one appears decides what the caller keeps.

    &self          lend for reading
    &mut self      lend, may modify
    self           take ownership — caller loses the value

Taking `self` and returning `Self` is what allows chaining:

    Finding::new("disk", Block, "6 GB free").with_fix("free space")

## enum

Exactly one of a fixed list. Each alternative may carry different data.

    enum Command {
        Doctor,                     // carries nothing
        Setup(SetupArgs),           // carries a bundle
        Update { yes: bool },       // carries a named field
    }

## `match`

Compare against shapes, run the arm that fits. The compiler rejects the program if a case is
missing, and the pattern unpacks the data while recognising it.

    match &cli.command {
        Command::Doctor         => run_doctor(),
        Command::Setup(args)    => run_setup(args),
        //             ────
        //               └── binds what Setup carries, only inside this arm
        Command::Update { yes } => self_update(*yes),
    }

## `if let`

A `match` with one arm. Checks a shape and binds its contents in one step.

    if let Some(payload) = detect_payload() { ... }
    if let Err(e)        = run(&cli)        { ... }
           ────  ───────
             │      └── the name for the contents, valid only inside the braces
             └───────── the shape being tested

## No null: `Option` and `Result`

A value that may be absent is `Option`; an operation that may fail is `Result`. You cannot reach
the contents without stating what happens in the other case.

    Option<T>    Some(value) | None
    Result<T>    Ok(value)   | Err(problem)

Failure is an ordinary return value, not an exception, so it cannot fly past a caller silently.

## Discarding a `Result` on purpose

Rust warns if you ignore one. These are the explicit ways to say "this may fail and I accept that".

    let _ = append(&entry);        // logging must never break an install
    outro_cancel("Interrupted.").ok();

## Ownership

Every value has exactly one owner. When the owner goes out of scope, the value is freed there.
Tracked while compiling, so there is no garbage collector and no manual free.

## Borrowing

    &x          lend for reading — any number at once
    &mut x      lend for writing — exactly one, and no readers alongside

The second rule makes data races a compile error. A reference also cannot be null and cannot
outlive what it points at, both checked at build time.

## `*` — the opposite of `&`

Follow a reference to the value underneath. Appears when a pattern binds a borrowed value.

    Command::Update { yes } => self_update(*yes)
    //                ───                  ────
    //                 │                     └── the bool itself
    //                 └───────────────────────── a borrowed bool

## A missing semicolon is a return

An expression with no trailing semicolon is the value of its block. Results travel up through
`match` arms and out of functions with no `return` written anywhere.

    fn is_installable(&self) -> bool {
        self.disk_gb >= 12       // no semicolon → this is the answer
    }

## Field and method may share a name

Looked up separately; `()` decides which you get. A real trap.

    cli.non_interactive       // the flag the user typed
    cli.non_interactive()     // a function: self.non_interactive || self.dry_run

## `#[derive(...)]` — code written for you

A macro reads the type definition and generates an implementation from it, at compile time. The
functions it produces are never in the source.

    #[derive(Parser)]                          // generates Cli::parse()
    #[command(version = env!("CARGO_PKG_VERSION"))]
    pub struct Cli {
        /// Print commands without executing   // becomes the --help line
        #[arg(long, global = true)]            // becomes --dry-run, valid anywhere
        pub dry_run: bool,
    }

So one definition yields the valid commands, the parser, the help text, and the list the compiler
checks a `match` against. `env!` reads a value at compile time — here the version from Cargo.toml.

## A function may exit rather than return

`Cli::parse()` reads the process arguments and returns a filled-in value — but on bad input, or on
`--help` or `--version`, it prints and terminates the process instead. It never returns those
cases, which is why callers do not check it for errors. `try_parse()` returns a `Result` if you
want to handle them yourself.

## struct vs dataclass vs C++ struct

Rust: data only, methods in `impl`, no inheritance. C++: `struct` and `class` are the same thing,
differing only in default visibility. Python: `@dataclass` writes the `__init__` and equality
boilerplate for an ordinary class. Rust and C++ structs are memory layouts fixed at compile time
with no field names left at runtime; a Python object carries a dictionary looked up by name while
the program runs.
