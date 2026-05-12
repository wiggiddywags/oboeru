import Foundation
import SwiftData

// MARK: - Data model

struct LibraryBundle: Identifiable {
    let id: String
    let title: String
    let description: String
    let authorName: String
    let colorHex: String
    let iconName: String
    let tags: [String]
    let isOfficial: Bool
    let subDecks: [LibrarySubDeck]

    var totalCards: Int { subDecks.reduce(0) { $0 + $1.cards.count } }
}

struct LibrarySubDeck {
    let title: String
    let colorHex: String
    let iconName: String
    let cards: [LibraryCard]
}

struct LibraryCard {
    let front: String
    let back: String
    let tags: [String]
}

// MARK: - Service

enum LibraryService {

    // MARK: - All available bundles

    static let allBundles: [LibraryBundle] = [pythonBundle]

    // MARK: - Install

    /// Creates the parent deck + sub-decks + cards in modelContext.
    @MainActor
    static func install(_ bundle: LibraryBundle, into modelContext: ModelContext, nextSortOrder: Int) throws {
        let parent = Deck(name: bundle.title, colorHex: bundle.colorHex, iconName: bundle.iconName)
        parent.libraryBundleID = bundle.id
        parent.sortOrder = nextSortOrder
        modelContext.insert(parent)

        for (i, sub) in bundle.subDecks.enumerated() {
            let child = Deck(name: sub.title, colorHex: sub.colorHex, iconName: sub.iconName, parentDeckID: parent.id)
            child.libraryBundleID = bundle.id
            child.sortOrder = i
            modelContext.insert(child)

            for lc in sub.cards {
                let card = OboerCard(deck: child, cardType: .basic, frontText: lc.front, backText: lc.back)
                card.tags = lc.tags
                modelContext.insert(card)
            }
        }
        try modelContext.save()
    }

    // MARK: - Python bundle

    static let pythonBundle = LibraryBundle(
        id: "oboeru.official.python",
        title: "Python",
        description: "A comprehensive four-level Python deck — from first print() to CPython internals. Made by the Oboeru team.",
        authorName: "Oboeru Team",
        colorHex: "#3776AB",
        iconName: "chevron.left.forwardslash.chevron.right",
        tags: ["programming", "python", "computer-science"],
        isOfficial: true,
        subDecks: [beginnerSubDeck, intermediateSubDeck, advancedSubDeck, pythonLordSubDeck]
    )

    // MARK: ── Beginner

    private static let beginnerSubDeck = LibrarySubDeck(
        title: "Beginner",
        colorHex: "#51CF66",
        iconName: "1.circle.fill",
        cards: [
            LibraryCard(
                front: "What is Python, and what makes it distinctive?",
                back: """
                Python is a high-level, interpreted, dynamically-typed language created by Guido van Rossum (1991).

                Key traits:
                • Readable syntax using indentation (no braces)
                • "Batteries included" standard library
                • Multi-paradigm: procedural, OOP, functional
                • Large ecosystem (pip, PyPI)

                📖 docs.python.org/3/tutorial/
                """,
                tags: ["basics", "intro"]
            ),
            LibraryCard(
                front: "What are Python's built-in numeric types?",
                back: """
                • int — arbitrary-precision whole numbers: 42, -7, 10_000_000
                • float — IEEE-754 double: 3.14, 1e10
                • complex — a+bj notation: 3+4j
                • bool — subclass of int; True == 1, False == 0

                int has no overflow. float has precision limits (0.1 + 0.2 ≠ 0.3).
                Use decimal.Decimal for exact decimal arithmetic.
                """,
                tags: ["basics", "types"]
            ),
            LibraryCard(
                front: "What is the difference between `/` and `//` in Python?",
                back: """
                / — true division, always returns float
                  7 / 2  →  3.5

                // — floor division, rounds toward −∞
                  7 // 2  →  3
                 -7 // 2  →  -4  ⚠️ not -3!

                % — modulo (remainder after //)
                  7 % 3  →  1
                """,
                tags: ["basics", "operators"]
            ),
            LibraryCard(
                front: "What is an f-string and why should you prefer it?",
                back: """
                f-strings (Python 3.6+) embed expressions directly in string literals:

                name = "Alice"
                age  = 30
                f"Hello, {name}! You are {age} years old."

                Supports expressions: f"{2 ** 10}"  →  "1024"
                Formatting:          f"{3.14159:.2f}"  →  "3.14"
                Debug (3.8+):        f"{name=}"  →  "name='Alice'"

                Faster than .format() and % formatting.
                📖 realpython.com/python-f-strings/
                """,
                tags: ["strings", "formatting"]
            ),
            LibraryCard(
                front: "What is the difference between a list and a tuple?",
                back: """
                List  [1, 2, 3]  — mutable, variable length
                Tuple (1, 2, 3)  — immutable after creation

                Use tuples when:
                • Data should not change (coordinates, RGB values)
                • As dict keys (tuples are hashable, lists are not)
                • Returning multiple values from a function

                Tuples are slightly faster and use less memory.
                Single-element tuple needs trailing comma: (42,)
                """,
                tags: ["data-structures", "lists", "tuples"]
            ),
            LibraryCard(
                front: "How does list slicing work?",
                back: """
                Syntax: list[start:stop:step]
                • start — inclusive (default 0)
                • stop  — exclusive (default len)
                • step  — stride (default 1)

                a = [0, 1, 2, 3, 4, 5]
                a[1:4]    →  [1, 2, 3]
                a[::2]    →  [0, 2, 4]
                a[::-1]   →  [5, 4, 3, 2, 1, 0]  ← reverses
                a[-2:]    →  [4, 5]               ← last two

                Slicing never raises IndexError.
                """,
                tags: ["lists", "slicing"]
            ),
            LibraryCard(
                front: "What is a Python dictionary?",
                back: """
                A mutable mapping of key → value pairs. Keys must be hashable.

                d = {"name": "Alice", "age": 30}
                d["name"]          →  "Alice"
                d.get("missing", 0) →  0          ← safe lookup
                d["new"] = 99      # insert/update
                "age" in d         →  True

                Key operations: .keys(), .values(), .items(), .update(), .pop()

                O(1) average lookup. Maintains insertion order (Python 3.7+).
                """,
                tags: ["data-structures", "dict"]
            ),
            LibraryCard(
                front: "What is the difference between `==` and `is`?",
                back: """
                == checks VALUE equality  (calls __eq__)
                is checks IDENTITY (same object in memory)

                a = [1, 2, 3]
                b = [1, 2, 3]
                a == b  →  True   ✓ same values
                a is b  →  False  ✗ different objects

                Use is only for:
                • None checks:  if x is None:
                • Singleton comparisons

                ⚠️ Small ints (-5 to 256) and interned strings may share identity — don't rely on it.
                """,
                tags: ["basics", "comparison"]
            ),
            LibraryCard(
                front: "What are Python's falsy values?",
                back: """
                These all evaluate to False in a boolean context:

                False     None      0       0.0     0j
                ""        []        {}      ()      set()
                b""       range(0)

                Everything else is truthy, including:
                • "0"  (non-empty string)
                • [0]  (non-empty list)
                • -1   (non-zero number)

                Idiomatic: if not my_list:  instead of  if len(my_list) == 0:
                """,
                tags: ["basics", "truthiness"]
            ),
            LibraryCard(
                front: "What is a list comprehension?",
                back: """
                A concise way to build a list from an iterable.

                [expression  for item in iterable  if condition]

                Examples:
                [x**2 for x in range(10)]
                # [0, 1, 4, 9, 16, 25, 36, 49, 64, 81]

                [x for x in range(20) if x % 3 == 0]
                # [0, 3, 6, 9, 12, 15, 18]

                Nested: [r*c for r in rows for c in cols]

                Prefer comprehensions over map/filter for readability.
                """,
                tags: ["comprehensions", "lists"]
            ),
            LibraryCard(
                front: "What is `enumerate()` and when should you use it?",
                back: """
                Returns (index, value) pairs when iterating.

                # Instead of:
                for i in range(len(items)):
                    print(i, items[i])

                # Do this:
                for i, item in enumerate(items):
                    print(i, item)

                Optional start:
                for i, item in enumerate(items, start=1):
                    print(f"{i}. {item}")

                More Pythonic, avoids off-by-one errors.
                """,
                tags: ["iteration", "builtins"]
            ),
            LibraryCard(
                front: "What does `zip()` do?",
                back: """
                Pairs up elements from multiple iterables:

                names  = ["Alice", "Bob", "Carol"]
                scores = [95, 87, 92]

                list(zip(names, scores))
                # [("Alice",95), ("Bob",87), ("Carol",92)]

                Stops at the shortest iterable.
                Use zip_longest (itertools) to pad with a fill value.

                Unzip: names, scores = zip(*pairs)
                """,
                tags: ["iteration", "builtins"]
            ),
            LibraryCard(
                front: "What is a set in Python and what is it good for?",
                back: """
                An unordered collection of UNIQUE hashable elements.

                s = {1, 2, 3, 3, 2}  →  {1, 2, 3}
                s = set()            # empty set (not {})

                Operations:
                | union        & intersection
                - difference   ^ symmetric difference

                Best uses:
                • Deduplication:  unique = list(set(items))
                • Membership test: O(1) vs O(n) for lists
                • Set math on groups of IDs

                ⚠️ No guaranteed order, no duplicate values.
                """,
                tags: ["data-structures", "sets"]
            ),
            LibraryCard(
                front: "How do default arguments work, and what is the mutable default pitfall?",
                back: """
                Default values are evaluated ONCE at function definition time:

                # ⚠️ BUG — the same list is reused across calls:
                def append_to(item, lst=[]):
                    lst.append(item)
                    return lst

                append_to(1)  →  [1]
                append_to(2)  →  [1, 2]  ← surprise!

                # ✓ Fix — use None as sentinel:
                def append_to(item, lst=None):
                    if lst is None:
                        lst = []
                    lst.append(item)
                    return lst
                """,
                tags: ["functions", "gotchas"]
            ),
            LibraryCard(
                front: "What is `*args` and `**kwargs`?",
                back: """
                *args   — collects extra positional args into a tuple
                **kwargs — collects extra keyword args into a dict

                def func(*args, **kwargs):
                    print(args)   # (1, 2, 3)
                    print(kwargs) # {"a": 4, "b": 5}

                func(1, 2, 3, a=4, b=5)

                Unpack when calling:
                func(*my_list, **my_dict)

                Order rule: positional, *args, keyword-only, **kwargs
                """,
                tags: ["functions", "arguments"]
            ),
            LibraryCard(
                front: "What is the difference between `append()`, `extend()`, and `insert()`?",
                back: """
                append(x)    — adds x as ONE new element at the end
                extend(iter) — adds EACH element of iter at the end
                insert(i, x) — inserts x before index i

                a = [1, 2]
                a.append([3, 4])   →  [1, 2, [3, 4]]  ← nested list
                a.extend([3, 4])   →  [1, 2, 3, 4]     ← flat
                a.insert(1, 99)    →  [1, 99, 2, 3, 4]

                Remove: a.pop()   removes & returns last
                        a.remove(x) removes first occurrence of x
                """,
                tags: ["lists", "methods"]
            ),
            LibraryCard(
                front: "How do `range()`, `for`, and `while` loops compare?",
                back: """
                range(stop)              → 0 .. stop-1
                range(start, stop)       → start .. stop-1
                range(start, stop, step) → with stride

                for x in range(5):  → 0 1 2 3 4

                while condition:    → runs until False; needs manual increment

                Loop control:
                break     → exit the loop immediately
                continue  → skip to next iteration
                else:     → runs if loop completed without break (rare but useful)
                """,
                tags: ["control-flow", "loops"]
            ),
            LibraryCard(
                front: "What are Python's most useful string methods?",
                back: """
                s.upper() / .lower()      case conversion
                s.strip() / .lstrip() / .rstrip()   trim whitespace/chars
                s.split(sep)              split into list
                sep.join(iterable)        join list into string
                s.replace(old, new)       substitution
                s.startswith(prefix)      boolean check
                s.endswith(suffix)        boolean check
                s.find(sub)               index or -1
                s.count(sub)              occurrences
                s.isdigit() / .isalpha()  character class
                s.zfill(width)            zero-pad

                📖 docs.python.org/3/library/stdtypes.html#string-methods
                """,
                tags: ["strings", "methods"]
            ),
            LibraryCard(
                front: "What is `None` and how should you check for it?",
                back: """
                None is Python's null / absence-of-value singleton.
                Type: NoneType. Only one instance ever exists.

                Functions return None implicitly when no return statement.

                ✓ Correct check:
                if x is None:
                if x is not None:

                ✗ Avoid:
                if x == None:   # works but misleading; == can be overridden

                Common uses:
                • Sentinel / missing value
                • Optional function parameters (def f(x=None))
                • Uninitialized state
                """,
                tags: ["basics", "none"]
            ),
            LibraryCard(
                front: "How does `open()` and file I/O work?",
                back: """
                with open("file.txt", "r") as f:
                    content = f.read()        # whole file as string
                    lines   = f.readlines()   # list of lines
                    # or iterate: for line in f:

                Modes:
                "r"   read (default)    "w"  write (truncates)
                "a"   append            "x"  exclusive create
                "rb"  binary read       "wb" binary write

                The with statement guarantees f.close() even on exceptions.

                Write: f.write("hello\n")
                       f.writelines(list_of_strings)
                """,
                tags: ["file-io", "basics"]
            ),
            LibraryCard(
                front: "What is `__name__ == '__main__'` and why use it?",
                back: """
                __name__ is set by Python:
                • '__main__'     when the file is run directly
                • The module name when it's imported

                Idiom:
                def main():
                    ...

                if __name__ == '__main__':
                    main()

                Why? Code inside the guard only runs when you
                execute the file directly — not when another
                module imports it. Prevents side effects on import.
                """,
                tags: ["modules", "best-practices"]
            ),
            LibraryCard(
                front: "What is `pass`, and when do you need it?",
                back: """
                pass is a no-op statement — it does nothing.

                Required wherever Python expects an indented block
                but you have nothing to put there yet:

                class MyError(Exception): pass

                def stub(): pass

                if condition:
                    pass   # TODO: implement
                else:
                    handle()

                Also used to silence exception branches:
                try:
                    risky()
                except SomeError:
                    pass
                """,
                tags: ["basics", "syntax"]
            ),
            LibraryCard(
                front: "What is `type()` and `isinstance()`?",
                back: """
                type(obj)             → exact type
                isinstance(obj, T)    → True if obj is T or subclass of T

                type("hello")         → <class 'str'>
                type(42)              → <class 'int'>

                isinstance(True, int) → True  ← bool IS an int
                isinstance(42, (int, float)) → True  ← tuple of types

                Prefer isinstance() over type() == X in most cases:
                it respects inheritance and is the Pythonic check.
                """,
                tags: ["basics", "types", "introspection"]
            ),
            LibraryCard(
                front: "How does Python handle variable scope? (LEGB rule)",
                back: """
                Python looks up names in this order:

                L — Local (inside current function)
                E — Enclosing (outer function, for nested funcs)
                G — Global (module level)
                B — Built-in (len, print, range, …)

                global x  — declares x refers to module-level x
                nonlocal x — declares x refers to enclosing scope x

                ⚠️ Pitfall: assigning to x inside a function makes
                it local even if a global x exists:
                  x = 10
                  def f(): print(x); x = 20  # UnboundLocalError!
                """,
                tags: ["scope", "functions"]
            ),
            LibraryCard(
                front: "What is `help()` and how do you explore the Python REPL?",
                back: """
                help(obj)       → full docstring and signature
                help("topic")   → topic from docs
                dir(obj)        → list of attributes/methods
                type(obj)       → class of object
                vars(obj)       → __dict__ of object

                In the REPL:
                >>> import os
                >>> help(os.path.join)
                >>> dir([])

                Also useful: id(obj), callable(obj), hasattr(obj, "name")

                The REPL is your best friend for exploration —
                try things interactively before writing scripts.
                """,
                tags: ["tools", "repl", "basics"]
            ),
        ]
    )

    // MARK: ── Intermediate

    private static let intermediateSubDeck = LibrarySubDeck(
        title: "Intermediate",
        colorHex: "#FF922B",
        iconName: "2.circle.fill",
        cards: [
            LibraryCard(
                front: "What is a Python class and how does OOP work?",
                back: """
                class Dog:
                    species = "Canis familiaris"   # class attribute

                    def __init__(self, name, age):  # constructor
                        self.name = name            # instance attributes
                        self.age  = age

                    def bark(self):
                        return f"{self.name} says Woof!"

                d = Dog("Rex", 3)
                d.bark()  →  "Rex says Woof!"

                self always refers to the current instance.
                📖 realpython.com/python3-object-oriented-programming/
                """,
                tags: ["oop", "classes"]
            ),
            LibraryCard(
                front: "How does inheritance work in Python?",
                back: """
                class Animal:
                    def __init__(self, name): self.name = name
                    def speak(self): raise NotImplementedError

                class Dog(Animal):               # inherits Animal
                    def speak(self): return "Woof"

                class Cat(Animal):
                    def speak(self): return "Meow"

                d = Dog("Rex")
                d.name    →  "Rex"     ← inherited attribute
                d.speak() →  "Woof"    ← overridden method

                super().__init__(name)  — call parent's method explicitly
                Multiple inheritance: class C(A, B): ...
                """,
                tags: ["oop", "inheritance"]
            ),
            LibraryCard(
                front: "What is a decorator and how do you write one?",
                back: """
                A decorator wraps a function to add behavior.

                def timer(func):
                    import time
                    def wrapper(*args, **kwargs):
                        t0 = time.time()
                        result = func(*args, **kwargs)
                        print(f"{func.__name__} took {time.time()-t0:.3f}s")
                        return result
                    return wrapper

                @timer
                def slow():
                    time.sleep(0.5)

                # @timer is syntactic sugar for: slow = timer(slow)

                Use functools.wraps(func) inside wrapper to
                preserve the original function's metadata.
                📖 realpython.com/primer-on-python-decorators/
                """,
                tags: ["decorators", "functions"]
            ),
            LibraryCard(
                front: "What is the `@property` decorator?",
                back: """
                Turns a method into a read-only attribute.

                class Circle:
                    def __init__(self, radius):
                        self._radius = radius

                    @property
                    def area(self):
                        return 3.14159 * self._radius ** 2

                    @area.setter
                    def area(self, value):
                        self._radius = (value / 3.14159) ** 0.5

                c = Circle(5)
                c.area         →  78.54   ← no () needed
                c.area = 50    →  sets radius

                Encapsulates computed attributes cleanly.
                """,
                tags: ["oop", "decorators", "property"]
            ),
            LibraryCard(
                front: "What is a generator function and why use one?",
                back: """
                A function that yields values one at a time, lazily.

                def fibonacci():
                    a, b = 0, 1
                    while True:
                        yield a
                        a, b = b, a + b

                fib = fibonacci()
                next(fib)  →  0
                next(fib)  →  1
                next(fib)  →  1
                next(fib)  →  2

                Why: infinite sequences, huge datasets, pipeline stages.
                Memory: holds only current state (vs full list in RAM).

                Generator expression: (x**2 for x in range(1000000))
                📖 realpython.com/introduction-to-python-generators/
                """,
                tags: ["generators", "iteration"]
            ),
            LibraryCard(
                front: "What is a context manager and how do you write one?",
                back: """
                Manages setup/teardown with the `with` statement.
                Guarantees cleanup even if an exception occurs.

                Protocol: __enter__ → setup, __exit__ → teardown

                # Using contextlib (easiest):
                from contextlib import contextmanager

                @contextmanager
                def managed_resource():
                    resource = acquire()
                    try:
                        yield resource      ← the "as" value
                    finally:
                        release(resource)   ← always runs

                with managed_resource() as r:
                    use(r)
                """,
                tags: ["context-managers", "with"]
            ),
            LibraryCard(
                front: "How does exception handling work?",
                back: """
                try:
                    risky_operation()
                except ValueError as e:
                    print(f"Value error: {e}")
                except (TypeError, KeyError):
                    print("Type or key error")
                except Exception as e:
                    print(f"Unexpected: {e}")
                    raise              ← re-raise
                else:
                    print("No exception")   ← runs if no exception
                finally:
                    print("Always runs")    ← cleanup

                Raise: raise ValueError("bad input")
                Custom: class MyError(Exception): pass
                """,
                tags: ["exceptions", "error-handling"]
            ),
            LibraryCard(
                front: "What are `@staticmethod` and `@classmethod`?",
                back: """
                Regular method:  receives self (instance)
                @classmethod:    receives cls (class itself)
                @staticmethod:   receives nothing special

                class Pizza:
                    def __init__(self, size): self.size = size

                    @classmethod
                    def large(cls):      # factory method
                        return cls(12)

                    @staticmethod
                    def is_valid_size(n):  # utility, no self/cls
                        return n > 0

                Pizza.large()            →  Pizza(size=12)
                Pizza.is_valid_size(10)  →  True
                """,
                tags: ["oop", "classmethod", "staticmethod"]
            ),
            LibraryCard(
                front: "What are `__str__` and `__repr__`?",
                back: """
                __repr__  — unambiguous; for developers (REPL, logging)
                           Ideally eval-able: repr(obj) → valid Python
                __str__   — readable; for end users (print())

                class Point:
                    def __init__(self, x, y):
                        self.x, self.y = x, y
                    def __repr__(self):
                        return f"Point({self.x}, {self.y})"
                    def __str__(self):
                        return f"({self.x}, {self.y})"

                p = Point(1, 2)
                repr(p)  →  "Point(1, 2)"
                print(p) →  "(1, 2)"

                Implement __repr__ first; __str__ falls back to it.
                """,
                tags: ["oop", "dunder-methods"]
            ),
            LibraryCard(
                front: "What is a lambda function?",
                back: """
                An anonymous single-expression function.

                square = lambda x: x ** 2
                square(5)  →  25

                Best for short callbacks:
                sorted(people, key=lambda p: p.age)
                sorted(data,   key=lambda x: (x[1], x[0]))

                filter(lambda x: x > 0, nums)
                map(lambda x: x * 2, nums)

                ⚠️ Avoid complex lambdas — use def instead.
                Lambdas can't contain statements, only expressions.
                """,
                tags: ["functions", "lambda"]
            ),
            LibraryCard(
                front: "What are dict and set comprehensions?",
                back: """
                Dict comprehension:
                {k: v for k, v in pairs}
                {name: score for name, score in zip(names, scores) if score >= 60}

                Set comprehension:
                {x**2 for x in range(10)}   →  {0, 1, 4, 9, 16, 25, 36, 49, 64, 81}

                Invert a dict:
                inverted = {v: k for k, v in original.items()}

                All comprehension forms are O(n) and more readable
                than equivalent for-loop accumulation patterns.
                """,
                tags: ["comprehensions", "dict", "sets"]
            ),
            LibraryCard(
                front: "What is `collections.defaultdict`?",
                back: """
                A dict subclass that creates default values for missing keys.

                from collections import defaultdict

                counts = defaultdict(int)
                counts["a"] += 1   ← no KeyError; starts at 0

                groups = defaultdict(list)
                for word in words:
                    groups[word[0]].append(word)
                # groups["a"] →  ["apple", "avocado", ...]

                Common factories: int, list, set, str, lambda: 42

                Alternative: dict.setdefault(key, [])
                             dict.get(key, default)
                """,
                tags: ["collections", "dict"]
            ),
            LibraryCard(
                front: "What is `collections.Counter`?",
                back: """
                A dict subclass for counting hashable objects.

                from collections import Counter

                c = Counter("mississippi")
                # Counter({'i':4, 's':4, 'p':2, 'm':1})

                c.most_common(2)    →  [('i',4), ('s',4)]
                c["i"]             →  4
                c["z"]             →  0   ← no KeyError!

                Counter arithmetic:
                c1 + c2   union
                c1 - c2   subtract (drops zero/negative)
                c1 & c2   min of each count
                c1 | c2   max of each count
                """,
                tags: ["collections", "counter"]
            ),
            LibraryCard(
                front: "What is `functools.lru_cache`?",
                back: """
                Memoization decorator — caches return values by input.

                from functools import lru_cache

                @lru_cache(maxsize=None)
                def fib(n):
                    if n < 2: return n
                    return fib(n-1) + fib(n-2)

                fib(100)  →  instantly (vs exponential without cache)

                @cache (Python 3.9+) is equivalent to lru_cache(maxsize=None)

                Cache info: fib.cache_info()
                Clear:      fib.cache_clear()

                ⚠️ Arguments must be hashable. Don't cache functions
                with mutable arguments or side effects.
                """,
                tags: ["functools", "performance", "caching"]
            ),
            LibraryCard(
                front: "What are type hints and how do you use them?",
                back: """
                Optional annotations (Python 3.5+). Don't affect runtime.

                def greet(name: str, times: int = 1) -> str:
                    return (name + " ") * times

                Variable annotation:
                x: int = 42
                items: list[str] = []

                Common types:
                str, int, float, bool, None
                list[int], dict[str, int], tuple[int, ...]
                Optional[str]  =  str | None  (3.10+)
                Union[int, str] = int | str   (3.10+)
                Any            — opts out of checking

                Check with: mypy, pyright, pylance
                📖 mypy.readthedocs.io
                """,
                tags: ["type-hints", "typing"]
            ),
            LibraryCard(
                front: "What is `@dataclass`?",
                back: """
                Auto-generates __init__, __repr__, __eq__ from annotations.

                from dataclasses import dataclass, field

                @dataclass
                class Point:
                    x: float
                    y: float
                    label: str = "origin"
                    tags: list = field(default_factory=list)

                p = Point(1.0, 2.0)
                p   →  Point(x=1.0, y=2.0, label='origin', tags=[])
                p == Point(1.0, 2.0)  →  True

                Options:
                frozen=True  →  immutable (hashable)
                order=True   →  adds <, >, <=, >=
                slots=True   →  uses __slots__ (3.10+)
                """,
                tags: ["dataclasses", "oop"]
            ),
            LibraryCard(
                front: "What is `nonlocal` and when do you need it?",
                back: """
                Lets a nested function rebind a variable from its enclosing scope.

                def make_counter():
                    count = 0
                    def increment():
                        nonlocal count   ← without this: UnboundLocalError
                        count += 1
                        return count
                    return increment

                c = make_counter()
                c()  →  1
                c()  →  2

                Without nonlocal, assignment creates a NEW local variable;
                the enclosing count is untouched (and reading before
                assignment raises UnboundLocalError).
                """,
                tags: ["closures", "scope"]
            ),
            LibraryCard(
                front: "What does `itertools` provide?",
                back: """
                Standard library module for efficient, lazy iterators.

                chain(a, b)           →  concatenate iterables
                islice(it, n)         →  take first n items
                cycle(it)             →  repeat infinitely
                repeat(x, n)          →  repeat x n times
                product(a, b)         →  cartesian product
                permutations(it, r)   →  ordered arrangements
                combinations(it, r)   →  unordered arrangements
                groupby(it, key)      →  group consecutive equal items
                accumulate(it, func)  →  running total/product
                pairwise(it)          →  (a,b), (b,c), ... (3.10+)

                All are lazy — perfect for large data pipelines.
                📖 docs.python.org/3/library/itertools.html
                """,
                tags: ["itertools", "iteration"]
            ),
            LibraryCard(
                front: "What is unpacking and when should you use it?",
                back: """
                Destructuring an iterable into named variables.

                a, b, c = [1, 2, 3]
                first, *rest = [1, 2, 3, 4, 5]
                # first=1, rest=[2,3,4,5]

                *init, last = range(5)
                # init=[0,1,2,3], last=4

                Swap without temp variable:
                a, b = b, a

                Function call unpack:
                args = [1, 2]
                func(*args, **{"key": "val"})

                Named tuple / dataclass:
                x, y = Point(1, 2)   ← if iterable

                Use for clarity; avoid deeply nested destructuring.
                """,
                tags: ["syntax", "unpacking"]
            ),
            LibraryCard(
                front: "What is `copy` vs `deepcopy`?",
                back: """
                import copy

                Shallow copy: copies the container, not nested objects.
                New container → same inner object references.

                original = [[1, 2], [3, 4]]
                shallow  = copy.copy(original)
                shallow[0].append(99)
                original  →  [[1, 2, 99], [3, 4]]  ← mutated!

                Deep copy: recursively copies everything.
                deep = copy.deepcopy(original)
                deep[0].append(99)
                original  →  [[1, 2], [3, 4]]  ← untouched

                Shallow: list[:], list.copy(), dict.copy()
                Deep:    copy.deepcopy(obj)
                """,
                tags: ["data-structures", "copy"]
            ),
            LibraryCard(
                front: "What is `__slots__` and when should you use it?",
                back: """
                Replaces the per-instance __dict__ with a fixed set of
                C-level slot descriptors.

                class Point:
                    __slots__ = ("x", "y")
                    def __init__(self, x, y):
                        self.x, self.y = x, y

                Benefits:
                • ~40–50% less memory per instance
                • Faster attribute access
                • Prevents accidental new attributes

                Downsides:
                • No __dict__ → no dynamic attributes
                • Inheritance tricky: parent must also use __slots__
                • Pickling needs extra care

                Use when creating millions of instances (e.g. graph nodes).
                """,
                tags: ["oop", "memory", "slots"]
            ),
            LibraryCard(
                front: "What are `__enter__` and `__exit__`?",
                back: """
                The context manager protocol. Implement them to use
                your class with the `with` statement.

                class Timer:
                    def __enter__(self):
                        import time
                        self.start = time.time()
                        return self              ← bound to `as` target

                    def __exit__(self, exc_type, exc_val, tb):
                        elapsed = time.time() - self.start
                        print(f"Elapsed: {elapsed:.3f}s")
                        return False             ← don't suppress exceptions

                with Timer() as t:
                    slow_operation()

                Return True from __exit__ to suppress exceptions.
                """,
                tags: ["context-managers", "dunder-methods"]
            ),
            LibraryCard(
                front: "What is `__init__.py` and what should go in it?",
                back: """
                Makes a directory a Python package (importable module).

                my_package/
                  __init__.py
                  utils.py
                  models.py

                What to put in it:
                • Nothing (empty is fine and common)
                • Re-export public API:
                    from .utils import helper_func
                    from .models import User
                • Package-level __all__ = ["helper_func", "User"]
                • Version: __version__ = "1.0.0"

                Python 3 namespace packages don't require __init__.py,
                but it's still needed for explicit package semantics.
                """,
                tags: ["modules", "packages"]
            ),
            LibraryCard(
                front: "What is `functools.partial`?",
                back: """
                Creates a new callable with some arguments pre-filled.

                from functools import partial

                def power(base, exp):
                    return base ** exp

                square = partial(power, exp=2)
                cube   = partial(power, exp=3)

                square(5)  →  25
                cube(3)    →  27

                Useful for:
                • Adapting functions to callback interfaces
                • Creating specialized versions of general functions
                • Simplifying repeated calls with the same args

                Alternative: lambda x: power(x, 2)  — but partial is clearer.
                """,
                tags: ["functools", "functions"]
            ),
        ]
    )

    // MARK: ── Advanced

    private static let advancedSubDeck = LibrarySubDeck(
        title: "Advanced",
        colorHex: "#CC5DE8",
        iconName: "3.circle.fill",
        cards: [
            LibraryCard(
                front: "What is a closure?",
                back: """
                A function that captures variables from its enclosing scope,
                keeping them alive after the outer function returns.

                def make_multiplier(n):
                    def multiply(x):
                        return x * n    ← captures n from enclosing scope
                    return multiply

                double = make_multiplier(2)
                triple = make_multiplier(3)

                double(5)  →  10
                triple(5)  →  15

                Each call to make_multiplier creates an independent closure.
                Inspect captured vars: double.__closure__[0].cell_contents → 2

                📖 realpython.com/inner-functions-what-are-they-good-for/
                """,
                tags: ["closures", "functions", "advanced"]
            ),
            LibraryCard(
                front: "What is a metaclass?",
                back: """
                The class of a class. `type` is the default metaclass.
                Metaclasses control class CREATION (not instantiation).

                class SingletonMeta(type):
                    _instances = {}
                    def __call__(cls, *args, **kw):
                        if cls not in cls._instances:
                            cls._instances[cls] = super().__call__(*args, **kw)
                        return cls._instances[cls]

                class Config(metaclass=SingletonMeta):
                    pass

                Config() is Config()  →  True

                Used by: Django ORM, SQLAlchemy, ABCs, Pydantic.
                Prefer __init_subclass__ or class decorators for simpler cases.
                📖 realpython.com/python-metaclasses/
                """,
                tags: ["metaclasses", "advanced", "oop"]
            ),
            LibraryCard(
                front: "What is the descriptor protocol?",
                back: """
                Descriptors define __get__, __set__, __delete__ and control
                attribute access on the OWNER CLASS.

                class Validated:
                    def __set_name__(self, owner, name):
                        self.name = name
                    def __get__(self, obj, owner):
                        return obj.__dict__.get(self.name)
                    def __set__(self, obj, value):
                        if not isinstance(value, int):
                            raise TypeError("int required")
                        obj.__dict__[self.name] = value

                class Foo:
                    x = Validated()

                f = Foo()
                f.x = 42    ← calls __set__
                f.x         ← calls __get__
                f.x = "hi"  ← raises TypeError

                property, classmethod, staticmethod are all descriptors.
                """,
                tags: ["descriptors", "advanced", "oop"]
            ),
            LibraryCard(
                front: "What is `async`/`await` and the asyncio event loop?",
                back: """
                Coroutines (async def) run cooperatively — they yield control
                at every await, letting other coroutines run.

                import asyncio

                async def fetch(url):
                    await asyncio.sleep(1)   ← yields control
                    return f"data from {url}"

                async def main():
                    # Run two fetches concurrently:
                    r1, r2 = await asyncio.gather(
                        fetch("url1"),
                        fetch("url2"),
                    )

                asyncio.run(main())

                Single thread, no GIL concerns, but only one coroutine
                runs at a time. Best for I/O-bound tasks (HTTP, DB, files).
                📖 realpython.com/async-io-python/
                """,
                tags: ["async", "asyncio", "concurrency"]
            ),
            LibraryCard(
                front: "What is the GIL and how does it affect concurrency?",
                back: """
                Global Interpreter Lock — a mutex in CPython that ensures
                only ONE thread executes Python bytecode at a time.

                Impact:
                • CPU-bound threads cannot truly run in parallel → use multiprocessing
                • I/O-bound threads: GIL is released during I/O waits → threads help
                • C extensions (NumPy) can release GIL for true parallelism

                Workarounds:
                • multiprocessing — separate processes, own memory, real parallelism
                • asyncio — cooperative concurrency (no threads, no GIL issue)
                • Jython / GraalPy — no GIL (different implementations)
                • CPython 3.13 — experimental "free-threaded" mode (no GIL)

                📖 realpython.com/python-gil/
                """,
                tags: ["concurrency", "gil", "threading", "advanced"]
            ),
            LibraryCard(
                front: "How does Python's garbage collection work?",
                back: """
                Two mechanisms:

                1. Reference counting (primary):
                   Every object has a refcount. When it hits 0 → deallocated.
                   sys.getrefcount(obj) → count (always +1 for the arg)

                2. Cyclic garbage collector (secondary):
                   Handles reference cycles that refcounting can't detect.
                   import gc; gc.collect() → force a collection pass
                   gc.get_threshold() → (700, 10, 10) — generation thresholds

                Generations 0, 1, 2: young objects promoted on survival.

                ⚠️ __del__ is not reliable — don't use for cleanup.
                Use context managers for deterministic resource release.
                """,
                tags: ["memory", "gc", "advanced"]
            ),
            LibraryCard(
                front: "What is `__getattr__` vs `__getattribute__`?",
                back: """
                __getattribute__(self, name)
                  Called for EVERY attribute access.
                  Override carefully — always call super().__getattribute__(name)
                  or you'll break everything.

                __getattr__(self, name)
                  Called ONLY when normal lookup fails.
                  Safe to override for "magic" dynamic attributes.

                class LazyLoader:
                    def __getattr__(self, name):
                        module = import_module(name)
                        setattr(self, name, module)  ← cache it
                        return module

                Use __getattr__ for: dynamic attributes, lazy loading,
                proxy objects, attribute forwarding.
                """,
                tags: ["oop", "dunder-methods", "advanced"]
            ),
            LibraryCard(
                front: "What is `threading` vs `multiprocessing` vs `asyncio`?",
                back: """
                threading:
                  OS threads, shared memory, GIL-limited
                  Best for: I/O-bound tasks (HTTP, disk, DB)

                multiprocessing:
                  Separate processes, own memory space (no GIL)
                  Best for: CPU-bound tasks (number crunching, image processing)
                  IPC overhead: pipes, queues, shared memory

                asyncio:
                  Single thread, cooperative multitasking
                  Best for: MANY concurrent I/O operations (servers)
                  No GIL concerns; needs async-aware libraries

                Decision tree:
                  Many I/O ops w/ async libs → asyncio
                  I/O, sync libs             → threading
                  CPU-bound                  → multiprocessing

                concurrent.futures provides a unified ThreadPoolExecutor /
                ProcessPoolExecutor API.
                """,
                tags: ["concurrency", "threading", "asyncio", "multiprocessing"]
            ),
            LibraryCard(
                front: "What is `yield from`?",
                back: """
                Delegates to a sub-generator, transparently forwarding
                all values (including .send() and .throw()).

                def chain(*iterables):
                    for it in iterables:
                        yield from it

                list(chain([1,2], [3,4], [5]))  →  [1,2,3,4,5]

                vs manual: for item in it: yield item
                (doesn't forward send/throw/close)

                Also the foundation for async/await:
                  async def foo():      ≈  yield from coro()
                      await coro()

                Use it to compose generators and build pipelines.
                """,
                tags: ["generators", "advanced", "yield"]
            ),
            LibraryCard(
                front: "What is the Method Resolution Order (MRO)?",
                back: """
                The order Python searches for methods in a class hierarchy.
                Uses the C3 linearization algorithm.

                class A: pass
                class B(A): pass
                class C(A): pass
                class D(B, C): pass

                D.__mro__  →  (D, B, C, A, object)

                super() follows MRO — critical for cooperative multiple inheritance.

                class Base:
                    def method(self): print("Base")

                class Mixin:
                    def method(self):
                        super().method()    ← follows MRO, not just direct parent
                        print("Mixin")

                Inspect: ClassName.__mro__ or ClassName.mro()
                """,
                tags: ["oop", "mro", "inheritance", "advanced"]
            ),
            LibraryCard(
                front: "What is Abstract Base Class (ABC)?",
                back: """
                Enforces interface contracts — subclasses MUST implement
                all @abstractmethod methods or instantiation raises TypeError.

                from abc import ABC, abstractmethod

                class Shape(ABC):
                    @abstractmethod
                    def area(self) -> float: ...

                    @abstractmethod
                    def perimeter(self) -> float: ...

                class Circle(Shape):
                    def __init__(self, r): self.r = r
                    def area(self): return 3.14 * self.r**2
                    def perimeter(self): return 2 * 3.14 * self.r

                Shape()   → TypeError (abstract)
                Circle(5) → works ✓

                Virtual subclasses: Shape.register(MyClass)
                """,
                tags: ["abc", "oop", "advanced"]
            ),
            LibraryCard(
                front: "What is `__init_subclass__`?",
                back: """
                Called automatically on the parent class when a
                subclass is defined (Python 3.6+). Simpler than metaclasses.

                class PluginBase:
                    _registry = []

                    def __init_subclass__(cls, **kwargs):
                        super().__init_subclass__(**kwargs)
                        PluginBase._registry.append(cls)

                class PluginA(PluginBase): pass
                class PluginB(PluginBase): pass

                PluginBase._registry  →  [PluginA, PluginB]

                Use for: plugin systems, automatic registration,
                enforcing constraints on subclasses.
                Prefer over metaclasses for most class-customization needs.
                """,
                tags: ["oop", "advanced", "metaclasses"]
            ),
            LibraryCard(
                front: "What is `weakref` and when should you use it?",
                back: """
                A reference to an object that doesn't prevent garbage collection.

                import weakref

                class Cache:
                    def __init__(self): self._data = {}
                    def store(self, obj): self._data[id(obj)] = weakref.ref(obj)
                    def get(self, key):
                        ref = self._data.get(key)
                        return ref() if ref else None   ← returns None if GC'd

                Use cases:
                • Caches that shouldn't keep objects alive
                • Event listeners / observer patterns (prevent memory leaks)
                • Circular reference breaking

                weakref.WeakValueDictionary — auto-removes dead entries
                weakref.WeakSet            — set of weak references
                """,
                tags: ["memory", "weakref", "advanced"]
            ),
            LibraryCard(
                front: "What is `functools.reduce`?",
                back: """
                Applies a function cumulatively to reduce an iterable to a value.

                from functools import reduce

                reduce(lambda acc, x: acc + x, [1,2,3,4,5])
                # ((((1+2)+3)+4)+5) → 15

                reduce(lambda acc, x: acc * x, range(1, 6))
                # 1*2*3*4*5 → 120  (factorial 5)

                Optional initializer:
                reduce(func, iterable, initial_value)

                In practice: sum(), max(), min(), any(), all() cover most
                common reduce patterns more readably. Use reduce when you
                have a truly custom accumulation function.
                """,
                tags: ["functools", "functional", "advanced"]
            ),
            LibraryCard(
                front: "What are Python dunder (magic) methods?",
                back: """
                Special methods with __ prefix/suffix that Python calls implicitly.

                Object creation:   __new__, __init__, __del__
                Representation:    __repr__, __str__, __format__
                Comparison:        __eq__, __lt__, __le__, __gt__, __ge__, __hash__
                Arithmetic:        __add__, __sub__, __mul__, __truediv__, __mod__
                Container:         __len__, __getitem__, __setitem__, __contains__
                Iteration:         __iter__, __next__
                Context manager:   __enter__, __exit__
                Callable:          __call__
                Attribute:         __getattr__, __setattr__, __delattr__

                class Vector:
                    def __add__(self, other):
                        return Vector(self.x + other.x, self.y + other.y)

                📖 docs.python.org/3/reference/datamodel.html
                """,
                tags: ["oop", "dunder-methods", "advanced"]
            ),
            LibraryCard(
                front: "What is `memoryview` and why does it matter for performance?",
                back: """
                Exposes the buffer protocol of bytes-like objects WITHOUT copying.

                data = bytearray(b"Hello, World!")
                mv = memoryview(data)

                mv[7:]       →  zero-copy slice
                mv[7:] = b"Python!"   →  in-place modification

                Why it matters:
                • Slicing bytes/bytearray creates a copy — O(n)
                • memoryview slicing is O(1) — just a view
                • Crucial for: networking, binary parsing, image processing

                Works with: bytes, bytearray, array.array, numpy arrays
                struct module can interpret memoryviews directly.
                """,
                tags: ["performance", "memory", "advanced"]
            ),
            LibraryCard(
                front: "What is `__all__` in a module?",
                back: """
                Defines the public API — the names exported by `from module import *`.

                # my_module.py
                __all__ = ["PublicClass", "public_func"]

                def _private_helper(): ...   ← not exported
                def public_func(): ...       ← exported
                class PublicClass: ...       ← exported

                Without __all__, `import *` exports everything not
                prefixed with underscore.

                Best practices:
                • Define __all__ in every public module
                • Use it to document your intended public interface
                • Helps IDE auto-complete and linters
                """,
                tags: ["modules", "best-practices"]
            ),
            LibraryCard(
                front: "What is `asyncio.gather()` vs `asyncio.wait()`?",
                back: """
                gather(*coros):
                  Runs coros concurrently, returns list of results in ORDER.
                  Raises first exception by default (return_exceptions=True to collect all).

                results = await asyncio.gather(fetch(url1), fetch(url2))

                wait(tasks, ...):
                  More control — returns (done, pending) sets.
                  Supports timeout and return_when conditions:
                    FIRST_COMPLETED, FIRST_EXCEPTION, ALL_COMPLETED

                tasks = [asyncio.create_task(f()) for f in funcs]
                done, pending = await asyncio.wait(tasks, timeout=5)

                create_task() schedules a coroutine immediately;
                gather() schedules lazily at the await point.
                """,
                tags: ["asyncio", "concurrency", "advanced"]
            ),
            LibraryCard(
                front: "What is `__slots__` interaction with inheritance?",
                back: """
                If a PARENT has __slots__ but the CHILD does NOT:
                  → Child gets __dict__ anyway. No memory benefit.

                If BOTH have __slots__:
                  → Child __slots__ should only list NEW attributes
                    (not repeat parent's slots).

                class Animal:
                    __slots__ = ("name",)

                class Dog(Animal):
                    __slots__ = ("breed",)  ← don't repeat "name"

                d = Dog()
                d.name  = "Rex"    ← inherited slot
                d.breed = "Lab"    ← own slot
                d.age   = 3        ← AttributeError (no __dict__)

                Mix-in classes with __slots__ = () prevents adding __dict__.
                """,
                tags: ["oop", "slots", "advanced", "inheritance"]
            ),
            LibraryCard(
                front: "What is `contextlib.suppress`?",
                back: """
                A context manager that silences specified exceptions.

                from contextlib import suppress

                # Instead of:
                try:
                    os.remove("file.txt")
                except FileNotFoundError:
                    pass

                # Do this:
                with suppress(FileNotFoundError):
                    os.remove("file.txt")

                Multiple exceptions:
                with suppress(KeyError, AttributeError):
                    do_something()

                Only use when you genuinely don't care about the failure.
                Don't suppress broad exceptions like Exception or BaseException.
                """,
                tags: ["context-managers", "exceptions", "contextlib"]
            ),
        ]
    )

    // MARK: ── Python Lord

    private static let pythonLordSubDeck = LibrarySubDeck(
        title: "Python Lord",
        colorHex: "#F03E3E",
        iconName: "crown.fill",
        cards: [
            LibraryCard(
                front: "What is CPython bytecode and how do you inspect it?",
                back: """
                CPython compiles source → bytecode (.pyc) before interpretation.
                Bytecode is a sequence of 2-byte instructions (opcode + arg).

                import dis

                def add(a, b):
                    return a + b

                dis.dis(add)
                #   RESUME        0
                #   LOAD_FAST     0 (a)
                #   LOAD_FAST     1 (b)
                #   BINARY_OP     0 (+)
                #   RETURN_VALUE

                Key opcodes:
                LOAD_FAST / STORE_FAST — local variables (fastest)
                LOAD_GLOBAL            — global lookup
                CALL                   — function call
                BINARY_OP              — arithmetic/comparison

                dis.Bytecode(func) gives structured object.
                code = func.__code__; code.co_consts, co_varnames, co_code
                """,
                tags: ["cpython", "bytecode", "internals"]
            ),
            LibraryCard(
                front: "How does CPython's reference counting work at the C level?",
                back: """
                Every PyObject has ob_refcnt (Py_ssize_t).

                Py_INCREF(op)  — increment (assignment, arg pass)
                Py_DECREF(op)  — decrement; calls dealloc when 0
                Py_XINCREF/XDECREF — NULL-safe versions

                Python side:
                import sys
                a = []
                sys.getrefcount(a)  →  2  (a + getrefcount arg)
                b = a
                sys.getrefcount(a)  →  3

                Immortal objects (Python 3.12+): None, True, False,
                small ints have ob_refcnt = maxsize (never freed).

                Reference cycles (a.ref = a) are caught by the
                cyclic GC using tri-color mark-and-sweep.
                📖 github.com/python/cpython/blob/main/Objects/object.c
                """,
                tags: ["cpython", "memory", "internals", "gc"]
            ),
            LibraryCard(
                front: "What are Python's concurrency primitives (threading module)?",
                back: """
                threading.Thread(target=f, args=(...)).start()
                threading.Lock()          — mutual exclusion
                threading.RLock()         — reentrant lock (same thread can acquire N times)
                threading.Event()         — set/wait signaling
                threading.Semaphore(n)    — counter-based lock
                threading.Condition()     — wait/notify on shared state
                threading.Barrier(n)      — all n threads must arrive

                Thread-safe queues:
                queue.Queue()     — FIFO
                queue.LifoQueue() — LIFO
                queue.PriorityQueue()

                ThreadPoolExecutor (concurrent.futures) is higher-level:
                with ThreadPoolExecutor(max_workers=8) as ex:
                    futures = [ex.submit(task, arg) for arg in args]
                    results = [f.result() for f in futures]
                """,
                tags: ["threading", "concurrency", "internals"]
            ),
            LibraryCard(
                front: "What is Python's import machinery and how do you customize it?",
                back: """
                import foo resolves in order:
                1. sys.modules cache (return immediately if found)
                2. sys.meta_path finders (list of MetaPathFinder objects)
                3. Each finder's find_spec() → returns ModuleSpec or None
                4. Loader from spec loads/executes the module
                5. Module cached in sys.modules

                Customize with import hooks:
                sys.meta_path.insert(0, MyFinder())  ← first wins

                class MyFinder:
                    def find_spec(self, name, path, target=None):
                        if name == "magic": return spec_from_loader(name, MyLoader())

                importlib.util.spec_from_file_location() — load from arbitrary path
                importlib.import_module(name) — programmatic import

                📖 docs.python.org/3/reference/import.html
                """,
                tags: ["import", "internals", "cpython"]
            ),
            LibraryCard(
                front: "What is `tracemalloc` and how do you find memory leaks?",
                back: """
                Standard library memory allocation tracer.

                import tracemalloc

                tracemalloc.start()
                # ... run your code ...
                snapshot = tracemalloc.take_snapshot()

                top = snapshot.statistics("lineno")
                for stat in top[:5]:
                    print(stat)

                Diff between two snapshots:
                snap1 = tracemalloc.take_snapshot()
                # ... more code ...
                snap2 = tracemalloc.take_snapshot()
                for stat in snap2.compare_to(snap1, "lineno"):
                    print(stat)

                Also useful: objgraph (pip) for reference graphs,
                memory_profiler (pip) for line-by-line memory usage.
                """,
                tags: ["memory", "profiling", "internals"]
            ),
            LibraryCard(
                front: "What is Cython and when should you use it?",
                back: """
                A superset of Python that compiles to C for speed.

                # mymodule.pyx
                def sum_array(double[:] arr):
                    cdef double total = 0.0
                    cdef int i
                    for i in range(len(arr)):
                        total += arr[i]
                    return total

                Compile: cythonize -i mymodule.pyx → .so file
                Import normally: import mymodule

                Speed gains: 10x–100x for tight loops, type-annotated code.
                Used by: NumPy, SciPy, pandas, lxml, gevent.

                When to use:
                ✓ Profiler shows Python loop is bottleneck
                ✓ NumPy vectorization isn't possible
                ✗ I/O-bound (no benefit)
                ✗ First try PyPy, numba, or numpy

                📖 cython.readthedocs.io
                """,
                tags: ["cython", "performance", "c-extensions"]
            ),
            LibraryCard(
                front: "What is PyPy and how does its JIT compiler work?",
                back: """
                PyPy is an alternative CPython implementation written in RPython.

                JIT (Just-In-Time) compilation:
                1. Traces hot execution paths (loops run ≥1000 times)
                2. Compiles trace to machine code
                3. Guards check assumptions; fall back to interpreter if violated

                Speed: 5–10× faster than CPython for CPU-bound code.
                Memory: Often uses MORE memory (JIT metadata overhead).

                Compatibility:
                ✓ Pure Python code
                ✓ Most stdlib
                ✗ C extensions (ctypes works; Cython doesn't)
                ✗ NumPy (use PyPy's numpy port)

                Best for: web servers, compilers, algorithms, text processing.
                Not ideal for: NumPy-heavy scientific code.

                📖 pypy.org/performance.html
                """,
                tags: ["pypy", "performance", "internals"]
            ),
            LibraryCard(
                front: "What is the CPython `__code__` object?",
                back: """
                Every function has a __code__ object containing its compiled bytecode.

                def f(x, y=1):
                    z = x + y
                    return z

                c = f.__code__
                c.co_varnames   →  ('x', 'y', 'z')
                c.co_argcount   →  1  (positional only; y is co_kwonlyargcount)
                c.co_consts     →  (None,)
                c.co_filename   →  '<stdin>'
                c.co_firstlineno→  1
                c.co_stacksize  →  2
                c.co_code       →  raw bytecode bytes

                Immutable — cannot be modified (use code.replace() in 3.8+).

                Applications: profilers, coverage tools, debuggers,
                code instrumentation frameworks.
                """,
                tags: ["cpython", "internals", "bytecode"]
            ),
            LibraryCard(
                front: "What is `ctypes` and when would you use it?",
                back: """
                Standard library for calling C functions from Python without
                writing a C extension.

                import ctypes
                libc = ctypes.CDLL("libc.so.6")  # or "msvcrt" on Windows

                # Define arg/return types
                libc.printf.argtypes = [ctypes.c_char_p]
                libc.printf.restype  = ctypes.c_int
                libc.printf(b"Hello %s\n", b"world")

                Define C structs:
                class Point(ctypes.Structure):
                    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

                Use when:
                • Wrapping existing C libraries (libssl, libcurl, etc.)
                • Calling OS APIs not exposed by stdlib
                • Quick prototyping before writing proper extension

                cffi is a popular alternative with cleaner syntax.
                """,
                tags: ["ctypes", "c-extensions", "internals"]
            ),
            LibraryCard(
                front: "What is `__prepare__` in metaclasses?",
                back: """
                Called BEFORE the class body is executed.
                Returns the namespace dict used to collect class attributes.

                class OrderedMeta(type):
                    @classmethod
                    def __prepare__(mcs, name, bases, **kw):
                        return OrderedDict()   ← custom namespace

                    def __new__(mcs, name, bases, ns):
                        # ns is the OrderedDict from __prepare__
                        cls = super().__new__(mcs, name, bases, dict(ns))
                        cls._field_order = list(ns.keys())
                        return cls

                class Record(metaclass=OrderedMeta):
                    first = "Alice"
                    last  = "Smith"
                    age   = 30

                Record._field_order → ['first', 'last', 'age']

                Used by: Python's own enum.EnumMeta, attrs, dataclasses internals.
                """,
                tags: ["metaclasses", "internals", "advanced"]
            ),
            LibraryCard(
                front: "What is Python's buffer protocol?",
                back: """
                A low-level C-API interface for objects that expose a
                contiguous block of memory (buffer) without copying.

                Objects implementing it: bytes, bytearray, array.array,
                numpy arrays, memoryview.

                Python access via memoryview:
                arr = array.array("d", [1.0, 2.0, 3.0])
                mv  = memoryview(arr)
                mv.format   →  'd'   (C double)
                mv.itemsize →  8
                mv.shape    →  (3,)

                Why it matters:
                • Zero-copy I/O: pass buffer directly to socket.recv_into()
                • NumPy shares memory with C libraries via buffer protocol
                • struct.pack_into() writes directly to a buffer

                📖 docs.python.org/3/c-api/buffer.html
                """,
                tags: ["buffer-protocol", "memory", "internals", "performance"]
            ),
            LibraryCard(
                front: "How do you profile Python code for performance?",
                back: """
                Timing (quick):
                python -m timeit "sum(range(1000))"
                timeit.timeit("expr", number=10000)

                CPU profiling:
                python -m cProfile -s cumtime myscript.py
                import cProfile; cProfile.run("f()")

                Visualize: snakeviz (pip) — flamegraph for cProfile output

                Line-level: line_profiler (pip)
                @profile decorator + kernprof -l script.py

                Memory: memory_profiler (pip), tracemalloc (stdlib)

                Workflow:
                1. Measure first — don't guess
                2. Find the 20% causing 80% of time
                3. Optimize the hotspot
                4. Measure again

                "Premature optimization is the root of all evil" — Knuth
                """,
                tags: ["performance", "profiling", "tools"]
            ),
            LibraryCard(
                front: "What is Python's `__future__` module?",
                back: """
                Imports future language features into current Python versions.
                Must be the first statement in the file (after docstrings/comments).

                from __future__ import annotations
                  → PEP 563: defers annotation evaluation (strings, not objects)
                  → Fixes forward references: class Foo: def method(self) -> Foo

                from __future__ import division         (Python 2 only)
                  → Makes / true division (Python 3 behavior)

                from __future__ import generator_stop   (made default in 3.7)
                from __future__ import unicode_literals (Python 2 only)

                Python 3.12+ deprecated annotations deferral;
                PEP 649 (lazy evaluation) is the new approach.

                The module itself only contains module-level string docs;
                all behavior is implemented in the compiler.
                """,
                tags: ["future", "internals", "language"]
            ),
            LibraryCard(
                front: "What is `sys.intern()` and string interning?",
                back: """
                Interning stores a string in a global table so that
                equal interned strings share the same object (identity).

                a = sys.intern("hello_world")
                b = sys.intern("hello_world")
                a is b  →  True   (same object)

                Python auto-interns:
                • String literals that look like identifiers
                • Strings used as dict keys in source code
                • Small strings at compile time

                Benefits:
                • O(1) identity check instead of O(n) equality for dict keys
                • Reduced memory when many duplicate strings exist

                Use in: parsers, compilers, high-frequency dict keys,
                large datasets with repeated categorical strings.
                """,
                tags: ["internals", "strings", "memory", "performance"]
            ),
            LibraryCard(
                front: "What is Python packaging and the modern `pyproject.toml`?",
                back: """
                Modern Python packages use pyproject.toml (PEP 517/518/660).

                [build-system]
                requires = ["hatchling"]
                build-backend = "hatchling.build"

                [project]
                name = "mypackage"
                version = "1.0.0"
                description = "..."
                dependencies = ["requests>=2.28"]

                [project.scripts]
                mycli = "mypackage.cli:main"

                Build tools: hatch, flit, poetry, setuptools
                Publish: python -m build → wheel + sdist → twine upload

                Install editable: pip install -e .
                Virtual envs: python -m venv .venv (or uv, poetry, pipenv)

                📖 packaging.python.org/tutorials/packaging-projects/
                """,
                tags: ["packaging", "tools", "pyproject"]
            ),
        ]
    )
}
