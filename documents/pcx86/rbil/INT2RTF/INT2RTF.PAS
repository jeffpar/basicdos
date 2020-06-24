{ INT2RTF. Main module for the Interrupt List -> .RTF compiler.}
{ The software included, data formats and basic algorithms are }
{ copyright (C) 1996 by Slava Gostrenko. All rights reserved.  }

{$M 16384}
{$IFNDEF DPMI}
  ! set Target to 'Protected Mode Application'
{$ENDIF}

{$X+}
program
  Int2RTF;

uses
  Upcaser, Objects, RTF;

var
  FO: THelpFile;
  IncompPattern: Text;
  Hdrs: TStringCollection;
  IntLists: array [Byte] of PTopic;
  IntNames: array [Byte] of string [12];
  KeyLists: TCollection;
  KeyNames: TCollection;
  IntList: PTopic;
  IntListName: string;
  Tables: PTopic;
  TablesName: string;
  CMOS: PTopic;
  CMOSName: string;
  FARCall: PTopic;
  FARCallName: string;
  Memory: PTopic;
  MemoryName: string;
  MSR: PTopic;
  MSRName: string;
  OpCodes: PTopic;
  OpCodesName: string;
  Ports: PTopic;
  PortSName: string;

  IntListIndex: PTopic;
  IntListIndexName: string;
  Interrup1st: Text;
  CopyrightStr: string;

const HexCh: array [0..$F] of Char = '0123456789ABCDEF';
function HexWord (W: Word): string;
begin
  HexWord := HexCh[Hi(W) shr 4] + HexCh[Hi(W) and $F]
           + HexCh[Lo(W) shr 4] + HexCh[Lo(W) and $F];
end;
function HexByte (B: Byte): string;
begin
  HexByte := HexCh[B shr 4] + HexCh[B and $F];
end;

function MemInitSwapFile(FileName: PChar; FileSize: Longint): Integer; far; external 'RTM' Index 35;
function MemCloseSwapFile(Delete: Integer): Integer; far; external 'RTM' Index 36;

function MakeCorrectTopicName (const TopicName: string): string;
var
  I: Integer;
  V: Integer;
  AddChar, TstTopic: string;
  Rez: string;
begin
  Rez := TopicName;

  V := 0;

  AddChar := '';

  TstTopic := StUpcase2 (Rez);
  while Hdrs. Search (@TstTopic, I) do begin
    Dec (Rez [0], Length (AddChar));
    Inc (V);
    if V > 99 then
      WriteLn ('error 3');

    System. Str (V, AddChar);
    if Length (AddChar) = 1 then
      AddChar := '_0' + AddChar
    else
      AddChar := '_'  + AddChar;

    Rez := Rez + AddChar;
    TstTopic := StUpcase2 (Rez);
  end;

  Hdrs. Insert (NewStr (TstTopic));

  MakeCorrectTopicName := Rez;
end;

function ProcessPattern (var Str: string; var Pos: Integer;
                         Pattern: string; Keyword: string;
                         Topic: PTopic; StepBack: Integer): Boolean;
var I, J: Integer;
begin
  I := 1;
  while I <= Length (Pattern) do begin
    if Pattern [I] in [#3, #6] then
      if Upcase [Str [Pos + I - 1]] in HexChars + ['X'] then begin
        J := System. Pos (#3, Keyword);
        if J > 0 then
          Keyword [J] := Str [Pos + I - 1]
        else
          if Pattern [I] = #3 then begin
            WriteLn (Str);
            WriteLn ('error in keyword pattern (1) ', Pattern, ' ', Keyword);
            ProcessPattern := False;
            Exit;
          end;
      end else begin
        ProcessPattern := False;
        Exit;
      end
    else
    if Pattern [I] in [#4, #7] then begin
      if (  (Upcase [Str [Pos + I - 1]] in ['B', 'C', 'D'])
        and (Upcase [Str [Pos + I]] in ['X', 'L', 'H']))
      or (  (Upcase [Str [Pos + I - 1]] in ['S', 'D'])
        and (Upcase [Str [Pos + I]] = 'I'))
      or (  (Upcase [Str [Pos + I - 1]] in ['B', 'S'])
        and (Upcase [Str [Pos + I]] = 'P'))
      or (  (Upcase [Str [Pos + I - 1]] in ['D', 'E', 'S', 'F', 'G'])
        and (Upcase [Str [Pos + I]] = 'S'))
      or (  (Upcase [Str [Pos + I - 1]] = 'S')
        and (Upcase [Str [Pos + I]] = 'F'))
      or (  (Upcase [Str [Pos + I - 1]] = 'V')
        and (Upcase [Str [Pos + I]] = 'X'))
      then begin
        J := System. Pos (#4, Keyword);
        if J > 0 then begin
          Keyword [J] := Str [Pos + I - 1];
          Keyword [J + 1] := Str [Pos + I];
          Inc (I);
        end else
          if Pattern [I] = #4 then begin
            WriteLn (Str);
            WriteLn ('error in keyword pattern (2) ', Pattern, ' ', Keyword);
            ProcessPattern := False;
            Exit;
          end else
            Inc (I);
      end else begin
        ProcessPattern := False;
        Exit;
      end
    end else
    if Pattern [I] in [#5, #8] then begin
      if (  (Upcase [Str [Pos + I - 1]] in ['B', 'C', 'D'])
        and (Upcase [Str [Pos + I]] in ['X', 'L', 'H']))
      or (  (Upcase [Str [Pos + I - 1]] = 'S')
        and (Upcase [Str [Pos + I]] = 'F'))
      or (  (Upcase [Str [Pos + I - 1]] = 'V')
        and (Upcase [Str [Pos + I]] = 'X'))
      then begin
        J := System. Pos (#5, Keyword);
        if J > 0 then begin
          Keyword [J] := Str [Pos + I - 1];
          Keyword [J + 1] := Str [Pos + I];
          Inc (I);
        end else
          if Pattern [I] = #5 then begin
            WriteLn (Str);
            WriteLn ('error in keyword pattern (3) ', Pattern, ' ', Keyword);
            ProcessPattern := False;
            Exit;
          end else
            Inc (I);
      end else begin
        ProcessPattern := False;
        Exit;
      end
    end else
    if ((Pattern [I] = 'X') and (Upcase [Str [Pos + I - 1]] in ['L', 'H']))
    or ((Pattern [I] in ['L', 'H']) and (Upcase [Str [Pos + I - 1]] = 'X'))
    then
      {Ok}
    else
    if Pattern [I] = 'H' then begin
      if Upcase [Str [Pos + I - 1]] <> 'H' then begin
        Delete (Pattern, I, 1);
        Dec (I);
      end;
    end else
    if Upcase [Str [Pos + I - 1]] <> Upcase [Pattern [I]] then begin
      ProcessPattern := False;
      Exit;
    end;

    Inc (I);
  end;

  {Once user's request for pattern with helper was confirmed}
  {make the pattern suitable for helper string analizis.    }
  if Pattern [Length (Pattern)] = '"' then
    Dec (Pattern [0]);

  if  (Pos + Length (Pattern) - 1 > Length (Str))
  and (Pattern [Length (Pattern)] in ['h', 'H']) then
    Dec (Pattern [0]);

  if Pos + Length (Pattern) - 1 <= Length (Str) then begin
    if (System. Pos (#3, Keyword) > 0)
    or (System. Pos (#4, Keyword) > 0)
    or (System. Pos (#5, Keyword) > 0) then begin
      WriteLn (Str);
      WriteLn ('error in keyword pattern (4) ', Pattern, ' ', Keyword);
    end;

    if  (Length (Keyword) < 13)
    and (Pos + Length (Pattern) <= Length (Str))
    and (Str [Pos + Length (Pattern)] in (['/', 'h', 'H', ':', '-'] + HexChars))
    and (Pos + Length (Pattern) + 1 <= Length (Str))
    and (not (Str [Pos + Length (Pattern) + 1] in ['I', 'R', 'W', '-', ' ']))
    then begin
      WriteLn (IncompPattern, Str);
      WriteLn (IncompPattern, 'not a complete pattern ', Pattern, ' for keyword ', Keyword);
    end;

    if  (Pos + Length (Pattern) <= Length (Str))
    and (Str [Pos + Length (Pattern)] = '"') then begin
      Keyword := Keyword + '"';
      I := Pos + Length (Pattern) + 1;
      while (I <= Length (Str)) and (Str [I] <> '"') do begin
        Keyword := Keyword + Str [I];
        Inc (I);
      end;
      if I <= Length (Str) then begin
        Keyword := Keyword + '"';
        if Copy (Keyword, 1, 4) = 'INT ' then
          Delete (Keyword, 1, 4);
      end else
        Delete (Keyword, System.Pos ('"', Keyword), Length (Keyword));
    end;

    Topic^. AddKeyword (Keyword, StepBack);
    Insert (#2, Str, Pos + Length (Pattern));
    Insert (#2, Str, Pos);
    Inc (Pos, Length (Pattern) + 1);

    ProcessPattern := True;
  end else
    ProcessPattern := False;
end;

function SkipPattern (var Str: string; var Pos: Integer;
                      Pattern: string): Boolean;
var I, J: Integer;
begin
  I := 1;
  while I <= Length (Pattern) do begin
    if Pattern [I] = #3 then
      if Upcase [Str [Pos + I - 1]] in HexChars + ['X'] then begin
        {Ok}
      end else begin
        SkipPattern := False;
        Exit;
      end
    else
    if Pattern [I] = #4 then begin
      if (  (Upcase [Str [Pos + I - 1]] in ['B', 'C', 'D'])
        and (Upcase [Str [Pos + I]] in ['X', 'L', 'H']))
      or (  (Upcase [Str [Pos + I - 1]] in ['S', 'D'])
        and (Upcase [Str [Pos + I]] = 'I'))
      or (  (Upcase [Str [Pos + I - 1]] in ['B', 'S'])
        and (Upcase [Str [Pos + I]] = 'P'))
      or (  (Upcase [Str [Pos + I - 1]] in ['D', 'E', 'S', 'F', 'G'])
        and (Upcase [Str [Pos + I]] = 'S'))
      or (  (Upcase [Str [Pos + I - 1]] = 'S')
        and (Upcase [Str [Pos + I]] = 'F'))
      or (  (Upcase [Str [Pos + I - 1]] = 'V')
        and (Upcase [Str [Pos + I]] = 'X'))
      then begin
        {Ok}
      end else begin
        SkipPattern := False;
        Exit;
      end
    end else
    if Pattern [I] = #5 then begin
      if (  (Upcase [Str [Pos + I - 1]] in ['B', 'C', 'D'])
        and (Upcase [Str [Pos + I]] in ['X', 'L', 'H']))
      or (  (Upcase [Str [Pos + I - 1]] = 'S')
        and (Upcase [Str [Pos + I]] = 'F'))
      or (  (Upcase [Str [Pos + I - 1]] = 'V')
        and (Upcase [Str [Pos + I]] = 'X'))
      then begin
        {Ok}
      end else begin
        SkipPattern := False;
        Exit;
      end
    end else
    if ((Pattern [I] = 'X') and (Upcase [Str [Pos + I - 1]] in ['L', 'H']))
    or ((Pattern [I] in ['L', 'H']) and (Upcase [Str [Pos + I - 1]] = 'X'))
    then
      {Ok}
    else
    if Pattern [I] = 'H' then begin
      if Upcase [Str [Pos + I - 1]] <> 'H' then begin
        Delete (Pattern, I, 1);
        Dec (I);
      end;
    end else
    if Upcase [Str [Pos + I - 1]] <> Upcase [Pattern [I]] then begin
      SkipPattern := False;
      Exit;
    end;

    Inc (I);
  end;

  if Pos + Length (Pattern) - 1 <= Length (Str) then begin
    if  (Pos + Length (Pattern) <= Length (Str))
    and (Str [Pos + Length (Pattern)] in (['/', 'h', 'H', ':', '-'] + HexChars))
    and (Pos + Length (Pattern) + 1 <= Length (Str))
    and (not (Str [Pos + Length (Pattern) + 1] in ['I', 'R', 'W', '-', ' ']))
    then begin
      WriteLn (IncompPattern, Str);
      WriteLn (IncompPattern, 'not a complete pattern ', Pattern);
    end;

    Inc (Pos, Length (Pattern) - 1);

    SkipPattern := True;
  end else
    SkipPattern := False;
end;

procedure AddStr2Topic (Str: string; var Topic: PTopic;
                        var TopicName: string; const CurInt, CurSubF, CurCat: string;
                        Indexed: Boolean);
var I: Integer;
    KeyCnt: Integer;
begin
  KeyCnt := 0;
  for I := 1 to Length (Str) do
    if Str [I] = #2 then
      Inc (KeyCnt);

  I := 1;
  while I <= Length (Str) do begin
    if Str [I] = #2 then
      Dec (KeyCnt);

    if not Odd (KeyCnt) then
      if  (I + 4 <= Length (Str))
      and (Str [I] = '#')
      and (Str [I + 1] in ['0'..'9', 'C', 'F', 'M', 'R', 'P'])
      and (Str [I + 2] in ['0'..'9'])
      and (Str [I + 3] in ['0'..'9'])
      and (Str [I + 4] in ['0'..'9'])
      then begin
        Topic^. AddKeyword (Copy (Str, I, 5), KeyCnt div 2);
        Insert (#2, Str, I + 5);
        Insert (#2, Str, I);
        Inc (I, 6);
      end else
        if (I = 1)
        or (not (Upcase [Str [I - 1]] in ['A'..'Z', '0'..'9'])) then
          case Upcase [Str [I]] of
          'I':
            if ProcessPattern (Str, I, 'INT '#3#3'H/AX='#3#3#3#3'H/'#4#4'='#3#3#3#3'H',
                 #3#3#3#3#3#3#4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'INT 13/AX=2000H/DL=81H', '1320' + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AX='#3#3#3#3'H/'#5#5'='#3#3'H',
                 #3#3#3#3#3#3#5#5#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'INT 21/AX=4202H/CX=0/DX=0', '2142' + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AX='#6#6#6#6'H-'#6#6#6#6'H',
                 'INT '#3#3, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AX='#3#3#3#3'H',
                 #3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'INT '#3#3'H/AH='#3#3#3#3'H',
                 #3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'INT '#3#3'H/AH='#3#3'H/'#4#4'='#3#3#3#3'H',
                 #3#3#3#3'--'#4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AH='#3#3'H/'#5#5'='#3#3'H',
                 #3#3#3#3'--'#5#5#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AH='#6#6'H-'#6#6'H',
                 'INT '#3#3, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AH='#3#3'H',
                 #3#3#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'INT '#3#3'H/AL='#3#3'H/'#4#4'='#3#3#3#3'H',
                 #3#3'--'#3#3#4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AL='#3#3'H/'#5#5'='#3#3'H',
                 #3#3'--'#3#3#5#5#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/AL='#3#3'H',
                 #3#3'--'#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'INT '#3#3'H/'#4#4'='#3#3#3#3'H',
                 #3#3'----'#4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/'#5#5'='#3#3'H',
                 #3#3'----'#5#5#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'INT '#3#3'H/'#3#3#3#3'H',
                 #3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/'#6#6'H-'#6#6'H',
                 'INT '#3#3, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H/'#3#3'H',
                 #3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#6#6'-INT '#6#6'H',
                 'TITLES', Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#6#6'-'#6#6'H',
                 'TITLES', Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT XXH',
                 'TITLES', Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'INT '#3#3'H',
                 'INT '#3#3, Topic, KeyCnt div 2)
            then
              ;
          'A':
            if ProcessPattern (Str, I, 'AX='#3#3#3#3'H/'#4#4'='#3#3#3#3'H',
                 CurInt + #3#3#3#3#4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AX='#3#3#3#3'H/'#5#5'='#3#3'H',
                 CurInt + #3#3#3#3#5#5#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AX='#6#6#6#6'H-'#6#6#6#6'H',
                 'INT ' + CurInt, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AX='#3#3#3#3'H',
                 CurInt + #3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AH='#3#3'H/AL='#3#3'H',
                 CurInt + #3#3#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'AH='#3#3'H/'#4#4'='#3#3#3#3'H',
                 CurInt + #3#3'--'#4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AH='#3#3'H/'#5#5'='#3#3'H',
                 CurInt + #3#3'--'#5#5#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AH='#6#6'H-'#6#6'H',
                 'INT ' + CurInt, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AH='#3#3'H',
                 CurInt + #3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'AL='#3#3'H/'#4#4'='#3#3#3#3'H',
                 CurInt + Copy (CurSubF, 1, 2) + #3#3#4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AL='#3#3'H/'#5#5'='#3#3'H',
                 CurInt + Copy (CurSubF, 1, 2) + #3#3#5#5#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AL='#6#6'H/'#6#6'H',
                 CurInt + Copy (CurSubF, 1, 2) + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AL='#6#6'H-'#6#6'H',
                 CurInt + Copy (CurSubF, 1, 2) + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'AL='#3#3'H',
                 CurInt + Copy (CurSubF, 1, 2) + #3#3 + CurCat, Topic, KeyCnt div 2)
            then
              ;
          'B', 'C', 'D', 'S', 'E', 'F', 'G', 'V':
            if ProcessPattern (Str, I, #4#4'='#3#3#3#3'H',
                 CurInt + CurSubF + #4#4#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or SkipPattern (Str, I, 'CX=CX-1')
            or ProcessPattern (Str, I, #8#8'='#6#6'H/'#6#6'H',
                 CurInt + CurSubF + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, #8#8'='#6#6'H-'#6#6'H',
                 CurInt + CurSubF + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, #5#5'='#3#3'H',
                 CurInt + CurSubF + #5#5#3#3 + CurCat, Topic, KeyCnt div 2)
            then
              {nothing}
            else
            if Upcase [Str [I]] = 'C' then begin
              if ProcessPattern (Str, I, 'CMOS DATA',
                   'CMOS', Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CMOS 8086/88',
                   'CMOS', Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CMOS 80C86/88',
                   'CMOS', Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CMOS '#3#3#3#3'H',
                   'R'#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CMOS '#3#3'H-'#3#3'H',
                   'R'#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CMOS '#3#3'H',
                   'R'#3#3 + CurCat, Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CMOS',
                   'CMOS', Topic, KeyCnt div 2)

              or ProcessPattern (Str, I, 'CALL XXXXH:XXXXH"',
                   '@xxxxxxxx', Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CALL XXXXH:XXXXH',
                   'FAR CALLS', Topic, KeyCnt div 2)
              or ProcessPattern (Str, I, 'CALL '#3#3#3#3'H:'#3#3#3#3'H',
                 '@'#3#3#3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
              then
                ;
            end;
          '@':
            if ProcessPattern (Str, I, '@XXXXH:XXXXH"',
                 '@xxxxxxxx', Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, '@XXXXH:XXXXH',
                 'FAR CALLS', Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, '@'#3#3#3#3'H:'#3#3#3#3'H',
                 '@'#3#3#3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            then
              ;
          'M':
            if ProcessPattern (Str, I, 'MEM '#6#6#6#6'H:xxxxH',
                 'MEMORY', Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'MEM '#3#3#3#3'H:'#3#3#3#3'H',
                 'M'#3#3#3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'MEM '#3#3#3#3#3#3#3#3'H',
                 'M'#3#3#3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)

            or ProcessPattern (Str, I, 'MSR '#3#3#3#3#3#3#3#3'H',
                 'S'#3#3#3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            then
              ;
          'P':
            if ProcessPattern (Str, I, 'PORT ACCESS',
                 'PORTS', Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'PORT '#3#3#3#3'H-'#3#3#3#3'H',
                 'P'#3#3#3#3#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'PORT '#3#3#3#3'H-'#3#3#3'H',
                 'P'#3#3#3#3#3#3#3' ' + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'PORT '#3#3#3#3'H-????H',
                 'P'#3#3#3#3'????' + CurCat, Topic, KeyCnt div 2)
            or ProcessPattern (Str, I, 'PORT '#3#3#3#3'H',
                 'P'#3#3#3#3 + CurCat, Topic, KeyCnt div 2)
            then
              ;
          end;

    Inc (I);
  end;

  Topic^. AddString (' ' + Str);
end;

function NoLinks (S: string): string;
var I: Integer;
begin
  I := Pos (#2, S);
  while I > 0 do begin
    Delete (S, I, 1);
    I := Pos (#2, S);
  end;
  NoLinks := S;
end;

procedure Tab2Spc (var Str: string);
var I, J: Integer;
begin
  I := Pos (#9, Str);
  while I > 0 do begin
    Delete (Str, I, 1);
    for J := 7 downto ((I - 1) mod 8) do
      Insert (' ', Str, I);
    I := Pos (#9, Str);
  end;
end;

function ProcessInterrup (const FileName: string; const FileIsATopic: string): Boolean;
type
  DividerRec = record
    Len: Byte;
    S: array [0..7] of Char;   (* '--------' *)
    Cat: Char;                 (* category *)
    C: Char;                   (* '-' *)
    case Integer of
      0: (Int: array [0..1] of Char; (* Interrupt number, 2 hex digits *)
          SubF: array [0..3] of Char;(* sub function, 4 hex digits or '-' *)
          R: array [0..1] of Char;   (* Secondary Register Name, Two Letters or '--' *)
          RV: array [0..3] of Char;  (* sec. reg. value, 4 hex digits or '-' *)
          Rest: array [0..17] of Char;
         );
      1: (RSign: Char;
          R1,
          R2: array [0..1] of Char;
         );
      2: (AtSign: Char;
          CallSeg,
          CallOfs: array [0..3] of Char;
         );
      3: (MSign: Char;
          MemSeg,
          MemOfs: array [0..3] of Char;
         );
      4: (SSign: Char;
          MSR: array [0..7] of Char;
         );
      5: (PSign: Char;
          P1,
          P2: array [0..3] of Char;
         );
      6: (Cat2: Char;                (* category *)
          C2: Char;                  (* '-' *)
         );
  end;            (* record dividerRec *)

  T2W = record Lo, Hi: Word; end;
  T22 = record Lo, Hi: array [0..1] of Char; end;

var
  FI: Text;
  Str, StrUp: string;
  TopicName: string;

  CurCat: string [1];
  CurInt: string [2];
  CurSubF: string [4];

  DR: DividerRec absolute Str;

procedure ProcessHdr (Hdr: string);
begin
  with DR do begin
    if (S <> '--------')
    or (not (Cat in ['A'..'Z', 'a'..'z', '!', '*', '-']))
    or (C <> '-')
    or ((Cat <> '!')
        and
        ((Cat <> '-')
      or (C2 <> '-')
      or (Pos ('OPCODES', StUpcase2 (FileName)) = 0)
        )
        and
        ((not (RSign in ['R', 'r']))
      or (not (R1 [0] in HexChars))
      or (not (R1 [1] in HexChars))
      or (  (R2 <> '--')
        and ((not (R2 [0] in HexChars))
          or (not (R2 [1] in HexChars)))
         )
        )
        and
        ((not (AtSign = '@'))
      or (not (CallSeg [0] in HexChars + ['x']))
      or (not (CallSeg [1] in HexChars + ['x']))
      or (not (CallSeg [2] in HexChars + ['x']))
      or (not (CallSeg [3] in HexChars + ['x']))
      or (not (CallOfs [0] in HexChars + ['x']))
      or (not (CallOfs [1] in HexChars + ['x']))
      or (not (CallOfs [2] in HexChars + ['x']))
      or (not (CallOfs [3] in HexChars + ['x']))
        )
        and
        ((not (MSign in ['M', 'm']))
      or (not (MemSeg [0] in HexChars + ['x']))
      or (not (MemSeg [1] in HexChars + ['x']))
      or (not (MemSeg [2] in HexChars + ['x']))
      or (not (MemSeg [3] in HexChars + ['x']))
      or (not (MemOfs [0] in HexChars + ['x']))
      or (not (MemOfs [1] in HexChars + ['x']))
      or (not (MemOfs [2] in HexChars + ['x']))
      or (not (MemOfs [3] in HexChars + ['x']))
        )
        and
        ((not (SSign in ['S', 's']))
      or (not (MSR [0] in HexChars))
      or (not (MSR [1] in HexChars))
      or (not (MSR [2] in HexChars))
      or (not (MSR [3] in HexChars))
      or (not (MSR [4] in HexChars))
      or (not (MSR [5] in HexChars))
      or (not (MSR [6] in HexChars))
      or (not (MSR [7] in HexChars))
        )
        and
        ((not (PSign in ['P', 'p']))
      or (not (P1 [0] in HexChars + ['x']))
      or (not (P1 [1] in HexChars + ['x']))
      or (not (P1 [2] in HexChars + ['x']))
      or (not (P1 [3] in HexChars + ['x']))
      or (  (P2 <> '----')
        and (P2 <> '????')
        and ((not (P2 [0] in HexChars))
          or (not (P2 [1] in HexChars))
          or (not (P2 [2] in HexChars))
          or (not (P2 [3] in HexChars + ['x', ' '])))
         )
        )
        and
        ((not (Int [0] in HexChars))
      or (not (Int [1] in HexChars))
      or (  (SubF <> '----')
        and ((T22 (SubF). Lo <> '--')
          or (not (SubF [2] in HexChars))
          or (not (SubF [3] in HexChars)))
        and ((T22 (SubF). Hi <> '--')
          or (not (SubF [0] in HexChars))
          or (not (SubF [1] in HexChars)))
        and ((not (SubF [0] in HexChars))
          or (not (SubF [1] in HexChars))
          or (not (SubF [2] in HexChars))
          or (not (SubF [3] in HexChars)))
         )
      or (  (R <> '--')
        and ((R <> 'BX') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'CX') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'DX') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'SI') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'DI') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'SP') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'BP') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'ES') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'DS') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))

        and ((R <> 'BH') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (T22 (RV). Hi <> '--'))
        and ((R <> 'BL') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (T22 (RV). Hi <> '--'))
        and ((R <> 'CH') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (T22 (RV). Hi <> '--'))
        and ((R <> 'CL') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (T22 (RV). Hi <> '--'))
        and ((R <> 'DH') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (T22 (RV). Hi <> '--'))
        and ((R <> 'DL') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (T22 (RV). Hi <> '--'))

        and ((R <> 'SF') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
        and ((R <> 'SF') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (T22 (RV). Hi <> '--'))

        and ((R <> 'Vx') or (not (RV [0] in HexChars))
                         or (not (RV [1] in HexChars))
                         or (not (RV [2] in HexChars))
                         or (not (RV [3] in HexChars)))
         )
      or (Rest <> '------------------')
        )
        and
        (Hdr <> '-----------------------------------------')
        and
        (Hdr <> '------------------------------------------')
        and
        (Hdr <> '--------------------------------------------')
        and
        (Hdr <> '---------------------------------------------')
        and
        (Hdr <> '----------------------------------------------')
        and
        (Hdr <> '------------------------------------------------')
        and
        (Hdr <> '-------------------------------------------------')
        and
        (Hdr <> '--------------------------------------------------')
        and
        (Hdr <> '---------------------------------------------------')
        and
        (Hdr <> '----------------------------------------------------')
        and
        (Hdr <> '-----------------------------------------------------')
        and
        (Hdr <> '------------------------------------------------------')
        and
        (Hdr <> '---------------------------------------------------------')
        and
        (Hdr <> '----------------------------------------------------------')
        and
        (Hdr <> '-----------------------------------------------------------')
        and
        (Hdr <> '------------------------------------------------------------')
        and
        (Hdr <> '-------------------------------------------------------------')
        and
        (Hdr <> '--------------------------------------------------------------')
       )
    then
      WriteLn (' ': 79, #13, 'header error: ', Hdr);

    if Cat = '!' then begin
      TopicName := Copy (Str, 10, Length (Str) - 9);
      CurInt := '';
      CurSubF := '';
    end else
    if  (Cat = '-') and (C2 = '-')
    and (Pos ('OPCODES', StUpcase2 (FileName)) > 0) then begin
      TopicName := Copy (Str, 12, Length (Str) - 11);
      CurInt := '';
      CurSubF := '';
    end else
      if RSign in ['R', 'r'] then begin
        TopicName := RSign + R1 + R2;
        CurInt := '';
        CurSubF := '';
      end else
      if AtSign = '@' then begin
        TopicName := AtSign + CallSeg + CallOfs;
        CurInt := '';
        CurSubF := '';
      end else
      if MSign in ['M', 'm'] then begin
        TopicName := MSign + MemSeg + MemOfs;
        CurInt := '';
        CurSubF := '';
      end else
      if SSign in ['S', 's'] then begin
        TopicName := SSign + MSR;
        CurInt := '';
        CurSubF := '';
      end else
      if PSign in ['P', 'p'] then begin
        TopicName := PSign + P1 + P2;
        CurInt := '';
        CurSubF := '';
      end else begin
        TopicName := Int + SubF + R + RV;
        CurInt := Int;
        CurSubF := SubF;
      end;

    while TopicName [Length (TopicName)] in ['-', ' ', #9] do Dec (TopicName [0]);
    if Length (TopicName) > 0 then
      while TopicName [1] in ['-', ' ', #9] do Delete (TopicName, 1, 1)
    else
      TopicName := FileName;

    if not (Cat in ['!', '-']) then begin
      TopicName := TopicName + Cat;
      CurCat := Cat;
    end else
      CurCat := '';
  end;
end;

var
  SectionStarted: Boolean;
  SectionClosed: Boolean;
  I, J: Integer;
  Topic: PTopic;
  ExtendedHeader: string;
  OriginalTopicName: string;

  TblStarted: Boolean;
  TblClosed: Boolean;
  TblTopic: PTopic;
  TblTopicName: string;

  PrevStr, SavePtr: PString;
  AddNextStringToTopicAsATblRef: Boolean;

begin
  Assign (FI, FileName);
  {$I-}
  Reset (FI);
  if IOResult = 0 then begin
    ProcessInterrup := True;
    WriteLn ('processing ', FileName, '                                      ');

    TblStarted := False;
    TblClosed := True;

    SectionStarted := False;
    SectionClosed := True;

    AddNextStringToTopicAsATblRef := False;

    if FileIsATopic <> '' then begin
      TopicName := FileIsATopic;
      CurCat := '';
      CurInt := '';
      CurSubF := '';

      New (Topic, Init (1, 1));
      SectionStarted := True;
      SectionClosed := False;
      TopicName := MakeCorrectTopicName (TopicName);
      OriginalTopicName := TopicName;
      ExtendedHeader := #2 + TopicName + #2;
    end;

    while not EOF (FI) do begin
      ReadLn (FI, Str);

      if  (Length (Str) > 0)
      and (FileIsATopic = '')
      and ((Str [1] = '-') and (Pos ('--------', Str) <> 0))
      and (Str <> '--------------')
      then begin
        if not TblClosed then begin
          TblTopic^.AddKeywordAtStart (OriginalTopicName);
          TblTopic^.SetSubHeader (ExtendedHeader);
          FO. IdxTbl. Insert (New (PIndexEntry, Init (
            TblTopicName, 0, TblTopic)));
          TblStarted := False;
          TblClosed := True;
        end;

        if not SectionClosed then begin
          if Pos ('CMOS', StUpcase2 (FileName)) > 0 then begin
            CMOS^.AddKeyword (OriginalTopicName, 0);
            AddStr2Topic (ExtendedHeader,
                          CMOS, CMOSName, CurInt, CurSubF, CurCat, True);
          end else
          if Pos ('FARCALL', StUpcase2 (FileName)) > 0 then begin
            FarCall^.AddKeyword (OriginalTopicName, 0);
            AddStr2Topic (ExtendedHeader,
                          FarCall, FarCallName, CurInt, CurSubF, CurCat, True);
          end else
          if Pos ('MEMORY', StUpcase2 (FileName)) > 0 then begin
            Memory^.AddKeyword (OriginalTopicName, 0);
            AddStr2Topic (ExtendedHeader,
                          Memory, MemoryName, CurInt, CurSubF, CurCat, True);
          end else
          if Pos ('MSR', StUpcase2 (FileName)) > 0 then begin
            MSR^.AddKeyword (OriginalTopicName, 0);
            AddStr2Topic (ExtendedHeader,
                          MSR, MSRName, CurInt, CurSubF, CurCat, True);
          end else
          if Pos ('OPCODES', StUpcase2 (FileName)) > 0 then begin
            OpCodes^.AddKeyword (OriginalTopicName, 0);
            AddStr2Topic (ExtendedHeader,
                          OpCodes, OpCodesName, CurInt, CurSubF, CurCat, True);
          end else
          if Pos ('PORTS', StUpcase2 (FileName)) > 0 then begin
            Ports^.AddKeyword (OriginalTopicName, 0);
            AddStr2Topic (ExtendedHeader,
                          Ports, PortsName, CurInt, CurSubF, CurCat, True);
          end else
          if  (FileIsATopic = '')
          and ((not (ExtendedHeader [2] in HexChars))
            or (not (ExtendedHeader [3] in HexChars)))
          then begin
            IntList^.AddKeyword (OriginalTopicName, 0);
            AddStr2Topic (ExtendedHeader,
                          IntList, IntListName, CurInt, CurSubF, CurCat, True);
          end;

          Topic^.SetHeader (NoLinks (ExtendedHeader));
          FO. IdxTbl. Insert (New (PIndexEntry, Init (
            TopicName, 0, Topic)));
          SectionClosed := True;
        end;

        ProcessHdr (Str);

        if (StUpcase2 (TopicName) <> 'SECTION') then begin
          New (Topic, Init (1, 1));
          SectionStarted := True;
          SectionClosed := False;
          TopicName := MakeCorrectTopicName (TopicName);
          OriginalTopicName := TopicName;
          ExtendedHeader := #2 + TopicName + #2;
          Write (TopicName: 31, ' mem - ', MaxAvail: 8, #13);
        end else
          SectionStarted := False;
      end else begin
        if SectionStarted then begin
          Tab2Spc (Str);

          StrUp := StUpcase2 (Str);

          if  (Copy (StrUp, 1, 4) = 'INT ')
          and (StrUp [5] in HexChars) and (StrUp [6] in HexChars)
          and (Pos ('INT', StUpcase2 (FileName)) > 0) then begin
            I := (Pos (StrUp [5], HexCh) - 1)*16 + Pos (StrUp [6], HexCh) - 1;
            IntLists [I]^.AddKeyword (OriginalTopicName, 0);
            ExtendedHeader := #2 + TopicName + #2
                            + Copy (Str, 7, Length (Str) - 6);
            AddStr2Topic (ExtendedHeader,
                          IntLists [I], string (Pointer(@IntNames [I])^), CurInt, CurSubF, CurCat, True);
          end;

          if  (Copy (StrUp, 1, 5) = 'CMOS ')
          and (StrUp [6] in HexChars) and (StrUp [7] in HexChars)
          and (StrUp [8] = 'H') then begin
            if  (StrUp [9] = '-')
            and (StrUp [10] in HexChars) and (StrUp [11] in HexChars)
            and (StrUp [12] = 'H') then
              ExtendedHeader := Copy (Str, 13, Length (Str) - 12)
            else
              ExtendedHeader := Copy (Str, 9, Length (Str) - 8);

            ExtendedHeader := #2 + TopicName + #2 + ExtendedHeader;
          end;

          if  (Copy (StrUp, 1, 5) = 'CALL ')
          and (StrUp [6] in HexChars + ['X']) and (StrUp [7] in HexChars + ['X'])
          and (StrUp [8] in HexChars + ['X']) and (StrUp [9] in HexChars + ['X'])
          and (StrUp [10] = 'H')
          and (StrUp [11] = ':')
          and (StrUp [12] in HexChars + ['X']) and (StrUp [13] in HexChars + ['X'])
          and (StrUp [14] in HexChars + ['X']) and (StrUp [15] in HexChars + ['X'])
          and (StrUp [16] = 'H')
          then begin
            ExtendedHeader := #2 + TopicName + #2
                            + Copy (Str, 17, Length (Str) - 16);
          end;

          if  (Copy (StrUp, 1, 4) = 'MEM ')
          and (StrUp [5] in HexChars + ['X']) and (StrUp [6] in HexChars + ['X'])
          and (StrUp [7] in HexChars + ['X']) and (StrUp [8] in HexChars + ['X'])
          then
            if  (StrUp [9] = 'H')
            and (StrUp [10] = ':')
            and (StrUp [11] in HexChars + ['X']) and (StrUp [12] in HexChars + ['X'])
            and (StrUp [13] in HexChars + ['X']) and (StrUp [14] in HexChars + ['X'])
            and (StrUp [15] = 'H')
            then
              ExtendedHeader := #2 + TopicName + #2
                              + Copy (Str, 16, Length (Str) - 15)
            else
            if  (StrUp  [9] in HexChars + ['X']) and (StrUp [10] in HexChars + ['X'])
            and (StrUp [11] in HexChars + ['X']) and (StrUp [12] in HexChars + ['X'])
            and (StrUp [13] = 'H')
            then
              ExtendedHeader := #2 + TopicName + #2
                              + Copy (Str, 14, Length (Str) - 13);

          if  (Copy (StrUp, 1, 4) = 'MSR ')
          and (StrUp [5] in HexChars + ['X']) and (StrUp [6] in HexChars + ['X'])
          and (StrUp [7] in HexChars + ['X']) and (StrUp [8] in HexChars + ['X'])
          and (StrUp [9] in HexChars + ['X']) and (StrUp [10] in HexChars + ['X'])
          and (StrUp [11] in HexChars + ['X']) and (StrUp [12] in HexChars + ['X'])
          and (StrUp [13] = 'H')
          then begin
            ExtendedHeader := #2 + TopicName + #2
                            + Copy (Str, 14, Length (Str) - 13);
          end;

          if (Copy (StrUp, 1, 7) = 'OPCODE ')
          then begin
            for I := 8 to Length (StrUp) do
              if StrUp [I] = ' ' then Break;
            if  (I > 8)
            and (Pos (Copy (StrUp, 8, I - 8), StUpcase2 (TopicName)) > 0) then
              ExtendedHeader := #2 + TopicName + #2
                              + Copy (Str, I, Length (Str) - I + 1);
          end;

          if  (Copy (StrUp, 1, 5) = 'PORT ')
          and (StrUp [6] in HexChars) and (StrUp [7] in HexChars)
          and (StrUp [8] in HexChars) and (StrUp [9] in HexChars)
          then begin
            if  (StrUp [10] = '-')
            and (StrUp [11] in HexChars + ['?']) and (StrUp [12] in HexChars + ['?'])
            and (StrUp [13] in HexChars + ['?']) and (StrUp [14] in HexChars + ['?', 'x', ' '])
            then
              ExtendedHeader := Copy (Str, 15, Length (Str) - 14)
            else
              ExtendedHeader := Copy (Str, 10, Length (Str) - 9);

            ExtendedHeader := #2 + TopicName + #2 + ExtendedHeader;
          end;

          if  (ExtendedHeader = #2 + TopicName + #2)
          and (Str <> '') then
            ExtendedHeader := #2 + TopicName + #2' ' + Str;

          if KeyNames. Count > 0 then
            for I := 0 to KeyNames. Count - 1 do begin
              J := Pos (StUpcase2 (PString (KeyNames. At (I))^), StrUp);
              if  (J > 0)
              and ((PTopic (KeyLists. At (I))^. Count = 0)
                or (PString (PTopic (KeyLists. At (I))^. At (
                    PTopic (KeyLists. At (I))^. Count - 1))^
                 <> ' ' + ExtendedHeader))
              then begin
                PTopic (KeyLists. Items^ [I])^.AddKeyword (OriginalTopicName, 0);
                AddStr2Topic (ExtendedHeader,
                              PTopic (KeyLists. Items^ [I]),
                              PString (KeyNames. At (I))^, CurInt, CurSubF, CurCat, True);
              end;
            end;

          I := Pos ('TABLE', StrUp);
          if  (I > 0) and (I + 9 <= Length (Str))
          and (Str [I + 6] in ['0'..'9', 'C', 'F', 'M', 'R', 'P'])
          and (Str [I + 7] in ['0'..'9'])
          and (Str [I + 8] in ['0'..'9'])
          and (Str [I + 9] in ['0'..'9'])
          then begin
            if not TblClosed then begin
              PrevStr := TblTopic^.At (TblTopic^.Count - 1);
              if (PrevStr <> nil) and (PrevStr^ <> '') and (PrevStr^ <> ' ') then begin
                TblTopic^. AtDelete (TblTopic^.Count - 1);
                if PrevStr <> nil then begin
                  J := Pos (#2, PrevStr^);
                  while J > 0 do begin
                    SavePtr := PrevStr;
                    PrevStr := NewStr (Copy (PrevStr^, 1, J - 1)
                               + Copy (PrevStr^, J + 1, Length (PrevStr^) - J));
                    DisposeStr (SavePtr);
                    J := Pos (#2, PrevStr^);
                    if J = 0 then
                      WriteLn ('error 5');
                    SavePtr := PrevStr;
                    PrevStr := NewStr (Copy (PrevStr^, 1, J - 1)
                               + Copy (PrevStr^, J + 1, Length (PrevStr^) - J));
                    DisposeStr (SavePtr);
                    TblTopic^. Keywords. AtFree (TblTopic^. Keywords. Count - 1);
                    J := Pos (#2, PrevStr^);
                  end;
                end;
              end else
                PrevStr := nil;

              TblTopic^.AddKeywordAtStart (OriginalTopicName);
              TblTopic^.SetSubHeader (ExtendedHeader);
              FO. IdxTbl. Insert (New (PIndexEntry, Init (
                TblTopicName, 0, TblTopic)));
              TblStarted := False;
              TblClosed := True;
            end else begin
              PrevStr := Topic^.At (Topic^.Count - 1);
              if (PrevStr <> nil) and (PrevStr^ <> '') and (PrevStr^ <> ' ') then begin
                Topic^. AtDelete (Topic^.Count - 1);
                if PrevStr <> nil then begin
                  J := Pos (#2, PrevStr^);
                  while J > 0 do begin
                    SavePtr := PrevStr;
                    PrevStr := NewStr (Copy (PrevStr^, 1, J - 1)
                               + Copy (PrevStr^, J + 1, Length (PrevStr^) - J));
                    DisposeStr (SavePtr);
                    J := Pos (#2, PrevStr^);
                    if J = 0 then
                      WriteLn ('error 5');
                    SavePtr := PrevStr;
                    PrevStr := NewStr (Copy (PrevStr^, 1, J - 1)
                               + Copy (PrevStr^, J + 1, Length (PrevStr^) - J));
                    DisposeStr (SavePtr);
                    Topic^. Keywords. AtFree (Topic^. Keywords. Count - 1);
                    J := Pos (#2, PrevStr^);
                  end;
                end;
              end else
                PrevStr := nil;
            end;

            New (TblTopic, Init (1, 1));
            TblStarted := True;
            TblClosed := False;
            TblTopicName := MakeCorrectTopicName ('#' + Copy (Str, I + 6, 4));

            if (PrevStr <> nil) and (PrevStr^ <> '') and (PrevStr^ <> ' ')
            then begin
              if Pos (#2, PrevStr^) > 0 then begin
                WriteLn (PrevStr^);
                WriteLn ('error 4');
              end;
              AddStr2Topic (PrevStr^, TblTopic, TblTopicName, CurInt, CurSubF, CurCat, False);

              AddStr2Topic (TblTopicName + PrevStr^, Topic, TopicName, CurInt, CurSubF, CurCat, True);
              TblTopic^.SetHeader (PrevStr^);
              Tables^.AddKeyword (TopicName, 0);
              AddStr2Topic (TblTopicName + ' '#2 + TopicName + #2
                          + PrevStr^, Tables, TablesName, CurInt, CurSubF, CurCat, True);
            end else
              AddNextStringToTopicAsATblRef := True;
            DisposeStr (PrevStr);

            AddStr2Topic (Str, TblTopic, TblTopicName, CurInt, CurSubF, CurCat, False);
          end else begin
            if TblStarted then begin
              if AddNextStringToTopicAsATblRef then begin
                AddStr2Topic (TblTopicName + ' ' + Str, Topic, TopicName, CurInt, CurSubF, CurCat, True);
                TblTopic^.SetHeader (Str);
                Tables^.AddKeyword (TopicName, 0);
                AddStr2Topic (TblTopicName + ' '#2 + TopicName + #2
                            + ' ' + Str, Tables, TablesName, CurInt, CurSubF, CurCat, True);
                AddNextStringToTopicAsATblRef := False;
              end;

              AddStr2Topic (Str, TblTopic, TblTopicName, CurInt, CurSubF, CurCat, False);
            end;
          end;

          if not TblStarted then
            AddStr2Topic (Str, Topic, TopicName, CurInt, CurSubF, CurCat, True);
        end;
      end;
    end;

    if not TblClosed then begin
      TblTopic^.AddKeywordAtStart (OriginalTopicName);
      TblTopic^.SetSubHeader (ExtendedHeader);
      FO. IdxTbl. Insert (New (PIndexEntry, Init (
        TblTopicName, 0, TblTopic)));
      TblStarted := False;
      TblClosed := True;
    end;

    if not SectionClosed then begin
      if Pos ('CMOS', StUpcase2 (FileName)) > 0 then begin
        CMOS^.AddKeyword (OriginalTopicName, 0);
        AddStr2Topic (ExtendedHeader,
                      CMOS, CMOSName, CurInt, CurSubF, CurCat, True);
      end else
      if Pos ('FARCALL', StUpcase2 (FileName)) > 0 then begin
        FarCall^.AddKeyword (OriginalTopicName, 0);
        AddStr2Topic (ExtendedHeader,
                      FarCall, FarCallName, CurInt, CurSubF, CurCat, True);
      end else
      if Pos ('MEMORY', StUpcase2 (FileName)) > 0 then begin
        Memory^.AddKeyword (OriginalTopicName, 0);
        AddStr2Topic (ExtendedHeader,
                      Memory, MemoryName, CurInt, CurSubF, CurCat, True);
      end else
      if Pos ('MSR', StUpcase2 (FileName)) > 0 then begin
        MSR^.AddKeyword (OriginalTopicName, 0);
        AddStr2Topic (ExtendedHeader,
                      MSR, MSRName, CurInt, CurSubF, CurCat, True);
      end else
      if Pos ('OPCODES', StUpcase2 (FileName)) > 0 then begin
        OpCodes^.AddKeyword (OriginalTopicName, 0);
        AddStr2Topic (ExtendedHeader,
                      OpCodes, OpCodesName, CurInt, CurSubF, CurCat, True);
      end else
      if Pos ('PORTS', StUpcase2 (FileName)) > 0 then begin
        Ports^.AddKeyword (OriginalTopicName, 0);
        AddStr2Topic (ExtendedHeader,
                      Ports, PortsName, CurInt, CurSubF, CurCat, True);
      end else
      if  (FileIsATopic = '')
      and ((not (ExtendedHeader [2] in HexChars))
        or (not (ExtendedHeader [3] in HexChars)))
      then begin
        IntList^.AddKeyword (OriginalTopicName, 0);
        AddStr2Topic (ExtendedHeader,
                      IntList, IntListName, CurInt, CurSubF, CurCat, True);
      end;

      Topic^.SetHeader (NoLinks (ExtendedHeader));
      FO. IdxTbl. Insert (New (PIndexEntry, Init (
        TopicName, 0, Topic)));
      SectionClosed := True;
    end;

    Close (FI);
  end else
    ProcessInterrup := False;
end;

var
  Param: string;
  C: Char;
  T: PTopic;
  I: Integer;

  KeyFile: Text;
  KeyStr: string;

  BoldFile: Text;
  BoldStr: string;

  SwapFileSize: Longint;

  F: file;

begin
  WriteLn;
  WriteLn ('=== Int2RTF Interrupt List Compiler v1.2 Copyright (C) 1996 Slava Gostrenko ===');
  WriteLn;

  for I := 1 to ParamCount do begin
    Param := StUpcase2 (ParamStr (I));
    if Param [1] in ['/', '\', '-'] then
      if Param [2] in ['?', 'H'] then begin
        WriteLn ('Converts Ralf Brown''s Interrupt List into Rich Text Format (.RTF)');
        WriteLn ('to compile it further into windows help file (.HLP) with HC31.EXE.');
        WriteLn;
        WriteLn ('Usage: Int2RTF <enter>');
        Exit;
      end;
  end;

  SwapFileSize := Longint (6144)*1024 - MemAvail;
  if SwapFileSize > 0 then
    SwapFileSize := SwapFileSize and (-1024)
  else
    SwapFileSize := 0;
  if SwapFileSize > 0 then begin
    MemInitSwapFile ('int2rtf.swp', SwapFileSize);
    WriteLn ('swap file size - ', SwapFileSize);
  end;

  New (SwapFile, Init ('topics.swp', stCreate, 2048));

  Hdrs. Init (256, 256);

  FO. Init ('intwin.rtf', stCreate, 32768);
  Assign (IncompPattern, 'incomplt.log');
  Rewrite (IncompPattern);

  New (T, Init (16, 16));
  T^. AddString ('Visit the home page of Slava Gostrenko at http://sunny.aha.ru/~gw/');
  T^. AddString (' ');
  T^. AddString ('There  you  may check for the latest versions of Int2RTF and other software.');
  T^. AddString ('You  can  register  on my page to get automatic notifications when Interrupt');
  T^. AddString ('List or Int2RTF is updated.');
  T^. AddString (' ');
  T^. AddString ('=== ARVID AUDIO ===');
  T^. AddString (' ');
  T^. AddString ('is a CD quality digital audio tape recorder made of Sound Blaster sound card');
  T^. AddString ('and  Arvid  streamer  board.  Arvid is a PC board priced at as little as $60');
  T^. AddString ('that  makes  a  streamer  of your home video tape recorder. It is capable of');
  T^. AddString ('storing  2  GigaBytes of data on a single tape. With the help of Arvid Audio');
  T^. AddString ('software you may record 3 hours of digital audio sound on a regular 180 min.');
  T^. AddString ('videotape.  Arvid  Audio  records from all audio sources available on(via) a');
  T^. AddString ('Sound Blaster sound card, e.i. CD player, Microphone, Line In. And now it is');
  T^. AddString ('capable  of  Direct  Digital Recording From CD! Download it now and you will');
  T^. AddString ('get 3 hours of 44.1 kHz 16 bit stereo sound on a $2 videotape! Visit my home');
  T^. AddString ('page for more info and references.');
  T^. AddString (' ');
  T^. AddString ('=== ARVID DRAW ===');
  T^. AddString (' ');
  T^. AddString ('copies a text file to the TV screen via Arvid. Requires Arvid 1031.');
  T^. AddString (' ');
  T^. AddString ('=== CD2WAV ===');
  T^. AddString (' ');
  T^. AddString ('is  a  CD-DA  (Digital  Audio)  grabber  with  an advanced jitter correction');
  T^. AddString ('algorithm.');
  T^. AddString (' ');
  T^. AddString ('=== CD2SB ===');
  T^. AddString (' ');
  T^. AddString ('is  a  CD-DA (Digital Audio) player that plays CDs via your sound card''s DAC');
  T^. AddString ('(Digital-to-Analog  Converter)  rather  then  CD-ROM drive''s DAC. So you can');
  T^. AddString ('compare the quality of the DACs. Requires Sound Blaster SB16.');
  T^. AddString (' ');
  T^. AddString ('=== INT2TPH ===');
  T^. AddString (' ');
  T^. AddString ('is  a  program  that converts Ralf Brown''s Interrupt List into Borland Turbo');
  T^. AddString ('Help File (.TPH file format) to use it with Turbo Help TSR or within Borland');
  T^. AddString ('(Turbo)  Pascal  IDE. Int2TPH uses hypertext features of the Interrupt List.');
  T^. AddString ('It  is  the  first  (and the only) Interrupt List compiler that makes a real');
  T^. AddString ('hypertext  of  the  Interrupt  List.  It is made possible due to an advanced');
  T^. AddString ('pattern  processing  technique  used  in  the  compiler. Not only it creates');
  T^. AddString ('comprehensive  indexes  for  all  the  topics in the list but it also allows');
  T^. AddString ('users to add their own indexes to the help file. Int2TPH is distributed with');
  T^. AddString ('source texts!');
  T^. AddString (' ');
  T^. AddString ('=== BORLAND PASCAL AUTO CORRECTOR ===');
  T^. AddString (' ');
  T^. AddString ('is  a  program  that  makes  it much easier to edit your programs in Borland');
  T^. AddString ('Pascal''s  IDE. Using expandable dictionary BP Auto Corrector beautifies your');
  T^. AddString ('sources  on  the fly. Type "tmysuperobject" and look at the screen. You will');
  T^. AddString ('see "TMySuperObject". And you do not have to press shift keys to type such a');
  T^. AddString ('nice  identifiers.  AutoSave  feature  will unglue your hands from <F2> key.');
  T^. AddString ('VideoSubst  feature  will enable Borland Pascal''s IDE to work in video modes');
  T^. AddString ('others  than 80x25 and 80x50. Now you may set up your BP to work in any text');
  T^. AddString ('video  mode  that  is  supported  by your video card. You may use VESA video');
  T^. AddString ('modes  too  and enjoy modes with the resolution up to 132x60! Auto Corrector');
  T^. AddString ('includes  patches  for BP to make a real full screen editor with no menu and');
  T^. AddString ('status  lines. It means 2 more lines will be used for displaying your source');
  T^. AddString ('texts.');
  T^. AddString (' ');
  T^. AddString ('=== TICKTOSS ===');
  T^. AddString (' ');
  T^. AddString ('is a fileechoprocessor for end-user fidonet systems. TickToss is just a .bat');
  T^. AddString ('file.  No  .exe''s  or  .com''s.  But it has all the features an end-user ever');
  T^. AddString ('needs. Automatic creation of new fileechoes with meaningful directory names.');
  T^. AddString ('Creating  and  updating of area configuration file. Creating and updating of');
  T^. AddString ('files.bbs''s  in  your  fileecho  areas.  Support  for  long  multilined file');
  T^. AddString ('descriptions. Logging of performed actions. And all the abovelisted features');
  T^. AddString ('are implemented as a single .bat file. TickToss requires 4dos or compaitable');
  T^. AddString ('command processor.');
  T^. AddString (' ');
  T^. AddString ('=== VOXEL EARTH ===');
  T^. AddString (' ');
  T^. AddString ('It  is  a  demo  of my new real-time voxel 3D engine. Download it and have a');
  T^. AddString ('virtual  flight over the virtual (but quite realistic) landscape. Pentium or');
  T^. AddString ('better CPU is recommended.');
  T^. AddString (' ');
  T^. AddString ('=== And MORE... ===');
  T^. AddString (' ');
  T^. AddString ('Visit my homepage NOW! ;-)');
  T^. AddString (' ');
  FO. IdxTbl. Insert (New (PIndexEntry, Init (
      'http://sunny.aha.ru/~gw/', 0, T)));

  for I := Low (IntLists) to High (IntLists) do begin
    New (IntLists [I], Init (16, 16));
    IntNames [I] := MakeCorrectTopicName ('INT ' + HexByte (I));
  end;

  New (IntListIndex, Init (16, 16));
  IntListIndexName := MakeCorrectTopicName (' INTERRUPT LIST INDEX ');

  Assign (Interrup1st, 'interrup.1st');
  {$I-}
  Reset (Interrup1st);
  {$I+}
  if IOResult = 0 then begin
    if not EOF (Interrup1st) then begin
      ReadLn (Interrup1st, CopyrightStr);
      Tab2Spc (CopyrightStr);
      while Pos ('       ', CopyrightStr) > 0 do
        Delete (CopyrightStr, Pos ('       ', CopyrightStr), 1);
      if CopyrightStr <> '' then
        IntListIndex^. SetHeader (CopyrightStr);

      if not EOF (Interrup1st) then begin
        ReadLn (Interrup1st, CopyrightStr);
        Tab2Spc (CopyrightStr);
        if CopyrightStr <> '' then
          IntListIndex^. SetSubHeader (CopyrightStr);
      end;
    end;

    Close (Interrup1st);
  end;

  IntListIndex^.AddString (' ===    This help file was compiled with    ===');
  IntListIndex^.AddString (' === Int2RTF v1.2 (C) 1996 Slava Gostrenko. ===');
  IntListIndex^.AddKeyword ('http://sunny.aha.ru/~gw/', 0);
  IntListIndex^.AddString (' === '#2'http://sunny.aha.ru/~gw/'#2' or gw@aha.ru, ===');
  IntListIndex^.AddString (' === FidoNet 2:5020/201.105,2:5020/468.105. ===');
  IntListIndex^.AddString (' ');
  IntListIndex^.AddKeyword ('TITLES', 0);
  IntListIndex^.AddString (' '#2'Interrupts'#2);

  KeyLists. Init (1, 1);
  KeyNames. Init (1, 1);
  Assign (KeyFile, 'int_keys.txt');
  {$I-}
  Reset (KeyFile);
  {$I+}
  if IOResult = 0 then begin
    while not EOF (KeyFile) do begin
      ReadLn (KeyFile, KeyStr);
      if KeyStr <> '' then begin
        KeyLists. AtInsert (KeyLists. Count, New (PTopic, Init (1, 1)));
        KeyStr := MakeCorrectTopicName (KeyStr);
        KeyNames. AtInsert (KeyNames. Count, NewStr (KeyStr));

        IntListIndex^.AddKeyword (KeyStr, 0);
        IntListIndex^.AddString (' '#2 + KeyStr + #2);
      end;
    end;

    Close (KeyFile);
  end;

  BoldNames. Init (1, 1);
  Assign (BoldFile, 'int_bold.txt');
  {$I-}
  Reset (BoldFile);
  {$I+}
  if IOResult = 0 then begin
    while not EOF (BoldFile) do begin
      ReadLn (BoldFile, BoldStr);
      if BoldStr <> '' then
        BoldNames. AtInsert (BoldNames. Count, NewStr (BoldStr));
    end;

    Close (BoldFile);
  end;

  New (IntList, Init (16, 16));
  IntListName := MakeCorrectTopicName ('Interrupt List Misc. Stuff');
  IntListIndex^.AddKeyword (IntListName, 0);
  IntListIndex^.AddString (' '#2 + IntListName + #2);

  New (Tables, Init (16, 16));
  TablesName := MakeCorrectTopicName ('Tables');
  IntListIndex^.AddKeyword (TablesName, 0);
  IntListIndex^.AddString (' '#2 + TablesName + #2);

  New (CMOS, Init (16, 16));
  CMOSName := MakeCorrectTopicName ('CMOS');
  IntListIndex^.AddKeyword (CMOSName, 0);
  IntListIndex^.AddString (' '#2 + CMOSName + #2);

  New (FarCall, Init (16, 16));
  FarCallName := MakeCorrectTopicName ('Far Calls');
  IntListIndex^.AddKeyword (FarCallName, 0);
  IntListIndex^.AddString (' '#2 + FarCallName + #2);

  New (Memory, Init (16, 16));
  MemoryName := MakeCorrectTopicName ('Memory');
  IntListIndex^.AddKeyword (MemoryName, 0);
  IntListIndex^.AddString (' '#2 + MemoryName + #2);

  New (MSR, Init (16, 16));
  MSRName := MakeCorrectTopicName ('Model-Specific Registers');
  IntListIndex^.AddKeyword (MSRName, 0);
  IntListIndex^.AddString (' '#2 + MSRName + #2);

  New (OpCodes, Init (16, 16));
  OpCodesName := MakeCorrectTopicName ('Opcodes List');
  IntListIndex^.AddKeyword (OpCodesName, 0);
  IntListIndex^.AddString (' '#2 + OpCodesName + #2);

  New (Ports, Init (16, 16));
  PortSName := MakeCorrectTopicName ('Ports');
  IntListIndex^.AddKeyword (PortsName, 0);
  IntListIndex^.AddString (' '#2 + PortsName + #2);

  ProcessInterrup ('interrup.1st', '');
  ProcessInterrup ('category.key', '');
  ProcessInterrup ('86bugs.lst', '86 Bugs');
  IntListIndex^.AddKeyword ('86 Bugs', 0);
  IntListIndex^.AddString (' '#2'86 Bugs'#2);
  ProcessInterrup ('biblio.lst', '');
  ProcessInterrup ('cmos.lst', '');
  ProcessInterrup ('farcall.lst', '');
  ProcessInterrup ('glossary.lst', 'Glossary of The Interrupt List');
  IntListIndex^.AddKeyword ('Glossary of The Interrupt List', 0);
  IntListIndex^.AddString (' '#2'Glossary of The Interrupt List'#2);
  ProcessInterrup ('memory.lst', '');
  ProcessInterrup ('msr.lst', '');
  ProcessInterrup ('opcodes.lst', '');
  ProcessInterrup ('overview.lst', '');
  ProcessInterrup ('ports.lst', '');
  ProcessInterrup ('tables.lst', '');
  ProcessInterrup ('interrup.pri', 'Interrupt Primer');
  IntListIndex^.AddKeyword ('Interrupt Primer', 0);
  IntListIndex^.AddString (' '#2'Interrupt Primer'#2);
  ProcessInterrup ('rbrown.txt', 'Ralf Brown');
  IntListIndex^.AddKeyword ('Ralf Brown', 0);
  IntListIndex^.AddString (' '#2'Ralf Brown'#2);

  if not ProcessInterrup ('interrup.lst', '') then
    for C := 'a' to 'z' do
      if not ProcessInterrup ('interrup.' + C, '') then
        Break;

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    PortsName, 0, Ports)));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    MemoryName, 0, Memory)));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    MSRName, 0, MSR)));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    OpCodesName, 0, OpCodes)));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    FarCallName, 0, FarCall)));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    CMOSName, 0, CMOS)));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    TablesName, 0, Tables)));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    IntListName, 0, IntList)));

  if KeyLists. Count > 0 then
    for I := 0 to KeyLists. Count - 1 do
      FO. IDXTbl. Insert (New (PIndexEntry, Init (
        PString (KeyNames. At (I))^, 0, PTopic (KeyLists. Items^ [I]))));

  FO. IdxTbl. Insert (New (PIndexEntry, Init (
    IntListIndexName, 0, IntListIndex)));

  for I := Low (IntLists) to High (IntLists) do
    FO. IdxTbl. Insert (New (PIndexEntry, Init (
      IntNames [I], 0, IntLists [I])));

  Close (IncompPattern);
  FO. Done;

  WriteLn (Hdrs. Count, ' topics processed.');
  Hdrs. Done;

  SwapFile^.Seek (0);
  SwapFile^.Truncate;
  Dispose (SwapFile, Done);
  Assign (F, 'topics.swp');
  Erase (F);

  if SwapFileSize > 0 then
    MemCloseSwapFile (1);
end.
