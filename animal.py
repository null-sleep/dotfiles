"""Animal/Dog/Cat/Bird demo — mirrors animal.go, for exploring aerial.nvim's
outline (same shapes: an interface-like protocol, three concrete types, free
functions, a composed Zoo, a generic-ish helper, and a nested function inside
main)."""

from typing import Protocol


class Animal(Protocol):
    def sound(self) -> str: ...
    def get_name(self) -> str: ...


class Dog:
    def __init__(self, name: str) -> None:
        self.name = name

    def sound(self) -> str:
        return "woof"

    def get_name(self) -> str:
        return self.name


class Cat:
    def __init__(self, name: str) -> None:
        self.name = name

    def sound(self) -> str:
        return "meow"

    def get_name(self) -> str:
        return self.name


class Bird:
    def __init__(self, name: str) -> None:
        self.name = name

    def sound(self) -> str:
        return "tweet"

    def get_name(self) -> str:
        return self.name

    def fly(self) -> str:
        return f"{self.name} flies away"


def describe(animal: Animal) -> str:
    return f"{animal.get_name()} says {animal.sound()}"


class Zoo:
    """Composition: holds a list of Animals, like Go's Zoo struct."""

    def __init__(self, animals: list[Animal]) -> None:
        self.animals = animals

    def describe(self) -> str:
        out = ""
        for animal in self.animals:
            out += describe(animal) + "\n"
        return out


def max_value(a, b):
    """Python has no type-parameter syntax like Go's Max[T] — duck typing covers it."""
    return a if a > b else b


def main() -> None:
    dog = Dog("Rex")
    cat = Cat("Whiskers")
    bird = Bird("Tweety")

    dog.sound()
    cat.sound()
    bird.fly()

    describe(dog)
    describe(cat)
    describe(bird)

    def greet(animal: Animal) -> str:
        """Nested function — unlike Go's anonymous closure, this IS a named
        `def` inside another `def`; worth checking whether aerial nests it."""
        return f"Hello, {animal.get_name()}!"

    greet(dog)

    zoo = Zoo([dog, cat, bird])
    zoo.describe()

    max_value(3, 7)


if __name__ == "__main__":
    main()
