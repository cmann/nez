as65 = ../bin/as65

all: functional interrupt

functional: 6502_functional_test.a65
	$(as65) -l -m -w -h0 6502_functional_test.a65

interrupt: 6502_interrupt_test.a65
	$(as65) -l -m -w -h0 6502_interrupt_test.a65
