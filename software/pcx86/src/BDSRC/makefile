all: boot.com

boot.obj: boot.asm
	masm /iinc boot;

boot.exe: boot.obj
	link boot;

boot.com: boot.exe
	exe2bin boot.exe boot.com
