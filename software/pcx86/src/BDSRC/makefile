all: boot.com wboott.com

boot.obj: boot.asm
	masm /iinc boot;

boot.exe: boot.obj
	link boot;

boot.com: boot.exe
	exe2bin boot.exe boot.com

wboot.obj: wboot.asm
	masm /iinc wboot;

wboot.exe: wboot.obj
	link wboot;

wboot.com: wboot.exe
	exe2bin wboot.exe wboot.com
