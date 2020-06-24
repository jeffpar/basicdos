{ Upcaser unit.                                                   }
{ The software included, data formats and basic algorithms are    }
{ copyright (C) 1995, 96 by Slava Gostrenko. All rights reserved. }

unit
  Upcaser;

interface

var
  Upcase : array [Char] of Char;

procedure StUpcase(var S: string);
function  StUpcase2(const S: string): string;

implementation

uses
  InitUpC;

procedure StUpcase(var S: string); assembler;
asm
  les  di, s
  cld

  xor  cx, cx
  mov  cl, es: [di]

  jcxz @ret

  inc  di

  mov  bx, offset Upcase
@loop:
  mov  al, es: [di]
  xlat
  stosb
  loop @loop

@ret:
end;

function  StUpcase2(const S: string): string; assembler;
asm
  mov  dx, ds

  lds  si, s
  les  di, @result
  mov  bx, di {save start pos}
  cld

  lodsb
  xor  cx, cx
  mov  cl, al
  stosb

  jcxz @ret

  shr  cx, 1
  jnc  @@1
  movsb
@@1:
  rep  movsw

  mov  ds, dx {now xlat table is available}
  mov  cl, es: [bx]
  lea  di, [bx + 1]

  mov  bx, offset Upcase
@loop:
  mov  al, es: [di]
  xlat
  stosb
  loop @loop

@ret:
  mov  ds, dx
end;

begin
  InitUpcaseArr (Upcase);
end.
