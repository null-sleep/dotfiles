"""unittest suite for animal.py — mirrors animal_test.go. Stdlib unittest
(pytest isn't installed); Zed's Python runnables use it via TEST_RUNNER in
zed/.config/zed/settings.json."""

import os
import sys
import unittest

# Zed runs tests from the worktree root as `fixtures.test_animal...`, where
# `import animal` wouldn't resolve without this.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from animal import Cat, Dog, describe, max_value  # noqa: E402


class TestAnimal(unittest.TestCase):
    def test_describe(self):
        dog = Dog("Rex")
        print("describing:", dog.get_name())
        self.assertEqual(describe(dog), "Rex says woof")

    def test_max_value(self):
        self.assertEqual(max_value(3, 7), 7)

    # Deliberately failing — confirms a red result and failure output render,
    # not just green ones. Delete once you've seen it fail.
    def test_sound_is_wrong(self):
        self.assertEqual(Cat("Whiskers").sound(), "moo")


if __name__ == "__main__":
    unittest.main()
