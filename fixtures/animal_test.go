package main

import "testing"

func TestDescribe(t *testing.T) {
	dog := Dog{name: "Rex"}
	t.Log("describing:", dog.Name()) // proves debug output reaches dap (outputMode=remote)
	if got := describe(dog); got != "Rex says woof" {
		t.Errorf("describe(dog) = %q", got)
	}
}

func TestMax(t *testing.T) {
	if got := Max(3, 7); got != 7 {
		t.Errorf("Max(3, 7) = %d", got)
	}
}

// Deliberately failing — confirms neotest renders a red sign and the failure
// output, not just green ones. Delete once you've seen it fail.
func TestSoundIsWrong(t *testing.T) {
	if got := (Cat{name: "Whiskers"}).Sound(); got != "moo" {
		t.Errorf("Sound() = %q, want %q", got, "moo")
	}
}
