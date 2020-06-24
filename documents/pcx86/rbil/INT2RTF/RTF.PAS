{ RTF unit for the Interrupt List -> .RTF compiler.            }
{ The software included, data formats and basic algorithms are }
{ copyright (C) 1996 by Slava Gostrenko. All rights reserved.  }

{$X+}
unit
  RTF;

interface

uses
  Objects;

const
  HexChars = ['0'..'9', 'A'..'F', 'a'..'f'];

  TPFileStamp = '{\rtf1\pc \deff1{\fonttbl{\f0\froman Times New Roman;}'#$D#$A
              + '{\f1\fmodern Courier New;}}'#$D#$A
              + '{\colortbl \red255\green0\blue0;\red0\green0\blue0;'#$D#$A
              + '\red0\green0\blue255;\red255\green255\blue255;}'#$D#$A
              + '\plain\fs18\pard\keep'#$D#$A;

  FileStamp : array [0 .. Length (TPFileStamp) - 1] of Char = TPFileStamp;

type
  PIdxTbl = ^TIdxTbl;
  TIdxTbl = object (TSortedCollection)
    function  KeyOf (Item: Pointer): Pointer; virtual;
    function  Compare (Key1, Key2: Pointer): Integer; virtual;
    procedure SetCtxs;
  end;

  PTopic = ^TTopic;
  TTopic = object (TStringCollection)
    Header,
    SubHeader: PString;

    Keywords: TStringCollection;
    InSwap: Boolean;
    SwapPos: Longint;

    constructor Init(ALimit, ADelta: Integer);
    destructor  Done; virtual;

    procedure   SetHeader (const S: string);
    procedure   SetSubHeader (const S: string);

    procedure   Store2Swap (var S: TStream);
    procedure   RestoreFromSwap (var S: TStream);

    procedure   AddString (S: string);
    procedure   Write (var S: TStream; var IdxTbl: TIdxTbl;
                       Ctx: Word; const Title: string);

    procedure   AddKeyword (S: string; StepBack: Integer);
    procedure   AddKeywordAtStart (S: string);
    function    ResolveKeyword (const I: Integer; var IdxTbl: TIdxTbl): Word;
  end;

  PIndexEntry = ^TIndexEntry;
  TIndexEntry = object (TObject)
    PS: PString;
    Ctx: Word;
    Topic: PTopic;

    constructor Init (const S: string; ACtx: Word; var ATopic: PTopic);
    destructor  Done; virtual;
  end;

  PHelpFile = ^THelpFile;
  THelpFile = object (TBufStream)
    IdxTbl: TIdxTbl;

    constructor Init(FileName: FNameStr; Mode, Size: Word);
    destructor  Done; virtual;
  end;

var
  SwapFile: PBufStream;

  BoldNames: TStringCollection;

implementation

uses
  Upcaser;

const EmptyString : string[1] = '';

function  PStr(P: PString): PString; {returns pointer to empty string if p = nil}
inline (
  $58/                {Pop    AX}
  $5A/                {Pop    DX}
  $0B/ $D2/           {Or     DX, DX}
  $75/ $05/           {JNE    Exit}
  $8C/ $DA/           {MOV    DX, DS}
  $B8/ >EmptyString   {MOV    AX, offset EmptyString}
);

{ TTopic = object (TStringCollection) }

constructor TTopic. Init(ALimit, ADelta: Integer);
begin
  inherited Init (ALimit, ADelta);
  Keywords. Init (ALimit, ADelta);

  InSwap := False;
  SwapPos := -1;

  Header := nil;
  SubHeader := nil;
end;

destructor  TTopic. Done;
begin
  DisposeStr (Header);
  DisposeStr (SubHeader);

  inherited Done;
end;

procedure   TTopic. SetHeader (const S: string);
begin
  Header := NewStr (S);
end;

procedure   TTopic. SetSubHeader (const S: string);
begin
  SubHeader := NewStr (S);
end;

procedure   TTopic. Store2Swap (var S: TStream);
var I: Integer;
begin
  if not InSwap then begin
    if SwapPos = -1 then begin
      SwapPos := S. GetSize;
      S. Seek (SwapPos);
      S. Write (Count, 2);

      if Count > 0 then
        for I := 0 to Count - 1 do begin
          S. WriteStr (Items^[I]);
          DisposeStr (Items^[I]);
          Items^[I] := nil;
        end;

      S. WriteStr (SubHeader);
      DisposeStr (SubHeader);
      SubHeader := nil;
    end else begin
      if Count > 0 then
        for I := 0 to Count - 1 do begin
          DisposeStr (Items^[I]);
          Items^[I] := nil;
        end;

      DisposeStr (SubHeader);
      SubHeader := nil;
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

      if C > 0 then
        for I := 0 to C - 1 do
          Items^[I] := S. ReadStr;

      SubHeader := S. ReadStr;

      InSwap := False;
    end;
end;

procedure   TTopic. AddString (S: string);
begin
  AtInsert (Count, NewStr (S));
end;

procedure TTopic. Write (var S: TStream; var IdxTbl: TIdxTbl;
                         Ctx: Word; const Title: string);

  const StartTopic = '\pard\keepn\li1060\fi-1060'#$D#$A;
        StartTopicStr: string [Length (StartTopic)] = StartTopic;

  var   KeywordN: Integer;
        DropOnePar: Boolean;

  procedure DoWrite (Str: string; NoPar: Boolean);

    procedure MakeBold (var S: string); far;
    var OldI, I: Integer;
    begin
      OldI := 0;
      I := Pos (S, Str);

      while I > 0 do begin
        Inc (I, OldI);

        System. Insert (#4, Str, I + Length (S));
        System. Insert (#3, Str, I);

        OldI := I + Length (S) + 1;
        I := Pos (S, Copy (Str, I + Length (S) + 2, Length (Str)));
      end;
    end;

  const EOL: string [2] = #$D#$A;
        Par: string [4] = '\par';
        StartKey: string [7] = '{\uldb ';
        EndKey:   string [5] = '}{\v ';
        StartBold: string [4] = '{\b ';

  var I: Integer;
      C: Char;
      LinkStr: string;
      StartFrom: Integer;
  begin
    BoldNames. ForEach (@MakeBold);

    StartFrom := 1;

    if NoPar then begin
      if (Length (Str) > 0) and (Str [1] = ' ') then
        StartFrom := 2;
    end else begin
      S. Write (Par [1], Length (Par));

      if (Length (Str) > 0) and (Str [1] <> ' ') then begin
        C := ' '; S. Write (C, 1);
      end;
    end;

    for I := StartFrom to Length (Str) do
      case Str [I] of
      #2: begin
            if Odd (KeywordN) then begin
              S. Write (EndKey [1], Length (EndKey));
              System. Str (ResolveKeyword (KeywordN div 2, IdxTbl), LinkStr);
              S. Write (LinkStr [1], Length (LinkStr));
              C := '}'; S. Write (C, 1);
            end else
              S. Write (StartKey [1], Length (StartKey));

            Inc (KeywordN);
          end;
      #3: S. Write (StartBold [1], Length (StartBold));
      #4: begin C := '}'; S. Write (C, 1); end;

      'Å': begin C := 'u'; S. Write (C, 1); end;
      'Ê': begin C := 'u'; S. Write (C, 1); end;
      '˝': begin C := '2'; S. Write (C, 1); end;
      '†': begin C := 'a'; S. Write (C, 1); end;
      'ƒ': begin C := '-'; S. Write (C, 1); end;
      '≥': begin C := '|'; S. Write (C, 1); end;
      '¬': begin C := '+'; S. Write (C, 1); end;

      '¡': begin C := '+'; S. Write (C, 1); end;
      '√': begin C := '+'; S. Write (C, 1); end;

      '¥': begin C := '+'; S. Write (C, 1); end;

      '≈': begin C := '+'; S. Write (C, 1); end;
      '⁄': begin C := '+'; S. Write (C, 1); end;
      'ø': begin C := '+'; S. Write (C, 1); end;

      '¿': begin C := '+'; S. Write (C, 1); end;
      'Ÿ': begin C := '+'; S. Write (C, 1); end;
      '’': begin C := '+'; S. Write (C, 1); end;
      '—': begin C := '+'; S. Write (C, 1); end;
      '∏': begin C := '+'; S. Write (C, 1); end;

      '∆': begin C := '+'; S. Write (C, 1); end;

      'ÿ': begin C := '+'; S. Write (C, 1); end;

      'µ': begin C := '+'; S. Write (C, 1); end;

      '‘': begin C := '+'; S. Write (C, 1); end;
      'œ': begin C := '+'; S. Write (C, 1); end;
      'æ': begin C := '+'; S. Write (C, 1); end;
      'Õ': begin C := '='; S. Write (C, 1); end;

      '‰': begin C := 'E'; S. Write (C, 1); end;
      'Ç': begin C := 'e'; S. Write (C, 1); end;
      'Ñ': begin C := 'a'; S. Write (C, 1); end;
      '¢': begin C := 'o'; S. Write (C, 1); end;
      'î': begin C := 'o'; S. Write (C, 1); end;
      '\', '{', '}':
           begin
             C := '\'; S. Write (C, 1);
             S. Write ((@(Str [I]))^, 1);
           end;
      else
        S. Write ((@(Str [I]))^, 1);
      end;
    S. Write (EOL [1], 2);
  end;

  procedure WriteOneString (PS: PString); far;
  begin
    if PS <> nil then
      DoWrite (PS^, DropOnePar)
    else
      DoWrite ('', DropOnePar);

    DropOnePar := False;
  end;

var CtxStr, Str: string;

begin
  RestoreFromSwap (SwapFile^);

  S. Write (StartTopicStr [1], Length (StartTopicStr));

  System. Str (Ctx, CtxStr);
  Str := '#{\footnote{#} ' + CtxStr + '}'#$D#$A;
  S. Write (Str [1], Length (Str));
  Str := '${\footnote{$} ' + Title + '}'#$D#$A;
  S. Write (Str [1], Length (Str));
  Str := '+{\footnote{+} l:0}'#$D#$A;
  S. Write (Str [1], Length (Str));
  Str := 'K{\footnote{K} ' + Title + '}'#$D#$A;
  S. Write (Str [1], Length (Str));

  KeywordN := 0;

  Str := '{\f0\fs28\keep ';
  S. Write (Str [1], Length (Str));

  if Header <> nil then
    DoWrite (Header^, True)
  else
    DoWrite (Title, True);

  if SubHeader <> nil then begin
    Str := '{\fs24 ';
    S. Write (Str [1], Length (Str));
    DoWrite (SubHeader^, False);
    Str := '}';
    S. Write (Str [1], Length (Str));
  end;

  Str := '}\par\pard\keep'#$D#$A;
  S. Write (Str [1], Length (Str));

  DropOnePar := True;
  ForEach (@WriteOneString);

  Store2Swap (SwapFile^);
end;

procedure   TTopic. AddKeyword (S: string; StepBack: Integer);
begin
  Keywords. AtInsert (Keywords. Count - StepBack, NewStr (S));
end;

procedure   TTopic. AddKeywordAtStart (S: string);
begin
  Keywords. AtInsert (0, NewStr (S));
end;

function    TTopic. ResolveKeyword (const I: Integer; var IdxTbl: TIdxTbl): Word;
var
  TmpW: Word;
  J, K, MinL, SaveMinLIdx, MatchLen, DecCnt: Integer;
  TmpS, MatchS, Helper: string;
  MatchFound: Boolean;
begin
  if (Keywords. Count > I) and (I >= 0) then begin
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
            or (Pos (Helper, StUpcase2 (PIndexEntry (
                     IdxTbl. At (K))^. Topic^. Header^)) > 0))
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
      WriteLn (Header^);
      WriteLn ('error searching for - ', PString (Keywords. At (I))^);
      WriteLn ('found match         - ', PIndexEntry (IdxTbl. At (J))^.PS^);
      TmpW := 1;
    end else
      if MinL > 1 then begin
        WriteLn (Header^);
        WriteLn ('approximate match to - ', PString (Keywords. At (I))^);
        WriteLn ('is                   - ', PIndexEntry (IdxTbl. At (J))^.PS^);
        TmpW := 1;
      end;

    ResolveKeyword := TmpW;
  end else begin
    WriteLn ('Internal error - invalid keyword number');
    Halt (1);
  end;
end;

{ TIndexEntry = object (TObject) }

constructor TIndexEntry. Init (const S: string; ACtx: Word; var ATopic: PTopic);
begin
  inherited Init;
  PS := NewStr (S);
  Ctx := ACtx;

  Topic := ATopic;
  ATopic := nil;
  Topic^.Store2Swap (SwapFile^);

  if Topic^.Header = nil then
    Topic^.SetHeader (S);
end;

destructor  TIndexEntry. Done;
begin
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

{ THelpFile = object (TBufStream) }

constructor THelpFile.Init(FileName: FNameStr; Mode, Size: Word);
begin
  inherited Init (FileName, Mode, Size);
  if Mode = stCreate then
    Write (FileStamp, SizeOf (FileStamp));

  IdxTbl. Init (MaxCollectionSize, 0);
  IdxTbl. Duplicates := True;
end;

destructor  THelpFile.Done;
const NewPage: string [5] = '\page';
      EndOfFile: Char = '}';
var I: Integer;
begin
  IdxTbl. SetCtxs;

  System. Write ('                                                      '#13);
  for I := 0 to IdxTbl.Count - 1 do begin
    if I > 0 then
      Write (NewPage [1], 5);
    PIndexEntry (IdxTbl. At (I))^.Topic^.Write (
      Self,
      IdxTbl,
      PIndexEntry (IdxTbl. At (I))^. Ctx,
      PStr (PIndexEntry (IdxTbl. At (I))^. PS)^);

    System. Write (I, #13);
  end;

  Write (EndOfFile, SizeOf (EndOfFile));

  IdxTbl. Done;
  inherited Done;
end;

end.
