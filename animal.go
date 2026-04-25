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

func describe(a Animal) string {
	return a.Name() + " says " + a.Sound()
}

func main() {
	dog := Dog{name: "Rex"}
	cat := Cat{name: "Whiskers"}

	_ = dog.Sound()
	_ = cat.Sound()

	describe(dog)
	describe(cat)
}
