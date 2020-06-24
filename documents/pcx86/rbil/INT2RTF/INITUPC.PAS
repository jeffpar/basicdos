{ InitUpC unit.                                                   }
{ The software included, data formats and basic algorithms are    }
{ copyright (C) 1995, 96 by Slava Gostrenko. All rights reserved. }

unit
  InitUpC;

interface

procedure InitUpcaseArr (var Arr: array of Char);

implementation

procedure InitUpcaseArr (var Arr: array of Char);
var I: Integer;
begin
  for I := Low (Arr) to High (Arr) do
    Arr [I] := Upcase (Chr (I));
end;

end.
