//! Animal/Dog/Cat/Bird demo — mirrors animal.go, for exploring aerial.nvim's
//! outline. Rust methods live inside an `impl` block, which is real lexical
//! containment (unlike Go's methods, which sit outside the struct entirely) —
//! this is the interesting middle ground: does aerial nest a method under its
//! `impl Dog { ... }` block? (Bird has two impl blocks — inherent + trait —
//! to see how aerial handles both under one struct.)

trait Animal {
    fn sound(&self) -> String;
    fn name(&self) -> String;
}

struct Dog {
    name: String,
}

impl Animal for Dog {
    fn sound(&self) -> String {
        "woof".to_string()
    }

    fn name(&self) -> String {
        self.name.clone()
    }
}

struct Cat {
    name: String,
}

impl Animal for Cat {
    fn sound(&self) -> String {
        "meow".to_string()
    }

    fn name(&self) -> String {
        self.name.clone()
    }
}

struct Bird {
    name: String,
}

impl Bird {
    fn fly(&self) -> String {
        format!("{} flies away", self.name)
    }
}

impl Animal for Bird {
    fn sound(&self) -> String {
        "tweet".to_string()
    }

    fn name(&self) -> String {
        self.name.clone()
    }
}

fn describe(animal: &dyn Animal) -> String {
    format!("{} says {}", animal.name(), animal.sound())
}

/// Composition: holds a Vec of boxed Animals, like Go's Zoo struct.
struct Zoo {
    animals: Vec<Box<dyn Animal>>,
}

impl Zoo {
    fn describe(&self) -> String {
        let mut out = String::new();
        for animal in &self.animals {
            out += &describe(animal.as_ref());
            out += "\n";
        }
        out
    }
}

/// Generic function — Rust's real type-parameter syntax.
fn max_value<T: PartialOrd>(a: T, b: T) -> T {
    if a > b {
        a
    } else {
        b
    }
}

fn main() {
    let dog = Dog { name: "Rex".to_string() };
    let cat = Cat { name: "Whiskers".to_string() };
    let bird = Bird { name: "Tweety".to_string() };

    println!("{}", dog.sound());
    println!("{}", cat.sound());
    println!("{}", bird.fly());

    println!("{}", describe(&dog));
    println!("{}", describe(&cat));
    println!("{}", describe(&bird));

    // Closure assigned to a local binding — like Go's anonymous func in main.
    let greet = |animal: &dyn Animal| format!("Hello, {}!", animal.name());
    println!("{}", greet(&dog));

    let zoo = Zoo {
        animals: vec![Box::new(dog), Box::new(cat), Box::new(bird)],
    };
    print!("{}", zoo.describe());

    println!("max_value(3, 7) = {}", max_value(3, 7));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_describe() {
        let dog = Dog { name: "Rex".to_string() };
        println!("describing: {}", dog.name()); // shows with --nocapture
        assert_eq!(describe(&dog), "Rex says woof");
    }

    #[test]
    fn test_max_value() {
        assert_eq!(max_value(3, 7), 7);
    }

    // Deliberately failing — confirms a red result and failure output render,
    // not just green ones. Delete once you've seen it fail.
    #[test]
    fn test_sound_is_wrong() {
        let cat = Cat { name: "Whiskers".to_string() };
        assert_eq!(cat.sound(), "moo");
    }
}
