
flash: program.hex
	avrdude -c jtag1 -b 115200 -p m32 -P /dev/ttyUSB0 -U flash:w:program.hex 

program.hex: program.elf
	avr-objcopy -j .text -j .data -O ihex program.elf program.hex

program.elf: avros.o testapp.o signal_test.o mutex_test.o semaphore_test.o lcd.o
	avr-gcc -Wl,-Map,program.map -Wa,--gstabs -mmcu=atmega32 avros.o testapp.o \
	signal_test.o mutex_test.o semaphore_test.o lcd.o -o program.elf 

signal_test.o: signal_test.c avros.h avros_asm.h
	avr-gcc -I/usr/lib/avr/include -Wall -g -mmcu=atmega32 -c signal_test.c

mutex_test.o: mutex_test.c avros.h avros_asm.h
	avr-gcc -I/usr/lib/avr/include -Wall -g -mmcu=atmega32 -c mutex_test.c

semaphore_test.o: semaphore_test.c avros.h avros_asm.h
	avr-gcc -I/usr/lib/avr/include -Wall -g -mmcu=atmega32 -c semaphore_test.c

testapp.o: testapp.c avros.h avros_asm.h
	avr-gcc -I/usr/lib/avr/include -Wall -g -mmcu=atmega32 -c testapp.c

avros.o: avros.S avros.h avros_asm.h
	avr-gcc -I/usr/lib/avr/include -Wa,--gstabs -mmcu=atmega32 -a -c avros.S

lcd.o: lcd.c lcd.h
	avr-gcc -I/usr/lib/avr/include -Wall -std=c99 -O2 -DF_CPU=16000000 -mmcu=atmega32 -c lcd.c

clean:
	rm *o *hex *elf

debug:
	avarice --part atmega32 --jtag /dev/ttyUSB0 :4242

disasm:
	avr-objdump -S -D program.elf > dasm

rfuses:
	avrdude -c jtag1 -p m32 -P /dev/ttyUSB0 -U lfuse:r:lfuse:b -U hfuse:r:hfuse:b
	cat lfuse
	cat hfuse
wfuses:
	avrdude -c jtag1 -p m32 -P /dev/ttyUSB0 -U lfuse:w:0xff:m
