package main

// Animal is an interface
type Animal interface {
	Sound() string
	Name() string
}

// Dog is a concrete implementation
type Dog struct {
	name string
}

// Compile-time checks that Dog and Cat implement Animal
var _ Animal = Dog{}
var _ Animal = Cat{}

func (d Dog) Sound() string {
	return "woof"
}

func (d Dog) Name() string {
	return d.name
}

// Cat is another concrete implementation
type Cat struct {
	name string
}

func (c Cat) Sound() string {
	return "meow"
}

func (c Cat) Name() string {
	return c.name
}

// Bird is a third concrete implementation, with an extra method not on Animal.
type Bird struct {
	name string
}

var _ Animal = Bird{}

func (b Bird) Sound() string {
	return "tweet"
}

func (b Bird) Name() string {
	return b.name
}

func (b Bird) Fly() string {
	return b.name + " flies away"
}

func describe(a Animal) string {
	return a.Name() + " says " + a.Sound()
}

// Zoo embeds a slice of Animals (composition) and has a method with a nested
// loop — the loop body itself isn't a symbol, but Describe() is.
type Zoo struct {
	Animals []Animal
}

func (z Zoo) Describe() string {
	var out string
	for _, a := range z.Animals {
		out += describe(a) + "\n"
	}
	return out
}

// Max is a generic function (Go type parameters) — treesitter's Go query
// picks this up the same as a non-generic func.
func Max[T int | float64](a, b T) T {
	if a > b {
		return a
	}
	return b
}

func main() {
	dog := Dog{name: "Rex"}
	cat := Cat{name: "Whiskers"}
	bird := Bird{name: "Tweety"}

	_ = dog.Sound()
	_ = cat.Sound()
	_ = bird.Fly()

	describe(dog)
	describe(cat)
	describe(bird)

	// Anonymous function assigned to a local var — worth seeing whether
	// aerial's treesitter query surfaces this as a nested symbol or not.
	greet := func(a Animal) string {
		return "Hello, " + a.Name() + "!"
	}
	_ = greet(dog)

	zoo := Zoo{Animals: []Animal{dog, cat, bird}}
	_ = zoo.Describe()

	_ = Max(3, 7)
}
