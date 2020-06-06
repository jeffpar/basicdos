#***********************************************************
#  INTSUM.MAK                                         
#  Makefile for Interrupt Summary searching program   
#***********************************************************

#  Comment out this line to remove debug information
# debug=1

MODEL=C

prog=intsum
progsrc=$(prog).cpp
progobj=$(prog).obj
progexe=$(prog).exe

!if !defined(debug)
AFLAGS = /Cp /W3
CFLAGS = /A$(MODEL) /Gs /Os /W3 /Zp1
LFLAGS = /noi
!else
AFLAGS = /Cp /W3 /Zi
CFLAGS = /A$(MODEL) /Gs /Os /W3 /Zp1 /Zi
LFLAGS = /noi /noe /m /CO
!endif

# libs = mcm$(MODEL) mrocket.lib

# OBJS    = $(progobj) config.obj err_exit.obj
OBJS    = $(progobj) idata.obj msgs.obj err_exit.obj dvideo.obj \
          reffile.obj listfile.obj strstri.obj config.obj

#   Pseudo-targets:

ALL : $(progexe)

dvideo.obj: dvideo.asm
        ml /c $(AFLAGS) $*.asm

strstri.obj: strstri.asm
        ml /c $(AFLAGS) $*.asm

$(progobj): $(progsrc) intsum.hpp
        cl /c $(CFLAGS) $*.cpp

idata.obj: idata.cpp intsum.hpp
        cl /c $(CFLAGS) $*.cpp

msgs.obj: msgs.cpp intsum.hpp
        cl /c $(CFLAGS) $*.cpp

reffile.obj: reffile.cpp intsum.hpp
        cl /c $(CFLAGS) $*.cpp

listfile.obj: listfile.cpp intsum.hpp
        cl /c $(CFLAGS) $*.cpp

config.obj: config.cpp intsum.hpp err_exit.hpp
        cl /c $(CFLAGS) $*.cpp

err_exit.obj: err_exit.cpp
        cl /c $(CFLAGS) $*.cpp

$(progexe) : $(OBJS)
   link $(LFLAGS) $(OBJS),$(prog),,$(libs);

