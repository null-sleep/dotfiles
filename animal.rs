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

    dog.sound();
    cat.sound();
    bird.fly();

    describe(&dog);
    describe(&cat);
    describe(&bird);

    // Closure assigned to a local binding — like Go's anonymous func in main.
    let greet = |animal: &dyn Animal| format!("Hello, {}!", animal.name());
    greet(&dog);

    let zoo = Zoo {
        animals: vec![Box::new(dog), Box::new(cat), Box::new(bird)],
    };
    zoo.describe();

    max_value(3, 7);
}
