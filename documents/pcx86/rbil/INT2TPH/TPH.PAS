{ TPH unit for the Interrupt List -> .TPH compiler.            }
{ The software included, data formats and basic algorithms are }
{ copyright (C) 1996 by Slava Gostrenko. All rights reserved.  }

{$X+}
unit
  TPH;

interface

uses
  Objects;

const
  HexChars = ['0'..'9', 'A'..'F', 'a'..'f'];

  TPFileStamp = 'TURBO PASCAL HELP FILE.'#0
              + #$1A
              + '$*$* &&&&$*$'#0
              + #$34#02;
  FileStamp : array [0 .. Length (TPFileStamp) - 1] of Char = TPFileStamp;

  Of_CaseSense = $0004;

  CT_Nibble = 2;

  NC_RawChar = $F;
  NC_RepChar = $E;

type
  TRecType =
    (RT_FileHeader,
     RT_Context,
     RT_Text,
     RT_Keyword,
     RT_Index,
     RT_Compression,
     RT_ScreenTags);

  TRecHdr = record
    RecType: TRecType;
    RecLength: Word;
  end;

  TPFileHdrRec = record
    Options: Word;
    MainIndexScreen: Word;
    MaxScreenSize: Word;
    Height: Byte;
    Width: Byte;
    LeftMargin: Byte;
  end;

  TPCompRec = record
    CompType: Byte;
    CharTable: array [0..13] of Char;
  end;

  TFileStart = record
    FileHdr_ : TRecHdr;
    FileHdr  : TPFileHdrRec;
    CompRec_ : TRecHdr;
    CompRec  : TPCompRec;
  end;

  PCtxTbl = ^TCtxTbl;
  TCtxTbl = record
    N: Word;
    T: array [0..16382] of Longint;
  end;

  TCharCounter = array [Char] of Longint;

  PIdxTbl = ^TIdxTbl;
  TIdxTbl = object (TSortedCollection)
    function  KeyOf (Item: Pointer): Pointer; virtual;
    function  Compare (Key1, Key2: Pointer): Integer; virtual;
    procedure SetCtxs;
    function  RealCount: Word;
    procedure Write (var S: TStream);
    procedure AltWrite (var S: TStream; const GlobalAltName: string);
    procedure ReBuild (Level: Integer);
  end;

  PTopic = ^TTopic;
  TTopic = object (TStringCollection)
    Size: Longint;
    Keywords: TStringCollection;
    InSwap: Boolean;
    SwapPos: Longint;

    constructor Init(ALimit, ADelta: Integer);

    procedure   Store2Swap (var S: TStream);
    procedure   RestoreFromSwap (var S: TStream);

    procedure   AddString (S: string);
    procedure   UpdateCharCounter (var C: TCharCounter);
    procedure   Write (var S: TStream; Compression: TPCompRec);

    procedure   AddKeyword (S: string; StepBack: Integer);
    procedure   WriteKeywords (var S: TStream; var IdxTbl: TIdxTbl);
  end;

  PIndexEntry = ^TIndexEntry;
  TIndexEntry = object (TObject)
    PS, PS1: PString;
    Ctx: Word;
    Topic: PTopic;
    Indexed: Boolean;

    constructor Init (const S, S1: string; ACtx: Word; var ATopic: PTopic; IsIndexed: Boolean);
    procedure   Write (var S: TStream; const PrevStr: string);
    procedure   AltWrite (var S: TStream);
    destructor  Done; virtual;
  end;

  PHelpFile = ^THelpFile;
  THelpFile = object (TBufStream)
    FileStart: TFileStart;
    CtxTbl: PCtxTbl;
    IdxTbl: TIdxTbl;

    constructor Init(FileName: FNameStr; Mode, Size: Word);
    destructor  Done; virtual;
  end;

var
  SwapFile: PBufStream;

implementation

uses
  Upcaser;

procedure CharCounter2CompRec (var C: TCharCounter; var R: TPCompRec);
var I: Integer;
    J, MC: Char;
    M: Longint;
begin
  for I := Low (R. CharTable) + 1 to High (R. CharTable) do begin
    M := 0;
    MC := #0;

    for J := Low (C) to High (C) do
      if C [J] > M then begin
        MC := J;
        M := C [J];
      end;

    R. CharTable [I] := MC;
    C [MC] := 0;
  end;
end;

{ TTopic = object (TStringCollection) }

constructor TTopic. Init(ALimit, ADelta: Integer);
begin
  inherited Init (ALimit, ADelta);
  Size := 0;
  Keywords. Init (ALimit, ADelta);

  InSwap := False;
  SwapPos := -1;
end;

procedure   TTopic. Store2Swap (var S: TStream);
var I: Integer;
begin
  if not InSwap then begin
    if SwapPos = -1 then begin
      SwapPos := S. GetSize;
      S. Seek (SwapPos);
      S. Write (Count, 2);
      if Count > 1 then
        for I := 1 to Count - 1 do begin
          S. WriteStr (Items^[I]);
          DisposeStr (Items^[I]);
          Items^[I] := nil;
        end;
    end else
      if Count > 1 then
        for I := 1 to Count - 1 do begin
          DisposeStr (Items^[I]);
          Items^[I] := nil;
        end;

    InSwap := True;
  end;
end;

procedure   TTopic. RestoreFromSwap (var S: TStream);
var I, C: Integer;
begin
  if InSwap then
    if SwapPos = -1 then begin
      WriteLn ('Swapping error 2');
      Halt (1);
    end else begin
      S. Seek (SwapPos);
      S. Read (C, 2);
      if C > 1 then
        for I := 1 to C - 1 do
          Items^[I] := S. ReadStr;
      InSwap := False;
    end;
end;

procedure   TTopic. AddString (S: string);
var I, J: Integer;
begin
  AtInsert (Count, NewStr (S));

  if Length (S) < 77 then begin
    Inc (Size, Length (S) + 1);
  end else begin
    I := 77;

    while (I > Length (S) - 75) and (S [I] <> ' ') do
      Dec (I);

    Inc (Size, I);

    J := I - 1 - (Length (S) - I + 1);
    if J < 0 then
      J := 0;

    Inc (Size, J + Length (S) - I + 1 + 1);
  end;

  if Size > 65535 then
    WriteLn ('error 1');
end;

procedure TTopic. UpdateCharCounter (var C: TCharCounter);
  procedure DoOneString (PS: PString); far;
  var I: Integer;
  begin
    if PS <> nil then
      for I := 1 to Length (PS^) do
        Inc (C [PS^ [I]]);
  end;
begin
  RestoreFromSwap (SwapFile^);
  ForEach (@DoOneString);
  Store2Swap (SwapFile^);
end;

procedure TTopic. Write (var S: TStream; Compression: TPCompRec);
var
  Buf: Byte;
  Nibble: Integer;

  procedure  WriteNibble (X: Byte);
  begin
    if Nibble = 0 then begin
      Buf := X;
      Nibble := 1;
    end else begin
      Buf := Buf + X shl 4;
      S. Write (Buf, 1);
      Nibble := 0;
    end;
  end;

  procedure  WriteChar (C: Char);
  var I: Integer;
  begin
    I := Pos (C, Compression. CharTable);
    if I > 0 then
      WriteNibble (I - 1)
    else begin
      WriteNibble (NC_RawChar);
      WriteNibble (Ord (C) and $F);
      WriteNibble (Ord (C) shr 4);
    end;
  end;

  procedure WriteOneString (PS: PString); far;
    procedure DoWrite (const S: string);
    var I, J: Integer;
    begin
      for I := 1 to Length (S) do begin
        J := I + 1;
        while (J <= Length (S)) and (S [J] = S [I]) do
         Inc (J);
        if ((Pos (S [I], Compression. CharTable) = 0) and (J - I > 1))
        or (J - I > 2) then begin
          WriteNibble (NC_RepChar);
          if J - I > 17 then
            J := I + 17;
          WriteNibble (J - I - 2);
          WriteChar (S [I]);
          I := J - 1;
        end else
          WriteChar (S [I]);
      end;

      WriteNibble (0);
    end;
  var I, J, KeyCnt, AllKeysCnt: Integer;
      Spcs: string;
  begin
    if PS <> nil then
      if Length (PS^) < 77 then
        DoWrite (PS^)
      else begin
        AllKeysCnt := 0;
        KeyCnt := 0;
        for I := 1 to Length (PS^) do
          if PS^ [I] = #2 then begin
            Inc (AllKeysCnt);
            if I <= 76 then
              Inc (KeyCnt);
          end;

        I := 77;

        while Odd (KeyCnt)
        or   ((I > Length (PS^) - 75)
          and (not (PS^ [I] in [' ']))
          and (not (PS^ [I - 1] in [','])))
        do begin
          Dec (I);
          if PS^ [I] = #2 then
            Dec (KeyCnt);
        end;

        DoWrite (Copy (PS^, 1, I - 1));

        J := I - 1 - (Length (PS^) - I + 1) - KeyCnt + (AllKeysCnt - KeyCnt);
        if J > 0 then begin
          Spcs [0] := Chr (J);
          FillChar (Spcs [1], Ord (Spcs [0]), ' ');
        end else
          Spcs := '';

        DoWrite (Spcs + Copy (PS^, I, Length (PS^) - I + 1));
      end
    else
      DoWrite ('');
  end;

var
  R: TRecHdr;
  TextRecStart,
  TextRecEnd: Longint;

begin
  RestoreFromSwap (SwapFile^);

  TextRecStart := S. GetPos;
  R. RecType := RT_Text;
  R. RecLength := 0;
  S. Write (R, SizeOf (R));

  Nibble := 0;
  ForEach (@WriteOneString);

  WriteChar (#1);

  if Nibble = 1 then
    WriteNibble (0);

  TextRecEnd := S. GetPos;
  R. RecLength := TextRecEnd - TextRecStart - SizeOf (R);
  S. Seek (TextRecStart);
  S. Write (R, SizeOf (R));
  S. Seek (TextRecEnd);

  Store2Swap (SwapFile^);
end;

procedure   TTopic. AddKeyword (S: string; StepBack: Integer);
begin
  Keywords. AtInsert (Keywords. Count - StepBack, NewStr (S));
end;

procedure   TTopic. WriteKeywords (var S: TStream; var IdxTbl: TIdxTbl);
var
  R: TRecHdr;
  TmpW: Word;
  I, J, K, MinL, SaveMinLIdx, MatchLen, DecCnt: Integer;
  TmpS, MatchS, Helper: string;
  MatchFound: Boolean;
begin
  R. RecType := RT_Keyword;
  R. RecLength := 6 + Keywords. Count * 2;
  S. Write (R, SizeOf (R));

  TmpW := 0;
  S. Write (TmpW, SizeOf (TmpW));
  TmpW := 0;
  S. Write (TmpW, SizeOf (TmpW));

  TmpW := Keywords. Count;
  S. Write (TmpW, SizeOf (TmpW));

  if Keywords. Count > 0 then
    for I := 0 to Keywords. Count - 1 do begin
      TmpS := StUpcase2 (PString (Keywords. At (I))^);

      J := Pos ('"', TmpS);
      if J > 0 then begin
        if TmpS [Length (TmpS)] <> '"' then begin
          Helper := '';
          WriteLn ('error in keyword format - ', TmpS)
        end else begin
          Helper := Copy (TmpS, J + 1, Length (TmpS) - J - 1);
          TmpS [0] := Chr (J - 1);
        end;
      end else
        Helper := '';

      DecCnt := 0;

      MatchFound := False;
      MinL := High (MinL);

      repeat
        IdxTbl. Search (@TmpS, J);
        for K := J to IdxTbl. Count - 1 do begin
          MatchS := StUpcase2 (PIndexEntry (IdxTbl. At (K))^.PS^);
          if Copy (MatchS, 1, Length (TmpS))
          <> TmpS then
            Break
          else begin
            if  ((Helper = '')
              or (Pos (Helper, StUpcase2 (PString (PIndexEntry (
                       IdxTbl. At (K))^. Topic^. At (0))^)) > 0))
            and (Length (MatchS) - Length (TmpS) < MinL)
            then begin
              MinL := Length (MatchS) - Length (TmpS);
              MatchLen := Length (TmpS);
              SaveMinLIdx := K;
            end;
          end;
        end;

        if (DecCnt < 2) and (MinL < High (MinL)) then begin
          MatchFound := True;
          J := SaveMinLIdx;
        end;

        Dec (TmpS [0]);
        Inc (DecCnt);
      until MatchFound or (Length (TmpS) < 2);

      if (Helper <> '') and (MinL < High (MinL)) then
        MinL := 0;

      if not MatchFound then begin
        MatchFound := MinL < High (MinL);
        J := SaveMinLIdx;
      end;

      if  ( ((Helper = '') or (MinL = High (MinL)))
        and (((MatchLen < 4) and (MinL > 0)) or (MinL > 1))
          )
      and (TmpS [1] in HexChars) and (TmpS [2] in HexChars) then begin
        TmpS := 'INT ' + TmpS [1] + TmpS [2];
        if not IdxTbl. Search (@TmpS, J) then begin
          WriteLn ('error searching for - ', TmpS);
        end else begin
          MinL := 0;
          MatchFound := True;
        end;
      end;

      if  ( ((Helper = '') or (MinL = High (MinL)))
        and (((MatchLen < 5) and (MinL > 0)) or (MinL > 1))
          )
      and (TmpS [1] = 'P')
      and (TmpS [2] in HexChars + ['x', 'X']) and (TmpS [3] in HexChars + ['x', 'X'])
      and (TmpS [4] in HexChars + ['x', 'X']) and (TmpS [5] in HexChars + ['x', 'X']) then begin
        TmpS := 'PORTS';
        if not IdxTbl. Search (@TmpS, J) then begin
          WriteLn ('error searching for - ', TmpS);
        end else begin
          MinL := 0;
          MatchFound := True;
        end;
      end;

      TmpW := PIndexEntry (IdxTbl. At (J))^.Ctx;

      if not MatchFound then begin
        WriteLn (PString (At (0))^);
        WriteLn ('error searching for - ', PString (Keywords. At (I))^);
        WriteLn ('found match         - ', PIndexEntry (IdxTbl. At (J))^.PS^);
        TmpW := 1;
      end else
        if MinL > 1 then begin
          WriteLn (PString (At (0))^);
          WriteLn ('approximate match to - ', PString (Keywords. At (I))^);
          WriteLn ('is                   - ', PIndexEntry (IdxTbl. At (J))^.PS^);
          TmpW := 1;
        end;

      S. Write (TmpW, SizeOf (TmpW));
    end;
end;

{ TIndexEntry = object (TObject) }

constructor TIndexEntry. Init (const S, S1: string; ACtx: Word; var ATopic: PTopic; IsIndexed: Boolean);
begin
  inherited Init;
  PS := NewStr (S);
  PS1 := NewStr (S1);
  Ctx := ACtx;

  Topic := ATopic;
  ATopic := nil;
  Topic^.Store2Swap (SwapFile^);

  Indexed := IsIndexed;
end;

procedure   TIndexEntry. Write (var S: TStream; const PrevStr: string);
var
  RptChars: Integer;
  LengthCode: Byte;
begin
  if Length (PS^) > 31 then
    WriteLn ('error 2');

  RptChars := 0;
  while (RptChars < Length (PrevStr))
  and   (PS^ [RptChars + 1] = PrevStr [RptChars + 1]) do
    Inc (RptChars);

  if Length (PS^) = RptChars then
    WriteLn ('error - duplicate index entry!');

  if RptChars > 7 then
    RptChars := 7;

  LengthCode := (Length (PS^) - RptChars)
              + (RptChars) shl 5;

  S. Write (LengthCode, SizeOf (LengthCode));
  S. Write (PS^ [RptChars + 1],  Length (PS^) - RptChars);
  S. Write (Ctx, SizeOf (Ctx));
end;

procedure   TIndexEntry. AltWrite (var S: TStream);
var B: Byte;
begin
  if Length (PS1^) > 36 then
    WriteLn ('error 2A');

  S. Write (Ctx, SizeOf (Ctx));
  S. Write (PS1^,  Length (PS1^) + 1);
  B := 0;
  S. Write (B, SizeOf (B));
end;

destructor  TIndexEntry. Done;
begin
  DisposeStr (PS1);
  DisposeStr (PS);
  inherited Done;
end;

{ TIdxTbl = object (TSortedCollection) }

function  TIdxTbl. KeyOf (Item: Pointer): Pointer;
begin
  KeyOf := PIndexEntry (Item)^. PS;
end;

function  TIdxTbl. Compare (Key1, Key2: Pointer): Integer;
begin
  if (Key1 = nil) or (StUpcase2 (PString (Key1)^) < StUpcase2 (PString (Key2)^)) then
    Compare := -1
  else
    if (Key2 <> nil) and (StUpcase2 (PString (Key1)^) = StUpcase2 (PString (Key2)^)) then
      Compare := 0
    else
      Compare := 1;
end;

procedure TIdxTbl. SetCtxs;
var I: Integer;
begin
  for I := 0 to Count - 1 do
    PIndexEntry (At (I))^. Ctx := I + 1;
end;

function  TIdxTbl. RealCount: Word;
var Cnt: Word;
  procedure AddOne (var X: TIndexEntry); far;
  begin
    if  (X. PS <> nil)
    and (X. PS^ <> '')
    and  X. Indexed then
      Inc (Cnt);
  end;
begin
  Cnt := 0;
  ForEach (@AddOne);
  RealCount := Cnt;
end;

procedure TIdxTbl. Write (var S: TStream);
var PrevStr: string;
  procedure WriteOne (var X: TIndexEntry); far;
  begin
    if  (X. PS <> nil)
    and (X. PS^ <> '')
    and  X. Indexed then begin
      X. Write (S, PrevStr);
      PrevStr := X. PS^;
    end;
  end;
begin
  PrevStr := '';
  ForEach (@WriteOne);
end;

procedure TIdxTbl. AltWrite (var S: TStream; const GlobalAltName: string);
  procedure WriteOne (var X: TIndexEntry); far;
  begin
    if  (X. PS1 <> nil)
    and (X. PS1^ <> '')
    and  X. Indexed then
      X. AltWrite (S);
  end;
var
  TmpW: Word;
  TmpS: string;
begin
  TmpW := $FFFF;
  S. Write (TmpW, SizeOf (TmpW));

  TmpS := GlobalAltName;
  TmpS [Length (GlobalAltName) + 1] := #0;
  S. Write (TmpS, Length (GlobalAltName) + 2);

  ForEach (@WriteOne);
end;

procedure TIdxTbl. ReBuild (Level: Integer);
var PrevStr: string;
  procedure ReBuildOne (var X: TIndexEntry); far;
  var CurStr: string;
      I: Integer;
  begin
    if  (X. PS <> nil)
    and (X. PS^ <> '')
    and  X.Indexed then begin
      if Length (X. PS^) > Level then begin
        CurStr := Copy (X. PS^, 1, Level);

        for I := Length (CurStr) downto 2 do
          if CurStr [I] = ' ' then begin
            CurStr [0] := Chr (I - 1);
            Break;
          end;

        DisposeStr (X. PS);
        X. PS := NewStr (CurStr);
      end;

      PrevStr := X. PS^;
    end;
  end;
begin
  PrevStr := '';
  ForEach (@ReBuildOne);
end;

{ THelpFile = object (TBufStream) }

constructor THelpFile.Init(FileName: FNameStr; Mode, Size: Word);
begin
  inherited Init (FileName, Mode, Size);
  if Mode = stCreate then begin
    Write (FileStamp, SizeOf (FileStamp));

    with FileStart do begin
      with FileHdr_ do begin
        RecType := RT_FileHeader;
        RecLength := SizeOf (FileHdr);
      end;
      with FileHdr do begin
        Options := 0;
        MainIndexScreen := 02;
        MaxScreenSize := High (MaxScreenSize) and (-256);
        Height := 24;
        Width := 80;
        LeftMargin := 0;
      end;

      with CompRec_ do begin
        RecType := RT_Compression;
        RecLength := SizeOf (CompRec);
      end;
      with CompRec do begin
        CompType := CT_Nibble;
        FillChar (CharTable, SizeOf (CharTable), 0);
      end;
    end;
  end;

  New (CtxTbl);
  if Mode = stCreate then begin
    CtxTbl^. N := 0;
  end;

  IdxTbl. Init (MaxCollectionSize, 0);
  IdxTbl. Duplicates := True;
end;

destructor  THelpFile.Done;
var I: Integer;
    R: TRecHdr;
    TmpW: Word;
    StartPos,
    EndPos,
    CtxStart: Longint;
    CC: TCharCounter;
begin
  System. Write ('building compression record...                        '#13);
  FillChar (CC, SizeOf (CC), 0);
  for I := 0 to IdxTbl.Count - 1 do
    PIndexEntry (IdxTbl. At (I))^.Topic^.UpdateCharCounter (CC);
  CharCounter2CompRec (CC, FileStart. CompRec);
  WriteLn ('building compression record... done');

  Write (FileStart, SizeOf (FileStart));

  CtxTbl^. N := IdxTbl. Count + 1;
  CtxTbl^. T [0] := $FFFFFFFF;

  R. RecType := RT_Context;
  R. RecLength := 2 + CtxTbl^. N * 3;
  Write (R, SizeOf (R));
  Write (CtxTbl^. N, SizeOf (CtxTbl^. N));
  CtxStart := GetPos;
  if CtxTbl^. N > 0 then
    for I := 0 to CtxTbl^. N - 1 do
      Write (CtxTbl^.T [I], 3);

  IdxTbl. SetCtxs;

  I := 31;
  repeat
    StartPos := GetPos;
    R. RecType := RT_Index;
    R. RecLength := 0;
    Write (R, SizeOf (R));
    TmpW := IdxTbl. RealCount;
    Write (TmpW, 2);
    IdxTbl. Write (Self);
    EndPos := GetPos;
    WriteLn ('index size - ', EndPos - StartPos - SizeOf (R));
    Seek (StartPos);
    if EndPos - StartPos - SizeOf (R) >= 65536 then begin
      Dec (I);
      WriteLn ('rebuilding index - level ', I);
      IdxTbl. ReBuild (I);
    end;
  until EndPos - StartPos - SizeOf (R) < 65536;
  R. RecLength := EndPos - StartPos - SizeOf (R);
  Write (R, SizeOf (R));
  Seek (EndPos);

  StartPos := GetPos;
  R. RecType := RT_ScreenTags;
  R. RecLength := 0;
  Write (R, SizeOf (R));
  IdxTbl. AltWrite (Self, 'Interrupt List');
  EndPos := GetPos;
  WriteLn ('alternative index size - ', EndPos - StartPos - SizeOf (R));
  Seek (StartPos);
  if EndPos - StartPos - SizeOf (R) >= 65536 then begin
    WriteLn ('alternative index is too large.');
    Halt (1);
  end;
  R. RecLength := EndPos - StartPos - SizeOf (R);
  Write (R, SizeOf (R));
  Seek (EndPos);

  for I := 0 to IdxTbl.Count - 1 do begin
    CtxTbl^. T [PIndexEntry (IdxTbl. At (I))^.Ctx] := GetPos;
    PIndexEntry (IdxTbl. At (I))^.Topic^.Write (Self, FileStart. CompRec);

    PIndexEntry (IdxTbl. At (I))^.Topic^.WriteKeywords (Self, IdxTbl);

    System. Write (I, #13);
  end;

  Seek (CtxStart);
  if CtxTbl^. N > 0 then
    for I := 0 to CtxTbl^. N - 1 do
      Write (CtxTbl^.T [I], 3);

  IdxTbl. Done;
  if CtxTbl <> nil then
    Dispose (CtxTbl);
  inherited Done;
end;

end.
